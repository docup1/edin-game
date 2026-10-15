-- =============================================================================
--  ФУНКЦИИ ИГРЫ ПОД СУЩЕСТВУЮЩУЮ СХЕМУ (init.sql НЕ МЕНЯЕТСЯ)
-- =============================================================================
--  Целевая архитектура: БД = хранилище + снимки состояния (fn_*) + мелкие
--  атомарные операции (sp_*). Правила игры (движок механик и порядок хода)
--  постепенно уезжают на сервер; ниже они помечены как кандидаты на вынос.
--  Рассылка событий через pg_notify убрана - её заменяют SSE и fn_get_game_state.
--
--  Кандидаты на вынос на сервер (пока в БД): _fire_leave_stable,
--  _apply_active_mechanics, _apply_play, _available, sp_begin_turn,
--  sp_apply_event, sp_end_turn, fn_check_victory.
--
--  Соглашения:
--   * move_status = TRUE  -> партия началась; закончилась, если объявлен
--     победитель (_finished -> fn_check_victory вернул непустой объект);
--   * number_of_players    -> максимум мест (2..6);
--   * имя партии синтетическое: 'Партия #<id>';
--   * зоны карты:
--       hand    = player_cards.is_public = FALSE;
--       stable  = player_cards.is_public = TRUE;
--       discard = строки в discard;
--       deck    = cards игры без строки в player_cards и без строки в discard;
--   * moves(id_player, move_number) - лог завершённых ходов;
--     открытый ход = count(moves по игре)+1; текущий игрок = следующий по
--     move_order после последнего хода (циклично);
--   * ready / request_id / метка пропуска / длительности эффектов - вне схемы
--     (кэш сервера). Пропуск приходит аргументом skip_player в sp_begin_turn и
--     фиксируется как пропущенный ход в moves; request_id не проверяется.
--   * пароль: сервер считает хеш сам, БД хранит и сравнивает равенство.
--
--  Публичные функции совпадают с контрактом API.md. Актор в запись не
--  передаётся: он всегда текущий игрок (_current_player), поэтому проверка
--  «не его ход» живёт на сервере. База всё равно проверяет, что карта лежит в
--  руке текущего игрока и что номер хода совпал. Служебные хелперы _* под
--  слэшем не считаются частью API.
--
--  Коды ошибок (SQLSTATE -> HTTP на сервере):
--     ED001 -> 404 not found
--     ED002 -> 403 forbidden
--     ED003 -> 409 conflict
--     ED004 -> 422 unprocessable
-- =============================================================================


-- =============================================================================
--  ВНУТРЕННИЕ ХЕЛПЕРЫ
-- =============================================================================

-- [1] _card_mechanics
CREATE OR REPLACE FUNCTION _card_mechanics(p_id_card bigint) RETURNS SETOF mechanic_name_enum AS $$
    SELECT m.mechanic_name
    FROM cards c
    JOIN template_mechanics tm ON tm.id_card_template = c.id_card_template
    JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
    WHERE c.id_card = p_id_card;
$$ LANGUAGE sql STABLE;


-- [2] _has_mechanic
CREATE OR REPLACE FUNCTION _has_mechanic(p_id_card bigint, p_name mechanic_name_enum)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1
        FROM cards c
        JOIN template_mechanics tm ON tm.id_card_template = c.id_card_template
        JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
        WHERE c.id_card = p_id_card AND m.mechanic_name = p_name
    );
$$ LANGUAGE sql STABLE;


-- [3] _template_mechanics
-- Механики шаблона как jsonb-массив кодов (для снимков каталога и партии).
CREATE OR REPLACE FUNCTION _template_mechanics(p_id_template bigint) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(m.mechanic_name::text ORDER BY m.mechanic_name), '[]'::jsonb)
    FROM template_mechanics tm
    JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
    WHERE tm.id_card_template = p_id_template;
$$ LANGUAGE sql STABLE;


-- --- зоны карт: единый универсальный примитив --------------------------------

-- [4] _move_card
-- Универсальное перемещение: карта уходит из любой зоны в указанную.
-- Если карта покидает стойло (в другую зону или к другому игроку) - сама
-- запускает leave-триггер, поэтому вызывающему коду об этом думать не нужно.
CREATE OR REPLACE FUNCTION _move_card(p_id_player bigint, p_id_card bigint, p_zone text) RETURNS void AS $$
DECLARE
    v_owner bigint;
BEGIN
    IF p_zone NOT IN ('hand', 'stable', 'deck', 'discard') THEN
        RAISE EXCEPTION 'неизвестная зона: %', p_zone USING ERRCODE = 'ED004';
    END IF;
    IF p_zone IN ('hand', 'stable') AND p_id_player IS NULL THEN
        RAISE EXCEPTION 'для зоны % нужен игрок', p_zone USING ERRCODE = 'ED004';
    END IF;

    SELECT pc.id_player INTO v_owner
    FROM player_cards pc
    WHERE pc.id_card = p_id_card AND pc.is_public = TRUE;

    IF v_owner IS NOT NULL AND (p_zone <> 'stable' OR v_owner <> p_id_player) THEN
        PERFORM _fire_leave_stable(p_id_card);
    END IF;

    DELETE FROM player_cards WHERE id_card = p_id_card;
    DELETE FROM discard       WHERE id_card = p_id_card;

    IF p_zone IN ('hand', 'stable') THEN
        INSERT INTO player_cards (id_player, id_card, is_public)
        VALUES (p_id_player, p_id_card, (p_zone = 'stable'));
    ELSIF p_zone = 'discard' THEN
        INSERT INTO discard (id_card, position)
        VALUES (p_id_card, COALESCE((SELECT max(position) FROM discard), 0) + 1)
        ON CONFLICT (id_card) DO NOTHING;
    END IF;
    -- zone = 'deck': карта просто покинула любую зону
END;
$$ LANGUAGE plpgsql;


-- [5] _cards_in_zone
-- Универсальный список карт в зоне. Для hand/stable игрок обязателен,
-- для stable без игрока - стойла всех игроков партии.
CREATE OR REPLACE FUNCTION _cards_in_zone(p_id_game bigint, p_zone text, p_id_player bigint DEFAULT NULL)
RETURNS SETOF bigint AS $$
    SELECT pc.id_card
    FROM player_cards pc
    JOIN players pl ON pl.id_player = pc.id_player
    WHERE pl.id_game = p_id_game
      AND p_zone IN ('hand', 'stable')
      AND pc.is_public = (p_zone = 'stable')
      AND (p_id_player IS NULL OR pc.id_player = p_id_player)
    UNION ALL
    SELECT c.id_card
    FROM cards c
    WHERE p_zone = 'deck'
      AND c.id_game = p_id_game
      AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
      AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
    UNION ALL
    SELECT d.id_card
    FROM discard d
    JOIN cards c ON c.id_card = d.id_card
    WHERE p_zone = 'discard'
      AND c.id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- [6] _hand
