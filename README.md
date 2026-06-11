# vibe

Parallel feature worktrees — with optional agent orchestration — for any git repo.

Spin up an isolated workspace per feature (its own git worktree, on a branch namespaced by
the base it forked from), hack on it (yourself, or hand it to a coding agent), then
`finish` it (PR → conflict-check → squash-merge) and clean up — fast-forwarding the base
branch locally so nothing needs a manual `git pull`. One feature, one vibe.

The **core** lifecycle (`new` / `ls` / `cd` / `pull` / `finish`) needs only `git`
(+ [`gh`](https://cli.github.com) for `finish`). An **optional agent layer**
(`code` / `attach` / `recall` and the live `ls` board) integrates, when present, with:

- [**herdr**](https://herdr.dev) — run & observe agents in panes
- **sessiongrep** — past agent session history

The dev shell auto-detects a Nix flake (`nix develop`), otherwise opens your `$SHELL`.

## Install

```bash
install -m 0755 vibe ~/bin/vibe        # or /usr/local/bin (name is just the filename)
```

Or with Nix — the flake exposes `packages.<system>.vibe`.

## Use

```bash
# core (git only)
vibe new feature-a [--from main]   # worktree + branch wt/<base>/feature-a, opens a shell
vibe cd feature-a                  # open a shell in a worktree (exact or substring)
vibe pull other-feature            # merge another feature into the current branch
vibe finish [feature-a]            # PR (created if missing) → conflict-check → squash-merge
                                   #   → remove worktree → fast-forward base. No name = cwd.
vibe finish --no-merge / --base b / --force

# agent layer (needs herdr; history needs sessiongrep)
vibe code "add WhatsApp opt-out"   # worktree + start an agent on the prompt
   [--name x] [--from b] [--agent cmd]
vibe ls            (alias: board)  # worktrees × live agent state × PR × session history
vibe attach feature-a              # jump into the agent's pane
vibe recall feature-a [--since 1d] # session history scoped to a worktree
```

### The board

```
VIBE                BRANCH               AGENT      PR          HISTORY
auth-fix            wt/main/auth-fix     ● working  –           2 · 18m ago
export-pdf          wt/main/export-pdf   ◍ blocked  #41 open    1 · 3h ago
billing             wt/main/billing      ✓ done     #39 open    4
```

`AGENT` ← herdr `agent_status` (matched to a worktree by cwd) · `PR` ← gh ·
`HISTORY` ← sessiongrep (one scan, bucketed to the longest matching worktree path,
case-insensitive). Each column degrades to `–` if its tool/server isn't available.

### How it works

- **Worktrees** are created as siblings under `../<repo>-wt/<name>` (override with
  `vibe.dir`). The directory keeps the short feature name.
- **Branches** are namespaced `wt/<base>/<feature>` (override the `wt` prefix with
  `vibe.prefix`) so each branch records the base it forked from. The literal
  `<base>/<feature>` can't exist in git (a ref can't nest under an existing branch), hence
  the prefix; base slashes are flattened to dashes.
- **Base** defaults to the branch you're on; it's recorded in
  `git config branch.<branch>.vibeBase` so `finish` knows where to merge back.
- **Opening a shell**: a child process can't `cd` its parent, so `new`/`cd` drop you into a
  subshell *inside* the worktree (`exit` returns). It runs `vibe.shell` if set, else
  `nix develop` when a `flake.nix` is present, else your `$SHELL` — so your aliases/prompt
  are preserved. `VIBE_BASE` is exported for your prompt. When stdout isn't a TTY, `cd`
  just prints the path, so `cd "$(vibe cd foo)"` works.
- **finish** looks up the *open* PR by `--head` (ignoring stale merged PRs from a reused
  name) and merges by number, deletes the remote branch itself (avoids `gh`'s
  worktree-switch failure), then fast-forwards the base in whatever worktree has it checked
  out — no manual pull. It refuses the primary checkout and `main`/`master`.

### Config

Simple knobs via git config or env:

| git config | env | default |
|---|---|---|
| `vibe.dir` | `VIBE_DIR` | `../<repo>-wt` |
| `vibe.prefix` | `VIBE_PREFIX` | `wt` |
| `vibe.shell` | `VIBE_SHELL_CMD` | auto (nix flake → `nix develop`, else `$SHELL`) |
| `vibe.remote` | `VIBE_REMOTE` | `origin` |

```bash
git config vibe.shell 'devenv shell'   # e.g. a devenv project
```

### Per-project setup: `.vibe.sh` + hooks

For anything beyond static knobs (compute per-worktree ports, write `.env` files, spin
services up/down), commit a **`.vibe.sh`** at the repo root. `vibe` sources it on every
run, so it can set `VIBE_*` defaults and define two optional hook functions:

- **`vibe_setup`** — runs after `new` creates a worktree and again on `cd` (before the
  shell opens). It receives `$VIBE_WORKTREE`, `$VIBE_BASE`, `$VIBE_BRANCH`, `$VIBE_NAME`,
  and anything it **`export`s flows into the shell** vibe then opens.
- **`vibe_teardown`** — runs in `finish` just before the worktree is removed (stop
  services, etc.), with the same variables.

```bash
# .vibe.sh — per-worktree isolated dev instance (committed, shared with the team)
VIBE_PREFIX=wt

vibe_setup() {
  # Deterministic port offset from the worktree name; write the app's local env.
  local off=$(( $(printf '%s' "$VIBE_NAME" | cksum | cut -d' ' -f1) % 50 ))
  export PORT=$(( 3000 + off )) COMPOSE_PROJECT_NAME="myapp-$VIBE_NAME"
  cat > "$VIBE_WORKTREE/.env.local" <<EOF
PORT=$PORT
DATABASE_URL=postgres://localhost:$(( 5432 + off ))/myapp
EOF
}

vibe_teardown() {
  COMPOSE_PROJECT_NAME="myapp-$VIBE_NAME" docker compose down >/dev/null 2>&1 || true
}
```

This is how a project layers its per-worktree ports / Docker compose project / `.env`
generation on top of the generic lifecycle — without forking `vibe`.
(`.vibe.sh` is sourced, i.e. executed; only commit ones you trust — it's your own repo.)

## Requirements

- `git` (worktrees), and `gh` for `finish`'s PR create/merge (skip with `--no-merge`).
