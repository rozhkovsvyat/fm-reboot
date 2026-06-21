# fm-reboot

Персональный **Obsidian-vault проекта reboot** + механика дисциплины для AI-агентов (Claude Code,
Cursor и др.). Это чистый каркас: знания наполняешь сам, а вся «обвязка» (хуки, контракт, правила,
команды, трекинг задач) уже перенесена из зрелого командного vault'а и очищена от корпоративной специфики.

Рассчитан на **соло → максимум 2 человека**.

## Что внутри (механика)

- **Контракт агента** — `meta/CLAUDE.md` (+ редиректы `CLAUDE.md`/`AGENTS.md`). Авто-подхватывается Claude Code.
- **Хуки** (`.claude/*.ps1`, PowerShell) на события Claude Code:
  - inbox-протокол (сообщения между участниками),
  - stale-check (`now.md`, ADR, черновики),
  - discipline (после значимой работы обнови daily/activity),
  - mistakes (детектор реверса рассуждения) + daily-review,
  - **verify-gate** (готово = доказано рантаймом, а не «рассудил»),
  - overview-stale, broken-wikilinks, draft-lifecycle, vault-integrity/consistency/bloat,
  - YouGile-задачи (сводка/дельта).
- **Правила** — `rules/` (security, verify-gate, vault-git-discipline, task-discipline).
- **Команды** — `/daily /inbox /msg /idea /handoff /status /create-task /update-overview` (`.claude/commands/`).
- **Задачи** — YouGile (доска `reboot`) через `_system/tools/yougile-sync/` (вместо корпоративной Репки).
- **setup.ps1** — на каждом старте: `git pull`, identity (`kb.author`), housekeeping, BOM-fix.

## Требования

- **PowerShell 7.6.2+** (macOS: `brew install powershell`; на arm64 именно ≥7.6.2 — у 7.6.1 регрессия). Проверка: `pwsh --version`.
- **Python 3** (для YouGile CLI; только stdlib, без зависимостей).
- **git**, **Obsidian** + плагин **Obsidian Git**.
- (опц.) **gh** CLI — если будешь работать с GitHub Issues/репо из агента.

## Первичная настройка

1. **Git + первый коммит** — уже инициализировано (`git init` + initial commit). Проверь автора:
   ```bash
   git -C ~/Проекты/fm-reboot config user.name  "Святослав Рожков"
   git -C ~/Проекты/fm-reboot config user.email "rozhkovsvyat@gmail.com"
   ```
2. **GitHub (личный, private).** Имя репо — **без `&`** (`&` GitHub в имени не пускает), например `fm-reboot`:
   ```bash
   gh repo create fm-reboot --private --source ~/Проекты/fm-reboot --remote origin --push
   # или вручную: создай repo на github.com → git remote add origin <url> → git push -u origin main
   ```
3. **Identity для агента:** `git -C ~/Проекты/fm-reboot config kb.author rozhkov`
   (или просто оставь — `setup.ps1` сам выставит по email из `team/_handles.yml`).
4. **Obsidian:** открой папку `~/Проекты/fm-reboot` как vault → установи плагин **Obsidian Git** →
   включи auto pull/commit/push (история линейная, коммиты `vault backup: ...`).
5. **YouGile (доска reboot):** один раз сгенерируй API-ключ и настрой доску —
   полная инструкция в `_system/tools/yougile-sync/README.md`. Кратко:
   ```bash
   cd _system/tools/yougile-sync
   python3 yougile-cli.py auth-companies --login <login> --password '***'      # → companyId
   python3 yougile-cli.py auth-key --login <login> --password '***' --company-id <id>
   echo '<key>' > ~/.claude/yougile-token && chmod 600 ~/.claude/yougile-token
   cp yougile-config.example.json yougile-config.json   # впиши id доски/колонок (boards/columns)
   ```
   Без токена хук YouGile молча выключен — vault работает и так.
6. **(опц.) post-commit хук** для авто-записи коммитов в `state/activity.md` и daily — в репозитории
   с кодом проекта: `git config kb.vault ~/Проекты/fm-reboot && git config kb.author rozhkov`,
   затем поставь `_system/tools/post-commit.sh` в `.git/hooks/post-commit`.

## Как агент это использует

Открываешь Claude Code в папке vault'а — он подхватывает `CLAUDE.md` (контракт) и `.claude/settings.json`
(хуки). Дальше всё работает само: на старте `git pull` + проверки, на промптах — напоминания
(`INBOX:`/`STALE:`/`OVERVIEW:`/`YOUGILE:`…), на Stop — дисциплина/verify-gate/mistakes. Полный контракт —
в `meta/CLAUDE.md`.

## Структура

```
fm-reboot/
├── CLAUDE.md / AGENTS.md       # редиректы на meta/CLAUDE.md (контракт)
├── README.md                   # этот файл
├── .claude/
│   ├── settings.json           # разводка хуков
│   ├── *.ps1                   # хуки (inbox, stale, discipline, mistakes, verify-gate, …)
│   └── commands/*.md           # slash-команды
├── _system/tools/
│   ├── setup.ps1               # SessionStart-оркестратор
│   ├── run-vault-checks.ps1    # раннер для IDE без хуков (Cursor/Codex)
│   ├── vault-link.ps1          # подключить код-репо к хукам vault'а
│   ├── post-commit.sh          # авто-запись коммитов в activity/daily
│   └── yougile-sync/           # CLI задач (YouGile) + config + README
├── meta/                       # контракт, карта, welcome, glossary, overview
├── state/                      # now / activity / daily / weekly / ideas
├── decisions/                  # ADR (+ 0001 описывает сам vault)
├── drafts/                     # черновики до ADR
├── mistakes/                   # журнал реверсов рассуждения
├── team/                       # профили + _handles.yml (identity)
├── inbox/                      # личные сообщения (под 2-го человека)
└── rules/                      # security / verify-gate / vault-git / task-discipline
```

## Второй человек

1. Клонирует репо с GitHub, открывает в Obsidian + Obsidian Git.
2. Добавляет себя в `team/_handles.yml` (email → handle) и `git config kb.author <handle>`.
3. Создаёт `team/<handle>.md` и `inbox/<handle>.md`. Дальше `/msg @<handle>` работает в обе стороны.

## Происхождение

Механика перенесена 2026-06-21 из командного vault'а Portal 5. Выкинуто как корпоративное:
Репка (→ YouGile), broker, hindsight, telegram-bridge, Keycloak/Vault/k8s-правила, .NET/frontend-конвенции,
инъекция в глобальный `~/.claude/CLAUDE.md`. Решение и границы — в `decisions/0001-vault-structure.md`.
