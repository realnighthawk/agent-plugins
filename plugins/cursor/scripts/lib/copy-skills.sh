#!/usr/bin/env bash
# Copy plugin skills (skills/*/SKILL.md) into a destination skills directory.
# Usage: copy_plugin_skills <src_skills_dir> <dest_skills_dir>
copy_plugin_skills() {
  local src="$1" dest="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"
  for skill_dir in "${src}"/*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    local name
    name=$(basename "$skill_dir")
    mkdir -p "${dest}/${name}"
    cp "${skill_dir}SKILL.md" "${dest}/${name}/"
  done
}
