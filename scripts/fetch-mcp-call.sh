#!/usr/bin/env bash
# Install mcp-call to DEST: download a GitHub release binary, or fall back to go build.
#
# Usage:
#   ./scripts/fetch-mcp-call.sh /path/to/mcp-call
#   MCP_CALL_VERSION=v1.2.3 ./scripts/fetch-mcp-call.sh plugins/cursor/bin/mcp-call
#
# Env:
#   MCP_CALL_VERSION   Tag (v1.2.3), "latest", or empty for latest release asset
#   NIGHTHAWK_MCP_CALL_REPO  default realnighthawk/agent-plugins
#   NIGHTHAWK_MCP_CALL_SKIP_DOWNLOAD=1  force local go build only
set -euo pipefail

DEST="${1:?usage: fetch-mcp-call.sh <dest-path>}"
REPO="${NIGHTHAWK_MCP_CALL_REPO:-realnighthawk/agent-plugins}"
VERSION="${MCP_CALL_VERSION:-latest}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

detect_platform() {
  local goos goarch
  case "$(uname -s)" in
    Darwin) goos=darwin ;;
    Linux) goos=linux ;;
    *)
      echo "unsupported OS: $(uname -s)" >&2
      return 1
      ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) goarch=amd64 ;;
    arm64 | aarch64) goarch=arm64 ;;
    *)
      echo "unsupported arch: $(uname -m)" >&2
      return 1
      ;;
  esac
  echo "${goos}-${goarch}"
}

download_release() {
  local platform asset url tmp
  platform="$(detect_platform)"
  asset="mcp-call-${platform}"
  tmp="${DEST}.$$.tmp"

  if [[ "${NIGHTHAWK_MCP_CALL_SKIP_DOWNLOAD:-}" == "1" ]]; then
    return 1
  fi

  if [[ -z "$VERSION" || "$VERSION" == "latest" ]]; then
    url="https://github.com/${REPO}/releases/latest/download/${asset}"
  else
    local tag="${VERSION#v}"
    url="https://github.com/${REPO}/releases/download/v${tag}/${asset}"
  fi

  echo "Downloading mcp-call (${asset})..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url"
  else
    echo "need curl or wget to download mcp-call" >&2
    return 1
  fi

  chmod +x "$tmp"
  mkdir -p "$(dirname "$DEST")"
  mv -f "$tmp" "$DEST"
  echo "Installed ${DEST} from release"
  return 0
}

build_local() {
  if ! command -v go >/dev/null 2>&1; then
    return 1
  fi
  if [[ ! -f "${ROOT}/cmd/mcp-call/main.go" ]]; then
    return 1
  fi
  echo "Building mcp-call with go..."
  mkdir -p "$(dirname "$DEST")"
  (cd "$ROOT" && go build -o "$DEST" ./cmd/mcp-call)
  chmod +x "$DEST"
  echo "Built ${DEST}"
  return 0
}

if download_release; then
  exit 0
fi

if build_local; then
  exit 0
fi

cat >&2 <<EOF
Could not install mcp-call.

  • Publish or pick a release: https://github.com/${REPO}/releases
  • Or install Go and build: go build -o "${DEST}" ./cmd/mcp-call

Optional: MCP_CALL_VERSION=vX.Y.Z $0 ${DEST}
EOF
exit 1
