-- 02: админка и каталог - шаблоны, механики, наполнение колоды.
-- Чёрный ящик: только публичные fn_*/sp_*. БД - тупое хранилище: проверок
-- существования и допустимости нет, осмысленные коды расставляет сервер.
BEGIN;

DO $$
DECLARE
    v_tpl    bigint;
    v        jsonb;
    v_game   bigint;
    v_uuid   uuid := gen_random_uuid();
    v_m_uni  bigint;
    v_m_draw bigint;
BEGIN
    SELECT (e->>'id')::bigint INTO v_m_uni
      FROM jsonb_array_elements(fn_list_mechanics()) e WHERE e->>'code' = 'COUNT_AS_UNICORN';
    SELECT (e->>'id')::bigint INTO v_m_draw
      FROM jsonb_array_elements(fn_list_mechanics()) e WHERE e->>'code' = 'DRAW_FROM_DECK';
    ASSERT v_m_uni IS NOT NULL AND v_m_draw IS NOT NULL, 'механики не найдены в справочнике';

    -- создание шаблона через upsert
    v := sp_upsert_card_template(NULL, 'Админ-карта', 'описание', 'admt://x');
    v_tpl := (v->>'id')::bigint;
    ASSERT v_tpl > 0, 'шаблон не создан';
    ASSERT jsonb_array_length(v->'mechanics') = 0, 'у нового шаблона уже есть механики';

    -- назначение механик (полная замена набора)
    v := sp_set_card_mechanics(v_tpl, ARRAY[v_m_uni, v_m_draw]);
    ASSERT jsonb_array_length(v->'mechanics') = 2, 'механики не назначены';
    v := sp_set_card_mechanics(v_tpl, ARRAY[v_m_uni]);
    ASSERT jsonb_array_length(v->'mechanics') = 1, 'набор механик не заменён';

    -- чтение одного
    ASSERT fn_get_card_template(v_tpl)->>'name' = 'Админ-карта', 'имя не совпало';
    ASSERT jsonb_array_length(fn_get_card_template(v_tpl)->'mechanics') = 1, 'механики не читаются';

    -- нет шаблона -> NULL
    ASSERT fn_get_card_template(999999) IS NULL, 'нет шаблона - не NULL';

    -- правка: заданные поля перезаписываются, остальные сохраняются (COALESCE)
    v := sp_upsert_card_template(v_tpl, 'Админ-карта 2', NULL, NULL);
    ASSERT v->>'name' = 'Админ-карта 2', 'имя не обновилось';
    ASSERT v->>'description' = 'описание', 'описание затёрлось';
    ASSERT v->>'img_link' = 'admt://x', 'картинка затёрлась';
    ASSERT jsonb_array_length(v->'mechanics') = 1, 'правка сбросила механики';

    -- поиск: имя, описание, код механики
    ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_card_templates('Админ-карта 2')) e
                   WHERE (e->>'id')::bigint = v_tpl), 'поиск по имени';
    ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_card_templates('описан')) e
                   WHERE (e->>'id')::bigint = v_tpl), 'поиск по описанию';
    ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_card_templates('COUNT_AS_UNICORN')) e
                   WHERE (e->>'id')::bigint = v_tpl), 'поиск по механике';

    -- наполнение колоды
    v_game := (sp_create_game(v_uuid, 2)->>'game_id')::bigint;
    v := sp_add_cards_to_game(v_game, v_tpl, 5);
    ASSERT (v->>'added')::int = 5, 'добавилось не 5';
    ASSERT (fn_get_game_state(v_game)->>'deck_count')::int = 5, 'в колоде не 5 карт';
    ASSERT (sp_add_cards_to_game(v_game, v_tpl, 0)->>'added')::int = 0, 'ноль карт - не ноль';

    -- нет валидации, но схема держит ссылки: неизвестный шаблон -> сырой FK
    BEGIN
        PERFORM sp_add_cards_to_game(v_game, 999999, 1);
        RAISE EXCEPTION 'ожидалась ошибка FK';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    -- неизвестная механика -> сырой FK
    BEGIN
        PERFORM sp_set_card_mechanics(v_tpl, ARRAY[999999]);
        RAISE EXCEPTION 'ожидалась ошибка FK';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    -- повтор картинки ловит уникальный индекс схемы -> сырая ошибка
    BEGIN
        PERFORM sp_upsert_card_template(NULL, 'Другая', 'o', 'admt://x');
        RAISE EXCEPTION 'ожидалась ошибка UNIQUE';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    PERFORM sp_cancel_game(v_game);
    RAISE NOTICE 'admin OK';
END $$;

ROLLBACK;
