# AceData Cloud + Suno API — ресёрч (что это, цены, риски)

> Отчёт Opus-субагента по запросу [[team/rozhkov]] (2026-06-21). Дополняет [[drafts/suno-integration-research]].
> ⚠️ Цены волатильны; точные per-operation тарифы AceData скрыты за авторизацией дашборда — отмечено ниже.

## TL;DR

- **AceData Cloud — агрегатор-реселлер 300+ AI-моделей** (Suno, Midjourney, GPT, Claude, Veo, Kling…) через
  один API-ключ, pay-as-you-go на кредитах. Оператор — **Germey Technology, LLC** (Delaware) + китайская база;
  за брендом — python-разработчик Cui Qingcai («Germey»).
- **Своя подписка Suno НЕ нужна** (высокая уверенность): AceData генерит через собственный backend (неофиц.,
  реверс-инжиниринг Suno); платишь только кредитами AceData, авторизация — Bearer-токен AceData.
- **SunoMCP — бесплатный open-source (MIT)**; отдельной платы нет, нужен только токен AceData. Поддерживает
  generate / cover / upload / stems / lyrics — ровно кейс дуэта. Есть и хостед-вариант (без установки).
- **Точные $-цены за генерацию/cover/стемы НЕ опубликованы** (за авторизацией). Кредит ≈ **$0.013–0.018**
  (оценка по соседнему сервису, валюта похоже ¥). Рыночный ориентир конкурентов: **$0.014–0.111/трек**.
  Чистый pay-as-you-go, без подписки, есть бесплатные пробные кредиты.
- **Главный риск — надёжность:** PiAPI и GoAPI закрыли свои Suno-API в 2025; категория реверс-инжиниринговая,
  может «лечь за ночь».

## Что это и зачем создан

- Единый AI-API gateway («Unified Interface for All Modalities»), ~300+ моделей 30+ провайдеров. Бизнес —
  **реселл AI-API с наценкой** («до 50% дешевле official»). Плюс open-source Nexior (фреймворк, чтобы другие
  поднимали AI-SaaS на backend'е AceData) и крипто-слой ($ACE на Solana — практически мёртв, ~$40 объёма/сутки — yellow flag).
- Компания: **Germey Technology LLC** (Delaware), China ICP (Шаньдун, 2024). За брендом — **Cui Qingcai** (崔庆才),
  известный автор по python web-scraping. Org GitHub: 2 участника. Маркетинг «since 2023», документировано с 2024.
- Репутация: self-reported 99.9% SLA, ~40M вызовов/30дн. **Независимых отзывов почти нет** (ни хвалебных, ни
  жалоб) → отсутствие жалоб ≠ надёжность.

## Цены (честно: точные скрыты за авторизацией)

| Операция | Кредиты | ≈ USD | Статус |
|---|---|---|---|
| 1 кредит (база) | — | ~$0.013–0.018 | оценка по соседнему сервису (¥), НЕ офиц. курс |
| Клон голоса (suno-voices) | 0.1 | ~$0.001–0.002 | утечка из documents-API ◐ |
| Генерация трека | не раскрыто | ориентир $0.014–0.111/трек | по конкурентам, НЕ AceData ⚠️ |
| upload_cover (кавер из демки) | не раскрыто (отд. тариф) | ≈ как генерация | оценка |
| Стемы (separation, до 12) | не раскрыто (отд. тариф) | ≈ как генерация | оценка |
| Подписка | НЕТ (pure pay-as-you-go) | — | ✅ подтверждено |

- Оплата: Stripe (карта), Alipay, WeChat Pay, on-chain USDC. Объёмные скидки есть, тиры не раскрыты.
  Бесплатные пробные кредиты при регистрации без карты.
- **Как узнать точно:** залогиниться в platform.acedata.cloud → сервис Suno → вкладка Pricing (рендерится
  client-side); либо замерить **эмпирически на пробных кредитах** (1 тестовый вызов на операцию); либо office@acedata.cloud.

## Нужна ли своя Suno-подписка? — НЕТ (высокая уверенность)

AceData = прокси: генерит через свой backend; клиент авторизуется только Bearer-токеном AceData; в запросах нет
полей под аккаунт/cookie/ключ Suno; позиционирование «no need to register with each provider»; биллинг — кредиты
AceData. ⚠️ Доступ неофициальный/реверс-инжиниринговый (офиц. публичного API у Suno нет).

## SunoMCP

MIT, бесплатный; платишь только за вызовы API. Запуск: `pip install mcp-suno` / `uvx mcp-suno` / Docker / хостед
`https://suno.mcp.acedata.cloud/mcp`. Нужен только `ACEDATACLOUD_API_TOKEN`. ~26 инструментов: generate/custom/
extend/cover/concat/remaster/mashup, upload_cover/upload_extend, stems/extract_vocals, lyrics, экспорт, persona, poll.
Активен (релиз v2026.6.18.0).

## Риски

- 🔴 **Надёжность:** PiAPI/GoAPI закрыли Suno-API в 2025; «изменение веб-UI Suno может сломать за ночь». Аварий
  именно AceData не зафиксировано, но и гарантий нет. → не строить mission-critical без fallback + локальный бэкап результатов.
- **Приватность демки:** политика заявляет «контент не для обучения, только метаданные для биллинга», но живой текст
  не подтверждён; аудио всё равно проходит через backend Suno. → прочитать privacy в браузере перед загрузкой реальной демки.
- **Легальность:** нарушает ToS Suno (scraping/перепродажа); «commercial license» от реселлера не гарантируема;
  копирайт на чистый AI-выход слабый; коммерческие права Suno привязаны к ПРЯМОЙ подписке → через реселлера цепочка рвётся.

## Вывод для дуэта

Самый низкофрикционный путь дёргать Suno из агента (один MIT-MCP, один токен, без своей Suno-подписки, есть
upload_cover + стемы). Но неофициальный, юридически серый, потенциально недолговечный. Стратегия: (1) пробные
кредиты → эмпирически замерить стоимость операций; (2) держать fallback; (3) бэкапить результаты локально;
(4) коммерческие права кавера проверять отдельно; (5) прочитать privacy перед загрузкой демки.

## Источники

[platform.acedata.cloud](https://platform.acedata.cloud/) · [docs](https://docs.acedata.cloud/en/introduction) · [SunoMCP](https://github.com/AceDataCloud/SunoMCP) · [pypi mcp-suno](https://pypi.org/project/mcp-suno/) · [The Suno API Reality](https://aimlapi.com/blog/the-suno-api-reality) · [PiAPI Suno (закрыт)](https://piapi.ai/suno-v5) · [GoAPI Suno (закрыт)](https://goapi.ai/suno-api) · [sunor.cc pricing](https://sunor.cc/blog/suno-api-pricing-2026) · [evolink pricing](https://evolink.ai/blog/suno-api-pricing) · [holder.io $ACE](https://holder.io/coins/ace-4/)
