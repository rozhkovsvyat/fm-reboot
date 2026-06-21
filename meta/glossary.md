# Глоссарий

Термины проекта и vault'а. Дополняй по ходу.

## Vault / процесс
- **vault** — эта база знаний (Obsidian + Git).
- **ADR** — Architecture Decision Record, запись архитектурного решения (`decisions/NNNN-*.md`).
- **handle** — короткий идентификатор участника (lowercase-латиница), он же `git config kb.author`.
- **inbox** — личные сообщения между участниками (`inbox/<handle>.md`, через `/msg`).
- **verify-gate** — правило «готово = доказано рантаймом» ([[../rules/verify-gate|verify-gate]]).
- **mistakes** — журнал реверсов рассуждения агента ([[../mistakes/README|mistakes]]).

## Инструменты
- **YouGile** — внешний таск-трекер (доска `reboot`). CLI — `_system/tools/yougile-sync/`.
- **хук** — PowerShell-скрипт в `.claude/`, срабатывает на события Claude Code (SessionStart/UserPromptSubmit/Stop).
- **vault-link** — подключение стороннего репозитория к хукам vault'а.

## Проект reboot
<!-- сюда — доменные термины проекта по мере появления -->
- _(заполняется по ходу проекта)_
