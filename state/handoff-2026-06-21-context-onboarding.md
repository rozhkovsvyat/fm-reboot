# HANDOFF — 2026-06-21 · контекст-интейк + онбординг/доступ Олега

> Для нового агента/сессии: прочитай это + [[meta/project-overview]] + [[state/now]] — и поедешь без потери контекста.
> Сессия была длинная: с нуля собран весь контекст музыкального проекта **reboot** и приняты решения по доступу/онбордингу.

## Что сделано (факты)

- **Obsidian Git настроен** (auto-pull on boot + commit/push каждые 10 мин) — [.obsidian/plugins/obsidian-git/data.json].
- **Полный контекст-интейк** → [[drafts/reboot-context-intake]] (дуэт **F&M** = FRVCTL & Monroe; пайплайн Suno→отбор→стемы→FL→живой вокал; «зерно»; трек-лист 11 шт; стек; стратегия портфолио→лейбл).
- **Наполнен** [[meta/project-overview]]; почищены legacy-wikilinks в [[meta/index]] под канон `[[папка/файл]]`.
- **Профили:** [[team/rozhkov]] (муз. роль), [[team/oleg]] (**Олег Гоков**, доступ/бюджет). [[team/_handles]] обновлён.
- **ADR приняты:** [[decisions/0002-release-as-singles|0002]] (синглы), [[decisions/0003-ru-ai-access|0003]] (РФ-доступ через AITunnel), [[decisions/0004-ship-before-tooling|0004]] (сингл прежде инструментов), [[decisions/0005-keep-claude-hooks|0005]] (остаёмся на Claude-хуках). Предложение: [[drafts/adr-generation-engine]].
- **YouGile синхронизирован:** 5 записанных треков (Это другое, Поцелуй, Блэкбэри, Плати-Лети, Я тебе нравлюсь) перемещены в колонку «На сведение» доски «Трек-лист».
- **Ресёрчи (субагенты):** [[drafts/suno-integration-research]], [[drafts/acedata-pricing-research]], [[drafts/claude-ru-access-risk]], [[drafts/claude-code-ru-aggregator-setup]], [[drafts/aitunnel-pricing-caching]], [[drafts/ai-tooling-feasibility]], [[drafts/vault-automation-decoupling]].

## Что in-flight / НЕ сделано (по «го» пользователя)

- **Git-хуки** (страховка из ADR 0005) — НЕ подключены. `_system/tools/post-commit.sh` готов; нужно `git config core.hooksPath _system/githooks` (каталог создать). Детали — [[drafts/vault-automation-decoupling]].
- **Переименование handle** `oleg`→`gokov` (для единообразия с `rozhkov`) — предложено, не сделано (затронет ссылки [[team/oleg]] в ADR/now/daily/howto).
- **Олег ещё не подключён:** нет git-email в [[team/_handles]]; не зарегистрирован на AITunnel.
- **Движок генерации** (Suno/AceData/ElevenLabs) — решение proposed, не принято ([[drafts/adr-generation-engine]]).
- **Сведение первого сингла «Это другое»** — НЕ начато.

## Следующий шаг (первым делом в новой сессии)

1. 🥇 **Двигать первый сингл «Это другое»** (ADR 0004): Свят выгружает из FL **стемы** (вокал-дубли + минус) в WAV + сообщает темп/тональность → агент делает ресёрч цепочки сведения (задача **REB-29**) + пошаговый гайд под FL → Свят сводит руками, итерации.
2. Параллельно (по «го»): подключить **git-хуки**; завести **Олега** по [[howto/oleg-claude-code-setup]].

## Контекст / подводные камни

- ⚠️ **Шум хуков:** напоминания `STALE-EXT` / `DRAFT-STALE` / `product/services` / `HINDSIGHT-OFFLINE` **протекают из ДРУГОГО vault'а** пользователя (Portal 5 / `vault-memory-core`). К reboot отношения не имеют — **игнорировать**.
- **RU-доступ Claude:** прямой Claude Pro из РФ = **ВЫСОКИЙ риск** (массбаны май 2026 с удалением данных). Решение — Claude Code через **AITunnel** (нативный Anthropic → хуки/MCP сохраняются, оплата ₽). Прямой аккаунт / белорусскую карту — НЕ пробовать.
- **AITunnel:** prompt-caching работает (cache read −90%, Claude Code шлёт `cache_control` сам); цены подтверждены скрином (Sonnet 4.6 **576/2880**₽/1M). Прогноз расхода Олега ~**3–6к₽/мес** (средний профиль), мерить на реальном usage.
- **Записано = 5 треков** по слову Свята (борд YouGile был рассинхронен — поправили; ✅-флаги на доске местами кривые, не источник правды).
- **Персона** (Kits.AI/Suno) — была задача REB-33, но **в воркфлоу НЕ используется** (не критерий интеграций).
- **Verify-gate:** всё сделанное — записи в vault (доказуемо); runtime ничего не проверялось (нечего). Obsidian Git заберёт изменения авто-коммитом.

## Ссылки

- Решения: [[decisions/0002-release-as-singles]] · [[decisions/0003-ru-ai-access]] · [[decisions/0004-ship-before-tooling]] · [[decisions/0005-keep-claude-hooks]]
- Состояние: [[state/now]] · [[state/daily/2026-06-21]] · [[meta/project-overview]]
- Гайд: [[howto/oleg-claude-code-setup]]
- YouGile: доска «Процесс» (откр.: REB-18 распевка, REB-28/29 сведение), доска «Трек-лист» (5 шт в «На сведение»).
