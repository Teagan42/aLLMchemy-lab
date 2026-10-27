#!/usr/bin/env bash
# Bootstraps a development environment for aLLMchemy from a bare clone of this lab.
#
#     ./setup.sh                 clone or update aLLMchemy, then run its own bootstrap
#     ./setup.sh --hooks         also install its pre-commit hook
#     ./setup.sh --check         also run the full suite (slow: ~70s)
#     ./setup.sh --https         clone over HTTPS instead of SSH
#     ./setup.sh --ref <branch>  check out a branch other than main
#
# Idempotent. Never touches a working tree that has uncommitted changes, and never resets,
# cleans or force-updates anything: this directory also holds detached scratch work.
#
# Portability floor matches the package it sets up — bash 3.2, no GNU-only flags — because
# the whole point of that floor is that it holds on the machine a developer actually has.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

REPO_DIR=aLLMchemy
REPO_SSH=git@github.com:Teagan42/aLLMchemy.git
REPO_HTTPS=https://github.com/Teagan42/aLLMchemy.git

# Authorship is pinned per-repository, not globally: a fresh clone otherwise inherits
# whatever identity the machine's global config carries, which is how commits end up
# attributed to an unrelated work address.
AUTHOR_NAME="Teagan42"
AUTHOR_EMAIL="that@teagantoally.rocks"

REF=main
WANT_HOOKS=0
WANT_CHECK=0
REMOTE=$REPO_SSH
fails=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hooks) WANT_HOOKS=1 ;;
    --check) WANT_CHECK=1 ;;
    --https) REMOTE=$REPO_HTTPS ;;
    --ref)   shift; REF="${1:-main}" ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'setup: unknown argument %s (try --help)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '%s\n' "$*"; }
ok()   { printf '  OK    %-22s %s\n' "$1" "${2:-}"; }
warn() { printf '  WARN  %-22s %s\n' "$1" "${2:-}"; }
bad()  { printf '  FAIL  %-22s %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
die()  { printf 'setup: FAIL %s\n' "$*" >&2; exit 1; }

# --- Required tools --------------------------------------------------------------------
say "Required tools:"
for t in git node jq make; do
  if command -v "$t" >/dev/null 2>&1; then
    case "$t" in
      node) ok node "$(node --version)" ;;
      git)  ok git "$(git --version | awk '{print $3}')" ;;
      *)    ok "$t" present ;;
    esac
  else
    bad "$t" "absent — install it and re-run"
  fi
done

# node --test is the billing-core runner, and its directory form only landed in 23. The
# repo uses the glob form for exactly this reason, so 18 is enough.
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
  case "$NODE_MAJOR" in
    ''|*[!0-9]*) warn node "cannot parse version; expected v18 or newer" ;;
    *) [ "$NODE_MAJOR" -lt 18 ] && bad node "v$NODE_MAJOR is too old; need 18 or newer" ;;
  esac
fi

[ "$fails" -eq 0 ] || die "$fails required tool(s) missing. Nothing was changed."

# --- Optional tools --------------------------------------------------------------------
# Named with what is lost, because "optional" alone tells a developer nothing about
# whether they should care.
say ""
say "Optional tools:"
command -v shellcheck >/dev/null 2>&1 \
  && ok shellcheck "$(shellcheck --version | awk '/version:/{print $2}')" \
  || warn shellcheck "absent — make lint skips its deepest shell checks"
command -v uvx >/dev/null 2>&1 \
  && ok uvx present \
  || warn uvx "absent — no model-failover gateway (curl -LsSf https://astral.sh/uv/install.sh | sh)"
command -v ollama >/dev/null 2>&1 \
  && ok ollama present \
  || warn ollama "absent — no local provider; keep model_chain cloud-only"

