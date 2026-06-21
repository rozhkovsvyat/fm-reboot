# Контракт для AI-агентов (fm-reboot vault)

Это персональная база знаний проекта **reboot** (Obsidian vault + Git). Её читают и обновляют
AI-агенты (Claude Code, Cursor и др.), работая в этом и в связанных репозиториях. Цель —
единый контекст: что делается сейчас, какие решения приняты, на чём обожглись. Сейчас в проекте
один человек, максимум появится второй — механика inbox/identity рассчитана на это.

## Структура

- `meta/README.md` — точка входа для людей · `meta/index.md` — карта vault'а (MOC) · `meta/CLAUDE.md` — этот контракт.
- `meta/glossary.md` — термины · `meta/project-overview.md` — сжатый обзор проекта (обновляется через `/update-overview`).
- `state/now.md` — **снимок текущего состояния**. Сюда смотрят первым делом. Статусы 🟢🟡🔴⚪✅.
- `state/activity.md` — лента событий (коммиты пишет git-хук, заметки — агент).
- `state/daily/YYYY-MM-DD.md` — дневной лог (секции по людям) · `state/weekly/` — недельные сводки · `state/ideas/` — backlog идей.
- `team/<handle>.md` — профиль участника · `team/_handles.yml` — маппинг git-email → handle (identity).
- `decisions/NNNN-<slug>.md` — ADR (architecture decision records) · `drafts/` — черновики до ADR.
- `mistakes/YYYY-MM-DD-<slug>.md` — журнал ошибок рассуждения агента (self-correction lessons).
- `rules/*.md` — обязательные правила (security, verify-gate, vault-git, task-discipline).
- `inbox/<handle>.md` — личные сообщения между участниками (human-to-human, через `/msg`).
- `_system/tools/` — скрипты автоматизации (хуки, setup, yougile-sync) · `_system/templates/` — шаблоны.

## Правила для агента

### 🔴 ГЛАВНЫЕ — ОБЯЗАТЕЛЬНО

**1. Безопасность прежде всего.** Соблюдай [[rules/security]]. Секрет рискует утечь в vault — **не пиши, флагуй пользователю**. Необратимые операции (удаление данных, прод-деплой, force-push, установка зависимостей, git push) — **спрашивай подтверждение**, не делай автономно. Перед любым shared-state write со значением не от человека — verify (probe/grep/спроси источник), не хардкодь наугад.

**2. База знаний всегда актуальна.** Каждое значимое изменение в коде/инфре ОБЯЗАНО быть отражено в vault'е в той же сессии. Устаревшая база хуже, чем её отсутствие.
- **Значимое:** правка в исходниках под коммит, изменение конфига/CI/миграций, установка/удаление зависимости, архитектурное решение, смена статуса задачи, обнаруженный нетривиальный факт о системе.
- **НЕ требует записи:** эксперименты, откатанные в той же сессии; чтение кода без правок; опечатки/форматирование.

### 🔴 Identity (правило №-1, до всего)

Без identity не выполнить правила про inbox и daily. Алгоритм (стоп на первом успехе):
1. `git -C <vault> config kb.author` — если непусто, это твой handle. Источник правды (setup.ps1 выставляет автоматически из email).
2. `git -C <vault> config user.email` + lookup в [[team/_handles|team/_handles.yml]] — fallback.
3. **СТОП, спроси пользователя** «Кто ты (handle)?». Не угадывай по активности.

### Перед работой над задачей

0. **Сначала синхронизируй vault:** `git pull --ff-only` (хук SessionStart уже сделал — вручную не дублируй; если `--ff-only` упал — **остановись и сообщи**, не делай rebase/merge/force автономно; линейная история `vault backup: ...` важнее тихого слияния).
1. Прочитай `state/now.md` — контекст.
2. Прочитай `team/<handle>.md` пользователя.
3. Архитектурная задача — просмотри `decisions/` + относящиеся `rules/`.
4. Задача затрагивает секреты/прод — перечитай [[rules/security]].
5. **Проверь маркеры входящих** в `inbox/<handle>.md` (🟡) — см. inbox-протокол ниже.

