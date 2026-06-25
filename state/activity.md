# Activity — лента событий

> Коммиты дописывает git-хук (`_system/tools/post-commit.sh`) автоматически.
> Заметки (note/adr/status) добавляет агент — новые сверху, сразу под `## События`.
> Хук `archive-activity-overflow.ps1` режет ленту до 50 событий, старшее → `state/weekly/`.

## События

```
2026-06-25 | task | rozhkov | YouGile: REB-82 (Олег — VPN Amnezia+Вездеход) и REB-83 (Свят — прослушать 3 звукарей + Babybear), дедлайн 2026-06-29 |
2026-06-25 | note | rozhkov | VPN для Олега: не нужен для AITunnel, лишь страховка сетапа → howto/oleg-claude-code-setup (Proton/Nord/Amnezia) |
2026-06-21 | adr  | rozhkov | ADR 0005 — путь A: остаёмся на Claude-хуках + git-страховка (не агностик-ребилд) |
2026-06-21 | note | rozhkov | финал ADR 0003: Claude Code через AITunnel (хуки/MCP сохраняются), гайд для Олега |
2026-06-21 | adr  | rozhkov | ADR 0003 — РФ-доступ к ИИ: агент через агрегатор (не прямой Claude Pro) |
2026-06-21 | adr  | rozhkov | ADR 0004 — приоритет: выпустить сингл прежде построения инструментов |
2026-06-21 | note | rozhkov | РФ-риск Claude ВЫСОКИЙ (ресёрч) → решение по Олегу пересмотрено |
2026-06-21 | note | rozhkov | решено: Олегу Claude Pro $20/мес (Sonnet); РФ-риск блокировки на проверке |
2026-06-21 | note | rozhkov | ресёрч Suno API (субагент) → drafts/suno-integration-research |
2026-06-21 | adr  | rozhkov | ADR 0002 — релиз синглами, не альбомом |
2026-06-21 | note | rozhkov | захват контекста reboot (intake): пайплайн, трек-лист, стек, стратегия |
2026-06-21 | note | rozhkov | vault fm-reboot заведён (механика перенесена из портального vault'а) |
```
