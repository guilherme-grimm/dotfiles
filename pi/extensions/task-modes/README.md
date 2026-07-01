# Task Modes

Global Pi extension providing four workflow modes:

- `conversation`: freeform discussion mode. No task enforcement, planning structure, or teaching constraints.
- `build`: executes implementation autonomously with minimal interruption, continuing through extracted tasks until a real human checkpoint is needed. Mutating tools are blocked unless a matching language/style-guide skill is available.
- `plan`: read-only planning. Plans must be repo-grounded, implementation-ready, and split into small self-contained tasks with deliverables, implementation details, validation, and quality criteria.
- `teacher`: guided learning mode. Avoids direct edits unless explicitly requested.

## Controls

- Empty-editor `Tab`: smart-cycle `conversation -> build -> plan -> teacher -> conversation`.
- Non-empty `Tab`: keeps normal autocomplete/path completion behavior.
- `/mode conversation|build|plan|teacher`: set mode directly.
- `/task`: show extracted tasks.
- `/task <n>`: select active task.
- `Ctrl+Alt+M`: cycle mode fallback.

## Indicator

The footer shows:

```text
[mode]:[task]
```

The task widget shows the extracted plan tasks when available, and expands the active task with its deliverable, implementation notes, validation, quality criteria, and any user checkpoint.
