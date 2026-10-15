-- =============================================================================
--  ЛОББИ: СПИСОК, СОЗДАНИЕ, ВХОД/ВЫХОД, НАСТРОЙКИ
-- =============================================================================
--  Домен "Лобби" (см. functions/lobby.md). Грузится ПОСЛЕ
--  20_functions_game.sql (использует хелперы _game_summary/_hand) и до
--  22_functions_admin.sql.
--
--  БД - тупое хранилище: запросы без проверок и обработки ошибок. Свободные
--  места, пароль, права хоста и признак "партия началась" проверяет сервер;
--  сюда приходят уже готовые решения. Хеш пароля сервер сравнивает сам с тем,
--  что отдаёт fn_get_game_password.
-- =============================================================================


-- [1] fn_get_player
-- Места пользователя: в каких партиях он сидит.
CREATE OR REPLACE FUNCTION fn_get_player(p_user_id uuid) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id_player', p.id_player,
        'id_game',   p.id_game,
        'move_order',p.move_order,
        'is_host',   p.is_admin
    ) ORDER BY p.id_game), '[]'::jsonb)
    FROM players p WHERE p.user_id = p_user_id;
$$ LANGUAGE sql STABLE;


-- [2] fn_list_open_games
-- Список партий (карточка _game_summary). has_slot - только со свободными
-- местами, mine - только свои, search - по номеру или синтетическому имени.
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


-- [3] fn_get_game_password
-- Хеш пароля партии или NULL, если пароля нет. Сравнивает сервер.
CREATE OR REPLACE FUNCTION fn_get_game_password(p_id_game bigint) RETURNS text AS $$
    SELECT password_hash FROM passwords WHERE id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- [4] sp_create_game
-- Создаёт партию и сажает создателя хостом. Число мест не проверяет.
CREATE OR REPLACE FUNCTION sp_create_game(
    p_user_id uuid, p_max_players int, p_password_hash text DEFAULT NULL
) RETURNS jsonb AS $$
    WITH g AS (
        INSERT INTO games (move_status, number_of_players)
        VALUES (FALSE, p_max_players)
        RETURNING id_game
    ), p AS (
        INSERT INTO players (id_game, move_order, user_id, is_admin)
        SELECT id_game, 1, p_user_id, TRUE FROM g
        RETURNING id_player, id_game
    ), pw AS (
        INSERT INTO passwords (id_game, password_hash)
        SELECT id_game, p_password_hash FROM g WHERE p_password_hash IS NOT NULL
    )
    SELECT jsonb_build_object('game_id', p.id_game, 'player_id', p.id_player, 'is_host', TRUE)
    FROM p;
$$ LANGUAGE sql;


-- [5] sp_join_game
-- Сажает игрока в партию. Пароль, свободное место и старт проверяет сервер.
-- Если игрок уже сидит за своим местом - вернёт его же (место сохраняется).
CREATE OR REPLACE FUNCTION sp_join_game(p_user_id uuid, p_id_game bigint) RETURNS jsonb AS $$
    WITH ins AS (
        INSERT INTO players (id_game, move_order, user_id, is_admin)
        VALUES (p_id_game,
                COALESCE((SELECT max(move_order) FROM players WHERE id_game = p_id_game), 0) + 1,
                p_user_id, FALSE)
        ON CONFLICT (id_game, user_id) DO UPDATE SET is_admin = players.is_admin
        RETURNING id_player, is_admin
    )
    SELECT jsonb_build_object(
        'player_id', ins.id_player,
        'is_host',   ins.is_admin,
        'hand',      _hand(ins.id_player))
    FROM ins;
$$ LANGUAGE sql;


-- [6] sp_leave_game
-- Свободные места и правила - на сервере. До старта место освобождается
-- (карты уходят каскадом); в игре место и лог ходов сохраняются, а рука
-- уходит в сброс. Оба правила включаются флагом move_status, поэтому
-- срабатывает ровно одно.
CREATE OR REPLACE FUNCTION sp_leave_game(p_id_player bigint) RETURNS void AS $$
    WITH gone AS (
        DELETE FROM player_cards pc
        USING players pl, games g
        WHERE pc.id_player = p_id_player
          AND pl.id_player = pc.id_player
          AND g.id_game = pl.id_game
          AND NOT pc.is_public
          AND g.move_status
        RETURNING pc.id_card
    )
    INSERT INTO discard (id_card, position)
    SELECT id_card, COALESCE((SELECT max(position) FROM discard), 0) + row_number() OVER ()
    FROM gone;

    DELETE FROM players pl
    USING games g
    WHERE pl.id_player = p_id_player
      AND g.id_game = pl.id_game
      AND NOT g.move_status;
$$ LANGUAGE sql;


-- [7] sp_set_game_seats
-- Меняет максимум мест партии. Диапазон и сравнение с занятыми - на сервере.
CREATE OR REPLACE FUNCTION sp_set_game_seats(p_id_game bigint, p_max_players int) RETURNS void AS $$
    UPDATE games SET number_of_players = p_max_players WHERE id_game = p_id_game;
$$ LANGUAGE sql;


-- [8] sp_set_game_password
-- Ставит пароль партии или снимает его (p_password_hash IS NULL).
CREATE OR REPLACE FUNCTION sp_set_game_password(p_id_game bigint, p_password_hash text) RETURNS void AS $$
    DELETE FROM passwords WHERE id_game = p_id_game;
    INSERT INTO passwords (id_game, password_hash)
    SELECT p_id_game, p_password_hash WHERE p_password_hash IS NOT NULL;
$$ LANGUAGE sql;


-- [9] sp_cancel_game
-- Удаляет партию вместе с игроками и картами (каскад). Лог ходов держит
-- RESTRICT на игроках, поэтому сначала чистим его.
CREATE OR REPLACE FUNCTION sp_cancel_game(p_id_game bigint) RETURNS void AS $$
    DELETE FROM moves m
    USING players p
    WHERE m.id_player = p.id_player AND p.id_game = p_id_game;

    DELETE FROM games WHERE id_game = p_id_game;
$$ LANGUAGE sql;
