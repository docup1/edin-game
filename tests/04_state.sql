-- 04: снимок состояния как контракт для движка на бэкенде.
-- Чёрный ящик: только публичные fn_*/sp_*. SQL не считает единорогов, ходы и
-- победу - он лишь отдаёт сырые данные (механики карт в стойлах, колода, сброс,
-- лог ходов), по которым считает сервер.
BEGIN;

DO $$
DECLARE
    u1 uuid := gen_random_uuid();
    u2 uuid := gen_random_uuid();
    r  jsonb;
    st jsonb;
    v_game bigint;
    p1 bigint;
    p2 bigint;
    t_uni bigint;
    v_m_uni bigint;
    c bigint;
    i int;
BEGIN
    SELECT (e->>'id')::bigint INTO v_m_uni
      FROM jsonb_array_elements(fn_list_mechanics()) e WHERE e->>'code' = 'COUNT_AS_UNICORN';
    r := sp_upsert_card_template(NULL, 'ST Uni', 'u', 'st://uni');
    t_uni := (r->>'id')::bigint;
    PERFORM sp_set_card_mechanics(t_uni, ARRAY[v_m_uni]);

    r := sp_create_game(u1, 2);
    v_game := (r->>'game_id')::bigint;
    p1     := (r->>'player_id')::bigint;
    p2     := (sp_join_game(u2, v_game)->>'player_id')::bigint;
    PERFORM sp_add_cards_to_game(v_game, t_uni, 10);
    PERFORM sp_set_game_started(v_game, TRUE);

    -- p1 выкладывает 2 единорога, p2 - одного
    FOR i IN 1..2 LOOP
        c := sp_draw(v_game, p1);
        PERFORM sp_move_card(p1, c, 'stable');
    END LOOP;
    c := sp_draw(v_game, p2);
    PERFORM sp_move_card(p2, c, 'stable');

    st := fn_get_game_state(v_game);

    -- по этим данным сервер сам считает единорогов (порог, победитель)
    ASSERT (SELECT count(*)
            FROM jsonb_array_elements(st->'players') pl,
                 jsonb_array_elements(pl->'stable') s
            WHERE (pl->>'id_player')::bigint = p1
              AND s->'mechanics' @> jsonb_build_array('COUNT_AS_UNICORN')) = 2,
        'стойло p1 не даёт посчитать единорогов';
    ASSERT (SELECT count(*)
            FROM jsonb_array_elements(st->'players') pl,
                 jsonb_array_elements(pl->'stable') s
            WHERE (pl->>'id_player')::bigint = p2
              AND s->'mechanics' @> jsonb_build_array('COUNT_AS_UNICORN')) = 1,
        'стойло p2 не даёт посчитать единорогов';

    -- порядок мест для вывода очереди хода на сервере
    ASSERT (SELECT array_agg((pl->>'move_order')::int ORDER BY (pl->>'move_order')::int)
            FROM jsonb_array_elements(st->'players') pl) = ARRAY[1, 2],
        'нет порядка мест';

    -- сырьё для тай-брейка: длина колоды и лог ходов
    ASSERT (st->>'deck_count')::int = 7, 'неверный остаток колоды';
    PERFORM sp_record_move(p1);
    ASSERT jsonb_array_length(fn_get_game_state(v_game)->'moves') = 1, 'лог ходов не растёт';

    -- отмена партии с непустым логом ходов не должна падать (RESTRICT на moves)
    PERFORM sp_cancel_game(v_game);
    ASSERT fn_get_game_state(v_game) IS NULL, 'партия не удалена';
    ASSERT fn_get_player(u1) = '[]'::jsonb, 'места не удалены вместе с партией';
    ASSERT fn_get_player(u2) = '[]'::jsonb, 'места гостя не удалены';

    RAISE NOTICE 'state OK';
END $$;

ROLLBACK;