-- Рука игрока как jsonb-массив карт (card_id, template_id, имя).
CREATE OR REPLACE FUNCTION _hand(p_id_player bigint) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'card_id',     c.id_card,
        'template_id', c.id_card_template,
        'name',        ct.card_name) ORDER BY pc.id_card), '[]'::jsonb)
    FROM player_cards pc
    JOIN cards c ON c.id_card = pc.id_card
    JOIN card_templates ct ON ct.id_card_template = c.id_card_template
    WHERE pc.id_player = p_id_player AND pc.is_public = FALSE;
$$ LANGUAGE sql STABLE;


-- --- состояние партии --------------------------------------------------------

-- [7] _game_started
CREATE OR REPLACE FUNCTION _game_started(p_id_game bigint) RETURNS boolean AS $$
    SELECT move_status FROM games WHERE id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- [8] _finished
-- Партия закончилась: объявлен победитель. До старта победителя нет (B1).
-- plpgsql, а не sql: fn_check_victory определена ниже, и тело не должно
-- проверяться при создании.
CREATE OR REPLACE FUNCTION _finished(p_id_game bigint) RETURNS boolean AS $$
BEGIN
    RETURN fn_check_victory(p_id_game) <> '{}'::jsonb;
END;
$$ LANGUAGE plpgsql STABLE;


-- [9] _game_summary
-- Одна карточка партии для лобби и ответов на настройки.
CREATE OR REPLACE FUNCTION _game_summary(p_id_game bigint) RETURNS jsonb AS $$
    SELECT jsonb_build_object(
        'id',             g.id_game,
        'name',           'Партия #' || g.id_game,
        'seats',          g.number_of_players,
        'occupied',       (SELECT count(*) FROM players p WHERE p.id_game = g.id_game),
        'needs_password', EXISTS (SELECT 1 FROM passwords pw WHERE pw.id_game = g.id_game),
        'started',        g.move_status)
    FROM games g WHERE g.id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- --- блокировки и общие проверки прав ----------------------------------------

-- [10] _lock_game
-- Блокирует партию под FOR UPDATE; при p_require_started дополнительно
-- требует, что она уже началась.
CREATE OR REPLACE FUNCTION _lock_game(p_id_game bigint, p_require_started boolean DEFAULT false) RETURNS void AS $$
BEGIN
    PERFORM 1 FROM games WHERE id_game = p_id_game FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'партия не найдена' USING ERRCODE = 'ED001';
    END IF;
    IF p_require_started AND NOT _game_started(p_id_game) THEN
        RAISE EXCEPTION 'партия не началась' USING ERRCODE = 'ED003';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [11] _lock_turn
-- Блокирует партию и требует, что открыт именно этот номер хода.
CREATE OR REPLACE FUNCTION _lock_turn(p_id_game bigint, p_turn int) RETURNS void AS $$
BEGIN
    PERFORM _lock_game(p_id_game, true);
    IF p_turn IS DISTINCT FROM _turn_number(p_id_game) THEN
        RAISE EXCEPTION 'номер хода не совпал' USING ERRCODE = 'ED003';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [12] _require_not_started
CREATE OR REPLACE FUNCTION _require_not_started(p_id_game bigint) RETURNS void AS $$
BEGIN
    IF _game_started(p_id_game) THEN
        RAISE EXCEPTION 'партия уже началась' USING ERRCODE = 'ED003';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [13] _require_host
CREATE OR REPLACE FUNCTION _require_host(p_id_game bigint, p_id_user uuid) RETURNS void AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM players
                   WHERE id_game = p_id_game AND is_admin = TRUE AND user_id = p_id_user) THEN
        RAISE EXCEPTION 'только создатель' USING ERRCODE = 'ED002';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [14] _require_enemy_stable_target
-- Цель эффекта - карта в чужом стойле той же партии.
CREATE OR REPLACE FUNCTION _require_enemy_stable_target(p_id_game bigint, p_actor bigint, p_target bigint)
RETURNS void AS $$
BEGIN
    IF p_target IS NULL THEN
        RAISE EXCEPTION 'нужна цель' USING ERRCODE = 'ED004';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM player_cards pc
        JOIN players pl ON pl.id_player = pc.id_player
        WHERE pc.id_card = p_target AND pc.is_public = TRUE
          AND pl.id_game = p_id_game AND pc.id_player <> p_actor
    ) THEN
        RAISE EXCEPTION 'неверная цель' USING ERRCODE = 'ED004';
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;


-- --- игроки и ход ------------------------------------------------------------

-- [15] _player_status
-- Сводка стойла игрока одним запросом: единороги, защита, запрет розыгрыша.
CREATE OR REPLACE FUNCTION _player_status(p_id_player bigint) RETURNS jsonb AS $$
    WITH mc AS (
        SELECT pc.id_card,
               bool_or(m.mechanic_name = 'COUNT_AS_UNICORN')   AS uni,
               bool_or(m.mechanic_name = 'PROTECT_STABLE')     AS prot,
               bool_or(m.mechanic_name = 'RESTRICT_CARD_PLAY') AS restr
        FROM player_cards pc
        JOIN cards c ON c.id_card = pc.id_card
        LEFT JOIN template_mechanics tm ON tm.id_card_template = c.id_card_template
        LEFT JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
        WHERE pc.id_player = p_id_player AND pc.is_public = TRUE
        GROUP BY pc.id_card
    )
    SELECT jsonb_build_object(
        'unicorns',   (count(*) FILTER (WHERE uni))::int,
        'protected',  COALESCE(bool_or(prot), FALSE),
        'restricted', COALESCE(bool_or(restr), FALSE)
    )
    FROM mc;
$$ LANGUAGE sql STABLE;


-- [16] _next_player
-- Следующий по move_order, по кругу. Без аргумента - первый в порядке хода.
CREATE OR REPLACE FUNCTION _next_player(p_id_game bigint, p_id_player bigint) RETURNS bigint AS $$
    SELECT p.id_player
    FROM players p
    WHERE p.id_game = p_id_game
    ORDER BY (p.move_order <= COALESCE((SELECT move_order FROM players WHERE id_player = p_id_player), 0)),
             p.move_order
    LIMIT 1;
