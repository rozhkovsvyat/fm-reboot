# 0001 — Структура vault'а и механика дисциплины

- **Статус:** ✅ принято
- **Дата:** 2026-06-21
- **Автор:** rozhkov

## Контекст
Нужна персональная база знаний для проекта reboot с дисциплиной, которая держит AI-агента в тонусе:
актуальное состояние, фиксация решений и ошибок, проверка результата рантаймом. Механику взяли из
зрелого командного vault'а (Portal 5) и очистили от корпоративной специфики.

## Решение
Obsidian vault + Git (Obsidian Git auto-pull/commit/push) со структурой: `state/` (now/activity/daily/
weekly/ideas), `decisions/` (ADR), `mistakes/` (журнал реверсов рассуждения), `team/` + `inbox/`
(identity + сообщения, под рост до 2 человек), `rules/`, `meta/` (контракт + карта), `_system/tools/`
(хуки, setup, yougile-sync).

Механика — PowerShell-хуки в `.claude/` (inbox, stale-check, discipline, mistakes, verify-gate,
overview-stale, broken-wikilinks, draft-lifecycle, vault-integrity/consistency/bloat) + `setup.ps1`
(git pull, kb.author, housekeeping, BOM-fix). Задачи — внешний трекер **YouGile** (доска reboot)
через `yougile-cli.py`, не файлы vault'а.

## Альтернативы
- **Bash/Python-хуки вместо PowerShell** — отвергнуто: переписывание ~15 выверенных скриптов с риском
  тонких багов; pwsh 7 уже стоит. Цена переноса 1:1 на PowerShell — почти ноль.
- **Файловый трекинг задач вместо YouGile** — отвергнуто: у проекта уже есть доска reboot в YouGile.
- **Repka/broker/hindsight/telegram-bridge** — выкинуты как корпоративная специфика, не нужны соло-проекту.

## Последствия
- Нужен `pwsh 7.6.2+` (Mac) для работы хуков.
- Для задач — разовая настройка токена YouGile (`~/.claude/yougile-token`) + `yougile-config.json`.
- Контракт держим в файлах vault'а (`meta/CLAUDE.md`), глобальный `~/.claude/CLAUDE.md` НЕ трогаем.

## Связи
- [[../meta/CLAUDE|meta/CLAUDE.md]] · [[../rules/verify-gate]] · [[../rules/task-discipline]] · `_system/tools/yougile-sync/README.md`
