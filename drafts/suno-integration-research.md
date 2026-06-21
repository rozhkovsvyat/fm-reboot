# Suno: программная интеграция — ресёрч

> Отчёт Opus-субагента по запросу [[team/rozhkov]] (2026-06-21). Связано: [[drafts/ai-tooling-feasibility]]
> (направление B — Suno), [[drafts/reboot-context-intake]], [[decisions/0002-release-as-singles]].
> **Кандидат в ADR** «выбор движка музыкальной генерации».
> ⚠️ Тема быстро устаревает: Suno активно меняет ToS (партнёрства с Warner Music и др.), официального API
> всё ещё нет, неофициальные обёртки появляются и исчезают. Помечено ⚠️, где данные особенно ломкие.

## TL;DR

- **Официального публичного API у Suno НЕТ** (на середину 2026). Нет developer-портала, нет генерации
  API-ключа в настройках, нет SDK. Все «Suno API» в интернете — **сторонние reverse-engineered обёртки**,
  нарушающие ToS Suno.
- **Полный нужный воркфлоу (cover из своей демки → батч-вариации → выгрузка 6–12 стемов) технически
  достижим только через неофициальные сервисы.** Работает, но юридически в серой зоне, с реальным риском
  бана аккаунта и вопросом приватности «невыпущенной музыки».
- **Самый «агентопригодный» путь** — managed-сервис AceData Cloud + их готовый MCP-сервер (`SunoMCP`):
  есть `upload_cover` (подать демку) и stem-separation, Bearer-токен, оплата по кредитам. Но это всё
  равно неофициальный посредник.
- **Если приоритет — легальность и приватность, а не именно «звук Suno»** — единственная альтернатива
  с официальным API на лицензированных данных, broad commercial use И встроенной stem-separation —
  **ElevenLabs Eleven Music API**. Cover именно «вашей демки» там нет, но композиционный контроль и стемы есть.

## 1. Официальный публичный API Suno

**Статус: отсутствует.** Подтверждено несколькими независимыми источниками 2025–2026 (MusicGPT 2026;
AI/ML API Blog: «Every "Suno API" you encounter… is a reverse-engineered workaround»). Suno остаётся
consumer-платформой (веб + Suno Studio); публичного self-serve ключа нет.

**ToS и автоматизация:** Terms прямо запрещают scrape/copy/frame и автоматизированный доступ без
авторизации. Повторные нарушения → перманентный бан. В 2025–2026 ToS переписывались под лицензионные
сделки (Warner Music и др.) — коммерческие условия использования вывода менялись.

⚠️ Встречалось одиночное утверждение «Suno и Udio запустили public API в конце 2025» — **противоречит**
официальной справке Udio и прямым 2026-источникам. Считать недостоверным агрегаторным шумом.

## 2. Неофициальные варианты

### A. Self-hosted open-source (вы приносите свой Suno-аккаунт)

| Проект | Авторизация | Что умеет | Caveats |
|---|---|---|---|
| **gcui-art/suno-api** (≈3k★, активный) | `SUNO_COOKIE` из DevTools + 2Captcha для hCaptcha | generate, custom_generate, extend, concat, **generate_stems**, lyrics, OpenAI-совместимый чат | **Нет upload/cover** (нельзя подать свою демку). «for research only». Бан-риск на ВАШЕМ аккаунте. CAPTCHA-расходы. |
| yihong0618/…, Malith-Rukshan/… | cookie/сессия | генерация, базовые операции | Та же серая зона; поддержка нерегулярная |

Механика: ваш cookie превращает аккаунт в локальный API-сервер = **прямое использование вашего реального
аккаунта роботом** → максимальный риск бана.

### B. Managed-сервисы (посредник держит пул аккаунтов)

| Сервис | Авторизация | Цена (≈2026) | Cover/upload | Стемы | Примечание |
|---|---|---|---|---|---|
| **AceData Cloud** | Bearer-токен | кредиты | **Да** (`upload_cover`, `upload_extend`) | Да | **Готовый MCP-сервер** `SunoMCP`. Persona, mashup, remaster, replace-section. |
| **sunoapi.org** | Bearer | $19–199/мес | Да | **`separate_vocal`=2; `split_stem`=до 12 стемов** | Модели V3.5–V5.5. Async через callback, ссылки живут 14 дней. |
| **kie.ai** | Bearer | кредиты | Да | vocal separation | base `api.kie.ai`, V3.5–V5.5 |
| **ApiPass/aimlapi** | API-key | **~$0.014/песня** pay-as-you-go | Да | 2 стема | Самые дешёвые; зависят от upstream |
| **Evolink** | API-key | ~$0.111/песня | Да | — | дороже, «99.9% uptime» |
| **PiAPI** | API-key | — | было | — | ⚠️ **Suno V5 API закрыт** на момент проверки (пример ломкости) |

