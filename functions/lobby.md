# Лобби

Создание партии, вход/выход, настройки и список открытых партий — [`diagrams/lobby.mmd`](../diagrams/lobby.mmd).

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_get_player`](../db/20_functions.sql#L470) | `p_user_id uuid` | `jsonb` | Возвращает места пользователя (партия, `id_player`, порядок, хост) | Определить, в каких партиях пользователь |
| 2 | [`fn_list_open_games`](../db/20_functions.sql#L482) | `p_has_slot boolean DEFAULT TRUE, p_mine boolean DEFAULT FALSE, p_id_user uuid DEFAULT NULL, p_search text DEFAULT NULL` | `jsonb` | Список партий; фильтр по свободным местам, по «только мои», поиск по номеру/имени партии | Экран лобби |
| 3 | [`sp_create_game`](../db/20_functions.sql#L806) | `p_user_id uuid, p_name text, p_max_players int, p_password_hash text DEFAULT NULL` | `jsonb` | Создаёт партию (мест 2..6) и сажает создателя хостом; вне диапазона → `ED004` | Создание партии |
| 4 | [`sp_join_game`](../db/20_functions.sql#L835) | `p_user_id uuid, p_id_game bigint, p_password_hash text DEFAULT NULL` | `jsonb` | Вход игрока (или возврат на место); неверный/отсутствующий пароль → `ED002`, нет места или старт → `ED003` | Присоединение к партии |
| 5 | [`sp_leave_game`](../db/20_functions.sql#L879) | `p_id_player bigint, p_id_game bigint` | `void` | До старта — удаляет место; в игре — сохраняет место, руку в сброс; чужой игрок → `ED002` | Выход из партии |
| 6 | [`sp_update_game`](../db/20_functions.sql#L903) | `p_id_game bigint, p_id_user uuid, p_name text DEFAULT NULL, p_max_players int DEFAULT NULL, p_password_hash text DEFAULT NULL` | `jsonb` | Меняет лимит мест (имя синтетическое, игнор) и пароль (пусто → снять); не хост → `ED002`, старт → `ED003`, плохой лимит → `ED004` | Настройки партии и пароль |
| 7 | [`sp_cancel_game`](../db/20_functions.sql#L952) | `p_id_game bigint, p_id_user uuid` | `void` | Удаляет партию; не хост → `ED002`, старт → `ED003` | Отмена партии |
