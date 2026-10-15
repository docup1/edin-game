-- 03: игровой цикл - старт, раздача, ход, доступные карты, цели, конец хода.
BEGIN;

DO $$
DECLARE
    u1 uuid := gen_random_uuid();
    u2 uuid := gen_random_uuid();
    r         jsonb;
    v_game    bigint;
    p1 bigint;
    p2 bigint;
    t_uni     bigint;
    t_destroy bigint;
    t_protect bigint;
    t_restrict bigint;
    c_play    bigint;
    c_target  bigint;
    c_discard bigint;
BEGIN
    -- шаблоны под тест
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('GP Uni', 'u', 'gp://uni') RETURNING id_card_template INTO t_uni;
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('GP Destroy', 'd', 'gp://destroy') RETURNING id_card_template INTO t_destroy;
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('GP Protect', 'p', 'gp://protect') RETURNING id_card_template INTO t_protect;
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES ('GP Restrict', 'r', 'gp://restrict') RETURNING id_card_template INTO t_restrict;

    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_uni, id_mechanic FROM mechanics WHERE mechanic_name = 'COUNT_AS_UNICORN';
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_destroy, id_mechanic FROM mechanics
       WHERE mechanic_name IN ('COUNT_AS_UNICORN', 'DESTROY_IN_STABLE');
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_protect, id_mechanic FROM mechanics WHERE mechanic_name = 'PROTECT_STABLE';
    INSERT INTO template_mechanics (id_card_template, id_mechanic)
      SELECT t_restrict, id_mechanic FROM mechanics WHERE mechanic_name = 'RESTRICT_CARD_PLAY';

    -- лобби
    r := sp_create_game(u1, 'gp', 2, NULL);
    v_game := (r->>'game_id')::bigint;
    p1     := (r->>'player_id')::bigint;
    r := sp_join_game(u2, v_game, NULL);
    p2 := (r->>'player_id')::bigint;

    -- колода
    PERFORM sp_add_cards_to_game(v_game, t_uni, 20);
    PERFORM sp_add_cards_to_game(v_game, t_destroy, 4);
    PERFORM sp_add_cards_to_game(v_game, t_protect, 2);
    PERFORM sp_add_cards_to_game(v_game, t_restrict, 2);

    r := sp_start_game(v_game);
    ASSERT _current_player(v_game) = p1, 'первым должен идти p1';
    ASSERT _turn_number(v_game) = 1, 'номер хода должен быть 1';
    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'hand', p1)) = 6, 'p1 должен добрать до 6';
    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'hand', p2)) = 5, 'p2 должен иметь 5';

    -- добавить карты после старта -> ED003
    BEGIN PERFORM sp_add_cards_to_game(v_game, t_uni, 1); RAISE EXCEPTION 'ожидалось ED003';
    EXCEPTION WHEN SQLSTATE 'ED003' THEN NULL; END;

    -- неверный номер хода -> ED003
    BEGIN
        PERFORM sp_apply_event(v_game, 99, 'x', 'discard',
            (SELECT min(id_card) FROM cards WHERE id_game = v_game), NULL);
        RAISE EXCEPTION 'ожидалось ED003';
    EXCEPTION WHEN SQLSTATE 'ED003' THEN NULL; END;

    -- карты нет в руке текущего игрока -> ED004
    BEGIN
        PERFORM sp_apply_event(v_game, 1, 'x', 'discard',
            (SELECT c.id_card FROM cards c
              WHERE c.id_game = v_game
                AND NOT EXISTS (SELECT 1 FROM _cards_in_zone(v_game, 'hand', p1) h WHERE h = c.id_card)
              LIMIT 1), NULL);
        RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL; END;

    -- сыграть единорога -> стойло
    SELECT h AS id_card INTO c_play FROM _cards_in_zone(v_game, 'hand', p1) AS h
      JOIN cards c ON c.id_card = h
     WHERE c.id_card_template = t_uni LIMIT 1;
    PERFORM sp_apply_event(v_game, 1, 'play1', 'play', c_play, NULL);
    ASSERT (_player_status(p1)->>'unicorns')::int = 1, 'единорог не засчитан';
    ASSERT EXISTS (SELECT 1 FROM _cards_in_zone(v_game, 'stable', p1) s WHERE s = c_play), 'карта не в стойле';
    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'hand', p1)) = 5, 'рука не уменьшилась';

    -- сброс карты из руки
    SELECT h AS id_card INTO c_discard FROM _cards_in_zone(v_game, 'hand', p1) AS h LIMIT 1;
    PERFORM sp_apply_event(v_game, 1, 'disc1', 'discard', c_discard, NULL);
    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'hand', p1)) = 4, 'рука после сброса не 4';
    ASSERT EXISTS (SELECT 1 FROM discard WHERE id_card = c_discard), 'карта не в сбросе';

    -- защита стойла (карту кладём напрямую, чтобы тест не зависел от случайной раздачи)
    INSERT INTO cards (id_game, id_card_template) VALUES (v_game, t_protect)
      RETURNING id_card INTO c_play;
    INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p1, c_play, TRUE);
    ASSERT (_player_status(p1)->>'protected')::boolean, 'защита не видна';

    -- уничтожение: карта-разрушитель в руке p1 и цель в стойле p2
    INSERT INTO cards (id_game, id_card_template) VALUES (v_game, t_destroy)
      RETURNING id_card INTO c_play;
    INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p1, c_play, FALSE);

    INSERT INTO cards (id_game, id_card_template) VALUES (v_game, t_uni)
      RETURNING id_card INTO c_target;
    INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p2, c_target, TRUE);

    -- без цели -> ED004
    BEGIN PERFORM sp_apply_event(v_game, 1, 'd0', 'play', c_play, NULL); RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL; END;

    -- цель - не чужое стойло -> ED004
    BEGIN PERFORM sp_apply_event(v_game, 1, 'd1', 'play', c_play, c_play); RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL; END;

    -- корректная цель
    PERFORM sp_apply_event(v_game, 1, 'd2', 'play', c_play, c_target);
    ASSERT EXISTS (SELECT 1 FROM discard WHERE id_card = c_target), 'цель не в сбросе';
    ASSERT NOT EXISTS (SELECT 1 FROM player_cards WHERE id_card = c_target AND is_public),
        'цель осталась в стойле';
    ASSERT EXISTS (SELECT 1 FROM _cards_in_zone(v_game, 'stable', p1) s WHERE s = c_play), 'разрушитель не в стойле p1';

    -- конец хода -> p2 (внутри сам пересчитывает стойла и открывает следующий)
    PERFORM sp_end_turn(v_game, 1);
    ASSERT _current_player(v_game) = p2, 'ход не перешёл к p2';
    ASSERT _turn_number(v_game) = 2, 'номер хода не 2';
    ASSERT (SELECT count(*) FROM _cards_in_zone(v_game, 'hand', p2)) = 6, 'p2 не добрал карту';

    -- устаревший номер хода на end_turn -> ED003
    BEGIN PERFORM sp_end_turn(v_game, 1); RAISE EXCEPTION 'ожидалось ED003';
    EXCEPTION WHEN SQLSTATE 'ED003' THEN NULL; END;

    -- конец хода p2 -> p1
    PERFORM sp_end_turn(v_game, 2);
    ASSERT _current_player(v_game) = p1, 'ход не вернулся к p1';
    ASSERT _turn_number(v_game) = 3, 'номер хода не 3';

    -- запрет розыгрыша (RESTRICT_CARD_PLAY)
    INSERT INTO cards (id_game, id_card_template) VALUES (v_game, t_restrict)
      RETURNING id_card INTO c_play;
    INSERT INTO player_cards (id_player, id_card, is_public) VALUES (p1, c_play, TRUE);
    ASSERT (_player_status(p1)->>'restricted')::boolean, 'запрет не виден';
    ASSERT jsonb_array_length(_available(v_game, p1)) = 0, 'available не пуст при запрете';
    SELECT h AS id_card INTO c_discard FROM _cards_in_zone(v_game, 'hand', p1) AS h LIMIT 1;
    BEGIN PERFORM sp_apply_event(v_game, 3, 'r1', 'play', c_discard, NULL); RAISE EXCEPTION 'ожидалось ED004';
    EXCEPTION WHEN SQLSTATE 'ED004' THEN NULL; END;

    RAISE NOTICE 'gameplay OK';
END $$;

ROLLBACK;
