/**
 * local-web-search — thin, dependency-light web search tool.
 *
 * Why this exists: pi-web-access registers a richly-typed `web_search` tool,
 * but its TypeBox schema is complex (StringEnum unions, optional nested
 * objects). Some OpenAI-compatible gateways silently drop tool defs they
 * can't validate, which leaves the agent with no callable search at all.
 *
 * This shim registers an equivalent tool with the SIMPLEST possible schema
 * ({ query: string, numResults?: number }) so any compliant gateway passes
 * it through unchanged. It calls the same keyless Exa MCP endpoint that
 * pi-web-access uses, so behavior and citations are identical.
 *
 * Auto-discovered by pi from ~/.pi/agent/extensions/*.ts. No restart-time
 * config needed; just (re)start pi.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const EXA_MCP_URL = "https://mcp.exa.ai/mcp";
const REQUEST_TIMEOUT_MS = 40_000;

interface ExaMcpResponse {
	result?: { content?: Array<{ type?: string; text?: string }>; isError?: boolean };
	error?: { code?: number; message?: string };
}

async function callExa(query: string, numResults: number, signal: AbortSignal | undefined): Promise<string> {
	const body = JSON.stringify({
		jsonrpc: "2.0",
		id: 1,
		method: "tools/call",
		params: {
			name: "web_search_exa",
			arguments: {
				query,
				numResults,
				livecrawl: "fallback",
				type: "auto",
				contextMaxCharacters: 3000,
			},
		},
	});

	const res = await fetch(EXA_MCP_URL, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Accept: "application/json, text/event-stream",
		},
		body,
		signal,
	});

	if (!res.ok) {
		const errText = await res.text().catch(() => "");
		throw new Error(`Exa MCP HTTP ${res.status}: ${errText.slice(0, 300)}`);
	}

	const raw = await res.text();
	// Exa MCP replies either as a single JSON object or as SSE `data:` frames.
	let parsed: ExaMcpResponse | null = null;
	for (const line of raw.split("\n")) {
		if (!line.startsWith("data:")) continue;
		const payload = line.slice(5).trim();
		if (!payload) continue;
		try {
			const candidate = JSON.parse(payload) as ExaMcpResponse;
			if (candidate?.result || candidate?.error) {
				parsed = candidate;
				break;
			}
		} catch {
			// keep scanning frames
		}
	}
	if (!parsed) {
		try {
			parsed = JSON.parse(raw) as ExaMcpResponse;
		} catch {
			parsed = null;
		}
	}

	if (!parsed) throw new Error("Exa MCP returned an unparseable response.");
	if (parsed.error) throw new Error(`Exa MCP error${parsed.error.code ? ` ${parsed.error.code}` : ""}: ${parsed.error.message ?? "unknown"}`);
	if (parsed.result?.isError) throw new Error("Exa MCP returned an error result.");

	const text = parsed.result?.content?.[0]?.text;
	if (!text) throw new Error("Exa MCP returned no content.");
	return text;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "pi_search",
		label: "Web Search",
		description:
			"Search the web for facts to verify claims or answer questions when local knowledge is insufficient, outdated, or needs a citation. Returns an Exa.ai synthesized answer with source URLs and highlights. " +
			"Use proactively whenever a factual claim is uncertain, dated, or would benefit from a source — e.g. release dates, spec numbers, changelog entries, compatibility tables, news. " +
			"Prefer 2-4 varied query phrasings over repeating the same query; each call gets its own synthesized answer, so different angles broaden coverage. " +
			"Free-form queries work best. Keep queries concrete and self-contained (include entity names, years, version numbers).",
		parameters: Type.Object({
			query: Type.String({ description: "Natural-language search query. Include key entities, dates, and version numbers." }),
			numResults: Type.Optional(
				Type.Number({
					description: "Number of sources to retrieve (default 5, max 12). More sources = broader coverage, slower.",
				}),
			),
		}),
		async execute(_toolCallId, params, signal) {
			const query = String(params?.query ?? "").trim();
			if (!query) {
				return {
					content: [{ type: "text", text: "Error: `query` is required and must be non-empty." }],
					details: { error: true },
				};
			}
			const want = Number(params?.numResults ?? 5);
			const numResults = Number.isFinite(want) ? Math.min(Math.max(Math.floor(want), 1), 12) : 5;

			try {
				const text = await callExa(query, numResults, signal);
				return {
					content: [{ type: "text", text }],
					details: { provider: "exa", query, numResults },
				};
			} catch (err) {
				const message = err instanceof Error ? err.message : String(err);
				return {
					content: [{ type: "text", text: `Web search failed: ${message}` }],
					details: { error: true, provider: "exa", query },
				};
			}
		},
	});
}