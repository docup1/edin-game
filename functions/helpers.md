# Внутренние хелперы

Служебные функции `_*` из [`db/20_functions.sql`](../db/20_functions.sql). В публичный API не входят — их вызывают только другие функции БД. `№` — сквозная нумерация по файлу.

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`_card_mechanics`](../db/20_functions.sql#L49) | `p_id_card bigint` | `SETOF mechanic_name_enum` | Возвращает механики карты через её шаблон (`template_mechanics`) | Проверка и применение эффектов карты |
| 2 | [`_has_mechanic`](../db/20_functions.sql#L59) | `p_id_card bigint, p_name mechanic_name_enum` | `boolean` | Есть ли у карты указанная механика | Условия на механики (победа, защита, триггеры) |
| 3 | [`_move_card`](../db/20_functions.sql#L74) | `p_id_player bigint, p_id_card bigint, p_zone text` | `void` | Универсальное перемещение карты в `hand`/`stable`/`deck`/`discard` без запуска leave-триггера | Один примитив вместо `_to_hand`/`_to_stable`/`_to_deck`/`_discard_card` |
| 4 | [`_cards_in_zone`](../db/20_functions.sql#L102) | `p_id_game bigint, p_zone text, p_id_player bigint DEFAULT NULL` | `SETOF bigint` | Универсальный список карт зоны: `hand`/`stable` (для игрока), `deck` (остаток колоды), `discard` (сброс партии) | Один примитив вместо `_hand`/`_stable`/`_deck_card_ids` |
| 5 | [`_game_lock`](../db/20_functions.sql#L130) | `p_id_game bigint` | `void` | Берёт строку партии под `FOR UPDATE`; если партии нет — `ED001` | Сериализует конкурентные изменения одной партии |
| 6 | [`_game_started`](../db/20_functions.sql#L141) | `p_id_game bigint` | `boolean` | Читает `games.move_status` | Единая проверка «партия уже началась» |
| 7 | [`_lock_started`](../db/20_functions.sql#L147) | `p_id_game bigint` | `void` | Берёт партию под `FOR UPDATE` и требует, что она началась; нет партии → `ED001`, не началась → `ED003` | Общий пролог изменяющих игру функций |
| 8 | [`_player_status`](../db/20_functions.sql#L159) | `p_id_player bigint` | `jsonb` | Сводка стойла одним запросом: `unicorns`, `protected` (`PROTECT_STABLE`), `restricted` (`RESTRICT_CARD_PLAY`) | Замена `_player_unicorns`/`_is_protected`/`_is_restricted` |
| 9 | [`_last_mover`](../db/20_functions.sql#L172) | `p_id_game bigint` | `bigint` | Игрок последнего завершённого хода (`moves`) | База для вычисления текущего игрока |
| 10 | [`_next_player`](../db/20_functions.sql#L183) | `p_id_game bigint, p_id_player bigint` | `bigint` | Следующий игрок по `move_order` (циклично); при `NULL` — первый | Передача хода по кругу |
| 11 | [`_current_player`](../db/20_functions.sql#L195) | `p_id_game bigint` | `bigint` | Текущий игрок = следующий после последнего хода | Определение, чей сейчас ход |
| 12 | [`_turn_number`](../db/20_functions.sql#L201) | `p_id_game bigint` | `int` | Номер открытого хода = `count(moves по игре) + 1` | Проверка актуальности хода и счётчик |
| 13 | [`_record_move`](../db/20_functions.sql#L210) | `p_id_player bigint` | `void` | Записывает завершённый ход игрока (`max(move_number)+1`) | Фиксация хода `sp_end_turn`/`sp_skip_turn` |
| 14 | [`_trigger_depth`](../db/20_functions.sql#L220) | — | `int` | Возвращает текущую глубину каскада триггеров из `edin.trigger_depth` | Защита от бесконечной рекурсии триггеров |
| 15 | [`_fire_leave_stable`](../db/20_functions.sql#L226) | `p_id_card bigint` | `void` | Запускает `TRIGGER_ON_LEAVE_STABLE` при выходе карты из стойла (лимит глубины 5) | Срабатывание «выход из стойла» (зовётся явно только на DESTROY/SACRIFICE) |
| 16 | [`_draw`](../db/20_functions.sql#L258) | `p_id_game bigint, p_id_player bigint` | `bigint` | Берёт случайную карту из колоды в руку; `NULL`, если колода пуста | Добор карт |
| 17 | [`_apply_active_mechanics`](../db/20_functions.sql#L284) | `p_id_game bigint, p_actor bigint, p_id_card bigint, p_target bigint, p_lenient boolean` | `void` | Применяет активные механики карты (DRAW/DISCARD/SACRIFICE/DESTROY/STEAL/SEARCH/SHUFFLE/SKIP); в lenient-режиме ошибки — только warning | Исполнение эффектов карты |
| 18 | [`_final_zone`](../db/20_functions.sql#L395) | `p_id_card bigint` | `text` | По `MOVE_TO_*` определяет итоговую зону (`stable`/`deck`/`hand`/`discard`) | Куда положить сыгранную карту |
| 19 | [`_apply_play`](../db/20_functions.sql#L423) | `p_id_game bigint, p_actor bigint, p_id_card bigint, p_target bigint` | `void` | Разыгрывает карту: разовые эффекты → перемещение в зону → enter-триггер | Логика розыгрыша карты |
| 20 | [`_fire_turn_start`](../db/20_functions.sql#L453) | `p_id_game bigint, p_id_player bigint` | `void` | Запускает `TRIGGER_ON_TURN_START` у всех карт стойла игрока | Эффекты «начало хода» |
| 21 | [`_available`](../db/20_functions.sql#L467) | `p_id_game bigint, p_id_player bigint` | `jsonb` | Карты руки, доступные к розыгрышу, с флагом цели и списком целей; пусто, если не ваш ход или есть RESTRICT (приватный, отдаётся внутри `fn_get_game_state`) | Подсказка «что можно сыграть» |