$$ LANGUAGE sql STABLE;


-- [17] _current_player
-- Чей сейчас ход: следующий по кругу после игрока, чей ход завершён последним.
CREATE OR REPLACE FUNCTION _current_player(p_id_game bigint) RETURNS bigint AS $$
    SELECT _next_player(p_id_game, (
        SELECT m.id_player
        FROM moves m
        JOIN players p ON p.id_player = m.id_player
        WHERE p.id_game = p_id_game
        ORDER BY m.id_move DESC
        LIMIT 1
    ));
$$ LANGUAGE sql STABLE;


-- [18] _turn_number
CREATE OR REPLACE FUNCTION _turn_number(p_id_game bigint) RETURNS int AS $$
    SELECT (count(*))::int + 1
    FROM moves m
    JOIN players p ON p.id_player = m.id_player
    WHERE p.id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- [19] _record_move
-- Зафиксировать завершённый ход игрока.
CREATE OR REPLACE FUNCTION _record_move(p_id_player bigint) RETURNS void AS $$
    INSERT INTO moves (id_player, move_number)
    SELECT p_id_player, COALESCE(max(move_number), 0) + 1
    FROM moves
    WHERE id_player = p_id_player;
$$ LANGUAGE sql;


-- [20] _fire_leave_stable
-- Зовётся из _move_card, когда карта уходит из стойла.
CREATE OR REPLACE FUNCTION _fire_leave_stable(p_id_card bigint) RETURNS void AS $$
DECLARE
    v_player bigint;
    v_game   bigint;
    v_depth  int;
BEGIN
    SELECT pc.id_player, c.id_game INTO v_player, v_game
    FROM player_cards pc
    JOIN cards c ON c.id_card = pc.id_card
    WHERE pc.id_card = p_id_card AND pc.is_public = TRUE;

    IF v_player IS NULL THEN
        RETURN;
    END IF;
    IF NOT _has_mechanic(p_id_card, 'TRIGGER_ON_LEAVE_STABLE') THEN
        RETURN;
    END IF;

    v_depth := COALESCE(NULLIF(current_setting('edin.trigger_depth', true), '')::int, 0);
    IF v_depth >= 5 THEN
        RAISE WARNING 'trigger depth limit reached for card %', p_id_card;
        RETURN;
    END IF;

    PERFORM set_config('edin.trigger_depth', (v_depth + 1)::text, true);
    PERFORM _apply_active_mechanics(v_game, v_player, p_id_card, NULL, true);
    PERFORM set_config('edin.trigger_depth', v_depth::text, true);
END;
$$ LANGUAGE plpgsql;


-- [21] _draw
CREATE OR REPLACE FUNCTION _draw(p_id_game bigint, p_id_player bigint) RETURNS bigint AS $$
DECLARE
    v_card bigint;
BEGIN
    SELECT c.id_card INTO v_card
    FROM cards c
    WHERE c.id_game = p_id_game
      AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
      AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
    ORDER BY random()
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_card IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM _move_card(p_id_player, v_card, 'hand');
    RETURN v_card;
END;
$$ LANGUAGE plpgsql;


-- --- применение активных механик ---------------------------------------------

-- [22] _apply_active_mechanics
CREATE OR REPLACE FUNCTION _apply_active_mechanics(
    p_id_game bigint,
    p_actor   bigint,
    p_id_card bigint,
    p_target  bigint,
    p_lenient boolean
) RETURNS void AS $$
DECLARE
    r        record;
    v_pick   bigint;
    v_owner  bigint;
BEGIN
    FOR r IN
        SELECT cm.mech AS mechanic_name
        FROM _card_mechanics(p_id_card) AS cm(mech)
        WHERE cm.mech IN (
            'DRAW_FROM_DECK','DISCARD_FROM_HAND','SACRIFICE_FROM_STABLE',
            'DESTROY_IN_STABLE','STEAL_FROM_STABLE','SEARCH_IN_DECK',
            'SEARCH_IN_DISCARD','SHUFFLE_DECK','SKIP_PLAYER_TURN')
    LOOP
        BEGIN
            CASE r.mechanic_name
                WHEN 'DRAW_FROM_DECK' THEN
                    PERFORM _draw(p_id_game, p_actor);

                WHEN 'DISCARD_FROM_HAND' THEN
                    SELECT t.card_id INTO v_pick
                    FROM _cards_in_zone(p_id_game, 'hand', p_actor) AS t(card_id)
                    WHERE t.card_id <> p_id_card
                    ORDER BY random() LIMIT 1;
                    IF v_pick IS NOT NULL THEN
                        PERFORM _move_card(NULL, v_pick, 'discard');
                    END IF;

                WHEN 'SACRIFICE_FROM_STABLE' THEN
                    IF NOT (_player_status(p_actor)->>'protected')::boolean THEN
                        SELECT t.card_id INTO v_pick
                        FROM _cards_in_zone(p_id_game, 'stable', p_actor) AS t(card_id)
                        ORDER BY random() LIMIT 1;
                        IF v_pick IS NOT NULL THEN
                            PERFORM _move_card(NULL, v_pick, 'discard');
                        END IF;
                    END IF;

                WHEN 'DESTROY_IN_STABLE' THEN
                    PERFORM _require_enemy_stable_target(p_id_game, p_actor, p_target);
                    SELECT pc.id_player INTO v_owner FROM player_cards pc WHERE pc.id_card = p_target;
                    IF (_player_status(v_owner)->>'protected')::boolean THEN
                        RAISE EXCEPTION 'стойло цели защищено' USING ERRCODE = 'ED004';
                    END IF;
                    PERFORM _move_card(NULL, p_target, 'discard');

                WHEN 'STEAL_FROM_STABLE' THEN
                    PERFORM _require_enemy_stable_target(p_id_game, p_actor, p_target);
                    PERFORM _move_card(p_actor, p_target, 'stable');

                WHEN 'SEARCH_IN_DECK' THEN
                    SELECT t.card_id INTO v_pick
                    FROM _cards_in_zone(p_id_game, 'deck') AS t(card_id)
                    ORDER BY random() LIMIT 1;
                    IF v_pick IS NOT NULL THEN
                        PERFORM _move_card(p_actor, v_pick, 'hand');
                    END IF;

                WHEN 'SEARCH_IN_DISCARD' THEN
                    SELECT t.card_id INTO v_pick
                    FROM _cards_in_zone(p_id_game, 'discard') AS t(card_id)
                    ORDER BY random() LIMIT 1;
                    IF v_pick IS NOT NULL THEN
                        PERFORM _move_card(p_actor, v_pick, 'hand');
                    END IF;

                WHEN 'SHUFFLE_DECK' THEN
                    NULL; -- колода всегда случайна

                WHEN 'SKIP_PLAYER_TURN' THEN
                    NULL; -- метку ведёт сервер (вне схемы)
            END CASE;
        EXCEPTION WHEN OTHERS THEN
            IF p_lenient THEN
                RAISE WARNING 'механика % упала: %', r.mechanic_name, SQLERRM;
            ELSE
                RAISE;
            END IF;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- [23] _apply_play
