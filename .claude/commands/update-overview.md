---
description: Проверить и точечно обновить meta/project-overview.md
---

Актуализируй `meta/project-overview.md`, если он отстал.

1. Узнай, что менялось после последнего апдейта overview:
   `git log --oneline <last-overview-commit>..HEAD -- decisions/ rules/ state/now.md team/ meta/CLAUDE.md`
   (хук `check-overview-stale.ps1` уже мог прислать `OVERVIEW:` с числом коммитов).
2. Прочитай `meta/project-overview.md` и сверь с актуальным состоянием (`state/now.md`, свежие `decisions/`).
3. Точечно обнови устаревшие места: стек, архитектура, текущий этап. **Не переписывай целиком** —
   правь только то, что разошлось с реальностью.
4. Не выдумывай — бери факты из vault'а/кода. Неясное помечай как вопрос, а не догадку.
5. В конце перечисли, что обновил.
