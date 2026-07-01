import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { AssistantMessage, TextContent } from "@earendil-works/pi-ai";
import { CustomEditor, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// Built-in mutating tools gated per mode. Custom/extension tools are preserved in
// every mode (see applyTools); only these built-ins get toggled.
const BUILTIN_MUTATING_TOOLS = ["edit", "write"] as const;
const MUTATING_TOOLS = new Set<string>(BUILTIN_MUTATING_TOOLS);

type Mode = "conversation" | "build" | "plan" | "teacher";

type Task = {
	id: number;
	title: string;
	deliverable?: string;
	implementation?: string;
	validation?: string;
	quality?: string;
	userCheckpoint?: string;
	completed: boolean;
};

const MODE_ORDER: Mode[] = ["conversation", "build", "plan", "teacher"];

const DESTRUCTIVE_BASH = [
	/\brm\b/i,
	/\brmdir\b/i,
	/\bmv\b/i,
	/\bcp\b/i,
	/\bmkdir\b/i,
	/\btouch\b/i,
	/\bchmod\b/i,
	/\bchown\b/i,
	/\btee\b/i,
	/(^|[^<])>(?!>)/,
	/>>/,
	/\bnpm\s+(install|uninstall|update|ci|link|publish)/i,
	/\byarn\s+(add|remove|install|publish)/i,
	/\bpnpm\s+(add|remove|install|publish)/i,
	/\bgo\s+(get|install)\b/i,
	/\bpip\s+(install|uninstall)/i,
	/\bgit\s+(add|commit|push|pull|merge|rebase|reset|checkout|stash|cherry-pick|revert|tag|init|clone)/i,
	/\bsudo\b/i,
	/\bkill\b/i,
	/\bpkill\b/i,
	/\bkillall\b/i,
];

function isAssistantMessage(m: AgentMessage): m is AssistantMessage {
	return m.role === "assistant" && Array.isArray(m.content);
}

function getTextContent(message: AssistantMessage): string {
	return message.content
		.filter((block): block is TextContent => block.type === "text")
		.map((block) => block.text)
		.join("\n");
}

function cleanLine(text: string): string {
	return text
		.replace(/\*{1,2}([^*]+)\*{1,2}/g, "$1")
		.replace(/`([^`]+)`/g, "$1")
		.replace(/\s+/g, " ")
		.trim();
}

function extractTasks(markdown: string): Task[] {
	const tasks: Task[] = [];
	const lines = markdown.split(/\r?\n/);
	let current: Task | undefined;

	for (const line of lines) {
		const taskMatch = line.match(/^\s*(?:[-*]\s*)?(\d+)[.)]\s+(.+)$/);
		if (taskMatch) {
			const raw = cleanLine(taskMatch[2] ?? "");
			if (raw.length < 5) continue;
			if (/^(deliverable|implementation|validation|test|quality|acceptance|user checkpoint)\s*:/i.test(raw)) continue;

			const title = raw.replace(/\s+-\s+(deliverable|implementation|validation|test|quality|acceptance|user checkpoint)\s*:.*$/i, "").trim();
			if (title.length < 5) continue;

			current = { id: tasks.length + 1, title, completed: false };
			tasks.push(current);
			continue;
		}

		if (!current) continue;
		const fieldMatch = line.match(/^\s*[-*]\s*(Deliverable|Implementation|Validation|Test|Quality|Acceptance|User Checkpoint)\s*:\s*(.+)$/i);
		if (!fieldMatch) continue;

		const label = (fieldMatch[1] ?? "").toLowerCase();
		const value = cleanLine(fieldMatch[2] ?? "");
		if (!value) continue;

		if (label === "deliverable") current.deliverable = value;
		else if (label === "implementation") current.implementation = value;
		else if (label === "validation" || label === "test") current.validation = value;
		else if (label === "quality" || label === "acceptance") current.quality = value;
		else if (label === "user checkpoint") current.userCheckpoint = value;
	}

	return tasks.slice(0, 20);
}

function markDone(text: string, tasks: Task[]): number {
	let count = 0;
	for (const match of text.matchAll(/\[(?:DONE|TASK-DONE):(\d+)\]/gi)) {
		const id = Number(match[1]);
		const task = tasks.find((t) => t.id === id);
		if (task && !task.completed) {
			task.completed = true;
			count++;
		}
	}
	return count;
}

function isDestructiveBash(command: string): boolean {
	return DESTRUCTIVE_BASH.some((pattern) => pattern.test(command));
}

function inferProjectLanguages(ctx: ExtensionContext): string[] {
	const entries = ctx.sessionManager.getBranch();
	const text = JSON.stringify(entries).toLowerCase();
	const langs = new Set<string>();

	if (text.includes(".go") || text.includes("go.mod") || text.includes("golang")) langs.add("go");
	if (text.includes(".ts") || text.includes("typescript")) langs.add("typescript");
	if (text.includes(".tsx") || text.includes("react")) langs.add("typescript");
	if (text.includes(".js") || text.includes("javascript")) langs.add("javascript");
	if (text.includes(".py") || text.includes("python")) langs.add("python");
	if (text.includes(".rs") || text.includes("rust")) langs.add("rust");

	// Current cwd hint: graph-go, foo-rs, etc.
	const cwd = ctx.cwd.toLowerCase();
	if (cwd.includes("go")) langs.add("go");
	if (cwd.includes("typescript") || cwd.includes("ts")) langs.add("typescript");
	if (cwd.includes("python") || cwd.includes("py")) langs.add("python");
	if (cwd.includes("rust") || cwd.includes("rs")) langs.add("rust");

	return [...langs];
}

function hasStyleGuideSkill(pi: ExtensionAPI, languages: string[]): boolean {
	const skillCommands = pi.getCommands().filter((command) => command.source === "skill");
	if (skillCommands.length === 0) return false;

	const haystack = skillCommands
		.map((command) => `${command.name} ${command.description ?? ""} ${command.sourceInfo.path}`)
		.join("\n")
		.toLowerCase();

	return languages.some((language) => {
		const langPattern = language === "go" ? /(\bgo\b|golang)/ : new RegExp(`\\b${language}\\b`, "i");
		return langPattern.test(haystack) && /(style|guide|convention|idiom|lint|quality)/i.test(haystack);
	});
}

function conversationInstructions(): string {
	return `[CONVERSATION MODE ACTIVE]
Interact naturally with the user.
Do not enforce task-only execution, plan structure, teaching behavior, or task completion markers.
Use normal judgment about tools and edits based on the user's request.`;
}

