# Админка

Библиотека карт и наполнение колод — [`diagrams/admin.mmd`](../diagrams/admin.mmd). Каталог и справочник механик читаются публичными [`fn_list_card_templates`](auth.md) и [`fn_list_mechanics`](auth.md) из `auth.md`.

| № | Функция | Принимает | Возвращает | Что делает | Зачем нужна |
|---|---|---|---|---|---|
| 1 | [`fn_get_card_template`](../db/20_functions.sql#L733) | `p_id bigint` | `jsonb` | Один шаблон с механиками; если нет — `ED001` | Просмотр шаблона |
| 2 | [`sp_upsert_card_template`](../db/20_functions.sql#L759) | `p_id bigint DEFAULT NULL, p_name text DEFAULT NULL, p_description text DEFAULT NULL, p_img_link text DEFAULT NULL` | `jsonb` | Создаёт шаблон (`p_id IS NULL`) или правит поля (`COALESCE`); нет шаблона → `ED001`, дубль картинки → `ED003`; возвращает объект шаблона | Создание и редактирование карты |
| 3 | [`sp_set_card_mechanics`](../db/20_functions.sql#L791) | `p_id_template bigint, p_ids bigint[]` | `jsonb` | Полностью заменяет набор механик; нет шаблона → `ED001`, неизвестная механика → `ED004` | Назначение эффектов карте |
| 4 | [`sp_add_cards_to_game`](../db/20_functions.sql#L816) | `p_id_game bigint, p_id_template bigint, p_count int` | `jsonb` | Добавляет `p_count` карт шаблона в колоду до старта; старт → `ED003`, плохой шаблон/кол-во → `ED004` | Наполнение колоды партии |
