-- =========================================================
-- СИД СПРАВОЧНИКА МЕХАНИК (20 штук)
-- Таблица mechanics не имеет name/description - только enum и тип.
-- Человекочитаемое имя = mechanic_name::text, описание отдаёт fn_list_mechanics.
-- =========================================================

INSERT INTO mechanics (mechanic_name, mechanic_type) VALUES
    ('MOVE_TO_DECK',            'active'),
    ('MOVE_TO_HAND',            'active'),
    ('MOVE_TO_STABLE',          'active'),
    ('MOVE_TO_DISCARD',         'active'),
    ('MOVE_TO_NURSERY',         'active'),
    ('DRAW_FROM_DECK',          'active'),
    ('DISCARD_FROM_HAND',       'active'),
    ('SACRIFICE_FROM_STABLE',   'active'),
    ('DESTROY_IN_STABLE',       'active'),
    ('STEAL_FROM_STABLE',       'active'),
    ('SEARCH_IN_DECK',          'active'),
    ('SEARCH_IN_DISCARD',       'active'),
    ('SHUFFLE_DECK',            'active'),
    ('SKIP_PLAYER_TURN',        'active'),
    ('PROTECT_STABLE',          'passive'),
    ('RESTRICT_CARD_PLAY',      'passive'),
    ('TRIGGER_ON_TURN_START',   'passive'),
    ('TRIGGER_ON_ENTER_STABLE', 'passive'),
    ('TRIGGER_ON_LEAVE_STABLE', 'passive'),
    ('COUNT_AS_UNICORN',        'passive')
ON CONFLICT (mechanic_name) DO NOTHING;
