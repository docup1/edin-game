-- =============================================================================
--  ИГРА: ХЕЛПЕРЫ ЧТЕНИЯ И ПРИМИТИВЫ ДАННЫХ
-- =============================================================================
--  Домен "Игра" (см. functions/game.md). Файл грузится ПЕРВЫМ: на его хелперы
--  _* опираются лобби (db/21_functions_lobby.sql) и админка
--  (db/22_functions_admin.sql).
--
--  БД - тупое хранилище: только запросы, подзапросы и джоины. Никакой обработки
--  ошибок, ветвлений, циклов и правил игры. Всё, что можно посчитать на сервере
--  (чей ход, победа, доступные карты, единороги, защиты), считает сервер. Здесь
--  только данные и снимки состояния.
--
--  Соглашения:
--   * move_status = TRUE  -> партия началась (ставит сервер через
--     sp_set_game_started);
--   * number_of_players    -> максимум мест (2..6, следит сервер);
--   * имя партии синтетическое: 'Партия #<id>';
--   * зоны карты:
--       hand    = player_cards.is_public = FALSE;
--       stable  = player_cards.is_public = TRUE;
--       discard = строки в discard;
--       deck    = cards игры без строки в player_cards и без строки в discard;
--   * moves(id_player, move_number) - лог завершённых ходов; текущего игрока и
--     номер хода из него выводит сервер;
--   * пароль: сервер считает хеш сам, БД хранит его и отдаёт через
--     fn_get_game_password.
--
--  Публичные функции совпадают с контрактом API.md. Записывающие примитивы
--  ничего не проверяют: всё, что нарушает целостность, падает сырой ошибкой
--  схемы, а осмысленные HTTP-коды расставляет сервер.
-- =============================================================================


-- =============================================================================
--  ХЕЛПЕРЫ ЧТЕНИЯ
-- =============================================================================

-- [1] _template_mechanics
-- Механики шаблона как jsonb-массив кодов (для каталога и снимка партии).
CREATE OR REPLACE FUNCTION _template_mechanics(p_id_template bigint) RETURNS jsonb AS $$
    SELECT COALESCE(jsonb_agg(m.mechanic_name::text ORDER BY m.mechanic_name), '[]'::jsonb)
    FROM template_mechanics tm
    JOIN mechanics m ON m.id_mechanic = tm.id_mechanic
    WHERE tm.id_card_template = p_id_template;
$$ LANGUAGE sql STABLE;


-- [2] _cards_in_zone
-- Список карт в зоне. Для hand/stable игрок обязателен; stable без игрока
-- вернёт стойла всех игроков партии.
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


-- [3] _hand
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


-- [4] _game_summary
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


-- =============================================================================
--  СНИМОК ПАРТИИ
-- =============================================================================

