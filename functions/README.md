# Функции БД

Все функции живут в [`db/20_functions.sql`](../db/20_functions.sql) — 41 штука. Разбиты по доменам, как потоки в [`diagrams/`](../diagrams):

| Домен | Файл | Что внутри |
|---|---|---|
| Внутренние хелперы | [`helpers.md`](helpers.md) | 21 служебная `_*` (перемещение карт, ход, триггеры, эффекты) |
| Логин и каталог | [`auth.md`](auth.md) | Публичные чтения `fn_list_mechanics`, `fn_list_card_templates` |
| Лобби | [`lobby.md`](lobby.md) | `fn_get_player`, `fn_list_open_games` и настройки партии |
| Игра | [`game.md`](game.md) | Снимок состояния, победа, старт и ход |
| Админка | [`admin.md`](admin.md) | Библиотека карт: шаблоны, механики, наполнение колод |

Коды ошибок (`SQLSTATE` → HTTP на сервере): `ED001`→404, `ED002`→403, `ED003`→409, `ED004`→422.

## Полный индекс

`№` — сквозная нумерация по файлу. Имя функции ведёт на её определение, домен — на файл с описанием.

| № | Функция | Домен |
|---|---|---|
| 1 | [`_card_mechanics`](../db/20_functions.sql#L49) | [helpers](helpers.md) |
| 2 | [`_has_mechanic`](../db/20_functions.sql#L59) | [helpers](helpers.md) |
| 3 | [`_move_card`](../db/20_functions.sql#L74) | [helpers](helpers.md) |
| 4 | [`_cards_in_zone`](../db/20_functions.sql#L102) | [helpers](helpers.md) |
| 5 | [`_game_lock`](../db/20_functions.sql#L130) | [helpers](helpers.md) |
| 6 | [`_game_started`](../db/20_functions.sql#L141) | [helpers](helpers.md) |
| 7 | [`_lock_started`](../db/20_functions.sql#L147) | [helpers](helpers.md) |
| 8 | [`_player_status`](../db/20_functions.sql#L159) | [helpers](helpers.md) |
| 9 | [`_last_mover`](../db/20_functions.sql#L172) | [helpers](helpers.md) |
| 10 | [`_next_player`](../db/20_functions.sql#L183) | [helpers](helpers.md) |
| 11 | [`_current_player`](../db/20_functions.sql#L195) | [helpers](helpers.md) |
| 12 | [`_turn_number`](../db/20_functions.sql#L201) | [helpers](helpers.md) |
| 13 | [`_record_move`](../db/20_functions.sql#L210) | [helpers](helpers.md) |
| 14 | [`_trigger_depth`](../db/20_functions.sql#L220) | [helpers](helpers.md) |
| 15 | [`_fire_leave_stable`](../db/20_functions.sql#L226) | [helpers](helpers.md) |
| 16 | [`_draw`](../db/20_functions.sql#L258) | [helpers](helpers.md) |
| 17 | [`_apply_active_mechanics`](../db/20_functions.sql#L284) | [helpers](helpers.md) |
| 18 | [`_final_zone`](../db/20_functions.sql#L395) | [helpers](helpers.md) |
| 19 | [`_apply_play`](../db/20_functions.sql#L423) | [helpers](helpers.md) |
| 20 | [`_fire_turn_start`](../db/20_functions.sql#L453) | [helpers](helpers.md) |
| 21 | [`_available`](../db/20_functions.sql#L467) | [helpers](helpers.md) |
| 22 | [`fn_get_player`](../db/20_functions.sql#L511) | [lobby](lobby.md) |
| 23 | [`fn_list_open_games`](../db/20_functions.sql#L523) | [lobby](lobby.md) |
| 24 | [`fn_get_game_state`](../db/20_functions.sql#L545) | [game](game.md) |
| 25 | [`fn_check_victory`](../db/20_functions.sql#L620) | [game](game.md) |
| 26 | [`fn_list_mechanics`](../db/20_functions.sql#L674) | [auth](auth.md) |
| 27 | [`fn_list_card_templates`](../db/20_functions.sql#L708) | [auth](auth.md) |
| 28 | [`fn_get_card_template`](../db/20_functions.sql#L733) | [admin](admin.md) |
| 29 | [`sp_upsert_card_template`](../db/20_functions.sql#L759) | [admin](admin.md) |
| 30 | [`sp_set_card_mechanics`](../db/20_functions.sql#L791) | [admin](admin.md) |
| 31 | [`sp_add_cards_to_game`](../db/20_functions.sql#L816) | [admin](admin.md) |
| 32 | [`sp_create_game`](../db/20_functions.sql#L843) | [lobby](lobby.md) |
| 33 | [`sp_join_game`](../db/20_functions.sql#L872) | [lobby](lobby.md) |
| 34 | [`sp_leave_game`](../db/20_functions.sql#L916) | [lobby](lobby.md) |
| 35 | [`sp_update_game`](../db/20_functions.sql#L940) | [lobby](lobby.md) |
| 36 | [`sp_cancel_game`](../db/20_functions.sql#L989) | [lobby](lobby.md) |
| 37 | [`sp_start_game`](../db/20_functions.sql#L1010) | [game](game.md) |
| 38 | [`sp_begin_turn`](../db/20_functions.sql#L1049) | [game](game.md) |
| 39 | [`sp_skip_turn`](../db/20_functions.sql#L1086) | [game](game.md) |
| 40 | [`sp_apply_event`](../db/20_functions.sql#L1103) | [game](game.md) |
| 41 | [`sp_end_turn`](../db/20_functions.sql#L1141) | [game](game.md) |
