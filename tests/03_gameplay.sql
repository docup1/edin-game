-- 03: игровые примитивы - старт, раздача, перемещение карт, лог ходов, снимок.
-- Чёрный ящик: только публичные fn_*/sp_*. БД - тупое хранилище: ходы, цели,
-- победу и правила считает сервер; здесь только данные.
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
    c1 bigint;
    c2 bigint;
BEGIN
    SELECT (e->>'id')::bigint INTO v_m_uni
      FROM jsonb_array_elements(fn_list_mechanics()) e WHERE e->>'code' = 'COUNT_AS_UNICORN';
    r := sp_upsert_card_template(NULL, 'GP Uni', 'u', 'gp://uni');
    t_uni := (r->>'id')::bigint;
    PERFORM sp_set_card_mechanics(t_uni, ARRAY[v_m_uni]);

    r := sp_create_game(u1, 2);
    v_game := (r->>'game_id')::bigint;
    p1     := (r->>'player_id')::bigint;
    p2     := (sp_join_game(u2, v_game)->>'player_id')::bigint;
    PERFORM sp_add_cards_to_game(v_game, t_uni, 3);

    -- снимок до старта
    st := fn_get_game_state(v_game, p1);
    ASSERT (st->>'game_id')::bigint = v_game, 'не тот game_id';
    ASSERT (st->>'name') = 'Партия #' || v_game, 'имя не синтетическое';
    ASSERT (st->>'seats')::int = 2, 'не те места';
    ASSERT NOT (st->>'started')::boolean, 'партия уже началась';
    ASSERT (st->>'deck_count')::int = 3, 'колода не 3';
    ASSERT st->'discard' = '[]'::jsonb, 'сброс не пуст';
    ASSERT st->'moves' = '[]'::jsonb, 'лог ходов не пуст';
    ASSERT jsonb_array_length(st->'players') = 2, 'не 2 игрока';
    ASSERT (st->'players'->0)->>'id_player' = p1::text, 'игроки не по move_order';
    ASSERT (st->'players'->0)->'hand' = '[]'::jsonb, 'рука не пуста';

    PERFORM sp_set_game_started(v_game, TRUE);
    ASSERT (fn_get_game_state(v_game)->>'started')::boolean, 'флаг старта не поднялся';

    -- раздача: карта уходит из колоды в руку
    c1 := sp_draw(v_game, p1);
    ASSERT c1 IS NOT NULL, 'карта не вытянулась';
    st := fn_get_game_state(v_game, p1);
    ASSERT (st->>'deck_count')::int = 2, 'колода не уменьшилась';
    ASSERT (st->'players'->0)->>'hand_count' = '1', 'рука не выросла';
    ASSERT (st->'players'->0)->'hand'->0->>'card_id' = c1::text, 'не та карта в руке';

    -- рука видна только запрошенному игроку
    ASSERT (st->'players'->1)->'hand' = 'null'::jsonb, 'чужая рука не скрыта';
    st := fn_get_game_state(v_game, p2);
    ASSERT (st->'players'->1)->'hand' = '[]'::jsonb, 'своя рука не отдана';

    -- рука -> стойло: карта и её механики видны в стойле
    PERFORM sp_move_card(p1, c1, 'stable');
    st := fn_get_game_state(v_game, p1);
    ASSERT jsonb_array_length((st->'players'->0)->'stable') = 1, 'стабил не пополнился';
    ASSERT (st->'players'->0)->'stable'->0->>'card_id' = c1::text, 'не та карта в стойле';
    ASSERT (st->'players'->0)->'stable'->0->'mechanics' @> to_jsonb(ARRAY['COUNT_AS_UNICORN']),
        'механики карты не видны в стойле';
    ASSERT (st->'players'->0)->>'hand_count' = '0', 'рука не опустела';

    -- рука -> сброс
    c2 := sp_draw(v_game, p1);
    PERFORM sp_move_card(p1, c2, 'discard');
    st := fn_get_game_state(v_game);
    ASSERT jsonb_array_length(st->'discard') = 1, 'сброс не пополнился';
    ASSERT st->'discard'->0->>'card_id' = c2::text, 'не та карта в сбросе';
    ASSERT jsonb_array_length((st->'players'->0)->'stable') = 1, 'стойло пострадало';

    -- лог завершённых ходов
    PERFORM sp_record_move(p1);
    PERFORM sp_record_move(p1);
    PERFORM sp_record_move(p2);
    st := fn_get_game_state(v_game);
    ASSERT jsonb_array_length(st->'moves') = 3, 'лог ходов неполон';
    ASSERT (SELECT array_agg((m->>'move_number')::int ORDER BY (m->>'move_number')::int)
            FROM jsonb_array_elements(st->'moves') m WHERE (m->>'id_player')::bigint = p1) = ARRAY[1, 2],
        'нумерация ходов игрока сбита';

    -- пустая колода -> NULL, а не ошибка
    PERFORM sp_draw(v_game, p1);
    ASSERT (fn_get_game_state(v_game)->>'deck_count')::int = 0, 'колода не пуста';
    ASSERT sp_draw(v_game, p1) IS NULL, 'пустая колода не вернула NULL';

    -- в игре выход сохраняет место, рука уходит в сброс
    PERFORM sp_add_cards_to_game(v_game, t_uni, 2);
    PERFORM sp_draw(v_game, p2);
    PERFORM sp_leave_game(p2);
    st := fn_get_game_state(v_game);
    ASSERT jsonb_array_length(st->'players') = 2, 'в игре место не сохранилось';
    ASSERT jsonb_array_length(st->'discard') = 2, 'рука выходящего не в сбросе';

    PERFORM sp_cancel_game(v_game);
    RAISE NOTICE 'gameplay OK';
END $$;

ROLLBACK;