CREATE OR REPLACE FUNCTION _apply_play(
    p_id_game bigint,
    p_actor   bigint,
    p_id_card bigint,
    p_target  bigint
) RETURNS void AS $$
DECLARE
    v_mechs     mechanic_name_enum[] := ARRAY(SELECT m FROM _card_mechanics(p_id_card) AS t(m));
    v_zone      text;
    v_enter     boolean;
    v_turnstart boolean;
BEGIN
    v_enter     := 'TRIGGER_ON_ENTER_STABLE' = ANY(v_mechs);
    v_turnstart := 'TRIGGER_ON_TURN_START'   = ANY(v_mechs);

    -- разовые эффекты применяем сразу, если карта не отложена под триггер
    IF NOT v_enter AND NOT v_turnstart THEN
        PERFORM _apply_active_mechanics(p_id_game, p_actor, p_id_card, p_target, FALSE);
    END IF;

    -- итоговая зона карты: явные MOVE_TO_* важнее пассивных свойств
    IF 'MOVE_TO_DISCARD' = ANY(v_mechs) OR 'MOVE_TO_NURSERY' = ANY(v_mechs) THEN
        v_zone := 'discard';
    ELSIF 'MOVE_TO_STABLE' = ANY(v_mechs) THEN
        v_zone := 'stable';
    ELSIF 'MOVE_TO_DECK' = ANY(v_mechs) THEN
        v_zone := 'deck';
    ELSIF 'MOVE_TO_HAND' = ANY(v_mechs) THEN
        v_zone := 'hand';
    ELSIF 'COUNT_AS_UNICORN' = ANY(v_mechs)
       OR 'PROTECT_STABLE' = ANY(v_mechs)
       OR 'RESTRICT_CARD_PLAY' = ANY(v_mechs)
       OR 'TRIGGER_ON_TURN_START' = ANY(v_mechs)
       OR 'TRIGGER_ON_ENTER_STABLE' = ANY(v_mechs)
       OR 'TRIGGER_ON_LEAVE_STABLE' = ANY(v_mechs) THEN
        v_zone := 'stable';
    ELSE
        v_zone := 'discard';
    END IF;
    PERFORM _move_card(CASE WHEN v_zone IN ('hand', 'stable') THEN p_actor END, p_id_card, v_zone);

    IF v_zone = 'stable' AND v_enter THEN
        PERFORM _apply_active_mechanics(p_id_game, p_actor, p_id_card, p_target, TRUE);
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [24] _available
-- Список доступных к розыгрышу карт (приватный, отдаётся внутри снимка партии).
CREATE OR REPLACE FUNCTION _available(p_id_game bigint, p_id_player bigint) RETURNS jsonb AS $$
BEGIN
    IF NOT _game_started(p_id_game) THEN
        RETURN '[]'::jsonb;
    END IF;
    IF _current_player(p_id_game) IS DISTINCT FROM p_id_player THEN
        RETURN '[]'::jsonb;
    END IF;
    IF (_player_status(p_id_player)->>'restricted')::boolean THEN
        RETURN '[]'::jsonb;
    END IF;

    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'card_id',      t.card_id,
            'template_id',  t.template_id,
            'needs_target', t.needs_target,
            'targets', CASE WHEN t.needs_target THEN COALESCE((
                SELECT jsonb_agg(jsonb_build_object('id', tt.card_id, 'label', 'Стойка ' || tt.move_order)
                                 ORDER BY tt.card_id)
                FROM (
                    SELECT pc2.id_card AS card_id, pl2.move_order
                    FROM player_cards pc2
                    JOIN players pl2 ON pl2.id_player = pc2.id_player
                    WHERE pl2.id_game = p_id_game AND pc2.is_public = TRUE
                      AND pc2.id_player <> p_id_player
                ) tt), '[]'::jsonb)
            END
        ) ORDER BY t.card_id)
        FROM (
            SELECT pc.id_card AS card_id, c.id_card_template AS template_id,
                   COALESCE(bool_or(m.mechanic_name IN ('DESTROY_IN_STABLE','STEAL_FROM_STABLE')), FALSE)
                       AS needs_target
            FROM player_cards pc
            JOIN cards c ON c.id_card = pc.id_card
            LEFT JOIN template_mechanics tm ON tm.id_card_template = c.id_card_template
            LEFT JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
            WHERE pc.id_player = p_id_player AND pc.is_public = FALSE
            GROUP BY pc.id_card, c.id_card_template
        ) t
    ), '[]'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE;


-- =============================================================================
--  ЧТЕНИЕ
-- =============================================================================

-- [25] fn_get_player
CREATE OR REPLACE FUNCTION fn_get_player(p_user_id uuid) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id_player', p.id_player,
        'id_game',   p.id_game,
        'move_order',p.move_order,
        'is_host',   p.is_admin
    ) ORDER BY p.id_game), '[]'::jsonb)
    FROM players p WHERE p.user_id = p_user_id;
$$ LANGUAGE sql STABLE;


-- [26] fn_list_open_games
CREATE OR REPLACE FUNCTION fn_list_open_games(
    p_has_slot boolean DEFAULT TRUE,
    p_mine     boolean DEFAULT FALSE,
    p_id_user  uuid    DEFAULT NULL,
    p_search   text    DEFAULT NULL
) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(_game_summary(g.id_game) ORDER BY g.id_game), '[]'::jsonb)
    FROM games g
    WHERE (NOT p_has_slot
           OR (SELECT count(*) FROM players p WHERE p.id_game = g.id_game) < g.number_of_players)
      AND (NOT p_mine
           OR EXISTS (SELECT 1 FROM players p WHERE p.id_game = g.id_game AND p.user_id = p_id_user))
      AND (p_search IS NULL OR p_search = ''
           OR ('Партия #' || g.id_game) ILIKE '%' || p_search || '%'
           OR g.id_game::text ILIKE p_search || '%');
$$ LANGUAGE sql STABLE;


