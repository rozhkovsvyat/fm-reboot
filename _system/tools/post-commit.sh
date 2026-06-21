#!/usr/bin/env bash
# post-commit hook: дописывает коммит в общую базу знаний.
# Установка: см. tools/README.md в vault'е.

set -euo pipefail

VAULT="$(git config --get kb.vault || true)"
AUTHOR="$(git config --get kb.author || true)"

if [[ -z "$VAULT" || -z "$AUTHOR" ]]; then
  echo "kb post-commit: kb.vault или kb.author не заданы в git config — пропускаю" >&2
  exit 0
fi

if [[ ! -d "$VAULT" ]]; then
  echo "kb post-commit: vault '$VAULT' не найден — пропускаю" >&2
  exit 0
fi

SHA="$(git rev-parse --short HEAD)"
SUBJECT="$(git log -1 --pretty=%s)"
REPO="$(basename "$(git rev-parse --show-toplevel)")"
DATE="$(date '+%Y-%m-%d')"
TIME="$(date '+%H:%M')"

# Список затронутых файлов (для определения сервисов).
FILES="$(git show --name-only --pretty=format: HEAD | sed '/^$/d')"

# 1) activity.md — добавляем строку после маркера "## События" + блок ```.
ACTIVITY="$VAULT/state/activity.md"
if [[ -f "$ACTIVITY" ]]; then
  LINE="$DATE $TIME | commit | $AUTHOR | $REPO@$SHA: $SUBJECT |"
  # Вставляем после строки, начинающейся с тройных бэктиков после "## События".
  awk -v line="$LINE" '
    BEGIN { inserted = 0 }
    {
      print
      if (!inserted && /^```$/) {
        # пропускаем — это закрывающие бэктики, нам нужны открывающие
      }
    }
    /^## События/ { in_section = 1; next_is_open = 1; print; next }
  ' "$ACTIVITY" > "$ACTIVITY.tmp" 2>/dev/null || cp "$ACTIVITY" "$ACTIVITY.tmp"
  # Простая надёжная вставка: ищем строку "```" после "## События" и вставляем после неё.
  python3 - "$ACTIVITY" "$LINE" <<'PY' || true
import sys, pathlib
path = pathlib.Path(sys.argv[1])
line = sys.argv[2]
text = path.read_text(encoding="utf-8").splitlines()
out = []
inserted = False
seen_header = False
for i, l in enumerate(text):
    out.append(l)
    if not inserted and l.strip().startswith("## События"):
        seen_header = True
    if not inserted and seen_header and l.strip() == "```":
        out.append(line)
        inserted = True
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
  rm -f "$ACTIVITY.tmp"
fi

# 2) daily/YYYY-MM-DD.md — добавляем bullet под секцией автора (создаём файл, если нет).
DAILY="$VAULT/state/daily/$DATE.md"
mkdir -p "$VAULT/state/daily"
if [[ ! -f "$DAILY" ]]; then
  cat > "$DAILY" <<EOF
# $DATE

> Дневной лог команды. Каждый дописывает свою секцию.

## [[team/$AUTHOR]]

**Сделано:**
- $REPO@$SHA: $SUBJECT

**В работе:**
-

**Заблокировано:**
-
EOF
else
  python3 - "$DAILY" "$AUTHOR" "$REPO@$SHA: $SUBJECT" <<'PY' || true
import sys, pathlib, re
path, author, msg = sys.argv[1], sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
header = f"## [[team/{author}]]"
if header not in text:
    # Добавляем секцию автора в конец.
    text += f"\n\n{header}\n\n**Сделано:**\n- {msg}\n\n**В работе:**\n-\n\n**Заблокировано:**\n-\n"
else:
    # Вставляем bullet под "**Сделано:**" в секции автора.
    pattern = re.compile(
        rf"({re.escape(header)}.*?\*\*Сделано:\*\*\n)((?:- .*\n)*)",
        re.DOTALL
    )
    def repl(m):
        return m.group(1) + m.group(2) + f"- {msg}\n"
    new = pattern.sub(repl, text, count=1)
    text = new if new != text else text + f"\n- {msg}\n"
path.write_text(text, encoding="utf-8")
PY
fi

# 3) now.md — обновляем "Активные касания сервисов", если в коммите есть файлы из known service.
NOW="$VAULT/state/now.md"
if [[ -f "$NOW" && -d "$VAULT/product/services" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  # Собираем затронутые сервисы по совпадению пути с именами карточек product/services/<svc>.md.
  for svc_file in "$VAULT/product/services/"*.md; do
    [[ -e "$svc_file" ]] || continue
    svc="$(basename "$svc_file" .md)"
    [[ "$svc" == "_template" ]] && continue
    if echo "$FILES" | grep -qiE "(^|/)$svc(/|$)"; then
      python3 - "$NOW" "$svc" "$AUTHOR" "$BRANCH" "$DATE" <<'PY' || true
import sys, pathlib, re
path, svc, author, branch, date = sys.argv[1:6]
text = pathlib.Path(path).read_text(encoding="utf-8")
row = f"| {svc} | [[team/{author}]] | `{branch}` | {date} |"
# Ищем таблицу под "## Активные касания сервисов".
m = re.search(r"(## Активные касания сервисов.*?\n\| Сервис .*?\n\|[-| ]+\|\n)((?:\|.*\n)*)", text, re.DOTALL)
if m:
    head, body = m.group(1), m.group(2)
    # Убираем существующую строку для (svc, author), чтобы заменить.
    body_lines = [l for l in body.splitlines() if not (l.startswith(f"| {svc} |") and f"[[team/{author}]]" in l)]
    # Убираем строку "_(пусто)_".
    body_lines = [l for l in body_lines if "_(пусто)_" not in l]
    body_lines.append(row)
    new_body = "\n".join(body_lines) + "\n"
    text = text[:m.start()] + head + new_body + text[m.end():]
    pathlib.Path(path).write_text(text, encoding="utf-8")
PY
    fi
  done
fi

exit 0
