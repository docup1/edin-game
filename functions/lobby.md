# Лобби

Создание партии, вход/выход, настройки и список открытых партий — [`diagrams/lobby.mmd`](../diagrams/lobby.mmd).

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_get_player`](../db/20_functions.sql#L587) | `p_user_id uuid` | `jsonb` | Возвращает места пользователя (партия, `id_player`, порядок, хост) | Определить, в каких партиях пользователь |
| 2 | [`fn_list_open_games`](../db/20_functions.sql#L599) | `p_has_slot boolean DEFAULT TRUE, p_mine boolean DEFAULT FALSE, p_id_user uuid DEFAULT NULL, p_search text DEFAULT NULL` | `jsonb` | Список партий (карточка `_game_summary`); фильтр по свободным местам, по «только мои», поиск по номеру/имени партии | Экран лобби |
| 3 | [`sp_create_game`](../db/20_functions.sql#L906) | `p_user_id uuid, p_name text, p_max_players int, p_password_hash text DEFAULT NULL` | `jsonb` | Создаёт партию (мест 2..6) и сажает создателя хостом; вне диапазона → `ED004` | Создание партии |
| 4 | [`sp_join_game`](../db/20_functions.sql#L937) | `p_user_id uuid, p_id_game bigint, p_password_hash text DEFAULT NULL` | `jsonb` | Вход игрока (или возврат на место); отдаёт `player_id`, `hand` (реальная рука; до старта пусто), `is_host`; неверный/отсутствующий пароль → `ED002`, нет места или старт → `ED003` | Присоединение к партии |
| 5 | [`sp_leave_game`](../db/20_functions.sql#L979) | `p_id_player bigint, p_id_game bigint` | `void` | До старта — удаляет место; в игре — сохраняет место, руку в сброс; завершённая партия → `ED003`, чужой игрок → `ED002` | Выход из партии |
| 6 | [`sp_update_game`](../db/20_functions.sql#L1008) | `p_id_game bigint, p_id_user uuid, p_name text DEFAULT NULL, p_max_players int DEFAULT NULL, p_password_hash text DEFAULT NULL, p_password_set boolean DEFAULT FALSE` | `jsonb` | Меняет лимит мест (имя синтетическое, игнор); пароль трогает только при `p_password_set` (пусто → снять); не хост → `ED002`, старт → `ED003`, плохой лимит → `ED004` | Настройки партии |
| 7 | [`sp_set_game_password`](../db/20_functions.sql#L1049) | `p_id_game bigint, p_id_user uuid, p_password_hash text` | `void` | Ставит/снимает пароль (`NULL` → снять); не хост → `ED002`, старт → `ED003` | Пароль партии |
| 8 | [`sp_cancel_game`](../db/20_functions.sql#L1067) | `p_id_game bigint, p_id_user uuid` | `void` | Удаляет партию; не хост → `ED002`, старт → `ED003` | Отмена партии |
