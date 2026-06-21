# Index — карта vault'а (MOC)

Ручная карта. Обновляй при появлении нового раздела/документа верхнего уровня.

## Точки входа
- [[meta/welcome|welcome]] — введение для людей
- [[meta/CLAUDE|meta/CLAUDE.md]] — контракт для AI-агентов
- [[meta/project-overview|project-overview]] — сжатый обзор проекта (через `/update-overview`)
- [[meta/glossary|glossary]] — термины
- [[drafts/reboot-context-intake|context-intake]] — полный собранный контекст проекта (черновик до дистилляции)

## Состояние
- [[state/now|state/now.md]] — снимок текущего состояния
- [[state/activity|state/activity.md]] — лента событий
- `state/daily/` — дневные логи · `state/weekly/` — недельные сводки · `state/ideas/` — backlog идей

## Правила
- [[rules/security|security]] — безопасность (всегда)
- [[rules/verify-gate|verify-gate]] — DoD = runtime smoke
- [[rules/vault-git-discipline|vault-git-discipline]] — git-дисциплина vault'а
- [[rules/task-discipline|task-discipline]] — задачи в YouGile

## Решения и уроки
- `decisions/` — ADR (architecture decision records) · [[decisions/0001-vault-structure|0001 — структура vault'а]] · [[decisions/0002-release-as-singles|0002 — релиз синглами]] · [[decisions/0003-ru-ai-access|0003 — РФ-доступ к ИИ]] · [[decisions/0004-ship-before-tooling|0004 — сингл прежде инструментов]] · [[decisions/0005-keep-claude-hooks|0005 — остаёмся на Claude-хуках]]
- `drafts/` — черновики до ADR ([[drafts/ai-tooling-feasibility|ai-tooling-feasibility]] · [[drafts/suno-integration-research|suno-integration-research]])
- `mistakes/` — журнал ошибок рассуждения ([[mistakes/README|README]])

## Команда
- `team/<handle>.md` — профили ([[team/rozhkov|rozhkov]] · [[team/oleg|oleg]]) · [[team/_handles|_handles.yml]] — identity-маппинг
- `howto/` — инструкции ([[howto/oleg-claude-code-setup|подключение Олега (Claude Code + AITunnel)]])
- `inbox/<handle>.md` — личные сообщения

## Автоматика
- `_system/tools/` — setup, хуки, `vault-link`, `yougile-sync`
- `.claude/` — хуки + slash-команды
