# vibe

Parallel feature worktrees for any git repo. Spin up an isolated workspace per feature
(its own git worktree, on a branch namespaced by the base it forked from), hack on it,
then `finish` it (PR → conflict-check → squash-merge) and clean up — fast-forwarding the
base branch locally so nothing needs a manual `git pull`. One feature, one vibe.

Generic over any git project. No assumptions about ports, Docker, or a build system —
the dev shell auto-detects a Nix flake (`nix develop`), otherwise opens your `$SHELL`.
Uses [`gh`](https://cli.github.com) for PR create/merge (only in `finish`).

## Install

```bash
# put it on PATH (the name is just the filename — rename freely)
install -m 0755 vibe ~/bin/vibe        # or /usr/local/bin
```

## Use

```bash
vibe new feature-a           # worktree + branch wt/<current-branch>/feature-a, opens a shell
vibe new feature-a --from main
vibe ls                      # worktrees + branch + PR state
vibe cd feature-a            # open a shell in a worktree (exact or substring match)
vibe pull other-feature      # merge another feature into the current branch
vibe finish                  # PR (created if missing) → conflict-check → squash-merge →
                             # remove worktree → fast-forward the base locally
vibe finish --base main      # override the merge base
vibe finish --no-merge       # just stop + remove (no PR merge)
```

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

| git config | env | default |
|---|---|---|
| `vibe.dir` | `VIBE_DIR` | `../<repo>-wt` |
| `vibe.prefix` | `VIBE_PREFIX` | `wt` |
| `vibe.shell` | `VIBE_SHELL_CMD` | auto (nix flake → `nix develop`, else `$SHELL`) |
| `vibe.remote` | `VIBE_REMOTE` | `origin` |

Example — a project that uses `devenv`:

```bash
git config vibe.shell 'devenv shell'
```

## Requirements

- `git` (worktrees), and `gh` for `finish`'s PR create/merge (skip with `--no-merge`).
