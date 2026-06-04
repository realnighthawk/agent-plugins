# Publishing plugin artifacts

There is **no** npm package and **no** GitHub Packages (GHCR) publish for these plugins. Distribution works like this:

### Where files show up on GitHub

| Location | What you see | Used by install? |
|----------|----------------|------------------|
| **Actions → workflow run → Artifacts** | `mcp-call-binaries` zip from `upload-artifact` | No — CI/debug only, expires |
| **Packages** (sidebar) | Nothing for this repo | No — workflow does not push here |
| **Releases** (sidebar) | `mcp-call-*` binaries attached to tag `v*` | **Yes** — `scripts/fetch-mcp-call.sh` downloads from here |

If you only see **Artifacts** but not **Releases**, the run was probably **workflow_dispatch** (manual) or a branch push — release upload runs only when the workflow is triggered by a **`v*` tag push**.

| Artifact | What it is | How it ships |
|----------|------------|--------------|
| **Plugin files** (hooks, templates) | Cursor / Claude / OpenClaw trees under `plugins/` | Public git repo + `curl \| bash` install scripts (`raw.githubusercontent.com/...`) |
| **`mcp-call` binary** | Go CLI in `cmd/mcp-call` | **GitHub Release** assets on tag `v*` (see [.github/workflows/publish.yml](../.github/workflows/publish.yml)) |
| **Cursor `/add-plugin`** | Marketplace listing | **Not published yet** — use `install.sh` until listed |

## One-time: make the repo public

Onboarding URLs in agent-brain / agent-web assume a **public** repo:

`https://github.com/realnighthawk/agent-plugins`

If the repo is private, anonymous users get **404** on raw install scripts and release downloads. Settings → General → Change repository visibility → Public.

## Publish `mcp-call` binaries

1. Merge `main` with `.github/workflows/publish.yml` and `cmd/mcp-call/`.
2. Tag and push (triggers the workflow):

   ```bash
   git tag -a v0.1.1 -m "mcp-call release"
   git push origin v0.1.1
   ```

3. In GitHub: **Actions** → “Publish plugin artifacts” → confirm the run for the tag succeeded.
4. In GitHub: **Releases** → open the tag → assets should include:
   - `mcp-call-linux-amd64`, `mcp-call-linux-arm64`
   - `mcp-call-darwin-amd64`, `mcp-call-darwin-arm64`
   - `checksums.txt`

5. Smoke-test download (replace arch as needed):

   ```bash
   curl -fsSL -o /tmp/mcp-call \
     https://github.com/realnighthawk/agent-plugins/releases/latest/download/mcp-call-darwin-arm64
   chmod +x /tmp/mcp-call && /tmp/mcp-call --help 2>&1 | head -3
   ```

**Manual “Run workflow”** builds CI artifacts only; it does **not** create a Release. Always publish installable binaries with:

```bash
git tag -a v0.1.1 -m "mcp-call release"
git push origin v0.1.1
```

Then open **Releases** (not Packages), not the Actions artifact zip.

## Re-publish the same version

GitHub does not re-run tag workflows on the same tag name. Bump the patch version:

```bash
git tag -d v0.1.0 && git push origin :refs/tags/v0.1.0   # only if you need to replace
git tag -a v0.1.1 -m "mcp-call release"
git push origin v0.1.1
```

## Cursor marketplace (separate)

`/add-plugin agent-brain` needs a Cursor marketplace submission for `plugins/cursor/.cursor-plugin/plugin.json`. That is independent of GitHub Releases.