-- [5] fn_get_game_state
-- Сырое состояние партии: партия, игроки со стойлами, колода, сброс, лог ходов.
-- Ничего не считает: чей ход, победу, единорогов и доступные карты выводит
-- сервер. Руку отдаёт только запрошенному игроку (передайте p_id_player).
-- Если партии нет - вернёт NULL.
CREATE OR REPLACE FUNCTION fn_get_game_state(p_id_game bigint, p_id_player bigint DEFAULT NULL)
RETURNS jsonb AS $$
    SELECT jsonb_build_object(
        'game_id',    g.id_game,
        'name',       'Партия #' || g.id_game,
        'seats',      g.number_of_players,
        'started',    g.move_status,
        'deck_count', (SELECT count(*) FROM _cards_in_zone(g.id_game, 'deck')),
        'discard', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'card_id', c.id_card, 'template_id', c.id_card_template, 'name', ct.card_name)
                ORDER BY d.position)
            FROM discard d
            JOIN cards c ON c.id_card = d.id_card
            JOIN card_templates ct ON ct.id_card_template = c.id_card_template
            WHERE c.id_game = g.id_game), '[]'::jsonb),
        'players', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id_player',  p.id_player,
                'user_id',    p.user_id,
                'move_order', p.move_order,
                'is_host',    p.is_admin,
                'hand_count', (SELECT count(*) FROM _cards_in_zone(g.id_game, 'hand', p.id_player)),
                'hand',       CASE WHEN p.id_player = p_id_player THEN _hand(p.id_player) END,
                'stable', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'card_id',   c.id_card,
                        'template_id', c.id_card_template,
                        'name',      ct.card_name,
                        'mechanics', _template_mechanics(c.id_card_template))
                        ORDER BY pc.id_card)
                    FROM player_cards pc
                    JOIN cards c ON c.id_card = pc.id_card
                    JOIN card_templates ct ON ct.id_card_template = c.id_card_template
                    WHERE pc.id_player = p.id_player AND pc.is_public = TRUE), '[]'::jsonb)
            ) ORDER BY p.move_order)
            FROM players p WHERE p.id_game = g.id_game), '[]'::jsonb),
        'moves', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id_move',     m.id_move,
                'id_player',   m.id_player,
                'move_number', m.move_number)
                ORDER BY m.id_move)
            FROM moves m
            JOIN players p ON p.id_player = m.id_player
            WHERE p.id_game = g.id_game), '[]'::jsonb)
    )
    FROM games g WHERE g.id_game = p_id_game;
$$ LANGUAGE sql STABLE;


-- =============================================================================
--  ПРИМИТИВЫ ЗАПИСИ
-- =============================================================================

-- [6] sp_move_card
-- Универсальное перемещение карты в зону hand/stable/deck/discard.
-- Зона deck - просто изъятие карты из любой текущей зоны. Для hand/stable
-- нужен игрок; для deck/discard он игнорируется. Ничего не проверяет.
CREATE OR REPLACE FUNCTION sp_move_card(p_id_player bigint, p_id_card bigint, p_zone text)
RETURNS void AS $$
    DELETE FROM player_cards WHERE id_card = p_id_card;
    DELETE FROM discard WHERE id_card = p_id_card;
    INSERT INTO player_cards (id_player, id_card, is_public)
    SELECT p_id_player, p_id_card, (p_zone = 'stable')
    WHERE p_zone IN ('hand', 'stable');
    INSERT INTO discard (id_card, position)
    SELECT p_id_card, COALESCE((SELECT max(position) FROM discard), 0) + 1
    WHERE p_zone = 'discard'
    ON CONFLICT (id_card) DO NOTHING;
$$ LANGUAGE sql;


-- [7] sp_draw
-- Кладёт случайную карту колоды в руку игрока и возвращает её id.
-- Колода пуста - вернёт NULL.
CREATE OR REPLACE FUNCTION sp_draw(p_id_game bigint, p_id_player bigint) RETURNS bigint AS $$
    WITH pick AS (
        SELECT c.id_card
        FROM cards c
        WHERE c.id_game = p_id_game
          AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
          AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
        ORDER BY random()
        LIMIT 1
    ), ins AS (
        INSERT INTO player_cards (id_player, id_card, is_public)
        SELECT p_id_player, id_card, FALSE FROM pick
        RETURNING id_card
    )
    SELECT id_card FROM ins;
$$ LANGUAGE sql;


-- [8] sp_record_move
-- Записывает завершённый ход игрока (move_number = max по игроку + 1).
CREATE OR REPLACE FUNCTION sp_record_move(p_id_player bigint) RETURNS void AS $$
    INSERT INTO moves (id_player, move_number)
    SELECT p_id_player, COALESCE(max(move_number), 0) + 1
    FROM moves
    WHERE id_player = p_id_player;
$$ LANGUAGE sql;


-- [9] sp_set_game_started
-- Поднимает/опускает флаг "партия началась". Раздачей карт занимается сервер
-- (через sp_draw).
CREATE OR REPLACE FUNCTION sp_set_game_started(p_id_game bigint, p_started boolean)
RETURNS void AS $$
    UPDATE games SET move_status = p_started WHERE id_game = p_id_game;
$$ LANGUAGE sql;
