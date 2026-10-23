#!/usr/bin/env bash
#
# publish-wiki.sh — mirror this repository's docs/ into the GitHub wiki
# (xxDoman/strata-gfx906.wiki) and check that every link in the published text is ABSOLUTE.
#
# The repository copy of docs/ is the canonical one; the wiki is a mirror. This script never
# invents content: it copies files, rewrites docs/index.md into the wiki's Home page and
# generates _Sidebar.md from the same mapping, so the sidebar cannot drift from the pages.
#
# Usage:
#   tools/publish-wiki.sh                     # DRY RUN (default): shows what would change, no commit
#   tools/publish-wiki.sh --write             # copies into the wiki clone and makes a LOCAL commit
#   tools/publish-wiki.sh --write --push      # ... and pushes (needs credentials; never done by default)
#   tools/publish-wiki.sh --check-links       # only the link check, no wiki involved
#   tools/publish-wiki.sh --wiki-dir DIR      # wiki clone elsewhere (default $STRATA_WIKI_DIR
#                                             # or $HOME/hermes_dane/strata-gfx906.wiki)
#
# Dry run is the default on purpose: nothing is committed or pushed unless --write/--push are given.
#
# Exit codes: 0 = ok / dry run clean, 1 = usage or environment error, 2 = link check failed,
#             3 = wiki clone missing or not a git repository.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIKI_URL="https://github.com/xxDoman/strata-gfx906.wiki.git"
WIKI_DIR="${STRATA_WIKI_DIR:-$HOME/hermes_dane/strata-gfx906.wiki}"
MODE="dry-run"      # dry-run | write
PUSH="no"
CHECK_ONLY="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)     MODE="dry-run" ;;
    --write)       MODE="write" ;;
    --push)        PUSH="yes" ;;
    --check-links) CHECK_ONLY="yes" ;;
    --wiki-dir)    shift; WIKI_DIR="${1:-}" ;;
    -h|--help)     sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

# ---------------------------------------------------------------------------
# 1. Link check: every markdown link in the published text must be absolute.
#    Relative docs/... paths do NOT work on the Docker Hub page, so they are a
#    hard error here.
# ---------------------------------------------------------------------------
link_check() {
  say "== LINK CHECK (absolute links only) =="
  python3 - "$REPO_DIR" <<'PY'
import os, re, sys
repo = sys.argv[1]

# Required: everything that is published as the image page or as the pages this change created.
REQUIRED = ["README.md", "llms.txt", "docs/index.md", "docs/operations.md", "docs/benchmarks.md"]
eng = os.path.join(repo, "docs", "engines")
if os.path.isdir(eng):
    REQUIRED += ["docs/engines/" + f for f in sorted(os.listdir(eng)) if f.endswith(".md")]
# Inherited: pages that were already in the repository with relative links (listed, not failed).
LEGACY = ["docs/measurements.md", "docs/image-history.md", "docs/rankings.md",
          "docs/where-we-stand.md", "docs/community-benchmark.md"]

link_re = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
ABS = re.compile(r"^(https?://|mailto:|#)")


def links(t):
    path = os.path.join(repo, t)
    if not os.path.isfile(path):
        return None
    out = []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        for url in link_re.findall(line):
            out.append((n, url))
    return out


ok, total = True, 0
print("  -- required: the image page, the engine pages and the indexes --")
for t in REQUIRED:
    rel = links(t)
    if rel is None:
        print(f"  {t}: MISSING")
        ok = False
        continue
    for n, url in rel:
        total += 1
        print(f"    {t}:{n}  {url}" + ("" if ABS.match(url) else "   <-- RELATIVE, must be fixed"))
    bad = [u for (n, u) in rel if not ABS.match(u)]
    if bad:
        ok = False
    print(f"  {t}: {len(rel)} link(s), " + ("all absolute" if not bad else f"{len(bad)} RELATIVE"))
print("  -- inherited: pages that already existed; listed here, not failed --")
n_legacy = 0
for t in LEGACY:
    rel = links(t)
    if rel is None:
        continue
    bad = [(n, u) for (n, u) in rel if not ABS.match(u)]
    n_legacy += len(bad)
    for n, u in bad:
        print(f"    {t}:{n}  {u}   <-- relative, inherited")
    if not bad:
        print(f"    {t}: no relative links")
print(f"  total: {total} required link(s) checked, {n_legacy} inherited relative link(s)")
print("  RESULT: " + ("OK - every required link is absolute" if ok else "FAIL - fix the relative links marked above"))
sys.exit(0 if ok else 2)
PY
  local rc=$?
  [ "$rc" -eq 0 ] || return 2
}