### Что делается автоматически (хуки — не дублируй вручную)

Хуки активны в самом vault'е и в проектах, подключённых через `vault-link`. Срабатывают в фоне;
ты видишь только их reminder-строки в системном контексте.

| Событие | Скрипт | Когда увидишь |
|---|---|---|
| SessionStart | `_system/tools/setup.ps1` | Молча: git pull, kb.author, housekeeping, BOM-fix, сброс announced |
| SessionStart | `check-vault-integrity.ps1` | `INTEGRITY: ...` если core-файл vault'а занулён/пропал или сломан XML диаграммы |
| SessionStart | `check-vault-bloat.ps1` | `BLOAT: ...` если файл-монолит (inbox/now/activity) раздулся к ~1MB |
| SessionStart/UserPromptSubmit | `check-inbox.ps1` | `INBOX: N непрочитанных...` когда в `inbox/<handle>.md` есть 🟡 |
| UserPromptSubmit | `check-overview-stale.ps1` | `OVERVIEW: ...` если `meta/project-overview.md` отстал от триггер-путей |
| UserPromptSubmit | `check-now-stale.ps1` | `STALE: ...` если в `state/now.md` записи с «Обновлено» старше 5 дней |
| UserPromptSubmit | `check-stale-extended.ps1` | `STALE-EXT: ...` ADR на ревью >7 дней, черновики >7 дней |
| UserPromptSubmit | `check-broken-wikilinks.ps1` | `BROKEN-LINKS: ...` сломанные `[[ссылки]]` в недавних файлах |
| UserPromptSubmit | `check-draft-lifecycle.ps1` | `DRAFT-STALE: ...` черновики без правок >30 дней |
| UserPromptSubmit | `check-mistakes-daily-review.ps1` | `MISTAKES-REVIEW: ...` раз в день — оцени накопленное в `mistakes/` |
| UserPromptSubmit | `check-inbox-adequacy-due.ps1` | `INBOX-ADEQUACY-DUE: ...` раз в 14 дней — vault-hygiene проход |
| SessionStart/UserPromptSubmit/Stop | `check-yougile-tasks.ps1` | `YOUGILE:` / `YOUGILE-UPD:` / `YOUGILE-EOT:` сводка/дельта задач (без токена молчит) |
| Stop | `check-vault-discipline.ps1` | `DISCIPLINE: ...` коммиты в decisions/team/now без апдейта daily/activity |
| Stop | `check-inbox-on-stop.ps1` | `INBOX-EOT: ...` новые 🟡 пришли пока работал |
| Stop | `check-vault-consistency.ps1` | `CONSISTENCY: ...` ADR без upstream-ссылок / dangling wikilinks |
| Stop | `check-mistakes-candidate.ps1` | `MISTAKE-CANDIDATE: ...` детектор реверса рассуждения |
| Stop | `check-verify-gate.ps1` | `VERIFY-GATE: ...` claim завершения без runtime-доказательства |

Дедуп: announced-файлы хранят хеш «уже сообщённого», затираются на SessionStart.

**Для IDE без хуков (Cursor/Codex):** единый раннер `_system/tools/run-vault-checks.ps1 -Phase <SessionStart|PromptCheck|EndOfWork>`.

### Inbox-протокол (human-to-human, актуально когда в проекте ≥2 человека)

Видишь `INBOX:` — **сам прочитай и обработай** каждое 🟡, без AskUserQuestion:
- **Информационное** → упомяни строкой в ответе, замени 🟡 → ✅.
- **Вопрос/мнение** → ответь через `/msg @<sender>`, замени 🟡 → ✅.
- **Запрос на ревью** → прочитай документ, напиши ревью в `state/daily/<today>.md`, отправь `/msg @<sender>`, 🟡 → ✅.
- **🔴 Write-side commitment в shared knowledge ИЛИ разрушительное действие** (новый ADR, принципиальный выбор, commitment от лица пользователя, удаление, прод, force-push) → спроси через `AskUserQuestion`, не действуй сам.
- **Срочное** (🆕/«срочно»/«блокер») — до основной задачи; несрочное — после.
- В конце ответа строкой: «Inbox: обработано N сообщений (✅), действия: ...».

