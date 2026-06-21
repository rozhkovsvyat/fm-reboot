# Claude из РФ зарубежной картой — анализ риска (ресёрч)

> Отчёт Opus-субагента по запросу [[team/rozhkov]] (2026-06-21). Связано: [[team/oleg]] (онбординг), [[state/now]].
> Вопрос: риск для Олега (РФ) при оформлении Claude Pro зарубежной картой; слух про «привязку паспорта».
> 🔴 **ИТОГ: риск ВЫСОКИЙ** — меняет решение об инструменте для Олега.

## TL;DR

- **Слух про паспортную/ID-верификацию — НЕ фейк, подтверждён частично.** Anthropic вводит проверку личности
  (госудостоверение + селфи, вендор Persona) для consumer Free / Pro / Max, **с 8 июля 2026**. НО проверка
  **условная** (не у всех/не при каждом входе, а «при доступе к отдельным функциям / комплаенс-проверках»),
  и Anthropic **нигде не называет её инструментом блокировки россиян** — эту связку домыслила пресса/слух.
- **Россия — неподдерживаемый регион.** Claude.ai / Claude Pro в РФ официально не работают; доступ из РФ уже
  нарушает Consumer Terms (OFAC-оговорка). Базовый давний факт.
- **Блокировки реальны и были массовыми.** Зафиксирована волна банов РФ-аккаунтов ~**8 мая 2026** («сотни»,
  по Baza + 6 изданий) — с **удалением данных** и возвратом денег за подписку.
- **Итоговый риск потерять аккаунт — ВЫСОКИЙ.**

## 1. Поддерживаемые страны / политика

