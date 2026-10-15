-- 00: проверка, что база поднялась и все функции на месте.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('fn_get_player(uuid)'),
        ('fn_list_open_games(boolean,boolean,uuid)'),
        ('fn_get_catalog()'),
        ('fn_get_game_state(bigint,bigint)'),
        ('fn_check_victory(bigint)'),
        ('fn_list_mechanics()'),
        ('fn_list_card_templates(text)'),
        ('fn_get_card_template(bigint)'),
        ('fn_notify(bigint,text)'),
        ('sp_create_card_template(text,text,text)'),
        ('sp_update_card_template(bigint,text,text,text)'),
        ('sp_set_card_mechanics(bigint,bigint[])'),
        ('sp_add_cards_to_game(bigint,bigint,integer)'),
        ('sp_create_game(uuid,text,integer,text)'),
        ('sp_join_game(uuid,bigint,text)'),
        ('sp_leave_game(bigint,bigint)'),
        ('sp_update_game(bigint,uuid,text,integer,text)'),
        ('sp_cancel_game(bigint,uuid)'),
        ('sp_set_game_password(bigint,text)'),
        ('sp_start_game(bigint)'),
        ('sp_begin_turn(bigint,bigint)'),
        ('sp_skip_turn(bigint)'),
        ('sp_apply_event(bigint,integer,text,text,bigint,bigint)'),
        ('sp_end_turn(bigint,integer)'),
        ('sp_resolve_stable_effects(bigint)'),
        ('sp_fire_turn_start(bigint)')
    ) AS t(sig)
    LOOP
        ASSERT to_regprocedure(r.sig) IS NOT NULL, 'нет функции: ' || r.sig;
    END LOOP;

    ASSERT (SELECT count(*) FROM mechanics) = 20, 'должно быть 20 механик';
    ASSERT (SELECT count(*) FROM card_templates WHERE img_link LIKE 'demo://%') >= 12,
        'демо-шаблоны не загрузились';

    -- каталог и справочник отвечают непустыми массивами
    ASSERT jsonb_array_length(fn_get_catalog()) >= 12, 'каталог пуст';
    ASSERT jsonb_array_length(fn_list_mechanics()) = 20, 'справочник механик неполон';

    RAISE NOTICE 'smoke OK';
END $$;
