-- =========================================================
-- ДЕМО-СИД: несколько шаблонов карт с механиками.
-- Нужен для ручного тыканья и как фактура для проверок.
-- Экземпляры карт в конкретную партию добавляет sp_add_cards_to_game.
-- Запускается один раз при initdb (файл смонтирован в entrypoint).
-- =========================================================

WITH new_templates AS (
    INSERT INTO card_templates (card_name, card_description, img_link)
    VALUES
        ('Обычный единорог',      'Просто единорог. Считается за единорога.',        'demo://unicorn-basic'),
        ('Малыш-единорог',        'Ещё один единорог для стада.',                    'demo://unicorn-baby'),
        ('Единорог-гроза',        'Уничтожает карту в чужом стойле.',                'demo://unicorn-storm'),
        ('Единорог-похититель',   'Крадёт карту из чужого стойла в своё.',           'demo://unicorn-thief'),
        ('Единорог-питомец',      'Считается единорогом и добирает карту из колоды.','demo://unicorn-pet'),
        ('Щит стойла',            'Защищает стойло от уничтожения и жертв.',         'demo://unstable-shield'),
        ('Оковы',                 'Не даёт владельцу играть карты.',                 'demo://unstable-chains'),
        ('Якорь',                 'Следующий ход игрока пропускается.',              'demo://unstable-anchor'),
        ('Сортировщик',           'Ищет карту в колоде и берёт в руку.',             'demo://action-sorter'),
        ('Возврат',               'Достаёт карту из сброса в руку.',                 'demo://action-return'),
        ('Мусорщик',              'Жертвует карту из своего стойла.',                'demo://action-scavenger'),
        ('Перемешивание',         'Мешает колоду.',                                 'demo://action-shuffle')
    RETURNING id_card_template, card_name
)
INSERT INTO template_mechanics (id_card_template, id_mechanic)
SELECT nt.id_card_template, m.id_mechanic
FROM new_templates nt
JOIN (VALUES
    ('Обычный единорог',    'COUNT_AS_UNICORN'),
    ('Малыш-единорог',      'COUNT_AS_UNICORN'),
    ('Единорог-гроза',      'COUNT_AS_UNICORN'),
    ('Единорог-гроза',      'DESTROY_IN_STABLE'),
    ('Единорог-похититель', 'COUNT_AS_UNICORN'),
    ('Единорог-похититель', 'STEAL_FROM_STABLE'),
    ('Единорог-питомец',    'COUNT_AS_UNICORN'),
    ('Единорог-питомец',    'DRAW_FROM_DECK'),
    ('Щит стойла',          'PROTECT_STABLE'),
    ('Оковы',               'RESTRICT_CARD_PLAY'),
    ('Якорь',               'SKIP_PLAYER_TURN'),
    ('Сортировщик',         'SEARCH_IN_DECK'),
    ('Сортировщик',         'MOVE_TO_DISCARD'),
    ('Возврат',             'SEARCH_IN_DISCARD'),
    ('Возврат',             'MOVE_TO_DISCARD'),
    ('Мусорщик',            'SACRIFICE_FROM_STABLE'),
    ('Мусорщик',            'MOVE_TO_DISCARD'),
    ('Перемешивание',       'SHUFFLE_DECK'),
    ('Перемешивание',       'MOVE_TO_DISCARD')
) AS v(card_name, code)
  ON v.card_name = nt.card_name
JOIN mechanics m ON m.mechanic_name = v.code::mechanic_name_enum;
