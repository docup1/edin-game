-- 02: админка - шаблоны, механики, наполнение колоды.
BEGIN;

DO $$
DECLARE
    v_tpl  bigint;
    v      jsonb;
    v_game bigint;
    v_uuid uuid := gen_random_uuid();
    v_m_uni bigint;
    v_m_draw bigint;
BEGIN
    SELECT id_mechanic INTO v_m_uni  FROM mechanics WHERE mechanic_name = 'COUNT_AS_UNICORN';
    SELECT id_mechanic INTO v_m_draw FROM mechanics WHERE mechanic_name = 'DRAW_FROM_DECK';

    -- создание
    v := sp_upsert_card_template(NULL, 'Админ-карта', 'описание', 'admt://x');
    v_tpl := (v->>'id')::bigint;
    ASSERT v_tpl > 0, 'шаблон не создан';

    -- дубль картинки -> ED003
    BEGIN
        PERFORM sp_upsert_card_template(NULL, 'Другая', 'o', 'admt://x');
        RAISE EXCEPTION 'ожидалось ED003';
    EXCEPTION WHEN SQLSTATE 'ED003' THEN NULL;
    END;

    -- назначение механик
    v := sp_set_card_mechanics(v_tpl, ARRAY[v_m_uni, v_m_draw]);
    ASSERT jsonb_array_length(v->'mechanics') = 2, 'механики не назначены';

    -- неизвестная механика -> ED004
    BEGIN
        PERFORM sp_set_card_mechanics(v_tpl, ARRAY[999999]);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL;
    END;

    -- чтение одного
    ASSERT fn_get_card_template(v_tpl)->>'name' = 'Админ-карта', 'имя не совпало';

    -- нет шаблона -> ED001
    BEGIN
        PERFORM fn_get_card_template(999999);
        RAISE EXCEPTION 'ожидалось ED001';
    EXCEPTION WHEN SQLSTATE 'ED001' THEN NULL;
    END;

    -- правка
    v := sp_upsert_card_template(v_tpl, 'Админ-карта 2', NULL, NULL);
    ASSERT v->>'name' = 'Админ-карта 2', 'правка не применилась';

    -- поиск по имени
    PERFORM 1 FROM jsonb_array_elements(fn_list_card_templates('Админ-карта 2')) e
      WHERE (e->>'id')::bigint = v_tpl;
    ASSERT FOUND, 'поиск не нашёл шаблон';

    -- поиск по коду механики
    PERFORM 1 FROM jsonb_array_elements(fn_list_card_templates('COUNT_AS_UNICORN')) e
      WHERE (e->>'id')::bigint = v_tpl;
    ASSERT FOUND, 'поиск по механике не нашёл шаблон';

    -- наполнение колоды до старта
    v := sp_create_game(v_uuid, 'наполнение', 2, NULL);
    v_game := (v->>'game_id')::bigint;
    v := sp_add_cards_to_game(v_game, v_tpl, 5);
    ASSERT (v->>'added')::int = 5, 'добавилось не 5';
    ASSERT (SELECT count(*) FROM cards WHERE id_game = v_game) = 5, 'в колоде не 5 карт';

    -- неизвестный шаблон -> ED004
    BEGIN
        PERFORM sp_add_cards_to_game(v_game, 999999, 1);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL;
    END;

    -- неположительное число -> ED004
    BEGIN
        PERFORM sp_add_cards_to_game(v_game, v_tpl, 0);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL;
    END;

    -- неизвестная партия -> ED001
    BEGIN
        PERFORM sp_add_cards_to_game(999999, v_tpl, 1);
        RAISE EXCEPTION 'ожидалось ED001';
    EXCEPTION WHEN SQLSTATE 'ED001' THEN NULL;
    END;

    RAISE NOTICE 'admin OK';
END $$;

ROLLBACK;
