# Claude Code из РФ через агрегатор — ресёрч (сохранение хуков)

> Отчёт Opus-субагента по запросу [[team/rozhkov]] (2026-06-21). Основание для [[decisions/0003-ru-ai-access]].
> Цель: Claude Code как полноценный агент из РФ, **с сохранением `.claude`-хуков и MCP**, без аккаунта
> Anthropic, оплата рублями. Источники — офиц. доки Claude Code (2026-06-21).

## Главное (подтверждено)

1. **Claude Code официально ходит на кастомный endpoint** через `ANTHROPIC_BASE_URL`. Авторизация по
   precedence: cloud-creds → `ANTHROPIC_AUTH_TOKEN` → `ANTHROPIC_API_KEY` → apiKeyHelper → OAuth. Если задан
   токен — **OAuth-логин в Anthropic НЕ нужен** (аккаунт Anthropic не создаётся → банить нечего). Доказательство
   архитектуры — офиц. Bedrock/Vertex («no browser login needed»). Работает в **терминальном CLI** (Desktop/web — всегда OAuth).
2. **Хуки и MCP — КЛИЕНТСКИЕ, от бэкенда не зависят.** Хуки — локальные shell-процессы (stdin/stdout),
   модельного API не касаются. MCP — Claude Code сам MCP-клиент, соединения локальные. `ANTHROPIC_BASE_URL`
   меняет только маршрут модельных вызовов. → **`.claude`-хуки vault'а и MCP сохраняются полностью.**
   - Единственный нюанс: «MCP Tool Search» по умолчанию выкл. на non-first-party endpoint (большинство прокси
     не пробрасывают `tool_reference`); сами MCP-серверы и вызов инструментов работают. Опц. `ENABLE_TOOL_SEARCH=true`.

## РФ-агрегаторы: нативный Anthropic-формат

| Провайдер | Claude | Формат | Гайд Claude Code | Оплата ₽ |
|---|---|---|---|---|
| **AITunnel** | Opus 4.5–4.8, Sonnet 4.6, Haiku | ✅ **нативный Anthropic** + OpenAI | ✅ да | карта РФ, **СБП**, счёт |
| **ProxyAPI** | Sonnet, Opus 4.7/4.8 | ✅ **нативный Anthropic** | ✅ да | карта РФ |
| VseGPT / BotHub / GPTunnel | ✅ | ⚠️ только OpenAI → нужен мост | ❌ | карта РФ/СБП |
| GenAPI | ✅ | ⚠️ свой async-формат | ❌ | карта РФ |

→ В `ANTHROPIC_BASE_URL` **напрямую (без моста)** годятся **AITunnel и ProxyAPI**.

## Рабочий конфиг (AITunnel, проверено по доке)

```bash
export ANTHROPIC_BASE_URL="https://api.aitunnel.ru"
export ANTHROPIC_AUTH_TOKEN="sk-aitunnel-xxx"
export ANTHROPIC_API_KEY=""        # важно: явно пустой, не логиниться в Anthropic
```
ProxyAPI — аналогично, endpoint `https://api.proxyapi.ru/anthropic`.

## Мост (если выбран OpenAI-only провайдер)

`claude-code-router` (`ccr code`, ~35k★, проще всего) — локальный прокси Anthropic↔OpenAI + роутинг.
LiteLLM — командный gateway, но ⚠️ были malware-версии PyPI (пинить чистую, ротировать ключи). y-router —
**не брать** (архив). Для AITunnel/ProxyAPI мост не нужен.

## Цены (₽/1M вх/вых, pay-as-you-go)

- **AITunnel:** Opus 4.5–4.7 ~960/4800; Opus 4.8 ~672/3360; Sonnet 4.6 ~576/2880. Мин. пополнение **399₽**, карта/СБП.
- **ProxyAPI:** Opus 4.7/4.8 ~1516/7579 (вкл. НДС 5%). Дороже ~1.5–2× → AITunnel выгоднее.

## Риски (честно)

- 🔴 **Приватность:** агрегатор видит все промпты/контент/ответы. Для **этого** проекта (музыкальный vault без
  секретов) — приемлемо; секреты в базу и так не пишем. Для проприетарного кода — было бы нет.
- 🔴 **Single-point-of-failure:** один upstream-аккаунт Anthropic на агрегатора → его бан рубит всех. → держать **ProxyAPI как fallback**.
- Не санкционировано Anthropic, гарантий непрерывности нет (но у Олега нет аккаунта Anthropic → персонального бана нет).
- **Не** использовать схемы «подписка через прокси/OAuth-токен» — их Anthropic банил (янв. 2026). Только pay-as-you-go API.

## Рекомендация

**Claude Code + AITunnel** (нативный Anthropic, без моста, хуки+MCP сохранены, рубли) — основной путь.
**ProxyAPI** — fallback-канал. Аккаунт Anthropic не создавать. **Cline** — запасной клиент, если Claude Code-путь
сломается (но теряются `.claude`-хуки). Гайд: [[howto/oleg-claude-code-setup]].

## Источники

Claude Code docs (2026-06-21): [Authentication](https://code.claude.com/docs/en/authentication) · [env-vars](https://code.claude.com/docs/en/env-vars) · [model-config](https://code.claude.com/docs/en/model-config) · [Hooks](https://code.claude.com/docs/en/hooks) · [MCP](https://code.claude.com/docs/en/mcp) · [Bedrock](https://code.claude.com/docs/en/amazon-bedrock) · [Vertex](https://code.claude.com/docs/en/google-vertex-ai) · [pricing](https://platform.claude.com/docs/en/about-claude/pricing)
Агрегаторы: [AITunnel — Claude Code](https://docs.aitunnel.ru/guides/claude-code-integration) · [AITunnel цены](https://aitunnel.ru/providers/anthropic) · [ProxyAPI docs](https://proxyapi.ru/docs) · [ProxyAPI pricing](https://proxyapi.ru/pricing)
Мосты: [claude-code-router](https://github.com/musistudio/claude-code-router) · [LiteLLM](https://docs.litellm.ai/docs/anthropic_unified/)
Риски РФ: [supported-countries](https://www.anthropic.com/supported-countries) · [OAuth-прокси бан (HN, янв 2026)](https://news.ycombinator.com/item?id=47069299)
