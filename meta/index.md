# Index — карта vault'а (MOC)

Ручная карта. Обновляй при появлении нового раздела/документа верхнего уровня.

## Точки входа
- [[welcome]] — введение для людей
- [[CLAUDE|meta/CLAUDE.md]] — контракт для AI-агентов
- [[project-overview]] — сжатый обзор проекта (через `/update-overview`)
- [[glossary]] — термины

## Состояние
- [[../state/now|state/now.md]] — снимок текущего состояния
- [[../state/activity|state/activity.md]] — лента событий
- `state/daily/` — дневные логи · `state/weekly/` — недельные сводки · `state/ideas/` — backlog идей

## Правила
- [[../rules/security|security]] — безопасность (всегда)
- [[../rules/verify-gate|verify-gate]] — DoD = runtime smoke
- [[../rules/vault-git-discipline|vault-git-discipline]] — git-дисциплина vault'а
- [[../rules/task-discipline|task-discipline]] — задачи в YouGile

## Решения и уроки
- `decisions/` — ADR (architecture decision records) · [[decisions/0001-vault-structure|0001 — структура vault'а]] · [[decisions/0002-release-as-singles|0002 — релиз синглами]]
- `drafts/` — черновики до ADR
- `mistakes/` — журнал ошибок рассуждения ([[../mistakes/README|README]])

## Команда
- `team/<handle>.md` — профили · [[../team/_handles|_handles.yml]] — identity-маппинг
- `inbox/<handle>.md` — личные сообщения

## Автоматика
- `_system/tools/` — setup, хуки, `vault-link`, `yougile-sync`
- `.claude/` — хуки + slash-команды
