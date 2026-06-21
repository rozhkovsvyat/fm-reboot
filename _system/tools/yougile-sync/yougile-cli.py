#!/usr/bin/env python3
"""
yougile-cli.py — тонкий CLI-клиент к YouGile REST API v2 (kanban-задачи).
Замена корпоративной Репки для проекта fm-reboot / доска "reboot".

Без внешних зависимостей (stdlib only: urllib). Не требует venv.

Аутентификация:
  Токен ищется в таком порядке:
    1. env YOUGILE_TOKEN
    2. файл ~/.claude/yougile-token  (plaintext, НЕ коммитить — он в .gitignore через ~/.claude)
  Сгенерировать токен один раз:
    python3 yougile-cli.py auth-companies --login you@mail --password ***   # узнать companyId
    python3 yougile-cli.py auth-key --login you@mail --password *** --company-id <id>
  → распечатает key; положи его:  echo '<key>' > ~/.claude/yougile-token && chmod 600 ~/.claude/yougile-token

Конфиг доски (без секретов, можно коммитить) — yougile-config.json рядом с этим файлом:
  { "board_id": "...", "columns": {"todo": "...", "doing": "...", "done": "..."},
    "default_column": "todo" }
  Узнать id:  python3 yougile-cli.py boards   и   python3 yougile-cli.py columns --board-id <id>

API: https://yougile.com/api-v2 — Authorization: Bearer <key>. Лимит 50 req/min.
Гайд по полям — _system/tools/yougile-sync/README.md.
"""
import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

API_BASE = "https://yougile.com/api-v2"
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "yougile-config.json")
TOKEN_FILE = os.path.expanduser("~/.claude/yougile-token")


# ─────────────────────────── низкоуровневый HTTP ───────────────────────────

def _request(method, path, token=None, body=None, query=None):
    url = API_BASE + path
    if query:
        qs = "&".join(f"{k}={urllib.parse.quote(str(v))}" for k, v in query.items() if v is not None)
        if qs:
            url += "?" + qs
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise ApiError(f"HTTP {e.code}", detail)
    except urllib.error.URLError as e:
        raise ApiError("network", str(e.reason))


class ApiError(Exception):
    def __init__(self, code, detail):
        self.code = code
        self.detail = detail
        super().__init__(f"{code}: {detail}")


# ─────────────────────────── токен / конфиг ───────────────────────────

def get_token():
    tok = os.environ.get("YOUGILE_TOKEN")
    if tok:
        return tok.strip()
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, encoding="utf-8") as f:
            return f.read().strip()
    return None

def require_token():
    tok = get_token()
    if not tok:
        fail("no_token", f"Токен не найден. Положи в env YOUGILE_TOKEN или в {TOKEN_FILE}. "
                         f"Сгенерируй: auth-companies → auth-key (см. шапку файла).")
    return tok

def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


# ─────────────────────────── вывод ───────────────────────────

def out(obj, as_json):
    if as_json:
        print(json.dumps(obj, ensure_ascii=False, indent=2))
    else:
        print(human(obj))

def fail(code, detail):
    print(json.dumps({"ok": False, "error": code, "detail": detail}, ensure_ascii=False))
    sys.exit(1)

def human(obj):
    if isinstance(obj, dict) and "tasks" in obj:
        lines = [f"Задач: {obj.get('count', len(obj['tasks']))}"]
        for t in obj["tasks"]:
            mark = "✅" if t.get("completed") else "▢"
            dl = f"  ⏰ {t['deadline']}" if t.get("deadline") else ""
            lines.append(f"  {mark} {t['id']}  {t['title']}{dl}")
        return "\n".join(lines)
    return json.dumps(obj, ensure_ascii=False, indent=2)

def ms_to_date(ms):
    if not ms:
        return None
    try:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return None

def date_to_ms(d):
    dt = datetime.strptime(d, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)

def simplify_task(t):
    dl = None
    if isinstance(t.get("deadline"), dict):
        dl = ms_to_date(t["deadline"].get("deadline"))
    return {
        "id": t.get("id"),
        "title": t.get("title"),
        "columnId": t.get("columnId"),
        "completed": t.get("completed", False),
        "assigned": t.get("assigned", []),
        "deadline": dl,
        "description": t.get("description", ""),
    }