**Риск:** все managed держатся на пулах реальных аккаунтов Suno; при ужесточении anti-bot любой может
«лечь» (как PiAPI). «Commercial license» от посредников юридически не обеспечена.

## 3. Cover (вход — ваша демка) + выгрузка стемов — ключ к воркфлоу

**Да, достижимо — но только через managed-сервисы, не gcui-art.**
- **Подать демку (cover/extend):** AceData (`upload_cover`/`upload_extend`), sunoapi.org, kie.ai, ApiPass. Аплоад до 8 мин.
- **Стемы:** лучший вариант — **sunoapi.org `split_stem` (до 12 дорожек)**, покрывает ваши «6–8» с запасом.
  У остальных чаще базовый `separate_vocal` (2 стема). Возврат асинхронный (webhook), ссылки временные (~14 дней).
- Батч-вариации = N параллельных вызовов generate/cover с одним промптом.

## 4. Persona / голос через API

> ⚠️ Свят (2026-06-21): **персона у дуэта НЕ используется** (была задача REB-33, в воркфлоу не вошла) →
> persona-поддержка **не является критерием** выбора интеграции.

- **AceData** — заявлена persona-based generation (консистентный «голос» между треками) + mashup/remaster.
- sunoapi.org/kie.ai — модели V5.5 «voice-customized». В self-hosted gcui-art persona нет.
- ⚠️ Persona чувствительна к версиям модели и ToS (клонирование голоса); через обёртки нестабильна.

## 5. Архитектура интеграции Claude-агента

**Путь A (официальный) — невозможен:** API нет. Остаётся только браузерная автоматизация веб-UI
(Playwright/Chrome-DevTools MCP — они у нас в окружении есть), но это тоже нарушает ToS, хрупко к
редизайну и упирается в CAPTCHA. Не для продакшна.

**Путь B (реалистичный):**
- **B1 — MCP-сервер (рекомендуется):** `Claude ──MCP──▶ AceData SunoMCP ──Bearer──▶ AceData ──▶ Suno (пул)`.
  SunoMCP даёт tools: generate / `upload_cover` / extend / concat / **stem-separation** / persona / lyrics /
  экспорт WAV·MP4·MIDI (релиз v2026.6.18.0). Я вызываю их прямо из диалога. **Автоматизируется:** сборка
  промптов, батч-генерация, опрос статуса, скачивание, stem-split, раскладка по папкам. **Вручную остаётся:**
  художественный финальный отбор, регистрация токена/оплата, юридическое решение.
- **B2 — прямые HTTP** к sunoapi.org/kie.ai (гибче по 12-стемам, но MCP писать самому; нужны webhooks/polling).
- **B3 — self-hosted gcui-art:** дешевле, но **нет cover** (ломает воркфлоу) + макс. бан-риск. Не рекомендуется.

## 6. Альтернативы с официальным API

| Сервис | Офиц. API | Cover вашей демки | Стемы | Лицензия | Примечание |
|---|---|---|---|---|---|
| **ElevenLabs Eleven Music** | **Да** | Нет (но `composition_plan`: секции/стиль/текст) | **Да, офиц. endpoint** | обучен на лицензир. стемах, broad commercial | Самый легальный. 59 языков вокала. Звук иной. |
| **Stable Audio 2.5/3.0** | **Да** | **audio inpainting** (своё аудио как контекст) | частично | лицензир. датасет | силён в инструментале, **слаб в вокале** |
| **Udio** | **Нет** | — | — | после сделки с UMG | только обёртки, та же серая зона |
| **MusicGPT** | Да | зависит | зависит | — | проверять условия отдельно |

## 7. Рекомендация и риски

**Рекомендация:**
1. **Если остаёмся на Suno:** AceData Cloud + SunoMCP (cover+стемы+persona, MCP под агента), либо
   sunoapi.org напрямую при нужде в полном 12-стем split.
2. **Если готовы сменить движок ради легальности/приватности:** ElevenLabs Eleven Music API (офиц.,
   лицензир., со стемами; cover вашей демки нет, но composition_plan + стемы закрывают многое). Для
   инструментальных идей — Stable Audio (inpainting от вашего сэмпла).

**Риски (проговорить с Олегом):**
- 🔴 **Приватность невыпущенной музыки.** Демка/референс уходят неофициальному посреднику с непрозрачным
  хранением. Для эксклюзивного релиза — серьёзный риск.
