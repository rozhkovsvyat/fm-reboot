# Activity — лента событий

> Коммиты дописывает git-хук (`_system/tools/post-commit.sh`) автоматически.
> Заметки (note/adr/status) добавляет агент — новые сверху, сразу под `## События`.
> Хук `archive-activity-overflow.ps1` режет ленту до 50 событий, старшее → `state/weekly/`.

## События

```
2026-06-21 | adr  | rozhkov | ADR 0002 — релиз синглами, не альбомом |
2026-06-21 | note | rozhkov | захват контекста reboot (intake): пайплайн, трек-лист, стек, стратегия |
2026-06-21 | note | rozhkov | vault fm-reboot заведён (механика перенесена из портального vault'а) |
```
