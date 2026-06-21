# yougile-sync — задачи проекта reboot через YouGile API v2

Тонкий CLI к [YouGile](https://yougile.com) REST API v2. Заменяет корпоративную Репку.
Без зависимостей (только stdlib Python 3), без venv.

## Разовая настройка (≈3 минуты)

1. **Получить API-ключ** (логин/пароль от YouGile):
   ```bash
   cd _system/tools/yougile-sync
   python3 yougile-cli.py auth-companies --login you@mail --password '***'   # → companyId
   python3 yougile-cli.py auth-key --login you@mail --password '***' --company-id <companyId>
   ```
   Команда напечатает `key`. Сохрани его (machine-local, НЕ в репо):
   ```bash
   echo '<key>' > ~/.claude/yougile-token && chmod 600 ~/.claude/yougile-token
   ```
   (альтернатива — переменная окружения `YOUGILE_TOKEN`.)

2. **Настроить доску** — узнать id доски `reboot` и её колонок:
   ```bash
   python3 yougile-cli.py boards                       # → id доски reboot
   python3 yougile-cli.py columns --board-id <boardId> # → id колонок (todo/doing/done)
   ```
   Скопируй `yougile-config.example.json` → `yougile-config.json` и впиши id.
   Секретов в этом файле нет — его можно коммитить (общий конфиг для двоих).

3. Проверка: `python3 yougile-cli.py list` — должны прийти открытые задачи доски.

## Команды

| Команда | Что делает |
|---|---|
| `boards` | список досок (id + title) |
| `columns --board-id <id>` | колонки доски |
| `users` | пользователи (id/email/имя) — для маппинга исполнителей |
| `list [--column-id X] [--assigned-to U] [--all]` | задачи (по умолчанию незакрытые; `--all` — все) |
| `show --task-id X [--with-comments]` | детали задачи |
| `create --title T [--column-id X] [--description D] [--deadline YYYY-MM-DD] [--assign userId]` | создать задачу |
| `move --task-id X (--column-id Y \| --column-name doing)` | переместить в колонку |
| `done --task-id X` | отметить выполненной |
| `comment --task-id X --text "..."` | комментарий в чат задачи |

`--json` (глобальный флаг) — машиночитаемый вывод (его использует хук и агент).

## Как агент это использует

- Хук `.claude/check-yougile-tasks.ps1` на SessionStart даёт сводку (`YOUGILE:`), на каждый
  промпт/Stop — дельту (`YOUGILE-UPD:` / `YOUGILE-EOT:`). Без токена молчит.
- Команда `/create-task` — диалоговое создание задачи.
- Дисциплина «обнови статус задачи после работы» — в `rules/task-discipline.md`.

## Особенности API (важно при доработке CLI)

- Базовый URL `https://yougile.com/api-v2`, заголовок `Authorization: Bearer <key>`.
- Список задач — `GET /task-list` (НЕ `/tasks`), пагинация `{paging:{next}, content:[]}`.
- Нет серверного фильтра «completed» — фильтруем `completed` на клиенте.
- `deadline` — объект `{ "deadline": <ms-epoch>, "withTime": false }`, не ISO-строка.
- `PUT /tasks/{id}` массивы (`assigned`) ЗАМЕНЯЕТ целиком (read-modify-write).
- Комментарий = сообщение в чат задачи: `POST /chats/{taskId}/messages`, где `chatId == task id`.
- Лимит **50 запросов/мин на компанию** — не дёргай в цикле без нужды.

## Безопасность

- Токен — только в `~/.claude/yougile-token` (chmod 600) или env. **Никогда** не коммить и не печатать в чат.
- `yougile-config.json` секретов не содержит (только id доски/колонок) — коммитить можно.