- 🔴 **Бан аккаунта.** Любой неофиц. доступ нарушает ToS; self-hosted рискует вашим аккаунтом, managed — пулом.
- 🔴 **Ломкость.** Обёртки ломаются без предупреждения (PiAPI уже «лёг»); цены/доступность нестабильны.
- **Юр. неопределённость вывода:** иск RIAA (июнь 2024) + меняющиеся ToS → коммерческие права на вывод Suno спорны.
- **Стоимость:** ~$0.014–0.11/песня + кредиты за стемы, поверх подписки Suno.

⚠️ **Перепроверить перед внедрением:** актуальность ToS Suno; живость выбранного сервиса; политику
хранения загруженного аудио; реальный набор стемов (2 vs 12) в конкретном плане.

## Разбор и стоимость (вопросы Свята, 2026-06-21)

- **Персона НЕ используется** дуэтом → не критерий выбора интеграции.
- **Приватность — не differentiator против AceData:** демки уже грузятся в сам Suno; AceData = +1 хоп
  (маргинальный рост, не новая категория). Снято.
- **Вердикт AceData:** для автоматизации Suno — подходящий выбор. Прежняя нерешительность была про
  **тайминг** (автоматизирует генерацию, а пробка — сведение), не про пригодность. Единственный caveat
  перед полным внедрением — **мини-POC** на вашем материале (cover-from-demo + нужные стемы), не прыжок по отчёту.

### Стоимость (модель расчёта)

⚠️ Точные тарифы AceData в ресёрче не зафиксированы — **требуют проверки** (страница цен AceData).

**Структурный момент:** AceData держит СВОЙ пул Suno-аккаунтов → платишь кредиты AceData; отдельная личная
подписка Suno Pro для AceData-пути формально НЕ обязательна. Два конфига:
- **(a) Manual Suno + AceData** (реалистично): платишь и подписку Suno, и кредиты AceData. Сохраняешь
  ручной воркфлоу + личную библиотеку.
- **(b) Всё через AceData:** только кредиты, но теряешь личный workspace/библиотеку Suno.

**Цифры (оценка, верифицировать):**
- Suno Pro ≈ $10/мес (~2500 кредитов ≈ ~250 генераций); Premier ≈ $30/мес (~10000 кредитов).
- AceData — credits, pay-per-use; по рынку обёрток генерация ≈ $0.014–0.11/песня, стемы — отдельно.
- Драйвер цены — **объём генераций** («мучаем»): при вашем объёме ≈ $1–15/мес кредитов (десятки $, не сотни).
- **Итого (конфиг a):** Suno ~$10 + AceData ~$1–15 ≈ **~$11–25/мес** (+ Claude Pro Олега $20 отдельно).

## Источники

- Suno [Terms](https://suno.com/terms-of-service) · [Community Guidelines](https://suno.com/community-guidelines)
- [The Suno API Reality — AI/ML API](https://aimlapi.com/blog/the-suno-api-reality) · [Public Suno API in 2026 — MusicGPT](https://musicgpt.com/blog/suno-api)
- [gcui-art/suno-api](https://github.com/gcui-art/suno-api) · [AceDataCloud/SunoMCP](https://github.com/AceDataCloud/SunoMCP) · [Ace Data Cloud](https://platform.acedata.cloud/)
- [docs.sunoapi.org](https://docs.sunoapi.org/) · [Stem Separation](https://docs.sunoapi.org/suno-api/separate-vocals-from-music) · [docs.kie.ai](https://docs.kie.ai/suno-api/quickstart)
- [PiAPI Suno V5 (закрыт)](https://piapi.ai/suno-v5) · [Top 7 Suno API Providers — CompanionLink, 2026-05](https://www.companionlink.com/blog/2026/05/top-7-suno-api-providers-ranked-by-cost-effectiveness-the-ultimate-guide/) · [Suno API Pricing 2026 — Sunor](https://sunor.cc/blog/suno-api-pricing-2026)
- ElevenLabs [Music API](https://elevenlabs.io/music-api) · [Stem Separation](https://elevenlabs.io/docs/api-reference/music/separate-stems) · [Composition plan](https://elevenlabs.io/docs/api-reference/music/create-composition-plan) · [Pricing](https://elevenlabs.io/pricing/api)
- [Udio — нет public API (12.03.2025)](https://help.udio.com/en/articles/10756277-udio-public-api)
- [Stable Audio 2.5](https://stability.ai/news-updates/stability-ai-introduces-stable-audio-25-the-first-audio-model-built-for-enterprise-sound-production-at-scale) · [Replicate API](https://replicate.com/stability-ai/stable-audio-2.5/api/api-reference)
- ⚠️ [Suno vs Udio vs ElevenLabs 2026 — AI Magicx](https://www.aimagicx.com/blog/suno-vs-udio-vs-elevenlabs-music-comparison-2026) (содержит недостоверное про «public API late 2025» — не опираться)