-- [27] fn_get_game_state
CREATE OR REPLACE FUNCTION fn_get_game_state(p_id_game bigint, p_id_player bigint DEFAULT NULL)
RETURNS jsonb AS $$
DECLARE
    v_game    games%ROWTYPE;
    v_turn    int;
    v_current bigint;
    v_json    jsonb;
BEGIN
    SELECT * INTO v_game FROM games WHERE id_game = p_id_game;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'партия не найдена' USING ERRCODE = 'ED001';
    END IF;

    IF v_game.move_status THEN
        v_turn    := _turn_number(p_id_game);
        v_current := _current_player(p_id_game);
    END IF;

    v_json := jsonb_build_object(
        'game_id',        v_game.id_game,
        'name',           'Партия #' || v_game.id_game,
        'started',        v_game.move_status,
        'finished',       _finished(p_id_game),
        'turn',           COALESCE(v_turn, 0),
        'current_player', v_current,
        'deck_count',     (SELECT count(*) FROM _cards_in_zone(p_id_game, 'deck')),
        'winner',         fn_check_victory(p_id_game),
        'discard', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'card_id', c.id_card, 'template_id', c.id_card_template, 'name', ct.card_name) ORDER BY d.position)
            FROM discard d
            JOIN cards c ON c.id_card = d.id_card
            JOIN card_templates ct ON ct.id_card_template = c.id_card_template
            WHERE c.id_game = p_id_game), '[]'::jsonb),
        'players', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id_player', p.id_player,
                'user_id',   p.user_id,
                'move_order',p.move_order,
                'is_host',   p.is_admin,
                'hand_count',(SELECT count(*) FROM _cards_in_zone(p_id_game, 'hand', p.id_player)),
                'unicorns',  (_player_status(p.id_player)->>'unicorns')::int,
                'protected', (_player_status(p.id_player)->>'protected')::boolean,
                'restricted',(_player_status(p.id_player)->>'restricted')::boolean,
                'stable', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'card_id',   c.id_card,
                        'template_id', c.id_card_template,
                        'name',      ct.card_name,
                        'mechanics', _template_mechanics(c.id_card_template)
                    ) ORDER BY pc.id_card)
                    FROM player_cards pc
                    JOIN cards c ON c.id_card = pc.id_card
                    JOIN card_templates ct ON ct.id_card_template = c.id_card_template
                    WHERE pc.id_player = p.id_player AND pc.is_public = TRUE), '[]'::jsonb)
            ) ORDER BY p.move_order)
            FROM players p WHERE p.id_game = p_id_game), '[]'::jsonb)
    );

    IF p_id_player IS NOT NULL THEN
        v_json := v_json || jsonb_build_object(
            'your_turn', (v_game.move_status AND v_current = p_id_player),
            'available', _available(p_id_game, p_id_player),
            'your_hand', _hand(p_id_player)
        );
    END IF;

    RETURN v_json;
END;
$$ LANGUAGE plpgsql STABLE;


-- [28] fn_check_victory
CREATE OR REPLACE FUNCTION fn_check_victory(p_id_game bigint) RETURNS jsonb AS $$
DECLARE
    v_players   int;
    v_threshold int;
    v_winner    bigint;
    v_count     int;
    v_deck      int;
BEGIN
    -- до старта победителя нет (B1)
    IF NOT COALESCE(_game_started(p_id_game), FALSE) THEN
        RETURN '{}'::jsonb;
    END IF;

    SELECT count(*) INTO v_players FROM players WHERE id_game = p_id_game;
    IF v_players = 0 THEN
        RETURN '{}'::jsonb;
    END IF;

    v_threshold := CASE WHEN v_players <= 5 THEN 7 ELSE 6 END;

    SELECT id_player, n INTO v_winner, v_count FROM (
        SELECT p.id_player, (_player_status(p.id_player)->>'unicorns')::int AS n
        FROM players p WHERE p.id_game = p_id_game
    ) t
    WHERE n >= v_threshold
    ORDER BY n DESC
    LIMIT 1;

    IF v_winner IS NOT NULL THEN
        RETURN jsonb_build_object('winner', v_winner, 'reason', 'unicorns', 'count', v_count);
    END IF;

    v_deck := (SELECT count(*) FROM _cards_in_zone(p_id_game, 'deck'));
    IF v_deck = 0 THEN
        SELECT id_player, n INTO v_winner, v_count FROM (
            SELECT p.id_player,
                   (_player_status(p.id_player)->>'unicorns')::int AS n,
                   COALESCE((
                       SELECT sum(length(ct.card_name))
                       FROM player_cards pc
                       JOIN cards c ON c.id_card = pc.id_card
                       JOIN card_templates ct ON ct.id_card_template = c.id_card_template
                       WHERE pc.id_player = p.id_player AND pc.is_public = TRUE), 0) AS letters
            FROM players p WHERE p.id_game = p_id_game
        ) t
        ORDER BY n DESC, letters DESC
        LIMIT 1;
        RETURN jsonb_build_object('winner', v_winner, 'reason', 'deck_empty', 'count', v_count);
    END IF;

    RETURN '{}'::jsonb;
END;
$$ LANGUAGE plpgsql STABLE;


-- =============================================================================
--  СПРАВОЧНИКИ / АДМИНКА
-- =============================================================================