# ─────────────────────────── команды ───────────────────────────

def cmd_auth_companies(args):
    res = _request("POST", "/auth/companies", body={"login": args.login, "password": args.password})
    companies = [{"id": c.get("id"), "name": c.get("name"), "isAdmin": c.get("isAdmin")}
                 for c in res.get("content", [])]
    out({"ok": True, "companies": companies}, args.json)

def cmd_auth_key(args):
    res = _request("POST", "/auth/keys",
                   body={"login": args.login, "password": args.password, "companyId": args.company_id})
    key = res.get("key")
    if not key:
        fail("no_key", f"Ключ не получен: {res}")
    out({"ok": True, "key": key,
         "hint": f"Сохрани: echo '{key}' > {TOKEN_FILE} && chmod 600 {TOKEN_FILE}"}, args.json)

def cmd_boards(args):
    tok = require_token()
    res = _request("GET", "/boards", token=tok, query={"limit": 1000})
    boards = [{"id": b.get("id"), "title": b.get("title")} for b in res.get("content", [])]
    out({"ok": True, "boards": boards}, args.json)

def cmd_columns(args):
    tok = require_token()
    board_id = args.board_id or load_config().get("board_id")
    if not board_id:
        fail("no_board", "Укажи --board-id или пропиши board_id в yougile-config.json")
    res = _request("GET", "/columns", token=tok, query={"boardId": board_id, "limit": 1000})
    cols = [{"id": c.get("id"), "title": c.get("title")} for c in res.get("content", [])]
    out({"ok": True, "board_id": board_id, "columns": cols}, args.json)

def cmd_users(args):
    tok = require_token()
    res = _request("GET", "/users", token=tok, query={"limit": 1000})
    users = [{"id": u.get("id"), "email": u.get("email"), "realName": u.get("realName")}
             for u in res.get("content", [])]
    out({"ok": True, "users": users}, args.json)

def _fetch_tasks(tok, column_id=None, assigned_to=None):
    """Постранично собирает задачи (paging.next), возвращает список raw-task."""
    tasks = []
    offset = 0
    while True:
        q = {"limit": 1000, "offset": offset}
        if column_id:
            q["columnId"] = column_id
        if assigned_to:
            q["assignedTo"] = assigned_to
        res = _request("GET", "/task-list", token=tok, query=q)
        tasks.extend(res.get("content", []))
        paging = res.get("paging", {})
        if not paging.get("next"):
            break
        offset += paging.get("limit", 1000)
    return tasks

def cmd_list(args):
    tok = require_token()
    cfg = load_config()
    column_ids = []
    if args.column_id:
        column_ids = [args.column_id]
    elif cfg.get("columns"):
        column_ids = list(cfg["columns"].values())
    raw = []
    if column_ids:
        for cid in column_ids:
            raw.extend(_fetch_tasks(tok, column_id=cid, assigned_to=args.assigned_to))
    else:
        raw = _fetch_tasks(tok, assigned_to=args.assigned_to)
    tasks = [simplify_task(t) for t in raw if not t.get("deleted")]
    if not args.all:
        tasks = [t for t in tasks if not t["completed"]]
    out({"ok": True, "count": len(tasks), "tasks": tasks}, args.json)

def cmd_show(args):
    tok = require_token()
    t = _request("GET", f"/tasks/{args.task_id}", token=tok)
    task = simplify_task(t)
    if args.with_comments:
        msgs = _request("GET", f"/chats/{args.task_id}/messages", token=tok, query={"limit": 50})
        task["comments"] = [{"text": m.get("text"), "from": m.get("fromUserId")}
                            for m in msgs.get("content", [])]
    out({"ok": True, "task": task}, args.json)