Россия **НЕ входит** в [Supported countries](https://www.anthropic.com/supported-countries) (пров. 2026-06-21;
есть Казахстан, Армения, Грузия, Азербайджан, Молдова). [Consumer Terms](https://www.anthropic.com/legal/consumer-terms)
(эфф. 2025-10-08) требуют подтвердить, что пользователь не в embargoed-стране. Сент. 2025 — добавлен запрет по
владению (компании с контролем из неподдерживаемых юрисдикций) — это про **компании**, не физлиц.

## 2. Реальные кейсы блокировок РФ

**Да, была массовая волна ~8 мая 2026** (первоисточник Baza, растиражирован): «сотни» аккаунтов удалены без
предупреждения **вместе с данными**, подписчикам вернули деньги. Пострадали те, кто работал через VPN +
зарубежную/виртуальную оплату. Механизм (эксперт MWS AI): гео по IP-базам, обновляются раз в недели/месяцы;
после обновления базы РФ-IP детектится → бан. Шаренные VPN-IP флагуются; частая смена стран → ручная проверка.
Отдельные кейсы 2024–2026: бан за массовую CLI-автоматизацию; «organization disabled» из-за корпоративного VPN.
⚠️ Цифра «сотни» — один первоисточник; Anthropic не комментировал. Дата «8 мая 2026» надёжна (6+ изданий).

## 3. Слух про «паспорт» — оценка: ПОДТВЕРЖДЁН ЧАСТИЧНО

Слух склеивает два независимо истинных факта и подразумевает ложную причинную связь.

**Подтверждено:** Anthropic вводит проверку личности на consumer Claude Pro —
[Identity verification on Claude](https://support.claude.com/en/articles/14328960-identity-verification-on-claude)
(«Updated this week», пров. 2026-06-21): нужен government-issued photo ID + live selfie, вендор **Persona**.
Триггер **условный** («when accessing certain capabilities … routine platform integrity checks … compliance
measures»). Формализуется в privacy policy **эфф. 8 июля 2026**, для **Free/Pro/Max**, **исключая** Team/
Enterprise/API. Данные: фото ID, биометрия лица; не используются для обучения.

**НЕ подтверждено (ложная часть):** «ID-верификация = инструмент бана россиян» — это НЕ заявление Anthropic;
официальные страницы про неё не упоминают РФ/гео/санкции. Гео-блок РФ — отдельный давний механизм.

**Путаница, которую развели:** age assurance (Yoti, 18+, тоже 08.07.2026) — другое; OpenAI ID-verification —
другая компания, только API; экспорт-контроль топ-моделей (июнь 2026) — не consumer-верификация.

## 4. Оплата зарубежной картой из РФ

Работает при **полном region-match** (карта несанкционной страны + IP/VPN + billing той же страны). Виртуальные
карты — billing-страну ставить = стране BIN (не РФ). **НЕ работают:** карты РФ; VPN без подходящей карты.
Главный риск — **mismatch IP↔billing**: платёж скорит Stripe (не Anthropic) → отклонение/hold; обрыв VPN при
оплате (всплывает РФ-IP) опасен. ⚠️ РФ-гайды — промо реселлеров (биас «у нас легко»).

## 5. Митигации и fallback

- **«Одна страна для всего»** (IP+карта+billing+телефон); always-on VPN на ОДНУ страну (не переключать);
  резидентский/мобильный IP лучше datacenter/шаренного; «прогрев» аккаунта; не «новый аккаунт → сразу хэви».
- **Регион Google-аккаунта** — не основной фактор (Anthropic скорит IP/карту/поведение).
- **Fallback (НИЖЕ риск):** **API-путь / РФ-агрегаторы** (GPTunnel, BotHub, GenAPI, AITunnel) — рубли/СБП,
  без VPN, экспозиция ToS на агрегаторе, а не на тебе. ⚠️ OpenRouter с ~11 мая 2026 заблокировал оплату для РФ.
  Свой VPS за рубежом + Claude Code по SSH (инструмент не видит РФ-IP). Без VPN/рубли: GigaChat, YandexGPT,
  DeepSeek, Qwen (в т.ч. локально через Ollama).

## 6. Итог: риск **ВЫСОКИЙ**

Не один риск, а стек: (1) доступ из РФ — нарушение ToS, бан «по праву» в любой момент; (2) реальный массовый
прецедент (май 2026) с **необратимой потерей данных**; (3) с 08.07.2026 — условная ID-верификация (если
сработает — РФ-пользователь без match-региона удостоверения в тупике); (4) апелляции почти не работают.

**Ответ на исходный страх:** «введут паспорт и заблокируют РФ» — наполовину правда: паспорт-проверку вводят
(условную, с 08.07.2026), блокировка РФ существует независимо; а связка «паспорт ради бана россиян» — домысел.

**Практика:** оформить Claude Pro из РФ зарубежной картой технически можно, но ставка высокая — аккаунт и все
наработки могут исчезнуть без предупреждения (вернут лишь деньги за подписку). Если данные важны:
(а) не держать в Claude единственную копию (у нас vault в Git — ✅ безопасно);
(б) рассмотреть **API-путь / РФ-агрегатор как основной** (ниже риск), consumer Pro — как дополнительный;
(в) при Pro строго «одна страна для всего» + резидентский always-on VPN;
(г) иметь fallback (DeepSeek/Qwen/GigaChat/локальные).

## Источники

Anthropic: [Supported countries](https://www.anthropic.com/supported-countries) · [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) · [AUP](https://www.anthropic.com/legal/aup) · [Restrictions to unsupported regions, 2025-09-04](https://www.anthropic.com/news/updating-restrictions-of-sales-to-unsupported-regions) · [Identity verification](https://support.claude.com/en/articles/14328960-identity-verification-on-claude) · [Age assurance](https://support.claude.com/en/articles/15171100-age-assurance-on-claude)
ID-верификация (июнь 2026): [cybernews](https://cybernews.com/ai-news/anthropic-privacy-policy-id-verification/) · [TechTimes 2026-06-21](https://www.techtimes.com/articles/318778/20260621/claude-identity-verification-starts-july-8-what-facial-data-anthropic-collects.htm)
Баны РФ (май 2026): [CNews 2026-05-08](https://www.cnews.ru/news/top/2026-05-08_nejroset_claude_poshla_vojnoj) · [thecode.media](https://thecode.media/claude-nachal-massovo-banit-polzovatelej-iz-rossii/) · [anti-malware.ru](https://www.anti-malware.ru/news/2026-05-08-121598/49979) · [hi-tech.mail.ru](https://hi-tech.mail.ru/news/147459-pochemu-ii-servis-claude-massovo-blokiruet-rossiyan-otvet-eksperta/)
Оплата/митигации/fallback: [vc.ru API-путь](https://vc.ru/ai/2879076-kak-razrabotchiku-nastroit-dostup-k-claude-v-rossii-legalo) · [Habr OpenRouter 2026-05](https://habr.com/ru/news/1034012/) · [dtf.ru без VPN](https://dtf.ru/top_rating/4777561-neyroseti-v-rossii-bez-vpn)

### Неопределённости
- «Сотни аккаунтов» — единственный первоисточник (Baza), точное число не подтверждено.
- Проценты (mismatch ~60%, апелляции ~3%) — community field data, не авторитетны.
