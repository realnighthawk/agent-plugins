#!/usr/bin/env python3
"""
Phase 1 of historical memory replay.

Reads all top-level Claude Code conversation JSONL files under
~/.claude/projects/, reconstructs clean turn-by-turn transcripts
(user + assistant, tool noise compressed), and writes them to
~/.claude/replay/transcripts/{project}/{date}-{uuid8}.txt

Also produces ~/.claude/replay/manifest.json sorted chronologically.

Usage:
    python3 extract_conversations.py [--dry-run]
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path


# Tool calls that are pure implementation noise — compress to one line.
COMPRESS_TOOLS = {
    "Read", "Write", "Edit", "Bash", "Grep", "Glob", "Find",
    "NotebookEdit", "WebFetch", "WebSearch",
}

# Projects to skip entirely.
SKIP_PROJECTS = {"superagents", "memory-superagents", "cognee", "private-tmp"}

# Minimum user turns for a conversation to be worth processing.
MIN_USER_TURNS = 3

# Tags injected by the Claude Code runtime — not the user's words.
INJECTED_PATTERNS = [
    re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL),
    re.compile(r"<local-command-stdout>.*?</local-command-stdout>", re.DOTALL),
    re.compile(r"<local-command-caveat>.*?</local-command-caveat>", re.DOTALL),
    re.compile(r"<command-name>.*?</command-name>", re.DOTALL),
    re.compile(r"<command-message>.*?</command-message>", re.DOTALL),
    re.compile(r"<command-args>.*?</command-args>", re.DOTALL),
    re.compile(r"<EXTREMELY_IMPORTANT>.*?</EXTREMELY_IMPORTANT>", re.DOTALL),
    re.compile(r"<claudeMd>.*?</claudeMd>", re.DOTALL),
    re.compile(r"<userEmail>.*?</userEmail>", re.DOTALL),
    re.compile(r"<currentDate>.*?</currentDate>", re.DOTALL),
]


def strip_injected(text: str) -> str:
    for pat in INJECTED_PATTERNS:
        text = pat.sub("", text)
    return text.strip()


def compress_tool_use(block: dict) -> str:
    name = block.get("name", "unknown")
    if name in COMPRESS_TOOLS:
        return f"[tool: {name}]"
    # For other tools (MCP, Agent, etc.) keep a brief summary of the input.
    inp = block.get("input", {})
    if isinstance(inp, dict):
        summary_parts = []
        for k, v in list(inp.items())[:3]:
            v_str = str(v)[:60].replace("\n", " ")
            summary_parts.append(f"{k}={v_str!r}")
        summary = ", ".join(summary_parts)
    else:
        summary = str(inp)[:80].replace("\n", " ")
    if name == "Agent":
        return "[subagent dispatched]"
    return f"[tool: {name}({summary})]"


def extract_text_from_content(content) -> str:
    """Turn a message content value into a clean string."""
    if isinstance(content, str):
        return strip_injected(content)

    if not isinstance(content, list):
        return ""

    parts = []
    for block in content:
        if not isinstance(block, dict):
            continue
        btype = block.get("type", "")
        if btype == "text":
            text = strip_injected(block.get("text", ""))
            if text:
                parts.append(text)
        elif btype == "tool_use":
            parts.append(compress_tool_use(block))
        elif btype == "tool_result":
            # Skip — raw tool output is noise.
            pass
        elif btype == "thinking":
            # Skip internal reasoning.
            pass

    return "\n".join(parts).strip()


def project_name_from_dir(dir_name: str) -> str:
    """Convert '-Users-abishekkumar-Documents-agent-brain' → 'agent-brain'."""
    parts = dir_name.lstrip("-").split("-")
    # Drop leading path segments (Users, abishekkumar, Documents)
    skip = {"Users", "abishekkumar", "Documents"}
    meaningful = [p for p in parts if p not in skip and p]
    if not meaningful:
        return dir_name
    return "-".join(meaningful)


def parse_conversation(path: Path) -> dict | None:
    """
    Parse a single JSONL file into a structured conversation dict.
    Returns None if the conversation is too short or otherwise skippable.
    """
    turns = []
    first_timestamp = None

    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue

                rtype = record.get("type", "")
                ts = record.get("timestamp", "")
                if ts and first_timestamp is None:
                    first_timestamp = ts

                if rtype not in ("user", "assistant"):
                    continue

                message = record.get("message", {})
                if not isinstance(message, dict):
                    continue

                role = message.get("role", rtype)
                content = message.get("content", "")
                text = extract_text_from_content(content)

                if not text:
                    continue

                turns.append({"role": role, "text": text})

    except (OSError, UnicodeDecodeError) as e:
        print(f"  warn: could not read {path}: {e}", file=sys.stderr)
        return None

    user_turns = sum(1 for t in turns if t["role"] == "user")
    if user_turns < MIN_USER_TURNS:
        return None

    date = (first_timestamp or "")[:10] or "unknown"
    return {
        "turns": turns,
        "date": date,
        "user_turns": user_turns,
    }


def estimate_tokens(text: str) -> int:
    """Rough token estimate: ~4 chars per token."""
    return len(text) // 4


def render_transcript(project: str, date: str, uuid: str, turns: list) -> str:
    lines = [
        f"PROJECT: {project}",
        f"DATE: {date}",
        f"CONVERSATION: {uuid}",
        "",
        "---",
        "",
    ]
    for turn in turns:
        role = "USER" if turn["role"] == "user" else "A"
        lines.append(f"{role}: {turn['text']}")
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Print manifest without writing files")
    parser.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"),
                        help="Path to Claude Code projects directory")
    parser.add_argument("--output-dir", default=os.path.expanduser("~/.claude/replay"),
                        help="Root output directory for transcripts and manifest")
    args = parser.parse_args()

    projects_dir = Path(args.projects_dir)
    output_dir = Path(args.output_dir)
    transcripts_dir = output_dir / "transcripts"

    if not projects_dir.exists():
        print(f"error: projects dir not found: {projects_dir}", file=sys.stderr)
        sys.exit(1)

    manifest = []
    processed = skipped = 0

    for project_dir in sorted(projects_dir.iterdir()):
        if not project_dir.is_dir():
            continue

        project = project_name_from_dir(project_dir.name)

        if project in SKIP_PROJECTS:
            print(f"skip (excluded): {project}")
            continue

        # Only process top-level JSONL files — skip subagents/ subdirectory.
        jsonl_files = sorted(project_dir.glob("*.jsonl"))
        if not jsonl_files:
            continue

        print(f"\n{project} ({len(jsonl_files)} conversations)")

        for jfile in jsonl_files:
            uuid = jfile.stem
            conversation = parse_conversation(jfile)

            if conversation is None:
                print(f"  skip (< {MIN_USER_TURNS} user turns): {uuid[:8]}")
                skipped += 1
                continue

            turns = conversation["turns"]
            date = conversation["date"]
            user_turns = conversation["user_turns"]

            transcript_text = render_transcript(project, date, uuid, turns)
            token_estimate = estimate_tokens(transcript_text)

            rel_path = f"transcripts/{project}/{date}-{uuid[:8]}.txt"
            full_path = output_dir / "transcripts" / project / f"{date}-{uuid[:8]}.txt"

            manifest.append({
                "project": project,
                "date": date,
                "uuid": uuid,
                "transcript": str(full_path),
                "user_turns": user_turns,
                "estimated_tokens": token_estimate,
                "processed": False,
            })

            if not args.dry_run:
                full_path.parent.mkdir(parents=True, exist_ok=True)
                full_path.write_text(transcript_text)

            print(f"  {date}-{uuid[:8]}  {user_turns} user turns  ~{token_estimate:,} tokens")
            processed += 1

    # Sort manifest chronologically.
    manifest.sort(key=lambda x: x["date"])

    manifest_path = output_dir / "manifest.json"
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, indent=2))
        print(f"\nmanifest written: {manifest_path}")

    total_tokens = sum(e["estimated_tokens"] for e in manifest)
    print(f"\n{'DRY RUN — ' if args.dry_run else ''}done")
    print(f"  conversations extracted : {processed}")
    print(f"  conversations skipped   : {skipped}")
    print(f"  total estimated tokens  : {total_tokens:,}")
    print(f"  output dir              : {output_dir}")


if __name__ == "__main__":
    main()
