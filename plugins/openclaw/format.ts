export type MemoryRow = {
  subject_raw?: string;
  SubjectRaw?: string;
  content?: string;
  Content?: string;
  confidence?: number;
  Confidence?: number;
};

export function formatRecallBlock(rows: MemoryRow[], maxItems: number): string {
  const list = Array.isArray(rows) ? rows : (rows as { memories?: MemoryRow[] }).memories ?? [];
  const slice = list.slice(0, maxItems);
  if (slice.length === 0) return "";

  const lines = slice.map((m) => {
    const subj = m.subject_raw ?? m.SubjectRaw ?? "fact";
    const content = m.content ?? m.Content ?? "";
    const conf = m.confidence ?? m.Confidence ?? 0.8;
    return `- [${subj}] ${content} (conf ${conf})`;
  });

  return [
    "<untrusted-data agent-brain>",
    "## Memory context (agent-brain)",
    ...lines,
    "</untrusted-data>",
  ].join("\n");
}

export type IntentionRow = {
  id?: string;
  ID?: string;
  topic?: string;
  content?: string;
  status?: string;
};

function parseIntentions(raw: string): IntentionRow[] {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed as IntentionRow[];
    if (parsed !== null && typeof parsed === "object") {
      const p = parsed as Record<string, unknown>;
      if (Array.isArray(p.intentions)) return p.intentions as IntentionRow[];
    }
  } catch {
    // ignore
  }
  return [];
}

export function formatIntentionsBlock(raw: string): string {
  const intentions = parseIntentions(raw).filter(
    (i) => i.status === "pending" || i.status === "triggered",
  );
  if (intentions.length === 0) return "";
  const lines = intentions.map((i) => `- [intention: ${i.topic ?? "task"}] ${i.content ?? ""}`);
  return ["## Pending intentions", ...lines].join("\n");
}

export function extractTriggeredIds(raw: string): string[] {
  return parseIntentions(raw)
    .filter((i) => i.status === "triggered")
    .map((i) => i.id ?? i.ID ?? "")
    .filter(Boolean);
}