function teacherInstructions(): string {
	return `[TEACHER MODE ACTIVE]
Guide the user as a programming teacher. Do not take over implementation unless explicitly asked.
Prefer hints, explanations, small challenges, and review. Avoid file-mutating tools unless the user clearly asks to implement or edit.
When explaining code, keep examples focused and map them to the current task.`;
}

function planInstructions(): string {
	return `[PLAN MODE ACTIVE]
Create an implementation-ready plan grounded in the current repository, not an open-ended design doc.

Hard requirements:
- Do not edit or write files in plan mode.
- Read the repo first and use what you learn to make the plan concrete.
- Produce a numbered list of small, self-contained build tasks.
- Each task should usually be completable in one focused build iteration.
- Each task must include enough implementation detail that build mode can execute without re-planning.
- Avoid creating speculative follow-up docs such as V1_*.md unless the user explicitly asked for them.
- Prefer code changes, tests, migrations, and focused docs over broad planning artifacts.
- Only leave work for the user when human judgment is actually required, such as UI validation, product choice, or unclear requirements.

Use this shape:
Plan:
1. Task title
   - Deliverable: concrete artifact/result
   - Implementation: specific files, components, modules, or approach based on repo inspection
   - Validation: command, test, inspection, or check to verify it
   - Quality: correctness and code-quality criteria
   - User Checkpoint: only if human validation is required; otherwise omit

Ask clarifying questions only when a blocking ambiguity prevents safe execution. Otherwise make the best repo-grounded plan you can.`;
}