Видишь `INBOX-EOT:` (Stop) — обработай новые 🟡 **до** финального ответа.

**Конвенция маркеров:** 🟡 = ТОЛЬКО непрочитанный заголовок сообщения. Для акцентов внутри текста бери ⚠️/🔴/▸, не 🟡 (иначе инфляция «непрочитанного»).

### Задачи проекта (YouGile, доска reboot)

Трекинг задач — через YouGile, а не файлы. Канон и intent-триггеры — в [[rules/task-discipline]]. Кратко:
- «создай задачу / поставь таск» → `/create-task` или `yougile-cli.py create`.
- «какие задачи / что в работе» → `yougile-cli.py list`.
- «взял в работу / готово» → `yougile-cli.py move`/`done` + **предложи пользователю**, не меняй статус молча.
- После значимой работы по задаче — обнови её статус/коммент в YouGile (см. чек-лист ниже).

### После значимой работы (ОБЯЗАТЕЛЬНЫЙ чек-лист)

Перед «готово» пройди список:
- [ ] **`state/daily/YYYY-MM-DD.md`** — запись: что сделано / в работе / заблокировано (нет файла — создай по формату прошлого).
- [ ] **`state/activity.md`** — строка события в начало `## События` (коммиты пишет git-хук — не дублируй).
- [ ] **`state/now.md`** — если статус задачи изменился, обнови строку + эмодзи-статус + «Обновлено».
- [ ] **YouGile** — если работа связана с задачей, **предложи** обновить статус (IN_PROGRESS/done) или добавь коммент. Не молча.
- [ ] **`decisions/`** — принял архитектурное решение → новый ADR `NNNN-<slug>.md` + ссылка в `meta/index.md`.
- [ ] **`mistakes/YYYY-MM-DD-<slug>.md`** — если был **реальный реверс рассуждения** (порог: стоимость >30 мин ИЛИ повторяемый паттерн ИЛИ развернулись после сделанной работы) — запись по [[mistakes/_template]] с полем **Signal**. Ниже порога — пропусти.

### Verify-gate (DoD = runtime smoke)

Полное правило — [[rules/verify-gate]]. Не выдавай «рассудил, что работает» за «проверил». Claim завершения («готово/работает») требует runtime-доказательства (запустил приложение / тесты зелёные на реальном прогоне / curl 2xx / скриншот / e2e) ЛИБО честного дисклеймера («реализовано, build зелёный, runtime НЕ верифицировал — прошу smoke»). Хук `check-verify-gate.ps1` это ловит — обязательство уровня INBOX.

### Журнал ошибок (mistakes/)

Видишь `MISTAKE-CANDIDATE:` — проверь порог (выше). Если выполняется — создай запись с **Signal** (как распознать ту же ошибку в будущем) до финального ответа. Видишь `MISTAKES-REVIEW:` — пробегись по `mistakes/`, если 2-3 однотипных → предложи поднять в `rules/*.md` или ADR (не авто-генерь — предлагай с черновиком в `drafts/`).

### Как сообщать о результате

В конце ответа **всегда** перечисли, какие файлы vault'а обновил. Ничего не обновил — объясни почему. Это даёт пользователю поймать, если забыл.

### Что НЕ писать в базу

Секреты/токены/пароли/connection strings · пошаговые рецепты отладки одного бага (это в коммит/PR) · дублирование того, что есть в коде/git-истории.

**Ссылки:** wiki-стиль Obsidian — `[[team/<handle>]]`, `[[decisions/0001-vault-structure]]`. **Даты:** абсолютные (`2026-06-21`). **Язык:** русский.
