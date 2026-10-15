# Функции БД

Одна таблица со всеми функциями (`db/20_functions.sql`). Коды ошибок (`SQLSTATE`): `ED001`→404, `ED002`→403, `ED003`→409, `ED004`→422.

| Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|
| `_mechanic_description` | `p_name mechanic_name_enum` | `text` | Возвращает человекочитаемое описание механики по её enum-значению | Наполняет справочник механик (`fn_list_mechanics`) |
| `_game_lock` | `p_id_game bigint` | `void` | Берёт строку партии под `FOR UPDATE`; если партии нет — `ED001` | Сериализует конкурентные изменения одной партии |
| `_game_started` | `p_id_game bigint` | `boolean` | Читает `games.move_status` | Единая проверка «партия уже началась» |
| `_lock_started` | `p_id_game bigint` | `void` | Берёт партию под `FOR UPDATE` и требует, что она началась; нет партии → `ED001`, не началась → `ED003` | Общий пролог изменяющих игру функций |
| `_cards_in_zone` | `p_id_game bigint, p_zone text, p_id_player bigint DEFAULT NULL` | `SETOF bigint` | Универсальный список карт зоны: `hand`/`stable` (для игрока), `deck` (остаток колоды), `discard` (сброс партии) | Один примитив вместо `_hand`/`_stable`/`_deck_card_ids` |
| `_move_card` | `p_id_player bigint, p_id_card bigint, p_zone text` | `void` | Универсальное перемещение карты в `hand`/`stable`/`deck`/`discard` без запуска leave-триггера | Один примитив вместо `_to_hand`/`_to_stable`/`_to_deck`/`_discard_card` |
| `_card_mechanics` | `p_id_card bigint` | `SETOF mechanic_name_enum` | Возвращает механики карты через её шаблон (`template_mechanics`) | Проверка и применение эффектов карты |
| `_has_mechanic` | `p_id_card bigint, p_name mechanic_name_enum` | `boolean` | Есть ли у карты указанная механика | Условия на механики (победа, защита, триггеры) |
| `_player_unicorns` | `p_id_player bigint` | `int` | Считает карты в стойле с механикой `COUNT_AS_UNICORN` | Определение победителя и тай-брейк |
| `_is_protected` | `p_id_player bigint` | `boolean` | Есть ли в стойле механика `PROTECT_STABLE` | Запрет уничтожения/жертвы стойла |
| `_is_restricted` | `p_id_player bigint` | `boolean` | Есть ли в стойле механика `RESTRICT_CARD_PLAY` | Запрет игроку разыгрывать карты |
| `_last_mover` | `p_id_game bigint` | `bigint` | Игрок последнего завершённого хода (`moves`) | База для вычисления текущего игрока |
| `_next_player` | `p_id_game bigint, p_id_player bigint` | `bigint` | Следующий игрок по `move_order` (циклично); при `NULL` — первый | Передача хода по кругу |
| `_current_player` | `p_id_game bigint` | `bigint` | Текущий игрок = следующий после последнего хода | Определение, чей сейчас ход |
| `_turn_number` | `p_id_game bigint` | `int` | Номер открытого хода = `count(moves по игре) + 1` | Проверка актуальности хода и счётчик |
| `_record_move` | `p_id_player bigint` | `void` | Записывает завершённый ход игрока (`max(move_number)+1`) | Фиксация хода `sp_end_turn`/`sp_skip_turn` |
| `_notify` | `p_id_game bigint, p_event text` | `void` | Шлёт `pg_notify` в канал `edin_game` с id партии и событием | Реалтайм-оповещение сервера/клиентов |
| `_trigger_depth` | — | `int` | Возвращает текущую глубину каскада триггеров из `edin.trigger_depth` | Защита от бесконечной рекурсии триггеров |
| `_fire_leave_stable` | `p_id_card bigint` | `void` | Запускает `TRIGGER_ON_LEAVE_STABLE` при выходе карты из стойла (лимит глубины 5) | Срабатывание «выход из стойла» (зовётся явно только на DESTROY/SACRIFICE) |
| `_draw` | `p_id_game bigint, p_id_player bigint` | `bigint` | Берёт случайную карту из колоды в руку; `NULL`, если колода пуста | Добор карт |
| `_apply_active_mechanics` | `p_id_game bigint, p_actor bigint, p_id_card bigint, p_target bigint, p_lenient boolean` | `void` | Применяет активные механики карты (DRAW/DISCARD/SACRIFICE/DESTROY/STEAL/SEARCH/SHUFFLE/SKIP); в lenient-режиме ошибки — только warning | Исполнение эффектов карты |
| `_final_zone` | `p_id_card bigint` | `text` | По `MOVE_TO_*` определяет итоговую зону (`stable`/`deck`/`hand`/`discard`) | Куда положить сыгранную карту |
| `_apply_play` | `p_id_game bigint, p_actor bigint, p_id_card bigint, p_target bigint` | `void` | Разыгрывает карту: разовые эффекты → перемещение в зону → enter-триггер | Логика розыгрыша карты |
| `_fire_turn_start` | `p_id_game bigint, p_id_player bigint` | `void` | Запускает `TRIGGER_ON_TURN_START` у всех карт стойла игрока | Эффекты «начало хода» |
| `fn_get_player` | `p_user_id uuid` | `jsonb` | Возвращает места пользователя (партия, `id_player`, порядок, хост) | Определить, в каких партиях пользователь |
| `fn_list_open_games` | `p_has_slot boolean DEFAULT TRUE, p_mine boolean DEFAULT FALSE, p_id_user uuid DEFAULT NULL` | `jsonb` | Список партий; фильтр по свободным местам и по «только мои» | Экран лобби |
| `fn_get_catalog` | — | `jsonb` | Все шаблоны карт с их механиками | Каталог карт |
| `_available` | `p_id_game bigint, p_id_player bigint` | `jsonb` | Карты руки, доступные к розыгрышу, с флагом цели и списком целей; пусто, если не ваш ход или есть RESTRICT (приватный, отдаётся внутри `fn_get_game_state`) | Подсказка «что можно сыграть» |
| `fn_get_game_state` | `p_id_game bigint, p_id_player bigint DEFAULT NULL` | `jsonb` | Полное состояние: ход, текущий игрок, колода, сброс, игроки со стойлами, победа; плюс рука/доступные для конкретного игрока | Основной снимок игры для клиента |
| `fn_check_victory` | `p_id_game bigint` | `jsonb` | Победа по единорогам (порог 7 при 2–5 игроках, 6 при 6); при пустой колоде — тай-брейк по единорогам, затем по длине имён | Определение победителя |
| `fn_list_mechanics` | — | `jsonb` | Справочник механик (id, код, тип, описание) | Данные для админки |
| `fn_list_card_templates` | `p_search text DEFAULT NULL` | `jsonb` | Шаблоны с поиском по имени, описанию и коду механики | Поиск/список шаблонов |
| `fn_get_card_template` | `p_id bigint` | `jsonb` | Один шаблон с механиками; если нет — `ED001` | Просмотр шаблона |
| `fn_notify` | `p_id_game bigint, p_event text` | `void` | Публичная обёртка над `_notify` | Ручное оповещение по API |
| `sp_create_card_template` | `p_name text, p_description text, p_img_link text` | `jsonb` | Создаёт шаблон; дубликат `img_link` → `ED003` | Добавление карты в каталог |
| `sp_update_card_template` | `p_id bigint, p_name text, p_description text, p_img_link text` | `jsonb` | Правит поля шаблона; нет шаблона → `ED001`, дубль картинки → `ED003` | Редактирование карты |
| `sp_set_card_mechanics` | `p_id_template bigint, p_ids bigint[]` | `jsonb` | Полностью заменяет набор механик; нет шаблона → `ED001`, неизвестная механика → `ED004` | Назначение эффектов карте |
| `sp_add_cards_to_game` | `p_id_game bigint, p_id_template bigint, p_count int` | `jsonb` | Добавляет `p_count` карт шаблона в колоду до старта; старт → `ED003`, плохой шаблон/кол-во → `ED004` | Наполнение колоды партии |
| `sp_create_game` | `p_user_id uuid, p_name text, p_max_players int, p_password_hash text DEFAULT NULL` | `jsonb` | Создаёт партию (мест 2..6) и сажает создателя хостом; вне диапазона → `ED004` | Создание партии |
| `sp_join_game` | `p_user_id uuid, p_id_game bigint, p_password_hash text DEFAULT NULL` | `jsonb` | Вход игрока (или возврат на место); неверный/отсутствующий пароль → `ED002`, нет места или старт → `ED003` | Присоединение к партии |
| `sp_leave_game` | `p_id_player bigint, p_id_game bigint` | `void` | До старта — удаляет место; в игре — сохраняет место, руку в сброс; чужой игрок → `ED002` | Выход из партии |
| `sp_update_game` | `p_id_game bigint, p_id_user uuid, p_name text DEFAULT NULL, p_max_players int DEFAULT NULL, p_password_hash text DEFAULT NULL` | `jsonb` | Меняет лимит мест (имя синтетическое, игнор) и пароль; не хост → `ED002`, старт → `ED003`, плохой лимит → `ED004` | Настройки партии |
| `sp_cancel_game` | `p_id_game bigint, p_id_user uuid` | `void` | Удаляет партию; не хост → `ED002`, старт → `ED003` | Отмена партии |
| `sp_set_game_password` | `p_id_game bigint, p_password_hash text` | `void` | Ставит/снимает пароль партии; старт → `ED003` | Управление паролем |
| `sp_start_game` | `p_id_game bigint` | `jsonb` | Раздаёт по 5 карт (первому при открытии хода — 6), ставит `move_status`, открывает ход; повторный старт/мало игроков → `ED003`, мало карт → `ED004` | Начало игры |
| `sp_begin_turn` | `p_id_game bigint, p_skip_player bigint DEFAULT NULL` | `jsonb` | Открывает ход: определяет игрока (пропуская `p_skip_player`), добирает карту, запускает turn-start, отдаёт `available`; не началась → `ED003` | Открытие хода |
| `sp_skip_turn` | `p_id_game bigint` | `jsonb` | Фиксирует ход за текущим игроком и сразу открывает следующий; не началась → `ED003` | Пропуск хода |
| `sp_apply_event` | `p_id_game bigint, p_turn int, p_request_id text, p_do text, p_id_card bigint, p_target bigint DEFAULT NULL` | `void` | Разыгрывает или сбрасывает карту текущего игрока с проверками (номер хода, карта в руке, действие, цель). Актор не передаётся — это всегда текущий игрок; «не его ход» проверяет сервер. Устаревший номер хода → `ED003`, карты нет в руке → `ED004`, не участник партии → `ED002` | Игровое действие (204) |
| `sp_end_turn` | `p_id_game bigint, p_turn int` | `void` | Завершает ход текущего игрока: автосброс лишних (>7), фиксирует ход, внутри зовёт `sp_resolve_stable_effects`, затем `sp_begin_turn`; устаревший ход → `ED003` | Конец хода (204) |
| `sp_resolve_stable_effects` | `p_id_game bigint` | `jsonb` | Сводка эффектов по игрокам (protected/restricted/unicorns) | Пересчёт длительных эффектов конца хода |
| `sp_fire_turn_start` | `p_id_player bigint` | `void` | Вручную запускает turn-start триггеры игрока; нет игрока → `ED001` | Повторный запуск эффектов «начало хода» |