-- [29] fn_list_mechanics
CREATE OR REPLACE FUNCTION fn_list_mechanics() RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',          id_mechanic,
        'code',        mechanic_name::text,
        'name',        mechanic_name::text,
        'type',        mechanic_type::text,
        'description', CASE mechanic_name
            WHEN 'MOVE_TO_DECK'            THEN 'Положить карту в колоду с указанием позиции'
            WHEN 'MOVE_TO_HAND'            THEN 'Передать карту в руку игрока'
            WHEN 'MOVE_TO_STABLE'          THEN 'Поместить карту в стойло игрока'
            WHEN 'MOVE_TO_DISCARD'         THEN 'Отправить карту в сброс'
            WHEN 'MOVE_TO_NURSERY'         THEN 'Отправить малыша в ясли (в этой реализации - в сброс)'
            WHEN 'DRAW_FROM_DECK'          THEN 'Игрок берёт карту из колоды'
            WHEN 'DISCARD_FROM_HAND'       THEN 'Игрок сбрасывает карту с руки'
            WHEN 'SACRIFICE_FROM_STABLE'   THEN 'Игрок уничтожает карту у себя в стойле'
            WHEN 'DESTROY_IN_STABLE'       THEN 'Уничтожить карту цели в чужом стойле'
            WHEN 'STEAL_FROM_STABLE'       THEN 'Переместить карту цели в своё стойло'
            WHEN 'SEARCH_IN_DECK'          THEN 'Найти карту в колоде по условию'
            WHEN 'SEARCH_IN_DISCARD'       THEN 'Найти карту в сбросе по условию'
            WHEN 'SHUFFLE_DECK'            THEN 'Перемешать колоду'
            WHEN 'SKIP_PLAYER_TURN'        THEN 'Следующий ход игрока пропускается'
            WHEN 'PROTECT_STABLE'          THEN 'Запрет на DESTROY/SACRIFICE для стойла'
            WHEN 'RESTRICT_CARD_PLAY'      THEN 'Запрет игроку играть карты'
            WHEN 'TRIGGER_ON_TURN_START'   THEN 'Запуск сценария в начале хода'
            WHEN 'TRIGGER_ON_ENTER_STABLE' THEN 'Запуск сценария при входе в стойло'
            WHEN 'TRIGGER_ON_LEAVE_STABLE' THEN 'Запуск сценария при выходе из стойла'
            WHEN 'COUNT_AS_UNICORN'        THEN 'Учитывается как единорог для победы'
        END
    ) ORDER BY id_mechanic), '[]'::jsonb)
    FROM mechanics;
$$ LANGUAGE sql STABLE;


-- [30] fn_list_card_templates
CREATE OR REPLACE FUNCTION fn_list_card_templates(p_search text DEFAULT NULL) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',          ct.id_card_template,
        'name',        ct.card_name,
        'description', ct.card_description,
        'img_link',    ct.img_link,
        'mechanics',   _template_mechanics(ct.id_card_template)
    ) ORDER BY ct.id_card_template), '[]'::jsonb)
    FROM card_templates ct
    WHERE p_search IS NULL OR p_search = ''
       OR ct.card_name ILIKE '%' || p_search || '%'
       OR ct.card_description ILIKE '%' || p_search || '%'
       OR EXISTS (
            SELECT 1 FROM template_mechanics tm
            JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
            WHERE tm.id_card_template = ct.id_card_template
              AND m.mechanic_name::text ILIKE '%' || p_search || '%');
$$ LANGUAGE sql STABLE;


-- [31] fn_get_card_template
CREATE OR REPLACE FUNCTION fn_get_card_template(p_id bigint) RETURNS jsonb AS $$
DECLARE
    v_json jsonb;
BEGIN
    SELECT jsonb_build_object(
        'id',          ct.id_card_template,
        'name',        ct.card_name,
        'description', ct.card_description,
        'img_link',    ct.img_link,
        'mechanics',   _template_mechanics(ct.id_card_template)
    ) INTO v_json
    FROM card_templates ct WHERE ct.id_card_template = p_id;

    IF v_json IS NULL THEN
        RAISE EXCEPTION 'шаблон не найден' USING ERRCODE = 'ED001';
    END IF;
    RETURN v_json;
END;
$$ LANGUAGE plpgsql STABLE;


-- [32] sp_upsert_card_template
-- Создаёт шаблон, если p_id не задан, иначе правит существующий.
CREATE OR REPLACE FUNCTION sp_upsert_card_template(
    p_id bigint DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_img_link text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
    v_id bigint := p_id;
BEGIN
    IF v_id IS NULL THEN
        INSERT INTO card_templates (card_name, card_description, img_link)
        VALUES (p_name, p_description, p_img_link)
        RETURNING id_card_template INTO v_id;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM card_templates WHERE id_card_template = v_id) THEN
            RAISE EXCEPTION 'шаблон не найден' USING ERRCODE = 'ED001';
        END IF;
        UPDATE card_templates
           SET card_name        = COALESCE(p_name, card_name),
               card_description = COALESCE(p_description, card_description),
               img_link         = COALESCE(p_img_link, img_link)
         WHERE id_card_template = v_id;
    END IF;
    RETURN fn_get_card_template(v_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'такая картинка уже есть' USING ERRCODE = 'ED003';
END;
$$ LANGUAGE plpgsql;


-- [33] sp_set_card_mechanics
CREATE OR REPLACE FUNCTION sp_set_card_mechanics(p_id_template bigint, p_ids bigint[])
RETURNS jsonb AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM card_templates WHERE id_card_template = p_id_template) THEN
        RAISE EXCEPTION 'шаблон не найден' USING ERRCODE = 'ED001';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) AS i
               WHERE NOT EXISTS (SELECT 1 FROM mechanics m WHERE m.id_mechanic = i)) THEN
        RAISE EXCEPTION 'неизвестная механика' USING ERRCODE = 'ED004';
    END IF;

    DELETE FROM template_mechanics WHERE id_card_template = p_id_template;
    INSERT INTO template_mechanics (id_mechanic, id_card_template)
    SELECT i, p_id_template FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) AS i;

    RETURN jsonb_build_object('mechanics', _template_mechanics(p_id_template));
END;
$$ LANGUAGE plpgsql;


-- [34] sp_add_cards_to_game
CREATE OR REPLACE FUNCTION sp_add_cards_to_game(p_id_game bigint, p_id_template bigint, p_count int)
RETURNS jsonb AS $$
BEGIN
    PERFORM _lock_game(p_id_game);
    PERFORM _require_not_started(p_id_game);
    IF NOT EXISTS (SELECT 1 FROM card_templates WHERE id_card_template = p_id_template) THEN
        RAISE EXCEPTION 'неизвестный шаблон' USING ERRCODE = 'ED004';
    END IF;
    IF p_count IS NULL OR p_count <= 0 THEN
        RAISE EXCEPTION 'количество должно быть положительным' USING ERRCODE = 'ED004';
    END IF;

    INSERT INTO cards (id_game, id_card_template)
    SELECT p_id_game, p_id_template FROM generate_series(1, p_count);

    RETURN jsonb_build_object('added', p_count);
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
--  ЛОББИ
-- =============================================================================

