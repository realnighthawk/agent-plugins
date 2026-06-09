#!/usr/bin/env python3
"""
Phase 1 of historical memory replay for Claude Code.

Reads top-level conversation JSONL files under ~/.claude/projects/,
reconstructs clean turn-by-turn transcripts (user + assistant, tool noise
compressed), and writes them to ~/.claude/replay/transcripts/{project}/{date}-{uuid8}.txt

Also produces ~/.claude/replay/manifest.json sorted chronologically.

Usage:
    python3 extract_conversations.py [--dry-run] [--project NAME]
    python3 extract_conversations.py --list-projects
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path


COMPRESS_TOOLS = {
    "Read", "Write", "Edit", "Bash", "Grep", "Glob", "Find",
    "NotebookEdit", "WebFetch", "WebSearch",
}

SKIP_PROJECTS = {"superagents", "memory-superagents", "cognee", "private-tmp"}
MIN_USER_TURNS = 3

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

    return "\n".join(parts).strip()


def project_name_from_dir(dir_name: str) -> str:
    parts = dir_name.lstrip("-").split("-")
    skip = {"Users", "abishekkumar", "Documents"}
    meaningful = [p for p in parts if p not in skip and p]
    if not meaningful:
        return dir_name
    return "-".join(meaningful)


def parse_conversation(path: Path) -> dict | None:
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


def load_processed_state(output_dir: Path, project_filter: str | None) -> dict[str, dict]:
    manifest_path = output_dir / "manifest.json"
    if not manifest_path.is_file():
        return {}
    try:
        data = json.loads(manifest_path.read_text())
    except (json.JSONDecodeError, OSError):
        return {}
    state = {}
    for item in data:
        if project_filter is not None and item.get("project") != project_filter:
            continue
        uuid = item.get("uuid")
        if not uuid:
            continue
        state[uuid] = {
            "processed": bool(item.get("processed")),
            "memories_written": item.get("memories_written", 0),
        }
    return state


def list_projects(projects_dir: Path) -> list[str]:
    names = []
    for project_dir in sorted(projects_dir.iterdir()):
        if not project_dir.is_dir():
            continue
        project = project_name_from_dir(project_dir.name)
        if project in SKIP_PROJECTS:
            continue
        if any(project_dir.glob("*.jsonl")):
            names.append(project)
    return names


def iter_conversation_files(projects_dir: Path, project_filter: str | None = None):
    for project_dir in sorted(projects_dir.iterdir()):
        if not project_dir.is_dir():
            continue

        project = project_name_from_dir(project_dir.name)
        if project in SKIP_PROJECTS:
            print(f"skip (excluded): {project}")
            continue
        if project_filter is not None and project != project_filter:
            continue

        jsonl_files = sorted(project_dir.glob("*.jsonl"))
        if not jsonl_files:
            continue

        yield project, jsonl_files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="Print manifest without writing files")
    parser.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"),
                        help="Path to Claude Code projects directory")
    parser.add_argument("--output-dir", default=os.path.expanduser("~/.claude/replay"),
                        help="Root output directory for transcripts and manifest")
    parser.add_argument("--project",
                        help="Extract only this project (manifest contains only its conversations)")
    parser.add_argument("--list-projects", action="store_true",
                        help="Print available project names and exit")
    args = parser.parse_args()

    projects_dir = Path(args.projects_dir)
    output_dir = Path(args.output_dir)

    if not projects_dir.exists():
        print(f"error: projects dir not found: {projects_dir}", file=sys.stderr)
        sys.exit(1)

    if args.list_projects:
        for name in list_projects(projects_dir):
            print(name)
        return

    project_filter = args.project
    if project_filter is not None:
        available = list_projects(projects_dir)
        if project_filter not in available:
            print(f"error: project not found: {project_filter}", file=sys.stderr)
            if available:
                print("available projects:", file=sys.stderr)
                for name in available:
                    print(f"  {name}", file=sys.stderr)
            else:
                print("no projects with conversations found", file=sys.stderr)
            sys.exit(1)

    prior_state = load_processed_state(output_dir, project_filter)
    manifest = []
    processed = skipped = resumed = 0
    projects_seen = 0

    for project, jsonl_files in iter_conversation_files(projects_dir, project_filter):
        projects_seen += 1
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
            full_path = output_dir / "transcripts" / project / f"{date}-{uuid[:8]}.txt"

            entry = {
                "project": project,
                "date": date,
                "uuid": uuid,
                "transcript": str(full_path),
                "user_turns": user_turns,
                "estimated_tokens": token_estimate,
                "processed": False,
            }
            if uuid in prior_state and prior_state[uuid]["processed"]:
                entry["processed"] = True
                entry["memories_written"] = prior_state[uuid]["memories_written"]
                resumed += 1
            manifest.append(entry)

            if not args.dry_run:
                full_path.parent.mkdir(parents=True, exist_ok=True)
                full_path.write_text(transcript_text)

            print(f"  {date}-{uuid[:8]}  {user_turns} user turns  ~{token_estimate:,} tokens")
            processed += 1

    if project_filter is not None and projects_seen == 0:
        print(f"error: no conversations found for project: {project_filter}", file=sys.stderr)
        sys.exit(1)

    manifest.sort(key=lambda x: x["date"])

    manifest_path = output_dir / "manifest.json"
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, indent=2))
        print(f"\nmanifest written: {manifest_path}")

    total_tokens = sum(e["estimated_tokens"] for e in manifest)
    scope = project_filter if project_filter else "all projects"
    print(f"\n{'DRY RUN — ' if args.dry_run else ''}done")
    print(f"  scope                   : {scope}")
    print(f"  conversations extracted : {processed}")
    print(f"  already processed       : {resumed}")
    print(f"  conversations skipped   : {skipped}")
    print(f"  total estimated tokens  : {total_tokens:,}")
    print(f"  output dir              : {output_dir}")


if __name__ == "__main__":
    main()
