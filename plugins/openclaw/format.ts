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

const PREFERENCE_RE =
  /\b(i prefer|i like|i love|i hate|i always|i never|i want|i need|my goal is|i am allergic)\b/i;
const CORRECTION_RE =
  /^\s*(no[,.]?\s+(not that|actually|do|use|try)|actually[,]?\s+|wrong[,.]?\s+|instead[,]?\s+|not\s+\w+[,]?\s+use\b)/i;
const CONSTRAINT_RE =
  /\b(in this (project|repo|codebase|service)|our convention|we always|we never|we don.t use|we use|we decided|let.s use|going with|use the)\b/i;
const DECISION_RE =
  /\b(let.s go with|we.ll use|decided to|going to use|approach is|architecture is|design is)\b/i;
const DEFERRED_RE =
  /\b(remind me|i.ll (do|check|fix|look at|revisit)|follow up on|i should(n.t forget)?|we should|don.t forget|next time|come back to)\b/i;
const BOILERPLATE_RE = /^(ok|thanks|thank you|yes|no|sure|done|got it|sounds good)[.!]?$/i;

export type WriteCandidate = {
  action?: string;
  content: string;
  signal_type: string;
  memory_type: string;
  subject: string;
  confidence: number;
  topic?: string;
};

export function indexCandidates(userText: string, _assistantText: string): WriteCandidate[] {
  const user = userText.trim();
  if (user.length < 12 || BOILERPLATE_RE.test(user)) return [];

  const slug = (prefix = "") =>
    prefix +
    user
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .slice(0, 40 - prefix.length);

  if (PREFERENCE_RE.test(user)) {
    return [
      { content: user, signal_type: "user-stated", memory_type: "stated_fact", subject: slug(), confidence: 0.90 },
    ];
  }
  if (CORRECTION_RE.test(user)) {
    return [
      { content: user, signal_type: "user-stated", memory_type: "stated_fact", subject: slug("correction-"), confidence: 0.85 },
    ];
  }
  if (CONSTRAINT_RE.test(user)) {
    return [
      { content: user, signal_type: "user-stated", memory_type: "stated_fact", subject: slug("project-convention-"), confidence: 0.80 },
    ];
  }
  if (DECISION_RE.test(user)) {
    return [
      { content: user, signal_type: "inferred", memory_type: "stated_fact", subject: slug("decision-"), confidence: 0.75 },
    ];
  }
  if (DEFERRED_RE.test(user)) {
    const topicMatch = user
      .toLowerCase()
      .match(
        /(remind me (?:to )?|follow up on |i.ll |check |fix |look at |revisit |come back to )([a-z0-9 _-]+)/i,
      );
    const topic = topicMatch ? topicMatch[2].slice(0, 60).trim() : "task";
    return [
      { action: "set_intention", content: user, signal_type: "inferred", memory_type: "stated_fact", subject: "", confidence: 0, topic },
    ];
  }

  return [];
}
