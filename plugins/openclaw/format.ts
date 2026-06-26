export type AssembledEMU = {
  episode_cluster_id?: string;
  support_count?: number;
  activation_score?: number;
  temporal_bucket?: string;
  stability_score?: number;
  salience?: number;
};

export type MemoryRecallResponse = {
  query_hash?: string;
  emus?: AssembledEMU[];
  context_tags?: string[];
  duration_ms?: number;
};

export type EntityResult = {
  name?: string;
  aliases?: string[];
};

export type PredicateResult = {
  name?: string;
  description?: string;
  inverse_name?: string;
  is_root?: boolean;
};

export type MemorySearchResponse = {
  entities?: EntityResult[];
  predicates?: PredicateResult[];
};

export function formatRecallBlock(
  raw: string | MemoryRecallResponse,
  maxItems: number,
): string {
  let resp: MemoryRecallResponse;
  if (typeof raw === "string") {
    try {
      const parsed: unknown = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "";
      resp = parsed as MemoryRecallResponse;
    } catch {
      return "";
    }
  } else {
    resp = raw;
  }

  const tags = resp.context_tags ?? [];
  const emus = (resp.emus ?? []).slice(0, maxItems);
  if (tags.length === 0 && emus.length === 0) return "";

  const lines: string[] = [];
  if (tags.length > 0) {
    lines.push(`context: ${tags.join(", ")}`);
  }
  for (const emu of emus) {
    const cluster = emu.episode_cluster_id ?? "unknown";
    const score = (emu.activation_score ?? 0).toFixed(2);
    lines.push(`- [${cluster}] activation ${score}`);
  }

  return [
    "<untrusted-data agent-brain>",
    "## Memory context (agent-brain)",
    ...lines,
    "</untrusted-data>",
  ].join("\n");
}

export function formatSearchBlock(raw: string | MemorySearchResponse): string {
  let resp: MemorySearchResponse;
  if (typeof raw === "string") {
    try {
      const parsed: unknown = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "";
      resp = parsed as MemorySearchResponse;
    } catch {
      return "";
    }
  } else {
    resp = raw;
  }

  const lines: string[] = [];
  for (const e of resp.entities ?? []) {
    const aliases = e.aliases?.length ? ` (${e.aliases.join(", ")})` : "";
    lines.push(`- entity: ${e.name ?? "unknown"}${aliases}`);
  }
  for (const p of resp.predicates ?? []) {
    const root = p.is_root ? " (root)" : "";
    lines.push(`- predicate: ${p.name ?? "unknown"}${root}`);
  }
  if (lines.length === 0) return "";
  return ["## Known vocabulary (agent-brain)", ...lines].join("\n");
}
