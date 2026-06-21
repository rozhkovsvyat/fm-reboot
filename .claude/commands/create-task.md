---
description: Создать задачу в YouGile (доска reboot) через диалог
argument-hint: "[название задачи]"
---

Создай задачу на доске **reboot** в YouGile.

Предусловие: настроен `~/.claude/yougile-token` и `_system/tools/yougile-sync/yougile-config.json`
(см. `_system/tools/yougile-sync/README.md`). Нет токена/конфига — скажи пользователю, как настроить.

1. Название: из `$ARGUMENTS` или спроси.
2. Уточни (коротко, можно одним `AskUserQuestion`): колонка (todo/doing/done — дефолт `default_column`
   из конфига), описание (опц.), дедлайн `YYYY-MM-DD` (опц.), исполнитель (опц. — `yougile-cli.py users`).
3. Покажи, что будешь создавать, подтверди.
4. Выполни:
   ```bash
   python3 _system/tools/yougile-sync/yougile-cli.py --json create --title "..." [--description "..."] [--deadline YYYY-MM-DD] [--column-id ... | дефолт из конфига]
   ```
5. Покажи `task_id` и подтверди создание. Не печатай токен.
6. Если задача стартует сейчас — предложи сразу `move --column-name doing`.
