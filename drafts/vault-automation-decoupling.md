# (предложение) Отвязка vault-автоматизации от Claude Code

- **Статус:** 🟡 предложено (2026-06-21). Запрос [[team/rozhkov]]: сохранить автоматизацию рутин, но не зависеть от Claude.
- Связано: [[decisions/0003-ru-ai-access]] (Олег может оказаться на Cline-фолбэке без `.claude`-хуков).

## Текущее состояние (проверено)

- **Логика УЖЕ decoupled:** проверки — отдельные скрипты; есть унифицированный раннер
  `_system/tools/run-vault-checks.ps1 -Phase <SessionStart|PromptCheck|EndOfWork>`.
- НО единственный активный **триггер** — хуки Claude Code (SessionStart / UserPromptSubmit / Stop).
- `_system/tools/post-commit.sh` **существует**, но как git-хук **НЕ установлен** (`.git/hooks` — только `.sample`,
  `core.hooksPath` не задан, `_system/githooks/` нет).

## Tool-agnostic триггеры (предложение)

| Тип рутины | Механизм без Claude |
|---|---|
| На коммит/пул (activity-лог, inbox/stale после pull) | **Git-хуки** через `core.hooksPath=_system/githooks/` (коммитим в репо → общие для всех клиентов). `post-commit.sh` уже готов. |
| Периодические (stale / yougile / discipline / checkpoint) | **OS-планировщик** (launchd на Mac / Task Scheduler на Win) → `run-vault-checks.ps1`. Работает даже без открытого редактора. |
| «На старте/в конце сессии» для не-Claude агентов | Инструкция в `AGENTS.md` запускать раннер + опц. MCP-обёртка над ним. Мягко (по комплаенсу). |

## Честный предел

Реактивные **per-turn** хуки (UserPromptSubmit/Stop) — фича именно Claude Code. Вне его — аппроксимация:
git-события + расписание + инструкции агенту. Важная автоматизация (синк, activity, stale, checkpoints)
становится tool-agnostic; per-turn-напоминания остаются бонусом Claude Code.

## Зависимость от PowerShell

Скрипты — `.ps1` (нужен pwsh, кроссплатформенный, уже стоит). Это отдельная связка — с PowerShell, не с Claude. Ок.

## Действия (если внедряем — infra, требует подтверждения)

1. `_system/githooks/` (post-commit, post-merge) → `git config core.hooksPath _system/githooks`.
2. launchd-plist (Mac) для периодического `run-vault-checks.ps1` (напр. раз в час).
3. Дополнить `AGENTS.md`: «не-Claude агент — запусти `run-vault-checks` на старте и в конце».
