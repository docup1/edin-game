# Документация архитектуры игры

Проект содержит **только документацию** сервер-авторитетной клиент-серверной архитектуры для карточной игры. Код бэкенда и OpenAPI не требуются.

## Цель

Спроектировать клиент-серверную архитектуру с доступом всех SQL-операций **только через веб-сервер** (прямой доступ клиента к PostgreSQL запрещён). PostgreSQL — единственный источник истины.

## Документы

| Документ | Описание |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Подробное описание архитектуры: компоненты, OIDC, REST+SSE, потоки, надёжность, конкурентность, ограничения схемы. |
| [`PROCEDURES.md`](PROCEDURES.md) | Каталог всех SQL-процедур и функций (`sp_*`, `fn_*`). Содержит параметры, проверки, возвращаемые значения, правила вызова, ошибки и последовательность транзакций. |
| [`diagrams/`](diagrams/) | Mermaid-диаграммы (.mmd). Валидированы через `@mermaid-js/mermaid-cli`. |

## Диаграммы

| № | Файл | Назначение |
|---|---|---|
| 01 | [`01-architecture-components.mmd`](diagrams/01-architecture-components.mmd) | Компонентная архитектура |
| 02 | [`02-oidc-authorization-code-pkce.mmd`](diagrams/02-oidc-authorization-code-pkce.mmd) | Авторизация OIDC (Authorization Code + PKCE) |
| 03 | [`03-authorized-api-request.mmd`](diagrams/03-authorized-api-request.mmd) | Авторизованный REST-запрос |
| 04 | [`04-game-create-join.mmd`](diagrams/04-game-create-join.mmd) | Создание партии, вход игроков, старт |
| 05 | [`05-turn-begin-and-draw.mmd`](diagrams/05-turn-begin-and-draw.mmd) | Открытие хода и добор карты |
| 06 | [`06-play-card.mmd`](diagrams/06-play-card.mmd) | Сыгрыш карты с руки |
| 07 | [`07-end-turn-and-elimination.mmd`](diagrams/07-end-turn-and-elimination.mmd) | Завершение хода и передача хода следующему |
| 08 | [`08-disconnect-and-skip.mmd`](diagrams/08-disconnect-and-skip.mmd) | Отключение игрока, grace-окно, пропуск хода |
| 09 | [`09-concurrent-actions.mmd`](diagrams/09-concurrent-actions.mmd) | Конкурентные действия, сериализация, блокировки |
| 10 | [`10-endgame-and-victory.mmd`](diagrams/10-endgame-and-victory.mmd) | Условия победы и конец партии |
| 11 | [`11-state-machine.mmd`](diagrams/11-state-machine.mmd) | Конечный автомат состояний партии |

## Исходные материалы

- [`init.sql`](init.sql) — исходная схема PostgreSQL (**не изменяется**)
- [`Игра.md`](Игра.md) — атомарные механики
- [`neuderzhimye_edinorozhki_rules.pdf`](neuderzhimye_edinorozhki_rules.pdf) — правила игры (экспорт PDF: [`/tmp/opencode/rules.txt`](file:///tmp/opencode/rules.txt))

## Ключевые архитектурные решения

- **PostgreSQL — источник истины.** Все изменения только через транзакции, вызовы `sp_*` (изменения) и `fn_*` (чтение).
- **Сервер-авторитетная модель.** Клиент к БД не подключается. Проверки, блокировки и переходы состояний — на сервере.
- **Сериализация.** Конкурентные действия упорядочиваются через `SELECT ... FOR UPDATE` по строке `games`.
- **REST + SSE.** Состояние меняется через REST, уведомления — через SSE (`pg_notify`). Реконнект с `Last-Event-ID` + полный снапшот.
- **OIDC Authorization Code + PKCE.** Public client, `sub` в формате UUID. Сессия в `HttpOnly`/`Secure` cookie.
- **Колода — неупорядоченный мешок.** Порядок колоды не хранится, добор — случайный (`ORDER BY random()`). Порядок важен только в `discard`.
- **Состояние «один ход».** Фазы хода, отложенные эффекты, временные запреты хранятся в `p_parameters` сервера (в памяти), а не в БД. То, что должно пережить рестарт — только в таблицах.
- **Выбывание игроков.** Единственное ограничение схемы: для корректного условия «остался один активный» рекомендуется добавить `players.is_eliminated BOOLEAN NOT NULL DEFAULT false` (см. [ARCHITECTURE.md#7-известные-ограничения-и-предлагаемое-расширение-схемы](ARCHITECTURE.md#7-известные-ограничения-и-предлагаемое-расширение-схемы)).

## Быстрая проверка диаграмм

Для рендера Mermaid используется [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli):

```bash
npx -y @mermaid-js/mermaid-cli -i diagrams/01-architecture-components.mmd -o /tmp/01.svg
```

Все диаграммы в репозитории успешно прошли валидацию.