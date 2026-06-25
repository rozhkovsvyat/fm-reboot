# How-to: подключить Олега к vault'у (Claude Code + AITunnel)

> Пошаговая настройка ИИ-агента для [[team/oleg]] из РФ. Основание — [[decisions/0003-ru-ai-access|ADR 0003]].
> Цель: полноценный Claude Code в VS Code, рубли, **с сохранением `.claude`-хуков и MCP**, без аккаунта Anthropic.
> Детали/риски — [[drafts/claude-code-ru-aggregator-setup]].

## Шаги

1. **Поставить инструменты:** VS Code + Claude Code (CLI и/или расширение). Git. (Obsidian + плагин Obsidian Git — для заметок и синка.)
2. **Агрегатор AITunnel:** зарегаться на aitunnel.ru → пополнить (от **399₽**, карта РФ / СБП) → получить API-ключ (`sk-aitunnel-...`).
3. **Выставить переменные окружения** (в шелл-профиль, напр. `~/.zshrc`):
   ```bash
   export ANTHROPIC_BASE_URL="https://api.aitunnel.ru"
   export ANTHROPIC_AUTH_TOKEN="sk-aitunnel-xxx"
   export ANTHROPIC_API_KEY=""        # явно пустой
   ```
   ⚠️ **В Anthropic НЕ логиниться** (`/login` не нужен) — аккаунта быть не должно.
4. **Клонировать vault-репо:** `git clone git@github.com:rozhkovsvyat/fm-reboot.git` (доступ к репо даёт Свят).
5. **Identity:** `git -C <vault> config kb.author oleg` + проставить `git config user.email <email>` и добавить
   этот email в [[team/_handles]] (секция handles → `oleg`).
6. **Запустить агента в папке репо:** `claude` в терминале vault'а. Проверить, что:
   - модель отвечает (значит endpoint/ключ ок);
   - `.claude`-хуки срабатывают (видны reminder-строки INBOX/STALE/YOUGILE и т.п.);
   - MCP-серверы подключаются (если настроены в `~/.claude`/`.mcp.json`).
7. **Модель:** Sonnet 4.6 для рутины; Opus — под тяжёлое.

## VPN — опционально (НЕ для самой работы)

- **Для Claude Code через AITunnel VPN не нужен:** эндпоинт `api.aitunnel.ru` доступен из РФ напрямую (в этом смысл выбора агрегатора, [[decisions/0003-ru-ai-access|ADR 0003]]).
- 🔴 **VPN НЕ использовать для входа в прямой аккаунт Claude / claude.ai** — это отвергнутый ВЫСОКИЙ-риск путь (массбаны май 2026 + удаление данных).
- VPN полезен лишь как страховка на сетап: доки `docs.claude.com` (гео-блок из РФ), GitHub, общее чтение.
- **Что работает в РФ (июнь 2026, нужна обфускация — plain OpenVPN/WireGuard заблокированы DPI):**
  - **Proton VPN** (режим *Stealth*) — есть бесплатный тариф, поставить заранее как стартовый;
  - **NordVPN** — платный (~$3–5/мес годовой), авто-обфускация, надёжнее, ставится в один клик;
  - **Amnezia VPN** на своём заграничном VPS (AmneziaWG / VLESS+Reality) — самый устойчивый, но требует VPS — поднимать лучше на созвоне вместе, не накануне.

## Fallback

- **ProxyAPI** — второй агрегатор (нативный Anthropic): `ANTHROPIC_BASE_URL=https://api.proxyapi.ru/anthropic`. Держать на случай downtime/бана AITunnel.
- **Cline** (расширение VS Code) — если Claude Code-путь сломается: provider-agnostic, MCP работает, но **`.claude`-хуки не запускаются** (vault-дисциплину тогда держать вручную через `run-vault-checks.ps1`).

## Гигиена / риски

- Ключ агрегатора — в env/secret-менеджере, **не в репозитории**.
- Агрегатор видит трафик → не слать секреты/то, что нельзя показать третьей стороне (для музыкального vault'а — ок).
- Наработки всегда в Git — бан клиента память не уносит.