# --- Reachability ----------------------------------------------------------------------
# Checked before cloning so an auth problem reports itself instead of surfacing as a
# confusing git error.
say ""
say "Remote:"
case "$REMOTE" in
  git@*)
    # Captured, not piped: github.com provides no shell access, so `ssh -T` exits 1 even
    # when the key authenticates, and under `pipefail` that status outranks grep's match.
    SSH_OUT=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
                  -T git@github.com 2>&1) || :
    case "$SSH_OUT" in
      *'successfully authenticated'*) ok ssh "github.com authenticated" ;;
      *) die "cannot authenticate to github.com over SSH.
  ssh said: $(printf '%s' "$SSH_OUT" | head -1)
  Add a key (https://github.com/settings/keys), or re-run with --https." ;;
    esac ;;
  *) ok https "$REMOTE" ;;
esac

# --- Clone or update -------------------------------------------------------------------
say ""
say "Repository:"
if [ ! -e "$REPO_DIR" ]; then
  git clone --branch "$REF" "$REMOTE" "$REPO_DIR" || die "clone failed"
  ok cloned "$REPO_DIR ($REF)"
elif [ ! -d "$REPO_DIR/.git" ]; then
  die "$REPO_DIR exists but is not a git repository.
  It may be detached scratch work. Move it aside, then re-run; this script will not
  overwrite a directory it did not create."
else
  HAVE=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)
  case "$HAVE" in
    "$REPO_SSH"|"$REPO_HTTPS") ok remote "$HAVE" ;;
    *) die "$REPO_DIR points at an unexpected remote:
  $HAVE
  Expected $REPO_SSH. Refusing to touch it." ;;
  esac
  git -C "$REPO_DIR" fetch --quiet origin || warn fetch "could not reach origin; using the local copy"
  # Report divergence; never resolve it. A pull here could conflict with work in progress,
  # and this script has no business deciding how that is merged.
  if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
    warn "working tree" "uncommitted changes present; left untouched"
  else
    ok "working tree" clean
  fi
  BEHIND=$(git -C "$REPO_DIR" rev-list --count "HEAD..origin/$REF" 2>/dev/null || echo 0)
  case "$BEHIND" in
    0) ok "up to date" "origin/$REF" ;;
    *) warn "behind origin" "$BEHIND commit(s). Merge when ready: git -C $REPO_DIR pull --ff-only" ;;
  esac
fi

# --- Authorship ------------------------------------------------------------------------
say ""
say "Authorship:"
for d in . "$REPO_DIR"; do
  git -C "$d" config user.name  "$AUTHOR_NAME"  2>/dev/null
  git -C "$d" config user.email "$AUTHOR_EMAIL" 2>/dev/null
  ok "$(basename "$(cd "$d" && pwd)")" \
     "$(git -C "$d" config user.name) <$(git -C "$d" config user.email)>"
done

# --- The repo's own bootstrap ----------------------------------------------------------
# Delegated, not reimplemented: aLLMchemy/dev/setup.sh owns the exec bits, the artifacts
# directory and its own tool doctor. A second copy here would drift from it.
say ""
say "Package bootstrap (aLLMchemy/dev/setup.sh):"
if [ "$WANT_HOOKS" = 1 ]; then
  ( cd "$REPO_DIR" && make setup ARGS=--hooks ) || die "package bootstrap failed"
else
  ( cd "$REPO_DIR" && make setup ) || die "package bootstrap failed"
fi

if [ "$WANT_CHECK" = 1 ]; then
  say ""
  say "Full suite (make check):"
  ( cd "$REPO_DIR" && make check ) || die "make check failed — the checkout is not healthy"
fi

say ""
say "Ready. Open THIS directory, not $REPO_DIR/, so you get the lab's Claude config:"
say "  questions and plan mode are permitted here; inside the package they are denied."
say ""
say "  cd $REPO_DIR"
say "  make check      # lint then test. Run before every commit"
say ""
say "The development contract is $REPO_DIR/DEVELOPING.md. Read it before changing anything:"
say "it carries the seam map, the TDD loop and the atomic-commit rules."
say ""
say "Never run $REPO_DIR/bin/run-*.sh to try something out. They provision real"
say "infrastructure and spend real money, and there is no dry-run flag."
