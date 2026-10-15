# Функции БД

Все функции живут в [`db/20_functions.sql`](../db/20_functions.sql) — 36 штук. Разбиты по доменам, как потоки в [`diagrams/`](../diagrams):

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
| 1 | [`_card_mechanics`](../db/20_functions.sql#L48) | [game](game.md) |
| 2 | [`_has_mechanic`](../db/20_functions.sql#L58) | [game](game.md) |
| 3 | [`_move_card`](../db/20_functions.sql#L73) | [game](game.md) |
| 4 | [`_cards_in_zone`](../db/20_functions.sql#L101) | [game](game.md) |
| 5 | [`_game_started`](../db/20_functions.sql#L129) | [game](game.md) |
| 6 | [`_lock_game`](../db/20_functions.sql#L135) | [game](game.md) |
| 7 | [`_player_status`](../db/20_functions.sql#L151) | [game](game.md) |
| 8 | [`_next_player`](../db/20_functions.sql#L164) | [game](game.md) |
| 9 | [`_current_player`](../db/20_functions.sql#L176) | [game](game.md) |
| 10 | [`_turn_number`](../db/20_functions.sql#L190) | [game](game.md) |
| 11 | [`_record_move`](../db/20_functions.sql#L199) | [game](game.md) |
| 12 | [`_fire_leave_stable`](../db/20_functions.sql#L209) | [game](game.md) |
| 13 | [`_draw`](../db/20_functions.sql#L241) | [game](game.md) |
| 14 | [`_apply_active_mechanics`](../db/20_functions.sql#L267) | [game](game.md) |
| 15 | [`_apply_play`](../db/20_functions.sql#L378) | [game](game.md) |
| 16 | [`_available`](../db/20_functions.sql#L426) | [game](game.md) |
| 17 | [`fn_get_player`](../db/20_functions.sql#L470) | [lobby](lobby.md) |
| 18 | [`fn_list_open_games`](../db/20_functions.sql#L482) | [lobby](lobby.md) |
| 19 | [`fn_get_game_state`](../db/20_functions.sql#L508) | [game](game.md) |
| 20 | [`fn_check_victory`](../db/20_functions.sql#L583) | [game](game.md) |
| 21 | [`fn_list_mechanics`](../db/20_functions.sql#L637) | [admin](admin.md) |
| 22 | [`fn_list_card_templates`](../db/20_functions.sql#L671) | [admin](admin.md) |
| 23 | [`fn_get_card_template`](../db/20_functions.sql#L696) | [admin](admin.md) |
| 24 | [`sp_upsert_card_template`](../db/20_functions.sql#L722) | [admin](admin.md) |
| 25 | [`sp_set_card_mechanics`](../db/20_functions.sql#L754) | [admin](admin.md) |
| 26 | [`sp_add_cards_to_game`](../db/20_functions.sql#L779) | [admin](admin.md) |
| 27 | [`sp_create_game`](../db/20_functions.sql#L806) | [lobby](lobby.md) |
| 28 | [`sp_join_game`](../db/20_functions.sql#L835) | [lobby](lobby.md) |
| 29 | [`sp_leave_game`](../db/20_functions.sql#L879) | [lobby](lobby.md) |
| 30 | [`sp_update_game`](../db/20_functions.sql#L903) | [lobby](lobby.md) |
| 31 | [`sp_cancel_game`](../db/20_functions.sql#L952) | [lobby](lobby.md) |
| 32 | [`sp_start_game`](../db/20_functions.sql#L973) | [game](game.md) |
| 33 | [`sp_begin_turn`](../db/20_functions.sql#L1012) | [game](game.md) |
| 34 | [`sp_skip_turn`](../db/20_functions.sql#L1057) | [game](game.md) |
| 35 | [`sp_apply_event`](../db/20_functions.sql#L1074) | [game](game.md) |
| 36 | [`sp_end_turn`](../db/20_functions.sql#L1112) | [game](game.md) |
