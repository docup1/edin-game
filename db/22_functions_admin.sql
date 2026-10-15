-- =============================================================================
--  АДМИНКА И КАТАЛОГ
-- =============================================================================
--  Домен "Админка и каталог" (см. functions/admin.md): справочник механик,
--  каталог шаблонов, наполнение колод. Грузится ПОСЛЕ 20_functions_game.sql
--  (использует _template_mechanics).
--
--  БД - тупое хранилище: запросы без проверок. Существование шаблона, роли
--  админа и допустимость действий проверяет сервер.
-- =============================================================================


-- [1] fn_list_mechanics
-- Справочник механик (id, код, тип, описание).
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


-- [2] fn_list_card_templates
-- Шаблоны с поиском по имени, описанию и коду механики; без поиска - весь каталог.
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


-- [3] fn_get_card_template
-- Один шаблон с механиками. Если нет - NULL.
CREATE OR REPLACE FUNCTION fn_get_card_template(p_id bigint) RETURNS jsonb AS $$
    SELECT jsonb_build_object(
        'id',          ct.id_card_template,
        'name',        ct.card_name,
        'description', ct.card_description,
        'img_link',    ct.img_link,
        'mechanics',   _template_mechanics(ct.id_card_template)
    )
    FROM card_templates ct WHERE ct.id_card_template = p_id;
$$ LANGUAGE sql STABLE;


-- [4] sp_upsert_card_template
-- Создаёт шаблон (p_id IS NULL) или правит указанные поля (COALESCE).
-- Возвращает объект шаблона.
CREATE OR REPLACE FUNCTION sp_upsert_card_template(
    p_id bigint DEFAULT NULL,
    p_name text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_img_link text DEFAULT NULL
) RETURNS jsonb AS $$
    INSERT INTO card_templates (id_card_template, card_name, card_description, img_link)
    SELECT COALESCE(p_id, nextval(pg_get_serial_sequence('card_templates', 'id_card_template'))),
           COALESCE(p_name,        ct.card_name),
           COALESCE(p_description, ct.card_description),
           COALESCE(p_img_link,    ct.img_link)
    FROM (SELECT 1) AS x
    LEFT JOIN card_templates ct ON ct.id_card_template = p_id
    ON CONFLICT (id_card_template) DO UPDATE
        SET card_name        = EXCLUDED.card_name,
            card_description = EXCLUDED.card_description,
            img_link         = EXCLUDED.img_link
    RETURNING jsonb_build_object(
        'id',          id_card_template,
        'name',        card_name,
        'description', card_description,
        'img_link',    img_link,
        'mechanics',   _template_mechanics(id_card_template));
$$ LANGUAGE sql;


-- [5] sp_set_card_mechanics
-- Полностью заменяет набор механик шаблона. Неизвестные id молча игнорируются.
CREATE OR REPLACE FUNCTION sp_set_card_mechanics(p_id_template bigint, p_ids bigint[])
RETURNS jsonb AS $$
    DELETE FROM template_mechanics WHERE id_card_template = p_id_template;
    INSERT INTO template_mechanics (id_mechanic, id_card_template)
    SELECT i, p_id_template FROM unnest(COALESCE(p_ids, ARRAY[]::bigint[])) AS i;
    SELECT jsonb_build_object('mechanics', COALESCE(
        jsonb_agg(m.mechanic_name::text ORDER BY m.mechanic_name), '[]'::jsonb))
    FROM mechanics m
    WHERE m.id_mechanic = ANY(COALESCE(p_ids, ARRAY[]::bigint[]));
$$ LANGUAGE sql;


-- [6] sp_add_cards_to_game
-- Добавляет p_count карт шаблона в колоду партии. Возвращает, сколько добавилось.
CREATE OR REPLACE FUNCTION sp_add_cards_to_game(p_id_game bigint, p_id_template bigint, p_count int)
RETURNS jsonb AS $$
    WITH ins AS (
        INSERT INTO cards (id_game, id_card_template)
        SELECT p_id_game, p_id_template FROM generate_series(1, p_count)
        RETURNING 1
    )
    SELECT jsonb_build_object('added', count(*)) FROM ins;
$$ LANGUAGE sql;
