# AITunnel — цены и prompt-caching (для бюджета Claude Code)

> Отчёт Opus-субагента (2026-06-21). Дополняет [[drafts/claude-code-ru-aggregator-setup]],
> [[decisions/0005-keep-claude-hooks]], [[team/oleg]]. Цены меняются — перепроверять перед закупкой.

## TL;DR

- **Prompt caching работает сквозняком** (нативный Anthropic `/v1/messages`, `cache_control: ephemeral`,
  TTL 5мин/1ч). **Claude Code сам шлёт `cache_control`** → кэш активируется автоматически, без настройки.
- Cache read ≈ **−90%** (Sonnet 0.1× input), cache write **+25%** (5-мин). Для агентных циклов Claude Code
  (большой повторяющийся системный промпт + контекст) — **главный рычаг экономии**.
- Оплата — **только РФ-инструменты** (МИР, СБП, счёт юрлиц). ❌ белорусские / казахстанские / иностранные
  карты, крипта, ЮMoney — нет. Мин. пополнение **399₽**.
- ⚠️ Cache-ставки **Opus 4.8** в прайсе не сходятся с формулой (read 0.143× вместо 0.1×, write 1.79× вместо 1.25×) — сверить на реальном usage.
- SLA/uptime публично нет; квантизации не заявлено (но и гарантий нет) → качество проверять на своём сценарии.
- Sticky routing → повышает cache-hit при повторных запросах (плюс для Claude Code).

## Цены (₽ за 1M токенов)

| Модель | Input | Output | Cache read | Cache write 5м | Контекст / max out |
|---|---:|---:|---:|---:|---|
| **Sonnet 4.6** | 576 | 2 880 | 57.6 (−90%) | 720 (1.25×) | 1M / 128k |
| **Haiku 4.5** | 192 | 960 | 19.2 (−90%) | 240 (1.25×) | 200k / 64k |
| **Opus 4.8** | 672 | 3 360 | 96 ⚠️ | 1 200 ⚠️ | 1M / 128k |
| Opus 4.5–4.7 | 960 | 4 800 | — | — | — |

(Opus 4.8 дешевле «старших» 4.5–4.7 — похоже на обновлённую ставку флагмана; сверить перед закупкой.)

## Настройка Claude Code

```
ANTHROPIC_BASE_URL="https://api.aitunnel.ru"
ANTHROPIC_AUTH_TOKEN="sk-aitunnel-xxx"
ANTHROPIC_API_KEY=""        # обязательно пустой
```

## Вывод для бюджета

- **Кэш режет повторный контекст на −90%** → Claude Code на Sonnet выходит ощутимо дешевле «наивной» оценки
  (большой системный промпт/контекст читается по 57.6₽/1M вместо 576₽/1M; запись +25% окупается со 2-го хита).
- Рабочая связка: **Sonnet 4.6** основная + кэш; **Haiku 4.5** для дешёвых сабагентов/роутинга; **Opus 4.8** точечно (cache-ставки сверить).
- Оплата Олегом — **МИР/СБП** (он в РФ → платит сам); зарубежная/белорусская карта не нужна и не принимается.
- Объёмные скидки — только на бизнес-тарифе по запросу.

## Источники

[prompt-caching](https://docs.aitunnel.ru/features/prompt-caching) · [Messages API](https://docs.aitunnel.ru/api/messages) · [Claude Code integration](https://docs.aitunnel.ru/guides/claude-code-integration) · [Sonnet 4.6](https://aitunnel.ru/models/claude-sonnet-4-6) · [Opus 4.8](https://aitunnel.ru/models/claude-opus-4-8) · [Haiku 4.5](https://aitunnel.ru/models/claude-haiku-4-5) · [оплата в РФ](https://aitunnel.ru/guide/kak-oplatit-openai-api-v-rossii) · [обзор toolfox 2026-05-16](https://toolfox.ru/services/s/aitunnel) · [Anthropic prompt-caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
