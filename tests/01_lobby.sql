-- 01: лобби - создание, список, join, пароль, настройки, отмена, выход.
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
    -- создание
    v := sp_create_game(v_host, 'Пятница', 2, NULL);
    v_game := (v->>'game_id')::bigint;
    v_p1   := (v->>'player_id')::bigint;
    ASSERT v_game > 0, 'партия не создана';
    ASSERT (v->>'is_host')::boolean, 'создатель не хост';

    -- виден в списке со свободным местом
    PERFORM 1 FROM jsonb_array_elements(fn_list_open_games(TRUE, FALSE)) e
      WHERE (e->>'id')::bigint = v_game;
    ASSERT FOUND, 'партия не видна в открытых';

    -- mine=1 (только мои)
    PERFORM 1 FROM jsonb_array_elements(fn_list_open_games(FALSE, TRUE, v_host)) e
      WHERE (e->>'id')::bigint = v_game;
    ASSERT FOUND, 'своя партия не видна в mine';
    ASSERT NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(FALSE, TRUE, v_third)) e
        WHERE (e->>'id')::bigint = v_game), 'чужая партия видна в mine';

    -- search: по номеру партии находит, чужой номер не находит
    ASSERT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE, FALSE, NULL, v_game::text)) e
        WHERE (e->>'id')::bigint = v_game), 'search не нашёл партию по номеру';
    ASSERT NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE, FALSE, NULL, (v_game + 999)::text)) e
        WHERE (e->>'id')::bigint = v_game), 'search нашёл лишнее';

    -- заходим вторым
    v := sp_join_game(v_guest, v_game, NULL);
    v_p2 := (v->>'player_id')::bigint;
    ASSERT v_p2 > 0, 'гость не зашёл';
    ASSERT NOT (v->>'is_host')::boolean, 'гость вдруг хост';

    -- мест больше нет -> has_slot=1 прячет
    ASSERT NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE, FALSE)) e
        WHERE (e->>'id')::bigint = v_game), 'полная партия не спрятана';

    -- третий -> нет места (ED003)
    BEGIN
        PERFORM sp_join_game(v_third, v_game, NULL);
        RAISE EXCEPTION 'ожидалось ED003';
    EXCEPTION WHEN SQLSTATE 'ED003' THEN NULL;
    END;

    -- повторный join тем же гостем -> возврат на место
    v := sp_join_game(v_guest, v_game, NULL);
    ASSERT (v->>'returning')::boolean, 'повторный join не вернул на место';
    ASSERT (v->>'player_id')::bigint = v_p2, 'вернулось не то место';

    -- выход до старта: место освобождается
    PERFORM sp_leave_game(v_p2, v_game);
    ASSERT NOT EXISTS (SELECT 1 FROM players WHERE id_player = v_p2), 'место не освободилось';

    -- снова есть слот
    ASSERT EXISTS (
        SELECT 1 FROM jsonb_array_elements(fn_list_open_games(TRUE, FALSE)) e
        WHERE (e->>'id')::bigint = v_game), 'слот не вернулся';

    -- смена max_players меньше занятых -> ED004
    BEGIN
        PERFORM sp_update_game(v_game, v_host, NULL, 1, NULL);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL;
    END;

    -- не хост меняет настройки -> ED002
    BEGIN
        PERFORM sp_update_game(v_game, v_guest, NULL, 3, NULL);
        RAISE EXCEPTION 'ожидалось ED002';
    EXCEPTION WHEN SQLSTATE 'ED002' THEN NULL;
    END;

    -- не хост отменяет -> ED002
    BEGIN
        PERFORM sp_cancel_game(v_game, v_guest);
        RAISE EXCEPTION 'ожидалось ED002';
    EXCEPTION WHEN SQLSTATE 'ED002' THEN NULL;
    END;

    -- хост меняет настройки: возвращается объект { game }
    v := sp_update_game(v_game, v_host, 'игнор', 4, NULL);
    ASSERT (v->'game'->>'name') = 'Партия #' || v_game, 'имя не синтетическое';
    ASSERT (v->'game'->>'seats')::int = 4, 'места не обновились';
    ASSERT (v->'game'->>'id')::bigint = v_game, 'id партии не тот';

    RAISE NOTICE 'lobby part 1 OK';
END $$;

-- пароль
DO $$
DECLARE
    v_host  uuid := gen_random_uuid();
    v_guest uuid := gen_random_uuid();
    v       jsonb;
    v_game  bigint;
BEGIN
    v := sp_create_game(v_host, 'c паролем', 3, 'hash-1');
    v_game := (v->>'game_id')::bigint;

    -- без пароля -> ED002
    BEGIN
        PERFORM sp_join_game(v_guest, v_game, NULL);
        RAISE EXCEPTION 'ожидалось ED002';
    EXCEPTION WHEN SQLSTATE 'ED002' THEN NULL;
    END;

    -- неверный пароль -> ED002
    BEGIN
        PERFORM sp_join_game(v_guest, v_game, 'wrong');
        RAISE EXCEPTION 'ожидалось ED002';
    EXCEPTION WHEN SQLSTATE 'ED002' THEN NULL;
    END;

    -- верный пароль -> ок; до старта рука пуста (B2)
    v := sp_join_game(v_guest, v_game, 'hash-1');
    ASSERT v->>'player_id' IS NOT NULL, 'не пустило с верным паролем';
    ASSERT jsonb_array_length(v->'hand') = 0, 'рука до старта не пуста';

    -- возврат на своё место отдаёт руку (B2)
    v := sp_join_game(v_guest, v_game, 'hash-1');
    ASSERT (v->>'returning')::boolean, 'возврат не сработал';
    ASSERT v->'hand' IS NOT NULL, 'возврат не отдал руку';

    -- снять пароль (p_password_set = TRUE)
    PERFORM sp_update_game(v_game, v_host, NULL, NULL, NULL, TRUE);
    ASSERT NOT EXISTS (SELECT 1 FROM passwords WHERE id_game = v_game), 'пароль не снят';

    -- поставить пароль отдельной функцией
    PERFORM sp_set_game_password(v_game, v_host, 'hash-2');
    ASSERT EXISTS (SELECT 1 FROM passwords WHERE id_game = v_game), 'пароль не поставлен';

    -- PATCH настроек без p_password_set не трогает пароль (B3)
    PERFORM sp_update_game(v_game, v_host, NULL, 2, NULL);
    ASSERT (SELECT password_hash FROM passwords WHERE id_game = v_game) = 'hash-2',
        'PATCH без password_set сбросил/сломал пароль';

    -- снять пароль через отдельную функцию
    PERFORM sp_set_game_password(v_game, v_host, NULL);
    ASSERT NOT EXISTS (SELECT 1 FROM passwords WHERE id_game = v_game), 'пароль не снят отдельной функцией';

    -- отмена хостом
    PERFORM sp_cancel_game(v_game, v_host);
    ASSERT NOT EXISTS (SELECT 1 FROM games WHERE id_game = v_game), 'партия не отменена';

    -- max_players вне диапазона -> ED004
    BEGIN
        PERFORM sp_create_game(gen_random_uuid(), 'x', 7, NULL);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL;
    END;

    RAISE NOTICE 'lobby part 2 OK';
END $$;

ROLLBACK;
