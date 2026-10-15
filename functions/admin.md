# Админка и каталог

Библиотека карт: справочник механик, каталог шаблонов и наполнение колод — [`diagrams/admin.mmd`](../diagrams/admin.mmd). Реестр механик (`fn_list_mechanics`) и каталог (`fn_list_card_templates`) читаются публично (`GET /api/mechanics`, `GET /api/catalog`), остальные — только админ.

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_list_mechanics`](../db/20_functions.sql#L674) | — | `jsonb` | Справочник механик (id, код, тип, описание) | Данные для админки и публичного списка |
| 2 | [`fn_list_card_templates`](../db/20_functions.sql#L708) | `p_search text DEFAULT NULL` | `jsonb` | Шаблоны с поиском по имени, описанию и коду механики; без поиска — весь каталог | Каталог карт и поиск/список шаблонов |
| 3 | [`fn_get_card_template`](../db/20_functions.sql#L733) | `p_id bigint` | `jsonb` | Один шаблон с механиками; если нет — `ED001` | Просмотр шаблона |
| 4 | [`sp_upsert_card_template`](../db/20_functions.sql#L759) | `p_id bigint DEFAULT NULL, p_name text DEFAULT NULL, p_description text DEFAULT NULL, p_img_link text DEFAULT NULL` | `jsonb` | Создаёт шаблон (`p_id IS NULL`) или правит поля (`COALESCE`); нет шаблона → `ED001`, дубль картинки → `ED003`; возвращает объект шаблона | Создание и редактирование карты |
| 5 | [`sp_set_card_mechanics`](../db/20_functions.sql#L791) | `p_id_template bigint, p_ids bigint[]` | `jsonb` | Полностью заменяет набор механик; нет шаблона → `ED001`, неизвестная механика → `ED004` | Назначение эффектов карте |
| 6 | [`sp_add_cards_to_game`](../db/20_functions.sql#L816) | `p_id_game bigint, p_id_template bigint, p_count int` | `jsonb` | Добавляет `p_count` карт шаблона в колоду до старта; старт → `ED003`, плохой шаблон/кол-во → `ED004` | Наполнение колоды партии |