function buildInstructions(currentTask: Task | undefined, languages: string[], styleGuideOk: boolean): string {
	const taskText = currentTask
		? `${currentTask.id}. ${currentTask.title}`
		: "No active task has been selected or extracted yet.";

	return `[BUILD MODE ACTIVE]
Current task: ${taskText}
Detected languages: ${languages.length > 0 ? languages.join(", ") : "unknown"}
Style-guide skill available: ${styleGuideOk ? "yes" : "no"}

Rules:
- Execute the plan autonomously with minimal user interruption.
- Focus on the current task, but if the task is complete and another extracted task naturally follows, continue to the next task without waiting for approval.
- Do not create broad interim planning docs or V1_*.md files unless explicitly requested.
- Document implementation in the codebase only where useful and scoped to the change.
- Stop and ask the user only for true human checkpoints: UI/UX validation, product decisions, ambiguous requirements, secrets/credentials, destructive operations, or anything requiring subjective approval.
- Code quality is mandatory.
- If no relevant language/style-guide skill is available, do not edit files or run mutating commands. Explain the block and ask the user to add/select a style-guide skill.
- Validate each task using its validation method or the closest appropriate project test.
- When a task is complete, include [TASK-DONE:${currentTask?.id ?? 0}] in the assistant response.`;
}

class SmartTabModeEditor extends CustomEditor {
	constructor(
		tui: ConstructorParameters<typeof CustomEditor>[0],
		theme: ConstructorParameters<typeof CustomEditor>[1],
		keybindings: ConstructorParameters<typeof CustomEditor>[2],
		private readonly onEmptyTab: () => void,
	) {
		super(tui, theme, keybindings);
	}

	handleInput(data: string): void {
		if (matchesKey(data, Key.tab) && this.getText().trim().length === 0 && !this.isShowingAutocomplete()) {
			this.onEmptyTab();
			return;
		}
		super.handleInput(data);
	}

	render(width: number): string[] {
		const lines = super.render(width);
		if (lines.length === 0) return lines;
		const label = " Tab: mode ";
		const last = lines.length - 1;
		if (visibleWidth(lines[last]!) >= label.length) {
			lines[last] = truncateToWidth(lines[last]!, width - label.length, "") + label;
		}
		return lines;
	}
}

