# Админка и каталог

Библиотека карт: справочник механик, каталог шаблонов и наполнение колод — [`diagrams/admin.mmd`](../diagrams/admin.mmd). Реестр механик (`fn_list_mechanics`) и каталог (`fn_list_card_templates`) читаются публично (`GET /api/mechanics`, `GET /api/catalog`), остальные — только админ. Роль и допустимость действий проверяет сервер; файл [`db/22_functions_admin.sql`](../db/22_functions_admin.sql).

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_list_mechanics`](../db/22_functions_admin.sql#L15) | — | `jsonb` | Справочник механик (id, код, тип, описание) | Данные для админки и публичного списка |
| 2 | [`fn_list_card_templates`](../db/22_functions_admin.sql#L50) | `p_search text DEFAULT NULL` | `jsonb` | Шаблоны с механиками; поиск по имени, описанию и коду механики; без поиска — весь каталог | Каталог карт и поиск/список шаблонов |
| 3 | [`fn_get_card_template`](../db/22_functions_admin.sql#L72) | `p_id bigint` | `jsonb` | Один шаблон с механиками; если нет — `NULL` | Просмотр шаблона |
| 4 | [`sp_upsert_card_template`](../db/22_functions_admin.sql#L87) | `p_id bigint DEFAULT NULL, p_name text DEFAULT NULL, p_description text DEFAULT NULL, p_img_link text DEFAULT NULL` | `jsonb` | Создаёт шаблон (`p_id IS NULL`) или правит указанные поля (`COALESCE`); возвращает объект шаблона | Создание и редактирование карты |
| 5 | [`sp_set_card_mechanics`](../db/22_functions_admin.sql#L115) | `p_id_template bigint, p_ids bigint[]` | `jsonb` | Полностью заменяет набор механик шаблона; неизвестные id молча игнорируются | Назначение эффектов карте |
| 6 | [`sp_add_cards_to_game`](../db/22_functions_admin.sql#L129) | `p_id_game bigint, p_id_template bigint, p_count int` | `jsonb` | Добавляет `p_count` экземпляров карты в колоду партии; возвращает `{ added }` | Наполнение колоды партии |
