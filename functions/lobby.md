# Лобби

Создание партии, вход/выход, настройки и список открытых партий — [`diagrams/lobby.mmd`](../diagrams/lobby.mmd). Свободные места, пароль, права хоста и признак «партия началась» проверяет сервер; сюда приходят уже готовые решения. Файл [`db/21_functions_lobby.sql`](../db/21_functions_lobby.sql).

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_get_player`](../db/21_functions_lobby.sql#L17) | `p_user_id uuid` | `jsonb` | Места пользователя: в каких партиях он сидит (партия, `id_player`, порядок, хост) | Определить, в каких партиях пользователь |
| 2 | [`fn_list_open_games`](../db/21_functions_lobby.sql#L31) | `p_has_slot boolean DEFAULT TRUE, p_mine boolean DEFAULT FALSE, p_id_user uuid DEFAULT NULL, p_search text DEFAULT NULL` | `jsonb` | Список карточек партий (`_game_summary`); фильтр по свободным местам, по «только мои», поиск по номеру/имени партии | Экран лобби |
| 3 | [`fn_get_game_password`](../db/21_functions_lobby.sql#L51) | `p_id_game bigint` | `text` | Хеш пароля партии или `NULL`, если пароля нет | Сервер сравнивает пароль сам |
| 4 | [`sp_create_game`](../db/21_functions_lobby.sql#L58) | `p_user_id uuid, p_max_players int, p_password_hash text DEFAULT NULL` | `jsonb` | Создаёт партию и сажает создателя хостом; имя синтетическое `Партия #<id>`. Возвращает `{ game_id, player_id, is_host }`. Число мест не проверяет | Создание партии |
| 5 | [`sp_join_game`](../db/21_functions_lobby.sql#L81) | `p_user_id uuid, p_id_game bigint` | `jsonb` | Сажает игрока (или возвращает ему его же место при повторном вызове); отдаёт `{ player_id, is_host, hand }`. Пароль, место и старт проверяет сервер | Присоединение к партии |
| 6 | [`sp_leave_game`](../db/21_functions_lobby.sql#L103) | `p_id_player bigint` | `void` | До старта удаляет место (карты уходят каскадом); в игре сохраняет место и лог ходов, а руку отправляет в сброс. Оба правила включаются флагом `move_status` | Выход из партии |
| 7 | [`sp_set_game_seats`](../db/21_functions_lobby.sql#L128) | `p_id_game bigint, p_max_players int` | `void` | Меняет максимум мест партии. Диапазон и сравнение с занятыми — на сервере | Настройка мест |
| 8 | [`sp_set_game_password`](../db/21_functions_lobby.sql#L135) | `p_id_game bigint, p_password_hash text` | `void` | Ставит пароль партии или снимает его (`NULL`) | Пароль партии |
| 9 | [`sp_cancel_game`](../db/21_functions_lobby.sql#L145) | `p_id_game bigint` | `void` | Удаляет партию с игроками и картами (каскад); лог ходов чистится первым (RESTRICT на игроках) | Отмена партии |