if [ "$CHECK_ONLY" = "yes" ]; then
  link_check || exit $?
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Mapping repo file -> wiki page file.
#    docs/index.md becomes the wiki's Home; the engine pages get an "Engine-" prefix so the
#    wiki lists them together and the URLs stay stable and readable.
# ---------------------------------------------------------------------------
map_lines() {
  cat <<'MAP'
docs/engines/README.md|Engines.md
docs/engines/0.2.3.md|Engine-0.2.3.md
docs/engines/0.2.1.md|Engine-0.2.1.md
docs/engines/0.1.45.md|Engine-0.1.45.md
docs/engines/0.1.43.1.md|Engine-0.1.43.1.md
docs/engines/0.1.44.1.b.md|Engine-0.1.44.1.b.md
docs/engines/0.1.44.1.c.md|Engine-0.1.44.1.c.md
docs/engines/0.1.44.1.d.md|Engine-0.1.44.1.d.md
docs/engines/0.1.44.1.e.md|Engine-0.1.44.1.e.md
docs/engines/0.1.44.1.f.md|Engine-0.1.44.1.f.md
docs/engines/0.1.44.1.g.md|Engine-0.1.44.1.g.md
docs/index.md|Home.md
docs/image-history.md|image-history.md
docs/measurements.md|measurements.md
docs/community-benchmark.md|community-benchmark.md
docs/rankings.md|rankings.md
docs/where-we-stand.md|where-we-stand.md
docs/operations.md|operations.md
docs/benchmarks.md|benchmarks.md
MAP
}

# docs/index.md uses repo-style "page.md" links; the wiki resolves "page". Only this pair needs it.
to_wiki_home() {
  sed -E 's/\]\(([a-z0-9._-]+)\.md\)/](\1)/g'
}

if [ ! -d "$WIKI_DIR/.git" ]; then
  say "wiki clone not found at $WIKI_DIR"
  say "clone it first (read-only for this script in --dry-run):"
  say "    git clone $WIKI_URL $WIKI_DIR"
  exit 3
fi

say "repo: $REPO_DIR"
say "wiki: $WIKI_DIR  (branch: $(git -C "$WIKI_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'))"
say "mode: $MODE$([ "$PUSH" = "yes" ] && echo ' + push')"
hr

# ---------------------------------------------------------------------------
# 3. Sync. Plan is always printed; writes happen only in --write.
# ---------------------------------------------------------------------------
CHANGED=0
PLAN=""
while IFS='|' read -r src dst; do
  [ -n "$src" ] || continue
  s="$REPO_DIR/$src"; d="$WIKI_DIR/$dst"
  if [ ! -f "$s" ]; then
    PLAN="${PLAN}MISSING  $src (skipped - not in this repository)\n"
    continue
  fi
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  if [ "$src" = "docs/index.md" ]; then to_wiki_home < "$s" > "$tmp"; else cp "$s" "$tmp"; fi
  if [ ! -f "$d" ]; then
    PLAN="${PLAN}NEW      $dst   <- $src\n"; CHANGED=$((CHANGED+1))
  elif cmp -s "$tmp" "$d"; then
    PLAN="${PLAN}unchanged $dst\n"
  else
    PLAN="${PLAN}UPDATE   $dst   <- $src\n"; CHANGED=$((CHANGED+1))
    say "--- diff $dst (wiki) vs $src (repo) ---"
    diff -u "$d" "$tmp" | sed -n '1,60p'
    hr
  fi
  if [ "$MODE" = "write" ]; then cp "$tmp" "$d"; fi
  rm -f "$tmp"; trap - EXIT