def cmd_create(args):
    tok = require_token()
    cfg = load_config()
    column_id = args.column_id
    if not column_id and cfg.get("columns") and cfg.get("default_column"):
        column_id = cfg["columns"].get(cfg["default_column"])
    if not column_id:
        fail("no_column", "Укажи --column-id или настрой columns+default_column в yougile-config.json")
    body = {"title": args.title, "columnId": column_id}
    if args.description:
        body["description"] = args.description
    if args.assign:
        body["assigned"] = args.assign.split(",")
    if args.deadline:
        body["deadline"] = {"deadline": date_to_ms(args.deadline), "withTime": False}
    res = _request("POST", "/tasks", token=tok, body=body)
    out({"ok": True, "task_id": res.get("id"), "title": args.title, "columnId": column_id}, args.json)

def cmd_move(args):
    tok = require_token()
    cfg = load_config()
    column_id = args.column_id
    if not column_id and args.column_name and cfg.get("columns"):
        column_id = cfg["columns"].get(args.column_name)
    if not column_id:
        fail("no_column", "Укажи --column-id или --column-name (из yougile-config.json columns)")
    _request("PUT", f"/tasks/{args.task_id}", token=tok, body={"columnId": column_id})
    out({"ok": True, "task_id": args.task_id, "moved_to": column_id}, args.json)

def cmd_done(args):
    tok = require_token()
    _request("PUT", f"/tasks/{args.task_id}", token=tok, body={"completed": True})
    out({"ok": True, "task_id": args.task_id, "completed": True}, args.json)

def cmd_comment(args):
    tok = require_token()
    # chatId == task id
    _request("POST", f"/chats/{args.task_id}/messages", token=tok, body={"text": args.text})
    out({"ok": True, "task_id": args.task_id, "commented": True}, args.json)


# ─────────────────────────── argparse ───────────────────────────

def build_parser():
    p = argparse.ArgumentParser(description="YouGile CLI (доска reboot)")
    p.add_argument("--json", action="store_true", help="JSON-вывод (по умолчанию человекочитаемо)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("auth-companies", help="список компаний по логину/паролю (узнать companyId)")
    s.add_argument("--login", required=True); s.add_argument("--password", required=True)
    s.set_defaults(func=cmd_auth_companies)

    s = sub.add_parser("auth-key", help="сгенерировать API-ключ")
    s.add_argument("--login", required=True); s.add_argument("--password", required=True)
    s.add_argument("--company-id", required=True); s.set_defaults(func=cmd_auth_key)

    s = sub.add_parser("boards", help="список досок"); s.set_defaults(func=cmd_boards)

    s = sub.add_parser("columns", help="колонки доски")
    s.add_argument("--board-id"); s.set_defaults(func=cmd_columns)

    s = sub.add_parser("users", help="список пользователей (для маппинга исполнителей)")
    s.set_defaults(func=cmd_users)

    s = sub.add_parser("list", help="список задач (по умолчанию незакрытые)")
    s.add_argument("--column-id"); s.add_argument("--assigned-to")
    s.add_argument("--all", action="store_true", help="включая закрытые")
    s.set_defaults(func=cmd_list)

    s = sub.add_parser("show", help="детали задачи")
    s.add_argument("--task-id", required=True)
    s.add_argument("--with-comments", action="store_true")
    s.set_defaults(func=cmd_show)

    s = sub.add_parser("create", help="создать задачу")
    s.add_argument("--title", required=True); s.add_argument("--column-id")
    s.add_argument("--description"); s.add_argument("--assign", help="userId(ы) через запятую")
    s.add_argument("--deadline", help="YYYY-MM-DD"); s.set_defaults(func=cmd_create)

    s = sub.add_parser("move", help="переместить задачу в колонку")
    s.add_argument("--task-id", required=True)
    s.add_argument("--column-id"); s.add_argument("--column-name", help="ключ из config columns: todo/doing/done")
    s.set_defaults(func=cmd_move)

    s = sub.add_parser("done", help="отметить задачу выполненной")
    s.add_argument("--task-id", required=True); s.set_defaults(func=cmd_done)

    s = sub.add_parser("comment", help="комментарий в чат задачи")
    s.add_argument("--task-id", required=True); s.add_argument("--text", required=True)
    s.set_defaults(func=cmd_comment)

    return p


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except ApiError as e:
        fail(e.code, e.detail)


if __name__ == "__main__":
    main()