-- [35] sp_create_game
CREATE OR REPLACE FUNCTION sp_create_game(
    p_user_id uuid, p_name text, p_max_players int, p_password_hash text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
    v_game   bigint;
    v_player bigint;
BEGIN
    IF p_max_players IS NULL OR p_max_players < 2 OR p_max_players > 6 THEN
        RAISE EXCEPTION 'число игроков вне диапазона 2..6' USING ERRCODE = 'ED004';
    END IF;

    INSERT INTO games (move_status, number_of_players)
    VALUES (FALSE, p_max_players)
    RETURNING id_game INTO v_game;

    INSERT INTO players (id_game, move_order, user_id, is_admin)
    VALUES (v_game, 1, p_user_id, TRUE)
    RETURNING id_player INTO v_player;

    IF p_password_hash IS NOT NULL THEN
        INSERT INTO passwords (id_game, password_hash) VALUES (v_game, p_password_hash);
    END IF;

    RETURN jsonb_build_object('game_id', v_game, 'player_id', v_player, 'is_host', TRUE);
END;
$$ LANGUAGE plpgsql;


-- [36] sp_join_game
-- Возврат на своё место отдаёт реальную руку (B2): после старта карты на месте,
-- до старта рука пуста.
CREATE OR REPLACE FUNCTION sp_join_game(
    p_user_id uuid, p_id_game bigint, p_password_hash text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
    v_player bigint;
    v_order  int;
    v_host   boolean;
BEGIN
    PERFORM _lock_game(p_id_game);

    SELECT id_player, is_admin INTO v_player, v_host
    FROM players WHERE id_game = p_id_game AND user_id = p_user_id;
    IF v_player IS NOT NULL THEN
        RETURN jsonb_build_object('player_id', v_player, 'is_host', v_host,
                                  'hand', _hand(v_player), 'returning', TRUE);
    END IF;

    PERFORM _require_not_started(p_id_game);

    IF EXISTS (SELECT 1 FROM passwords WHERE id_game = p_id_game) THEN
        IF p_password_hash IS NULL
           OR p_password_hash <> (SELECT password_hash FROM passwords WHERE id_game = p_id_game) THEN
            RAISE EXCEPTION 'неверный пароль' USING ERRCODE = 'ED002';
        END IF;
    END IF;

    IF (SELECT count(*) FROM players WHERE id_game = p_id_game)
       >= (SELECT number_of_players FROM games WHERE id_game = p_id_game) THEN
        RAISE EXCEPTION 'нет свободного места' USING ERRCODE = 'ED003';
    END IF;

    SELECT COALESCE(max(move_order), 0) + 1 INTO v_order FROM players WHERE id_game = p_id_game;
    INSERT INTO players (id_game, move_order, user_id, is_admin)
    VALUES (p_id_game, v_order, p_user_id, FALSE)
    RETURNING id_player INTO v_player;

    RETURN jsonb_build_object('player_id', v_player, 'is_host', FALSE, 'hand', _hand(v_player));
END;
$$ LANGUAGE plpgsql;


-- [37] sp_leave_game
CREATE OR REPLACE FUNCTION sp_leave_game(p_id_player bigint, p_id_game bigint) RETURNS void AS $$
DECLARE
    r record;
BEGIN
    PERFORM _lock_game(p_id_game);

    IF NOT EXISTS (SELECT 1 FROM players WHERE id_player = p_id_player AND id_game = p_id_game) THEN
        RAISE EXCEPTION 'игрок не в этой партии' USING ERRCODE = 'ED002';
    END IF;
    IF _finished(p_id_game) THEN
        RAISE EXCEPTION 'партия уже закончилась' USING ERRCODE = 'ED003';
    END IF;

    IF NOT _game_started(p_id_game) THEN
        -- до старта место освобождается (вышел - строки игрока нет)
        DELETE FROM players WHERE id_player = p_id_player;
    ELSE
        -- в игре место за игроком сохраняется, рука уходит в сброс
        FOR r IN SELECT t.card_id FROM _cards_in_zone(p_id_game, 'hand', p_id_player) AS t(card_id) LOOP
            PERFORM _move_card(NULL, r.card_id, 'discard');
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [38] sp_update_game
-- Пароль трогаем только при p_password_set: иначе PATCH settings его не касается
-- (B3). p_password_hash = NULL при p_password_set = TRUE означает «снять пароль».
CREATE OR REPLACE FUNCTION sp_update_game(
    p_id_game bigint, p_id_user uuid,
    p_name text DEFAULT NULL, p_max_players int DEFAULT NULL,
    p_password_hash text DEFAULT NULL, p_password_set boolean DEFAULT FALSE
) RETURNS jsonb AS $$
DECLARE
    v_occupied int;
BEGIN
    PERFORM _lock_game(p_id_game);
    PERFORM _require_host(p_id_game, p_id_user);
    PERFORM _require_not_started(p_id_game);

    IF p_max_players IS NOT NULL THEN
        v_occupied := (SELECT count(*) FROM players WHERE id_game = p_id_game);
        IF p_max_players < 2 OR p_max_players > 6 THEN
            RAISE EXCEPTION 'число игроков вне диапазона 2..6' USING ERRCODE = 'ED004';
        END IF;
        IF p_max_players < v_occupied THEN
            RAISE EXCEPTION 'меньше занятых мест' USING ERRCODE = 'ED004';
        END IF;
        UPDATE games SET number_of_players = p_max_players WHERE id_game = p_id_game;
    END IF;

    -- имя синтетическое, p_name игнорируется
    IF p_password_set THEN
        IF p_password_hash IS NULL THEN
            DELETE FROM passwords WHERE id_game = p_id_game;
        ELSE
            INSERT INTO passwords (id_game, password_hash) VALUES (p_id_game, p_password_hash)
            ON CONFLICT (id_game) DO UPDATE SET password_hash = EXCLUDED.password_hash;
        END IF;
    END IF;

    RETURN jsonb_build_object('game', _game_summary(p_id_game));
END;
$$ LANGUAGE plpgsql;


-- [39] sp_set_game_password
-- Отдельный путь для POST /api/games/{game_id}/password: пароль ставит/снимает
-- хост (роль admin) до старта. NULL снимает пароль.
CREATE OR REPLACE FUNCTION sp_set_game_password(p_id_game bigint, p_id_user uuid, p_password_hash text)
RETURNS void AS $$
BEGIN
    PERFORM _lock_game(p_id_game);
    PERFORM _require_host(p_id_game, p_id_user);
    PERFORM _require_not_started(p_id_game);

    IF p_password_hash IS NULL THEN
        DELETE FROM passwords WHERE id_game = p_id_game;
    ELSE
        INSERT INTO passwords (id_game, password_hash) VALUES (p_id_game, p_password_hash)
        ON CONFLICT (id_game) DO UPDATE SET password_hash = EXCLUDED.password_hash;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [40] sp_cancel_game
CREATE OR REPLACE FUNCTION sp_cancel_game(p_id_game bigint, p_id_user uuid) RETURNS void AS $$
BEGIN
    PERFORM _lock_game(p_id_game);
    PERFORM _require_host(p_id_game, p_id_user);
    PERFORM _require_not_started(p_id_game);

    DELETE FROM games WHERE id_game = p_id_game;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
--  ИГРА
-- =============================================================================

-- [41] sp_start_game
CREATE OR REPLACE FUNCTION sp_start_game(p_id_game bigint) RETURNS jsonb AS $$
DECLARE
    v_players int;
    v_deck    int;
    r         record;
    i         int;
    v_first   jsonb;
BEGIN
    PERFORM _lock_game(p_id_game);
    PERFORM _require_not_started(p_id_game);

    v_players := (SELECT count(*) FROM players WHERE id_game = p_id_game);
    IF v_players < 2 THEN
        RAISE EXCEPTION 'нужно минимум 2 игрока' USING ERRCODE = 'ED003';
    END IF;

    v_deck := (SELECT count(*) FROM _cards_in_zone(p_id_game, 'deck'));
    IF v_deck < v_players * 5 THEN
        RAISE EXCEPTION 'мало карт в колоде' USING ERRCODE = 'ED004';
    END IF;

    FOR r IN SELECT id_player FROM players WHERE id_game = p_id_game ORDER BY move_order LOOP
        FOR i IN 1..5 LOOP
            PERFORM _draw(p_id_game, r.id_player);
        END LOOP;
    END LOOP;

    UPDATE games SET move_status = TRUE WHERE id_game = p_id_game;

    v_first := sp_begin_turn(p_id_game);
    RETURN jsonb_build_object('game_id', p_id_game, 'first', v_first);
END;
$$ LANGUAGE plpgsql;


-- [42] sp_begin_turn
-- Пропущенный ход фиксируется в moves, чтобы счётчик и текущий игрок реально
-- сдвинулись (B4/B5): единственный путь пропуска - аргумент skip_player.
CREATE OR REPLACE FUNCTION sp_begin_turn(p_id_game bigint, p_skip_player bigint DEFAULT NULL) RETURNS jsonb AS $$
DECLARE
    v_candidate bigint;
    v_skips     int := 0;
    v_players   int;
    v_drawn     bigint;
    v_avail     jsonb;
    r           record;
BEGIN
    PERFORM _lock_game(p_id_game, true);
    IF _finished(p_id_game) THEN
        RAISE EXCEPTION 'партия уже закончилась' USING ERRCODE = 'ED003';
    END IF;

    v_players   := (SELECT count(*) FROM players WHERE id_game = p_id_game);
    v_candidate := _current_player(p_id_game);

    WHILE p_skip_player IS NOT NULL AND v_candidate = p_skip_player LOOP
        PERFORM _record_move(v_candidate);
        v_candidate := _current_player(p_id_game);
        v_skips := v_skips + 1;
        IF v_skips >= v_players THEN
            RAISE EXCEPTION 'все ходы пропущены' USING ERRCODE = 'ED003';
        END IF;
    END LOOP;

    v_drawn := _draw(p_id_game, v_candidate);

    -- триггеры начала хода у карт стойла
    FOR r IN SELECT t.card_id FROM _cards_in_zone(p_id_game, 'stable', v_candidate) AS t(card_id) LOOP
        IF _has_mechanic(r.card_id, 'TRIGGER_ON_TURN_START') THEN
            PERFORM _apply_active_mechanics(p_id_game, v_candidate, r.card_id, NULL, true);
        END IF;
    END LOOP;

    v_avail := _available(p_id_game, v_candidate);

    RETURN jsonb_build_object(
        'player',    v_candidate,
        'turn',      _turn_number(p_id_game),
        'drawn',     v_drawn,
        'skipped',   (v_skips > 0),
        'available', v_avail
    );
END;
$$ LANGUAGE plpgsql;


-- [43] sp_apply_event
-- Актор не передаётся: это всегда текущий игрок. Проверка «не его ход» живёт на
-- сервере; база проверяет номер хода и что карта лежит в руке текущего игрока.
CREATE OR REPLACE FUNCTION sp_apply_event(
    p_id_game bigint, p_turn int,
    p_request_id text, p_do text, p_id_card bigint, p_target bigint DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_actor bigint;
BEGIN
    PERFORM _lock_turn(p_id_game, p_turn);
    IF _finished(p_id_game) THEN
        RAISE EXCEPTION 'партия уже закончилась' USING ERRCODE = 'ED003';
    END IF;
    IF p_do NOT IN ('play', 'discard') THEN
        RAISE EXCEPTION 'неизвестное действие' USING ERRCODE = 'ED004';
    END IF;

    v_actor := _current_player(p_id_game);
    IF NOT EXISTS (
        SELECT 1 FROM player_cards
        WHERE id_player = v_actor AND id_card = p_id_card AND is_public = FALSE
    ) THEN
        RAISE EXCEPTION 'карты нет в руке' USING ERRCODE = 'ED004';
    END IF;

    IF p_do = 'play' THEN
        IF (_player_status(v_actor)->>'restricted')::boolean THEN
            RAISE EXCEPTION 'розыгрыш запрещён' USING ERRCODE = 'ED004';
        END IF;
        PERFORM _apply_play(p_id_game, v_actor, p_id_card, p_target);
    ELSE
        PERFORM _move_card(NULL, p_id_card, 'discard');
    END IF;
END;
$$ LANGUAGE plpgsql;


-- [44] sp_end_turn
-- Закрывает ход; следующий открывает только если партия не закончилась (B6).
CREATE OR REPLACE FUNCTION sp_end_turn(p_id_game bigint, p_turn int) RETURNS void AS $$
DECLARE
    v_actor  bigint;
    v_excess bigint;
BEGIN
    PERFORM _lock_turn(p_id_game, p_turn);
    IF _finished(p_id_game) THEN
        RAISE EXCEPTION 'партия уже закончилась' USING ERRCODE = 'ED003';
    END IF;

    v_actor := _current_player(p_id_game);

    -- автосброс лишних карт (предел руки = 7)
    WHILE (SELECT count(*) FROM _cards_in_zone(p_id_game, 'hand', v_actor)) > 7 LOOP
        SELECT t.card_id INTO v_excess
        FROM _cards_in_zone(p_id_game, 'hand', v_actor) AS t(card_id)
        ORDER BY random() LIMIT 1;
        PERFORM _move_card(NULL, v_excess, 'discard');
    END LOOP;

    PERFORM _record_move(v_actor);

    IF NOT _finished(p_id_game) THEN
        PERFORM sp_begin_turn(p_id_game);
    END IF;
END;
$$ LANGUAGE plpgsql;
