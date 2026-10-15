-- 04: победа - по единорогам, порог для 6 игроков, тай-брейк пустой колоды.
BEGIN;

-- два игрока: порог 7
DO $$
DECLARE
    u1 uuid := gen_random_uuid();
    u2 uuid := gen_random_uuid();
    t_uni bigint;
    v_game bigint;
    p1 bigint;
    r jsonb;
    v jsonb;
    rec record;
BEGIN
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('VC Uni', 'u', 'vc://uni') RETURNING id_card_template INTO t_uni;
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_uni, id_mechanic FROM mechanics WHERE mechanic_name = 'COUNT_AS_UNICORN';

    r := sp_create_game(u1, 'v2', 2, NULL);
    v_game := (r->>'game_id')::bigint;
    p1 := (r->>'player_id')::bigint;
    PERFORM sp_join_game(u2, v_game, NULL);
    PERFORM sp_add_cards_to_game(v_game, t_uni, 20);
    PERFORM sp_start_game(v_game);

    FOR rec IN
        SELECT c.id_card FROM cards c
         WHERE c.id_game = v_game
           AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
           AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
         LIMIT 7
    LOOP
        INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p1, rec.id_card, TRUE);
    END LOOP;

    ASSERT (_player_status(p1)->>'unicorns')::int = 7, 'не 7 единорогов';
    v := fn_check_victory(v_game);
    ASSERT v->>'reason' = 'unicorns', 'нет победы по единорогам';
    ASSERT (v->>'winner')::bigint = p1, 'не тот победитель';

    RAISE NOTICE 'victory 2p OK';
END $$;

-- шесть игроков: порог 6
DO $$
DECLARE
    uuids uuid[] := ARRAY[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
                          gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
    t_uni bigint;
    v_game bigint;
    p1 bigint;
    r jsonb;
    v jsonb;
    i int;
    rec record;
BEGIN
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('VC Uni 6', 'u', 'vc://uni6') RETURNING id_card_template INTO t_uni;
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_uni, id_mechanic FROM mechanics WHERE mechanic_name = 'COUNT_AS_UNICORN';

    r := sp_create_game(uuids[1], 'v6', 6, NULL);
    v_game := (r->>'game_id')::bigint;
    p1 := (r->>'player_id')::bigint;
    FOR i IN 2..6 LOOP
        PERFORM sp_join_game(uuids[i], v_game, NULL);
    END LOOP;
    PERFORM sp_add_cards_to_game(v_game, t_uni, 40);
    PERFORM sp_start_game(v_game);

    FOR rec IN
        SELECT c.id_card FROM cards c
         WHERE c.id_game = v_game
           AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
           AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
         LIMIT 6
    LOOP
        INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p1, rec.id_card, TRUE);
    END LOOP;

    ASSERT (_player_status(p1)->>'unicorns')::int = 6, 'не 6 единорогов';
    v := fn_check_victory(v_game);
    ASSERT v->>'reason' = 'unicorns', 'порог 6 не сработал';
    ASSERT (v->>'winner')::bigint = p1, 'не тот победитель (6 игроков)';

    RAISE NOTICE 'victory 6p OK';
END $$;

-- пустая колода: тай-брейк по числу единорогов
DO $$
DECLARE
    u1 uuid := gen_random_uuid();
    u2 uuid := gen_random_uuid();
    t_uni bigint;
    v_game bigint;
    p1 bigint;
    p2 bigint;
    r jsonb;
    v jsonb;
    rec record;
    n int := 0;
BEGIN
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('VC Uni TB', 'u', 'vc://uni-tb') RETURNING id_card_template INTO t_uni;
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_uni, id_mechanic FROM mechanics WHERE mechanic_name = 'COUNT_AS_UNICORN';

    r := sp_create_game(u1, 'vtb', 2, NULL);
    v_game := (r->>'game_id')::bigint;
    p1 := (r->>'player_id')::bigint;
    r := sp_join_game(u2, v_game, NULL);
    p2 := (r->>'player_id')::bigint;
    PERFORM sp_add_cards_to_game(v_game, t_uni, 20);
    PERFORM sp_start_game(v_game);

    -- p2 получает 2 единорога в стойло
    FOR rec IN
        SELECT c.id_card FROM cards c
         WHERE c.id_game = v_game
           AND NOT EXISTS (SELECT 1 FROM player_cards pc WHERE pc.id_card = c.id_card)
           AND NOT EXISTS (SELECT 1 FROM discard d WHERE d.id_card = c.id_card)
         LIMIT 2
    LOOP
        INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p2, rec.id_card, TRUE);
    END LOOP;

    -- вычищаем колоду в сброс
    INSERT INTO discard (id_card, position)
    SELECT d AS id_card,
           (SELECT COALESCE(max(position), 0) FROM discard) + row_number() OVER ()
    FROM _cards_in_zone(v_game, 'deck') d;

    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'deck')) = 0, 'колода не пуста';

    v := fn_check_victory(v_game);
    ASSERT v->>'reason' = 'deck_empty', 'нет тай-брейка пустой колоды';
    ASSERT (v->>'winner')::bigint = p2, 'тай-брейк выбрал не того';
    ASSERT (v->>'count')::int = 2, 'неверный счёт у победителя';

    RAISE NOTICE 'victory deck_empty OK';
END $$;

ROLLBACK;