done < <(map_lines)

printf '%b' "$PLAN"
say "pages to change: $CHANGED"

# ---------------------------------------------------------------------------
# 4. _Sidebar.md is generated from the same mapping (dry-run prints it, --write stores it).
# ---------------------------------------------------------------------------
WIKI_BASE="https://github.com/xxDoman/strata-gfx906/wiki"
SB="$(mktemp)"
{
  echo "**Strata on gfx906** — running record"
  echo
  echo "* [Home]($WIKI_BASE/Home)"
  echo "* [Engines — every tag, sums, what it fixes, what is not proven]($WIKI_BASE/Engines)"
  echo "* [image-history]($WIKI_BASE/image-history) · [measurements]($WIKI_BASE/measurements)"
  echo "* [community-benchmark]($WIKI_BASE/community-benchmark) · [rankings]($WIKI_BASE/rankings) · [where-we-stand]($WIKI_BASE/where-we-stand)"
  echo "* [operations]($WIKI_BASE/operations) · [benchmarks]($WIKI_BASE/benchmarks)"
  echo
  # Generated from the SAME mapping, so a new engine page cannot be missing from the sidebar.
  englist="$(map_lines | awk -v base="$WIKI_BASE" -F'|' '/^docs\/engines\// && $1 !~ /README/ {
      n = $1; sub(/^docs\/engines\//, "", n); sub(/\.md$/, "", n);
      printf "%s[%s](%s/Engine-%s)", (c++ ? " \302\267 " : ""), n, base, n }')"
  echo "Engine pages: $englist"
  echo
  echo "Source of truth: [\`docs/\`](https://github.com/xxDoman/strata-gfx906/tree/master/docs) in the repo"
  echo "(the wiki is a mirror, generated by \`tools/publish-wiki.sh\`)."
} > "$SB"
sidefile="$WIKI_DIR/_Sidebar.md"
if [ -f "$sidefile" ] && cmp -s "$SB" "$sidefile"; then
  say "_Sidebar.md: unchanged"
else
  say "_Sidebar.md: $([ -f "$sidefile" ] && echo UPDATE || echo NEW) (generated)"
  diff -u "$sidefile" "$SB" 2>/dev/null | sed -n '1,40p'
  [ "$MODE" = "write" ] && cp "$SB" "$sidefile"
fi
rm -f "$SB"

# ---------------------------------------------------------------------------
# 5. Commit / push — only in --write, and push only with an explicit --push.
# ---------------------------------------------------------------------------
say "git status in the wiki clone:"
git -C "$WIKI_DIR" status --short | sed 's/^/    /'
hr
if [ "$MODE" = "dry-run" ]; then
  say "DRY RUN: nothing copied, nothing committed, nothing pushed."
  link_check || exit $?
  say "re-run with --write to copy into the wiki clone (still local, no push)."
  exit 0
fi
if git -C "$WIKI_DIR" diff --quiet && git -C "$WIKI_DIR" diff --cached --quiet && [ -z "$(git -C "$WIKI_DIR" ls-files --others --exclude-standard)" ]; then
  say "nothing to commit"; exit 0
fi
git -C "$WIKI_DIR" add -A
git -C "$WIKI_DIR" commit -q -m "mirror docs/: engine pages (0.1.43.1, 0.1.44.1.b-.g), engine index, operations, benchmarks"
say "committed locally: $(git -C "$WIKI_DIR" rev-parse --short HEAD)  (NOT pushed)"
if [ "$PUSH" = "yes" ]; then
  git -C "$WIKI_DIR" push origin HEAD
else
  say "push not requested; when you want it: git -C $WIKI_DIR push origin HEAD"
fi
