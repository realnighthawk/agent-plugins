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

const PREFERENCE_RE =
  /\b(i prefer|i like|i hate|i always|i never|my goal is|i am allergic)\b/i;
const BOILERPLATE_RE = /^(ok|thanks|thank you|yes|no|sure|done)[.!]?$/i;

export type WriteCandidate = {
  content: string;
  signal_type: string;
  memory_type: string;
  subject: string;
  confidence: number;
};

export function indexCandidates(userText: string, _assistantText: string): WriteCandidate[] {
  const user = userText.trim();
  if (user.length < 12 || BOILERPLATE_RE.test(user)) return [];
  if (!PREFERENCE_RE.test(user)) return [];

  const subj = user
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .slice(0, 40);

  return [
    {
      content: user,
      signal_type: "user-stated",
      memory_type: "stated_fact",
      subject: subj || "user-preference",
      confidence: 0.85,
    },
  ];
}