export default function taskModesExtension(pi: ExtensionAPI): void {
	let mode: Mode = "conversation";
	let tasks: Task[] = [];
	let activeTaskId = 1;
	let lastStyleGuideOk = false;
	let lastLanguages: string[] = [];

	function currentTask(): Task | undefined {
		return tasks.find((task) => task.id === activeTaskId && !task.completed) ?? tasks.find((task) => !task.completed);
	}

	function statusText(): string {
		if (mode === "conversation") {
			return `[conversation]`;
		}

		const task = currentTask();
		return `[${mode}]:[${task ? `${task.id} ${task.title}` : "no-task"}]`;
	}

	function updateUi(ctx: ExtensionContext): void {
		const color = mode === "build" ? "success" : mode === "plan" ? "warning" : "accent";
		ctx.ui.setStatus("task-modes", ctx.ui.theme.fg(color, statusText()));

		if (tasks.length > 0) {
			const active = currentTask();
			const lines = tasks.map((task) => {
				const marker = task.completed ? ctx.ui.theme.fg("success", "☑") : task.id === active?.id ? ctx.ui.theme.fg("accent", "▶") : ctx.ui.theme.fg("muted", "☐");
				const text = task.completed ? ctx.ui.theme.fg("muted", ctx.ui.theme.strikethrough(task.title)) : task.title;
				return `${marker} ${task.id}. ${text}`;
			});

			if (active) {
				if (active.deliverable) lines.push(`   Deliverable: ${active.deliverable}`);
				if (active.implementation) lines.push(`   Implementation: ${active.implementation}`);
				if (active.validation) lines.push(`   Validation: ${active.validation}`);
				if (active.quality) lines.push(`   Quality: ${active.quality}`);
				if (active.userCheckpoint) lines.push(`   User Checkpoint: ${active.userCheckpoint}`);
			}

			ctx.ui.setWidget("task-modes-tasks", lines);
		} else {
			ctx.ui.setWidget("task-modes-tasks", undefined);
		}
	}

	function persist(): void {
		pi.appendEntry("task-modes-state", { mode, tasks, activeTaskId });
	}

	function applyTools(ctx: ExtensionContext): void {
		lastLanguages = inferProjectLanguages(ctx);
		lastStyleGuideOk = hasStyleGuideSkill(pi, lastLanguages);

		// Preserve tools provided by other extensions (and SDK) so setActiveTools
		// doesn't silently disable them. setActiveTools replaces the full set,
		// so we union with all non-builtin tools registered so far.
		const extensionTools = pi
			.getAllTools()
			.filter((tool) => tool.sourceInfo.source !== "builtin" && tool.sourceInfo.source !== "sdk")
			.map((tool) => tool.name);
		const tools = new Set([...pi.getActiveTools(), ...extensionTools]);

		// Only toggle the built-in mutating tools; custom tools stay available in all modes.
		if (mode === "plan" || mode === "teacher") {
			tools.delete("edit");
			tools.delete("write");
			pi.setActiveTools([...tools]);
			return;
		}

		if (mode === "conversation" || (mode === "build" && lastStyleGuideOk)) {
			tools.add("edit");
			tools.add("write");
			pi.setActiveTools([...tools]);
			return;
		}

		// build without a matching style-guide skill: block built-in mutations
		// but keep extension tools available. The tool_call guard still blocks
		// destructive bash in this state.
		tools.delete("edit");
		tools.delete("write");
		pi.setActiveTools([...tools]);
	}

	function setMode(next: Mode, ctx: ExtensionContext, notify = true): void {
		mode = next;
		applyTools(ctx);
		updateUi(ctx);
		persist();
		if (notify) {
			const suffix = mode === "build" && !lastStyleGuideOk ? " — build mutations blocked: no matching language/style-guide skill" : "";
			ctx.ui.notify(`${statusText()}${suffix}`, mode === "build" && !lastStyleGuideOk ? "warning" : "info");
		}
	}

	function isMode(value: string): value is Mode {
		return ["conversation", "build", "plan", "teacher"].includes(value);
	}

	function cycleMode(ctx: ExtensionContext): void {
		const index = MODE_ORDER.indexOf(mode);
		setMode(MODE_ORDER[(index + 1) % MODE_ORDER.length]!, ctx);
	}

	pi.registerCommand("mode", {
		description: "Set task mode: conversation, build, plan, or teacher",
		handler: async (args, ctx) => {
			const requested = args.trim().toLowerCase();
			if (!isMode(requested)) {
				ctx.ui.notify("Usage: /mode conversation|build|plan|teacher", "info");
				return;
			}
			setMode(requested, ctx);
		},
	});

	pi.registerCommand("task", {
		description: "Set active task by number, or show current tasks",
		handler: async (args, ctx) => {
			const id = Number(args.trim());
			if (!Number.isFinite(id)) {
				if (tasks.length === 0) {
					ctx.ui.notify("No tasks extracted yet.", "info");
					return;
				}

				const details = tasks.flatMap((task) => {
					const lines = [`${task.id}. ${task.completed ? "✓" : "○"} ${task.title}`];
					if (task.deliverable) lines.push(`   Deliverable: ${task.deliverable}`);
					if (task.implementation) lines.push(`   Implementation: ${task.implementation}`);
					if (task.validation) lines.push(`   Validation: ${task.validation}`);
					if (task.quality) lines.push(`   Quality: ${task.quality}`);
					if (task.userCheckpoint) lines.push(`   User Checkpoint: ${task.userCheckpoint}`);
					return lines;
				});
				ctx.ui.notify(details.join("\n"), "info");
				return;
			}
			if (!tasks.some((task) => task.id === id)) {
				ctx.ui.notify(`Unknown task: ${id}`, "warning");
				return;
			}
			activeTaskId = id;
			updateUi(ctx);
			persist();
		},
	});

	pi.registerShortcut("ctrl+alt+m", {
		description: "Cycle Conversation/Build/Plan/Teacher mode",
		handler: async (ctx) => cycleMode(ctx),
	});

	pi.on("session_start", async (_event, ctx) => {
		const state = ctx.sessionManager
			.getEntries()
			.filter((entry: { type: string; customType?: string }) => entry.type === "custom" && entry.customType === "task-modes-state")
			.pop() as { data?: { mode?: Mode; tasks?: Task[]; activeTaskId?: number } } | undefined;

		if (state?.data) {
			mode = state.data.mode ?? mode;
			tasks = state.data.tasks ?? tasks;
			activeTaskId = state.data.activeTaskId ?? activeTaskId;
		}

		applyTools(ctx);
		updateUi(ctx);
		ctx.ui.setEditorComponent((tui, theme, keybindings) => new SmartTabModeEditor(tui, theme, keybindings, () => cycleMode(ctx)));
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		applyTools(ctx);
		updateUi(ctx);

		if (mode === "conversation") {
			return { message: { customType: "task-modes-context", content: conversationInstructions(), display: false } };
		}

		if (mode === "plan") {
			return { message: { customType: "task-modes-context", content: planInstructions(), display: false } };
		}

		if (mode === "teacher") {
			return { message: { customType: "task-modes-context", content: teacherInstructions(), display: false } };
		}

		return {
			message: {
				customType: "task-modes-context",
				content: buildInstructions(currentTask(), lastLanguages, lastStyleGuideOk),
				display: false,
			},
		};
	});

	pi.on("tool_call", async (event) => {
		if (mode === "plan" && (MUTATING_TOOLS.has(event.toolName) || (event.toolName === "bash" && isDestructiveBash(String(event.input.command ?? ""))))) {
			return { block: true, reason: "Plan mode is read-only. Switch to build mode when the plan is ready." };
		}

		if (mode === "teacher" && MUTATING_TOOLS.has(event.toolName)) {
			return { block: true, reason: "Teacher mode avoids direct edits. Ask explicitly for implementation or switch to build mode." };
		}

		if (mode === "build" && !lastStyleGuideOk && (MUTATING_TOOLS.has(event.toolName) || (event.toolName === "bash" && isDestructiveBash(String(event.input.command ?? ""))))) {
			return {
				block: true,
				reason: `Build mode blocked: no relevant language/style-guide skill was found for ${lastLanguages.join(", ") || "this project"}. Add a style-guide skill or switch modes before mutating files.`,
			};
		}
	});

	pi.on("agent_end", async (event, ctx) => {
		const lastAssistant = [...event.messages].reverse().find(isAssistantMessage);
		if (!lastAssistant) return;

		const text = getTextContent(lastAssistant);

		if (mode === "plan") {
			const extracted = extractTasks(text);
			if (extracted.length > 0) {
				tasks = extracted;
				activeTaskId = tasks[0]?.id ?? 1;
				ctx.ui.notify(`Extracted ${tasks.length} implementation task(s) from plan. Switch to build mode with empty-editor Tab.`, "info");
			}
		}

		if (mode === "build" && tasks.length > 0 && markDone(text, tasks) > 0) {
			const next = tasks.find((task) => !task.completed);
			if (next) activeTaskId = next.id;
		}

		updateUi(ctx);
		persist();
	});

	pi.on("session_shutdown", async () => {
		persist();
	});
}
