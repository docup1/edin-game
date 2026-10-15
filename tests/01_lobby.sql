-- 01: лобби - создание, список, вход/выход, места, пароль, отмена.
-- Чёрный ящик: только публичные fn_*/sp_*. БД - тупое хранилище: бизнес-правил
-- (свободные места, пароль, права хоста) она не проверяет - это делает сервер.
-- Здесь проверяются данные и что читалки отдают NULL/[] вместо ошибок.
BEGIN;

DO $$
DECLARE
    v_host  uuid := gen_random_uuid();
    v_guest uuid := gen_random_uuid();
    v_third uuid := gen_random_uuid();
    v       jsonb;
    v_game  bigint;
    v_p1    bigint;
    v_p2    bigint;
BEGIN
    -- создание: синтетическое имя, создатель - хост
    v := sp_create_game(v_host, 2);
    v_game := (v->>'game_id')::bigint;
    v_p1   := (v->>'player_id')::bigint;
    ASSERT v_game > 0, 'партия не создана';
    ASSERT (v->>'is_host')::boolean, 'создатель не хост';

    -- партии нет -> читалки отдают NULL/[]
    ASSERT fn_get_game_state(v_game + 100000) IS NULL, 'нет партии - не NULL';
    ASSERT fn_get_game_password(v_game + 100000) IS NULL, 'нет партии - пароль не NULL';
    ASSERT fn_get_player(v_guest) = '[]'::jsonb, 'нет мест - не пустой массив';

    -- места пользователя
    ASSERT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_get_player(v_host)) e
        WHERE (e->>'id_game')::bigint = v_game
          AND (e->>'is_host')::boolean
          AND (e->>'move_order')::int = 1), 'fn_get_player не отдал место';

    -- видна в списке со свободным местом
    ASSERT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE)) e
        WHERE (e->>'id')::bigint = v_game
          AND (e->>'name') = 'Партия #' || v_game
          AND (e->>'seats')::int = 2
          AND (e->>'occupied')::int = 1
          AND NOT (e->>'needs_password')::boolean
          AND NOT (e->>'started')::boolean), 'партия не видна в открытых';

    -- mine=TRUE - только свои
    ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_open_games(FALSE, TRUE, v_host)) e
                   WHERE (e->>'id')::bigint = v_game), 'своя партия не видна в mine';
    ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_open_games(FALSE, TRUE, v_third)) e
                       WHERE (e->>'id')::bigint = v_game), 'чужая партия видна в mine';

    -- search: по номеру находит
    ASSERT fn_list_open_games(FALSE, FALSE, NULL, v_game::text)
           @> jsonb_build_array(jsonb_build_object('id', v_game)), 'search не нашёл партию';

    -- заходим вторым
    v := sp_join_game(v_guest, v_game);
    v_p2 := (v->>'player_id')::bigint;
    ASSERT v_p2 > 0 AND NOT (v->>'is_host')::boolean, 'гость не зашёл';
    ASSERT v->'hand' = '[]'::jsonb, 'рука до старта не пуста';

    -- мест больше нет -> has_slot прячет
    ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE)) e
                       WHERE (e->>'id')::bigint = v_game), 'полная партия не спрятана';

    -- БД не проверяет заполненность: третий всё равно садится (это забота сервера)
    ASSERT (sp_join_game(v_third, v_game)->>'player_id')::bigint > 0, 'вставка места не удалась';
    ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_get_game_state(v_game)->'players') e
                   WHERE (e->>'id_player')::bigint = v_p2), 'нет игрока в снимке';

    -- повторный join тем же гостем -> то же место
    v := sp_join_game(v_guest, v_game);
    ASSERT (v->>'player_id')::bigint = v_p2, 'повторный join не вернул на место';

    -- выход до старта: место освобождается
    PERFORM sp_leave_game(v_p2);
    ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(fn_get_player(v_guest)) e
                       WHERE (e->>'id_player')::bigint = v_p2), 'место не освободилось';

    -- смена максимума мест
    PERFORM sp_set_game_seats(v_game, 4);
    ASSERT (fn_get_game_state(v_game)->>'seats')::int = 4, 'места не обновились';

    -- схема всё ещё держит границы: 99 мест -> сырая ошибка CHECK
    BEGIN
        PERFORM sp_set_game_seats(v_game, 99);
        RAISE EXCEPTION 'ожидалась ошибка CHECK';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- отмена хостом: партия больше не читается
    PERFORM sp_cancel_game(v_game);
    ASSERT fn_get_game_state(v_game) IS NULL, 'партия не удалена';

    RAISE NOTICE 'lobby part 1 OK';
END $$;

-- пароль: его хранит БД, сравнивает сервер
DO $$
DECLARE
    v_host uuid := gen_random_uuid();
    v      jsonb;
    v_game bigint;
BEGIN
    v := sp_create_game(v_host, 3, 'hash-1');
    v_game := (v->>'game_id')::bigint;
    ASSERT fn_get_game_password(v_game) = 'hash-1', 'пароль не сохранён';
    ASSERT (SELECT (e->>'needs_password')::boolean FROM jsonb_array_elements(fn_list_open_games(FALSE)) e
            WHERE (e->>'id')::bigint = v_game), 'флаг пароля не выставлен';

    -- замена и снятие пароля
    PERFORM sp_set_game_password(v_game, 'hash-2');
    ASSERT fn_get_game_password(v_game) = 'hash-2', 'пароль не заменён';
    PERFORM sp_set_game_password(v_game, NULL);
    ASSERT fn_get_game_password(v_game) IS NULL, 'пароль не снят';
    ASSERT NOT (SELECT (e->>'needs_password')::boolean FROM jsonb_array_elements(fn_list_open_games(FALSE)) e
                WHERE (e->>'id')::bigint = v_game), 'флаг пароля не снят';

    PERFORM sp_cancel_game(v_game);
    RAISE NOTICE 'lobby part 2 OK';
END $$;

ROLLBACK;
