# Игра

Хелперы чтения `_*`, снимок партии и примитивы записи — [`diagrams/game.mmd`](../diagrams/game.mmd), файл [`db/20_functions_game.sql`](../db/20_functions_game.sql). Верхние строки (`_*`) служебные: их зовут только другие функции БД, в публичный API они не входят. Чей ход, победу, единорогов, доступные карты и эффекты механик считает сервер; SQL здесь только читает и пишет данные.

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`_template_mechanics`](../db/20_functions_game.sql#L40) | `p_id_template bigint` | `jsonb` | Механики шаблона как jsonb-массив кодов | Единый формат механик для каталога и снимка партии |
| 2 | [`_cards_in_zone`](../db/20_functions_game.sql#L51) | `p_id_game bigint, p_zone text, p_id_player bigint DEFAULT NULL` | `SETOF bigint` | Список карт зоны: `hand`/`stable` (для игрока), `deck` (остаток колоды), `discard` (сброс партии) | Один примитив вместо `_hand`/`_stable`/`_deck_card_ids` |
| 3 | [`_hand`](../db/20_functions_game.sql#L78) | `p_id_player bigint` | `jsonb` | Рука игрока: карты (`is_public = FALSE`) с `card_id`, `template_id`, именем | Снимок руки в `fn_get_game_state` и возврат из `sp_join_game` |
| 4 | [`_game_summary`](../db/20_functions_game.sql#L92) | `p_id_game bigint` | `jsonb` | Карточка партии: `id`, `name`, места, занято, нужен ли пароль, началась ли | Единый формат партии для лобби и ответов на настройки |
| 5 | [`fn_get_game_state`](../db/20_functions_game.sql#L113) | `p_id_game bigint, p_id_player bigint DEFAULT NULL` | `jsonb` | Сырое состояние партии: партия, игроки со стойлами и механиками карт, колода, сброс, лог ходов. Руку отдаёт только запрошенному игроку. Ничего не считает. Нет партии → `NULL` | Основной снимок игры для клиента |
| 6 | [`sp_move_card`](../db/20_functions_game.sql#L172) | `p_id_player bigint, p_id_card bigint, p_zone text` | `void` | Перемещает карту в `hand`/`stable`/`deck`/`discard`. Зона `deck` — изъятие из текущей зоны; для `hand`/`stable` нужен игрок, для `deck`/`discard` он игнорируется. Ничего не проверяет | Один примитив перемещения карты |
| 7 | [`sp_draw`](../db/20_functions_game.sql#L189) | `p_id_game bigint, p_id_player bigint` | `bigint` | Кладёт случайную карту колоды в руку игрока и возвращает её id; колода пуста → `NULL` | Добор карт |
| 8 | [`sp_record_move`](../db/20_functions_game.sql#L209) | `p_id_player bigint` | `void` | Записывает завершённый ход игрока (`move_number = max по игроку + 1`) | Фиксация ходов в логе |
| 9 | [`sp_set_game_started`](../db/20_functions_game.sql#L220) | `p_id_game bigint, p_started boolean` | `void` | Поднимает или опускает флаг «партия началась». Раздачей карт занимается сервер | Начало игры |
