# Функции БД

Все функции живут в [`db/20_functions.sql`](../db/20_functions.sql) — 44 штуки. Разбиты по доменам, как потоки в [`diagrams/`](../diagrams):

| Домен | Файл | Что внутри |
|---|---|---|
| Игра | [`game.md`](game.md) | Внутренние хелперы `_*` и ход партии |
| Лобби | [`lobby.md`](lobby.md) | Список партий, создание/вход/выход, настройки |
| Админка и каталог | [`admin.md`](admin.md) | Справочник механик, каталог шаблонов, наполнение колод |

Коды ошибок (`SQLSTATE` → HTTP на сервере): `ED001`→404, `ED002`→403, `ED003`→409, `ED004`→422.

## Полный индекс

`№` — сквозная нумерация по файлу. Имя функции ведёт на её определение, домен — на файл с описанием.

| № | Функция | Домен |
|---|---|---|
| 1 | [`_card_mechanics`](../db/20_functions.sql#L50) | [game](game.md) |
| 2 | [`_has_mechanic`](../db/20_functions.sql#L60) | [game](game.md) |
| 3 | [`_template_mechanics`](../db/20_functions.sql#L74) | [game](game.md) |
| 4 | [`_move_card`](../db/20_functions.sql#L88) | [game](game.md) |
| 5 | [`_cards_in_zone`](../db/20_functions.sql#L126) | [game](game.md) |
| 6 | [`_hand`](../db/20_functions.sql#L153) | [game](game.md) |
| 7 | [`_game_started`](../db/20_functions.sql#L168) | [game](game.md) |
| 8 | [`_finished`](../db/20_functions.sql#L175) | [game](game.md) |
| 9 | [`_game_summary`](../db/20_functions.sql#L182) | [game](game.md) |
| 10 | [`_lock_game`](../db/20_functions.sql#L199) | [game](game.md) |
| 11 | [`_lock_turn`](../db/20_functions.sql#L214) | [game](game.md) |
| 12 | [`_require_not_started`](../db/20_functions.sql#L225) | [game](game.md) |
| 13 | [`_require_host`](../db/20_functions.sql#L235) | [game](game.md) |
| 14 | [`_require_enemy_stable_target`](../db/20_functions.sql#L247) | [game](game.md) |
| 15 | [`_player_status`](../db/20_functions.sql#L269) | [game](game.md) |
| 16 | [`_next_player`](../db/20_functions.sql#L293) | [game](game.md) |
| 17 | [`_current_player`](../db/20_functions.sql#L305) | [game](game.md) |
| 18 | [`_turn_number`](../db/20_functions.sql#L318) | [game](game.md) |
| 19 | [`_record_move`](../db/20_functions.sql#L328) | [game](game.md) |
| 20 | [`_fire_leave_stable`](../db/20_functions.sql#L338) | [game](game.md) |
| 21 | [`_draw`](../db/20_functions.sql#L370) | [game](game.md) |
| 22 | [`_apply_active_mechanics`](../db/20_functions.sql#L396) | [game](game.md) |
| 23 | [`_apply_play`](../db/20_functions.sql#L487) | [game](game.md) |
| 24 | [`_available`](../db/20_functions.sql#L537) | [game](game.md) |
| 25 | [`fn_get_player`](../db/20_functions.sql#L587) | [lobby](lobby.md) |
| 26 | [`fn_list_open_games`](../db/20_functions.sql#L599) | [lobby](lobby.md) |
| 27 | [`fn_get_game_state`](../db/20_functions.sql#L618) | [game](game.md) |
| 28 | [`fn_check_victory`](../db/20_functions.sql#L691) | [game](game.md) |
| 29 | [`fn_list_mechanics`](../db/20_functions.sql#L751) | [admin](admin.md) |
| 30 | [`fn_list_card_templates`](../db/20_functions.sql#L785) | [admin](admin.md) |
| 31 | [`fn_get_card_template`](../db/20_functions.sql#L806) | [admin](admin.md) |
| 32 | [`sp_upsert_card_template`](../db/20_functions.sql#L829) | [admin](admin.md) |
| 33 | [`sp_set_card_mechanics`](../db/20_functions.sql#L860) | [admin](admin.md) |
| 34 | [`sp_add_cards_to_game`](../db/20_functions.sql#L881) | [admin](admin.md) |
| 35 | [`sp_create_game`](../db/20_functions.sql#L906) | [lobby](lobby.md) |
| 36 | [`sp_join_game`](../db/20_functions.sql#L937) | [lobby](lobby.md) |
| 37 | [`sp_leave_game`](../db/20_functions.sql#L979) | [lobby](lobby.md) |
| 38 | [`sp_update_game`](../db/20_functions.sql#L1008) | [lobby](lobby.md) |
| 39 | [`sp_set_game_password`](../db/20_functions.sql#L1049) | [lobby](lobby.md) |
| 40 | [`sp_cancel_game`](../db/20_functions.sql#L1067) | [lobby](lobby.md) |
| 41 | [`sp_start_game`](../db/20_functions.sql#L1083) | [game](game.md) |
| 42 | [`sp_begin_turn`](../db/20_functions.sql#L1121) | [game](game.md) |
| 43 | [`sp_apply_event`](../db/20_functions.sql#L1172) | [game](game.md) |
| 44 | [`sp_end_turn`](../db/20_functions.sql#L1209) | [game](game.md) |
