import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type TeacherMode = "off" | "guide" | "build";

const GUIDE_TOOLS = ["read", "bash", "grep", "find", "ls"];
const MUTATING_TOOLS = new Set(["edit", "write"]);

const SAFE_BASH_COMMANDS = new Set([
	"cat",
	"head",
	"tail",
	"less",
	"more",
	"grep",
	"rg",
	"find",
	"fd",
	"ls",
	"pwd",
	"tree",
	"git",
	"npm",
	"bun",
	"yarn",
	"pnpm",
	"node",
	"python",
	"python3",
	"which",
	"whereis",
	"type",
	"date",
	"whoami",
	"uname",
]);

const BLOCKED_BASH_PATTERNS = [
	/\brm\b/,
	/\bmv\b/,
	/\bcp\b/,
	/\bmkdir\b/,
	/\btouch\b/,
	/\bchmod\b/,
	/\bchown\b/,
	/\bsudo\b/,
	/\bkill(?:all)?\b/,
	/\breboot\b/,
	/\bshutdown\b/,
	/\b(git\s+add|git\s+commit|git\s+push|git\s+reset|git\s+clean|git\s+checkout|git\s+switch)\b/,
	/\b(npm\s+install|npm\s+i|npm\s+update|npm\s+audit\s+fix)\b/,
	/\b(bun\s+install|bun\s+add|bun\s+remove|bun\s+update)\b/,
	/\b(yarn\s+add|yarn\s+install|yarn\s+remove|yarn\s+upgrade)\b/,
	/\b(pnpm\s+add|pnpm\s+install|pnpm\s+remove|pnpm\s+update)\b/,
	/[>|]{1,2}/,
	/\btee\b/,
];

function firstCommand(command: string): string | undefined {
	const trimmed = command.trim();
	if (!trimmed) return undefined;
	return trimmed.split(/\s+/)[0];
}

function isSafeBash(command: string): boolean {
	const normalized = command.trim().toLowerCase();
	if (!normalized) return true;
	if (BLOCKED_BASH_PATTERNS.some((pattern) => pattern.test(normalized))) return false;

	const cmd = firstCommand(normalized);
	if (!cmd) return true;
	return SAFE_BASH_COMMANDS.has(cmd);
}

function modeLabel(mode: TeacherMode): string {
	if (mode === "guide") return "teacher";
	if (mode === "build") return "teacher:build";
	return "";
}

function instructionsFor(mode: TeacherMode): string {
	const base = `

IMPORTANT: TEACHER MODE IS ACTIVE.

Primary goal:
Help the user learn by doing. Act like a patient programming teacher, not an autopilot implementation agent.

Core rules:
- Do not directly modify project code unless the user explicitly asks you to make the change or teacher build mode is active.
- Prefer explanations, questions, hints, and small teaching examples over complete solutions.
- When a concept appears that the user may not have seen before, explain it briefly before relying on it.
- Before showing a full answer, give the user a small challenge, next step, or question to attempt.
- Code examples should be generic first, then contextualized only when helpful.
- Contextualized examples must include comments explaining how each part maps to the user's current task.
- If the user asks for the answer, provide it, but still explain the reasoning and encourage them to hand-code the final version.
- Keep the user in control. Ask before escalating from guidance into implementation.

Teaching response pattern:
1. Briefly restate the goal.
2. Explain the relevant concept(s).
3. Give a small challenge or next action for the user.
4. Provide a generic example if useful.
5. Only then provide a contextualized example, clearly marked as an example rather than a patch.
`;

	if (mode === "guide") {
		return `${base}
Current mode: GUIDED.
- You may inspect and read project files.
- You must not call edit or write.
- You must not run shell commands that modify files, dependencies, git history, or system state.
- If implementation is needed, describe what the user should type instead of doing it yourself.
`;
	}

	if (mode === "build") {
		return `${base}
Current mode: BUILD.
- Direct code modification is allowed, but only when it serves the user's explicit request.
- Still teach while editing: explain the intent before changes and summarize what changed after.
- Prefer small, reviewable changes and invite the user to take over when appropriate.
`;
	}

	return "";
}

