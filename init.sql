-- =========================================================
-- ENUMS
-- =========================================================

CREATE TYPE mechanic_name_enum AS ENUM (
    'MOVE_TO_DECK',
    'MOVE_TO_HAND',
    'MOVE_TO_STABLE',
    'MOVE_TO_DISCARD',
    'MOVE_TO_NURSERY',
    'DRAW_FROM_DECK',
    'DISCARD_FROM_HAND',
    'SACRIFICE_FROM_STABLE',
    'DESTROY_IN_STABLE',
    'STEAL_FROM_STABLE',
    'SEARCH_IN_DECK',
    'SEARCH_IN_DISCARD',
    'SHUFFLE_DECK',
    'SKIP_PLAYER_TURN',
    'PROTECT_STABLE',
    'RESTRICT_CARD_PLAY',
    'TRIGGER_ON_TURN_START',
    'TRIGGER_ON_ENTER_STABLE',
    'TRIGGER_ON_LEAVE_STABLE',
    'COUNT_AS_UNICORN'
    );

CREATE TYPE mechanic_type_enum AS ENUM (
    'active',
    'passive'
    );

-- =========================================================
-- GAMES
-- =========================================================
CREATE TABLE games (
    id_game           BIGSERIAL PRIMARY KEY,
    move_status       BOOLEAN NOT NULL,
    number_of_players INT NOT NULL CHECK (number_of_players BETWEEN 0 AND 6)
);

-- =========================================================
-- PLAYERS
-- =========================================================
CREATE TABLE players (
    id_player   BIGSERIAL PRIMARY KEY,
    id_game     BIGINT NOT NULL,
    move_order  INT NOT NULL,
    user_id     UUID NOT NULL,
    is_admin    BOOLEAN NOT NULL,

    CONSTRAINT fk_players_game
    FOREIGN KEY (id_game)
    REFERENCES games(id_game)
    ON DELETE CASCADE,

    -- игрок уникален в рамках игры
    CONSTRAINT uq_players_game_user UNIQUE (id_game, user_id),
    CONSTRAINT uq_players_game_order UNIQUE (id_game, move_order)
);

-- =========================================================
-- CARD TEMPLATES
-- =========================================================
CREATE TABLE card_templates (
    id_card_template BIGSERIAL PRIMARY KEY,
    card_name        VARCHAR(128) NOT NULL,
    card_description TEXT NOT NULL,
    img_link         VARCHAR(512) NOT NULL,

    CONSTRAINT uq_card_templates_img UNIQUE (img_link)
);

-- =========================================================
-- MECHANICS
-- =========================================================
CREATE TABLE mechanics (
    id_mechanic   BIGSERIAL PRIMARY KEY,
    mechanic_name mechanic_name_enum NOT NULL,
    mechanic_type mechanic_type_enum NOT NULL,

    CONSTRAINT uq_mechanic_name UNIQUE (mechanic_name)
);

-- =========================================================
-- TEMPLATE_MECHANICS (M:N)
-- =========================================================
CREATE TABLE template_mechanics (
    id_mechanic       BIGINT NOT NULL,
    id_card_template  BIGINT NOT NULL,

    PRIMARY KEY (id_mechanic, id_card_template),

    CONSTRAINT fk_tm_mechanic
    FOREIGN KEY (id_mechanic)
    REFERENCES mechanics(id_mechanic)
    ON DELETE CASCADE,

    CONSTRAINT fk_tm_template
    FOREIGN KEY (id_card_template)
    REFERENCES card_templates(id_card_template)
    ON DELETE CASCADE
);

-- =========================================================
-- CARDS (экземпляры карт в игре)
-- =========================================================
CREATE TABLE cards (
    id_card          BIGSERIAL PRIMARY KEY,
    id_game          BIGINT NOT NULL,
    id_card_template BIGINT NOT NULL,

    CONSTRAINT fk_cards_game
    FOREIGN KEY (id_game)
    REFERENCES games(id_game)
    ON DELETE CASCADE,

    CONSTRAINT fk_cards_template
    FOREIGN KEY (id_card_template)
    REFERENCES card_templates(id_card_template)
    ON DELETE RESTRICT
);

-- =========================================================
-- PASSWORDS
-- =========================================================
CREATE TABLE passwords (
    id_game       BIGINT PRIMARY KEY,
    password_hash VARCHAR(512) NOT NULL,

    CONSTRAINT fk_passwords_game
    FOREIGN KEY (id_game)
    REFERENCES games(id_game)
    ON DELETE CASCADE
);

-- =========================================================
-- MOVES
-- =========================================================
CREATE TABLE moves (
    id_move     BIGSERIAL PRIMARY KEY,
    id_player   BIGINT NOT NULL,
    move_number INT NOT NULL CHECK (move_number > 0),

    CONSTRAINT fk_moves_player
    FOREIGN KEY (id_player)
    REFERENCES players(id_player)
    ON DELETE RESTRICT,

    -- уникальность хода игрока
    CONSTRAINT uq_player_move UNIQUE (id_player, move_number)
);

-- =========================================================
-- CARDS IN MOVES
-- =========================================================
CREATE TABLE cards_in_moves (
    id_move BIGINT NOT NULL,
    id_card BIGINT NOT NULL,

    PRIMARY KEY (id_move, id_card),

    CONSTRAINT fk_cim_move
    FOREIGN KEY (id_move)
    REFERENCES moves(id_move)
    ON DELETE CASCADE,

    CONSTRAINT fk_cim_card
    FOREIGN KEY (id_card)
    REFERENCES cards(id_card)
    ON DELETE CASCADE
);

-- =========================================================
-- DISCARD
-- =========================================================
CREATE TABLE discard (
    id_card  BIGINT PRIMARY KEY,
    position INT NOT NULL CHECK (position > 0),

    CONSTRAINT fk_discard_card
    FOREIGN KEY (id_card)
    REFERENCES cards(id_card)
    ON DELETE CASCADE
);

-- =========================================================
-- PLAYER CARDS
-- =========================================================
CREATE TABLE player_cards (
    id_player BIGINT NOT NULL,
    id_card   BIGINT NOT NULL,
    is_public BOOLEAN NOT NULL,

    PRIMARY KEY (id_player, id_card),

    CONSTRAINT fk_pc_player
    FOREIGN KEY (id_player)
    REFERENCES players(id_player)
    ON DELETE CASCADE,

    CONSTRAINT fk_pc_card
    FOREIGN KEY (id_card)
    REFERENCES cards(id_card)
    ON DELETE CASCADE
);