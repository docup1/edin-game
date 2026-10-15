-- 00: проверка, что база поднялась и весь набор функций на месте.
-- Чёрный ящик: только публичные функции fn_*/sp_* и их хелперы _*.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        -- хелперы чтения
        ('_template_mechanics(bigint)'),
        ('_cards_in_zone(bigint,text,bigint)'),
        ('_hand(bigint)'),
        ('_game_summary(bigint)'),
        -- чтения
        ('fn_get_player(uuid)'),
        ('fn_list_open_games(boolean,boolean,uuid,text)'),
        ('fn_get_game_password(bigint)'),
        ('fn_get_game_state(bigint,bigint)'),
        ('fn_list_mechanics()'),
        ('fn_list_card_templates(text)'),
        ('fn_get_card_template(bigint)'),
        -- запись
        ('sp_create_game(uuid,integer,text)'),
        ('sp_join_game(uuid,bigint)'),
        ('sp_leave_game(bigint)'),
        ('sp_set_game_seats(bigint,integer)'),
        ('sp_set_game_password(bigint,text)'),
        ('sp_cancel_game(bigint)'),
        ('sp_upsert_card_template(bigint,text,text,text)'),
        ('sp_set_card_mechanics(bigint,bigint[])'),
        ('sp_add_cards_to_game(bigint,bigint,integer)'),
        ('sp_move_card(bigint,bigint,text)'),
        ('sp_draw(bigint,bigint)'),
        ('sp_record_move(bigint)'),
        ('sp_set_game_started(bigint,boolean)')
    ) AS t(sig)
    LOOP
        ASSERT to_regprocedure(r.sig) IS NOT NULL, 'нет функции: ' || r.sig;
    END LOOP;

    -- справочник и каталог отвечают непустыми массивами
    ASSERT jsonb_array_length(fn_list_mechanics()) = 20, 'должно быть 20 механик';
    ASSERT jsonb_array_length(fn_list_card_templates()) >= 12, 'каталог пуст';
    ASSERT (SELECT count(*) FROM jsonb_array_elements(fn_list_card_templates()) e
            WHERE e->>'img_link' LIKE 'demo://%') >= 12, 'демо-шаблоны не загрузились';

    RAISE NOTICE 'smoke OK';
END $$;
