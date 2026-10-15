# Функции БД

24 функции разложены по трём файлам-доменам (совпадают с потоками в [`diagrams/`](../diagrams)) и грузятся по порядку номеров:

| Домен | Файл | Что внутри |
|---|---|---|
| Игра | [`db/20_functions_game.sql`](../db/20_functions_game.sql) | Хелперы чтения `_*`, снимок партии и примитивы записи |
| Лобби | [`db/21_functions_lobby.sql`](../db/21_functions_lobby.sql) | Список партий, создание/вход/выход, настройки |
| Админка и каталог | [`db/22_functions_admin.sql`](../db/22_functions_admin.sql) | Справочник механик, каталог шаблонов, наполнение колод |

Порядок загрузки важен: `20_functions_game.sql` идёт первым (на его хелперы опираются лобби и админка), затем `21_functions_lobby.sql`, затем `22_functions_admin.sql`.

База - тупое хранилище: кодов ошибок и проверок правил в SQL нет. Все `fn_*` только читают, все `sp_*` только пишут, а осмысленные HTTP-коды расставляет сервер (см. [`API.md`](../API.md)).

## Полный индекс

`№` — нумерация внутри файла. Имя функции ведёт на её определение, домен — на файл с описанием.

### Игра — [`game.md`](game.md)

| № | Функция | № | Функция |
|---|---|---|---|
| 1 | [`_template_mechanics`](../db/20_functions_game.sql#L40) | 6 | [`sp_move_card`](../db/20_functions_game.sql#L172) |
| 2 | [`_cards_in_zone`](../db/20_functions_game.sql#L51) | 7 | [`sp_draw`](../db/20_functions_game.sql#L189) |
| 3 | [`_hand`](../db/20_functions_game.sql#L78) | 8 | [`sp_record_move`](../db/20_functions_game.sql#L209) |
| 4 | [`_game_summary`](../db/20_functions_game.sql#L92) | 9 | [`sp_set_game_started`](../db/20_functions_game.sql#L220) |
| 5 | [`fn_get_game_state`](../db/20_functions_game.sql#L113) | | |

### Лобби — [`lobby.md`](lobby.md)

| № | Функция | № | Функция |
|---|---|---|---|
| 1 | [`fn_get_player`](../db/21_functions_lobby.sql#L17) | 6 | [`sp_leave_game`](../db/21_functions_lobby.sql#L103) |
| 2 | [`fn_list_open_games`](../db/21_functions_lobby.sql#L31) | 7 | [`sp_set_game_seats`](../db/21_functions_lobby.sql#L128) |
| 3 | [`fn_get_game_password`](../db/21_functions_lobby.sql#L51) | 8 | [`sp_set_game_password`](../db/21_functions_lobby.sql#L135) |
| 4 | [`sp_create_game`](../db/21_functions_lobby.sql#L58) | 9 | [`sp_cancel_game`](../db/21_functions_lobby.sql#L145) |
| 5 | [`sp_join_game`](../db/21_functions_lobby.sql#L81) | | |

### Админка и каталог — [`admin.md`](admin.md)

| № | Функция | № | Функция |
|---|---|---|---|
| 1 | [`fn_list_mechanics`](../db/22_functions_admin.sql#L15) | 4 | [`sp_upsert_card_template`](../db/22_functions_admin.sql#L87) |
| 2 | [`fn_list_card_templates`](../db/22_functions_admin.sql#L50) | 5 | [`sp_set_card_mechanics`](../db/22_functions_admin.sql#L115) |
| 3 | [`fn_get_card_template`](../db/22_functions_admin.sql#L72) | 6 | [`sp_add_cards_to_game`](../db/22_functions_admin.sql#L129) |