export default function teacherModeExtension(pi: ExtensionAPI): void {
	let mode: TeacherMode = "off";
	let previousTools: string[] | undefined;

	pi.registerFlag("teacher", {
		description: "Start in teacher mode (guided, no direct code edits)",
		type: "boolean",
		default: false,
	});

	function persistState(): void {
		pi.appendEntry("teacher-mode", { mode });
	}

	function updateUi(ctx: ExtensionContext): void {
		if (mode === "off") {
			ctx.ui.setStatus("teacher-mode", undefined);
			ctx.ui.setWidget("teacher-mode", undefined);
			return;
		}

		const label = modeLabel(mode);
		const color = mode === "guide" ? "accent" : "warning";
		ctx.ui.setStatus("teacher-mode", ctx.ui.theme.fg(color, `🎓 ${label}`));

		const lines =
			mode === "guide"
				? [
						ctx.ui.theme.fg("accent", "🎓 Teacher mode: guided"),
						ctx.ui.theme.fg("muted", "No direct edits. I explain, challenge, and guide."),
					]
				: [
						ctx.ui.theme.fg("warning", "🎓 Teacher mode: build"),
						ctx.ui.theme.fg("muted", "Edits allowed, but explanations stay on."),
					];

		ctx.ui.setWidget("teacher-mode", lines, { placement: "belowEditor" });
	}

	function applyMode(nextMode: TeacherMode, ctx: ExtensionContext, announce = true): void {
		const oldMode = mode;
		mode = nextMode;

		if (mode === "guide") {
			if (oldMode === "off") previousTools = pi.getActiveTools();
			pi.setActiveTools(GUIDE_TOOLS);
		} else if (mode === "build") {
			if (oldMode === "off") previousTools = pi.getActiveTools();
			if (previousTools && previousTools.length > 0) {
				pi.setActiveTools(previousTools);
			}
		} else {
			if (previousTools && previousTools.length > 0) {
				pi.setActiveTools(previousTools);
			}
			previousTools = undefined;
		}

		updateUi(ctx);
		persistState();

		if (!announce) return;
		if (mode === "guide") ctx.ui.notify("Teacher mode enabled: guided, no direct edits.", "info");
		else if (mode === "build") ctx.ui.notify("Teacher mode build enabled: edits allowed, teaching stays on.", "info");
		else ctx.ui.notify("Teacher mode disabled.", "info");
	}

	pi.registerCommand("teacher", {
		description: "Toggle teacher mode: /teacher [on|off|guide|build|status]",
		handler: async (args, ctx) => {
			const action = args.trim().toLowerCase();

			if (action === "on" || action === "guide") {
				applyMode("guide", ctx);
				return;
			}

			if (action === "build") {
				applyMode("build", ctx);
				return;
			}

			if (action === "off") {
				applyMode("off", ctx);
				return;
			}

			if (action === "status") {
				ctx.ui.notify(`Teacher mode: ${mode}`, "info");
				return;
			}

			if (action.length > 0) {
				ctx.ui.notify("Usage: /teacher [on|off|guide|build|status]", "warning");
				return;
			}

			applyMode(mode === "off" ? "guide" : "off", ctx);
		},
	});

	pi.on("before_agent_start", async (event) => {
		if (mode === "off") return undefined;
		return { systemPrompt: event.systemPrompt + instructionsFor(mode) };
	});

	pi.on("tool_call", async (event) => {
		if (mode === "off") return undefined;

		if (mode === "guide" && MUTATING_TOOLS.has(event.toolName)) {
			return {
				block: true,
				reason: "Teacher mode is guided: direct file edits are blocked. Use /teacher build to allow implementation.",
			};
		}

		if (mode === "guide" && event.toolName === "bash") {
			const input = event.input as { command?: unknown };
			const command = typeof input.command === "string" ? input.command : "";
			if (!isSafeBash(command)) {
				return {
					block: true,
					reason: `Teacher mode is guided: mutating or risky shell commands are blocked. Use /teacher build if you want implementation help.\nCommand: ${command}`,
				};
			}
		}

		return undefined;
	});

	pi.on("session_start", async (_event, ctx) => {
		if (pi.getFlag("teacher") === true) mode = "guide";

		const restored = ctx.sessionManager
			.getEntries()
			.filter((entry: { type: string; customType?: string }) => entry.type === "custom" && entry.customType === "teacher-mode")
			.pop() as { data?: { mode?: TeacherMode } } | undefined;

		if (restored?.data?.mode === "guide" || restored?.data?.mode === "build" || restored?.data?.mode === "off") {
			mode = restored.data.mode;
		}

		if (mode === "guide") {
			previousTools = pi.getActiveTools();
			pi.setActiveTools(GUIDE_TOOLS);
		}

		updateUi(ctx);
	});
}
