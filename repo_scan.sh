#!/usr/bin/env bash
# =============================================================================
# git-hidden-history-scan.sh
#
# Finds things that LOOK gone but are still in your local repository:
#   A. Refs hidden from 'git branch -a' / 'git tag' (refs/original, refs/pull...)
#   B. Old tips of force-pushed remote branches (history rewritten on the server)
#   C. Unreachable commit tips: left behind by rebase, amend, reset --hard,
#      deleted branches, dropped stashes - with or without a reflog entry
#   D. Leftovers on GitHub: overwritten / deleted branch and tag tips and pull-
#      request refs that GitHub still serves by hash although no ref reaches
#      them. Those commits are downloaded to a temporary folder OUTSIDE the repo
#      so the next two sections can scan them too. The only section that uses
#      the network (read-only requests).
#   E. Potential secret leaks in ALL of the above (refs + reflogs + unreachable
#      commits + GitHub-only commits). Findings are tagged HIDDEN (in this clone,
#      no ref reaches it), SERVER (only on GitHub) or visible. Uses gitleaks if
#      installed (needs jq), else a coarse regex scan. Secret values never printed.
#   F. Personal data in ALL of the above: author/committer identities, plus
#      emails, phone numbers, IBANs and private IPs in file contents, file names
#      and commit messages, plus your own list of terms (names, customers,
#      hostnames, streets). Same tags as E.
#
# Normal branches (merged / unmerged / orphan) are deliberately NOT scanned:
# 'git branch -a' already shows those.
#
# USAGE (from anywhere inside the repo):
#   ./git-hidden-history-scan-v2.sh [terms-file]
#   SHOW_VALUES=1 ./git-hidden-history-scan-v2.sh [terms-file]
#
#   terms-file (optional, or env TERMS_FILE): one term per line, case-insensitive,
#     '#' comments and blank lines ignored, minimum 3 characters. Put in whatever
#     must not appear in a public repo: customer names, people, internal
#     hostnames, street names, project code names.
#   SHOW_VALUES=1: section F also prints the matched text (emails, numbers).
#     Default is to hide it so the output is safe to paste.
#   NO_NET=1 skips section D entirely; NO_SERVER_FETCH=1 keeps the GitHub check but
#     does not download the GitHub-only commits (they are then not content-scanned).
#
# ZERO-WRITE GUARANTEE: this script never writes anything to the repository.
#   - NO 'git fetch' (it would update/prune your local remote-tracking refs).
#   - NO '--lost-found' on fsck (that would write files into .git/lost-found).
#   - NO branch creation, no gc, no prune. Only read commands are used.
#   The output tells you the command to rescue something, but YOU run it.
#   Section D downloads GitHub-only commits into a temporary folder OUTSIDE the
#   repo (read via GIT_ALTERNATE_OBJECT_DIRECTORIES) that is deleted on exit; the
#   repo itself is still never written.
#
# LIMIT: it can only see objects that exist in THIS clone. A force-push that
#   happened on the server before you ever fetched leaves no trace here. Old
#   tips show up only if your clone had fetched them before the rewrite. Section D
#   closes that gap for GitHub by asking the server what the clone cannot know.
# =============================================================================

# -----------------------------------------------------------------------------
# Shell safety flags
#   set -u          : error on use of an undefined variable (catches typos that
#                     would otherwise silently expand to an empty string).
#   set -o pipefail : a pipeline fails if ANY stage fails, not just the last.
#   NOT used: 'set -e'. Several commands are expected to return non-zero
#   (grep with no match, rev-list on odd refs); -e would kill the script on
#   exactly the results we are looking for.
# -----------------------------------------------------------------------------
set -u
set -o pipefail

# -----------------------------------------------------------------------------
# GIT_OPTIONAL_LOCKS=0
#   Some git commands opportunistically refresh the index (and write to it)
#   even when you only wanted to read. This env var tells git not to take
#   optional locks / do such background writes. Belt and braces for the
#   zero-write guarantee.
# -----------------------------------------------------------------------------
export GIT_OPTIONAL_LOCKS=0

# -----------------------------------------------------------------------------
# Sanity check: are we inside a git repository?
#   rev-parse --git-dir : prints the .git path, fails outside a repo.
#   >/dev/null 2>&1     : only the exit code matters, hide all output.
# -----------------------------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not inside a git repository. cd into one and re-run." >&2
    exit 1
fi

# Helper: one-line description of a commit.
#   git log -1            : only one commit
#   --date=short          : YYYY-MM-DD
#   --format='%ad %h ...' : date, abbreviated hash, author name, subject
#   2>/dev/null           : hide the error if the object is missing/corrupt
describe() {
    git log -1 --date=short --format='%ad %h  %an  %s' "$1" 2>/dev/null || echo "$1 (cannot read)"
}

# =============================================================================
# Section A: refs that 'git branch -a' and 'git tag' do not show
#
# Everything git tracks is a ref under refs/. Normal ones live in refs/heads
# (local branches), refs/remotes (remote branches), refs/tags and refs/stash.
# Anything ELSE is invisible to everyday commands but keeps history alive:
#   refs/original/*  : backup left by 'git filter-branch' (pre-rewrite history!)
#   refs/replace/*   : 'git replace' objects that silently alter history
#   refs/notes/*     : git notes
#   refs/pull/*, refs/changes/*, refs/merge-requests/* : forge-specific refs
#                      fetched by custom refspecs (GitHub / Gerrit / GitLab)
#
#   git for-each-ref   : machine-friendly ref listing.
#   --format=...       : full ref name, tip hash (short), tip subject.
#   grep -Ev '^refs/(heads|remotes|tags)/|^refs/stash' : drop the ordinary ones
#       -E extended regex, -v invert match (keep non-matching lines).
# =============================================================================
echo "================ A. Refs hidden from 'git branch -a' / 'git tag' ================"
hidden=$(git for-each-ref --format='%(refname)  %(objectname:short)  %(subject)' \
    | grep -Ev '^refs/(heads|remotes|tags)/|^refs/stash')
if [ -z "$hidden" ]; then
    echo "(none)"
else
    echo "$hidden"
fi
echo

# =============================================================================
# Section B: old tips of force-pushed remote branches
#
# Every time you 'git fetch', git logs the move of each remote-tracking ref in
# its reflog. When the server branch was rewritten (force-push), the entry says
# "forced-update". The commit that ref pointed to BEFORE that entry is the old,
# overwritten history. If nothing else references it, it is invisible in
# normal views.
#
#   git for-each-ref --format='%(refname)' refs/remotes
#       all remote-tracking refs as full names (refs/remotes/origin/foo).
#   case */HEAD) continue   : skip origin/HEAD, a pointer not a real branch.
#
#   git reflog show --format='%H %gs' <ref>
#       show: print that ref's reflog (newest entry first).
#       %H  : full commit hash of the entry.
#       %gs : reflog subject, e.g. "fetch origin: forced-update".
#
#   awk: reads entries newest -> oldest. When a line says forced-update, the
#       NEXT (older) line's hash is the tip that was overwritten, so we print it.
#
#   git rev-list --count <hash> --not --all
#       counts commits reachable from <hash> but NOT from any ref. If the count
#       is 0, the old tip is still on some branch/tag -> not hidden, skip it.
#       If >0, that history is hidden. (--all = all refs; reflogs are not
#       included in --all, which is what we want.)
# =============================================================================
echo "================ B. Old tips of force-pushed remote branches (hidden) ================"
found=0
for ref in $(git for-each-ref --format='%(refname)' refs/remotes); do
    case "$ref" in
        */HEAD) continue ;;
    esac
    while read -r oldtip; do
        [ -z "$oldtip" ] && continue
        n=$(git rev-list --count "$oldtip" --not --all 2>/dev/null || echo 0)
        if [ "${n:-0}" -gt 0 ]; then
            printf '%s  [%s commits hidden, was %s]\n' "$(describe "$oldtip")" "$n" "${ref#refs/remotes/}"
            echo "      full hash: $oldtip"
            found=1
        fi
    done < <(git reflog show --format='%H %gs' "$ref" 2>/dev/null \
        | awk 'forced { print $1; forced = 0 } /forced-update/ { forced = 1 }')
done
[ "$found" -eq 0 ] && echo "(none - no force-pushes seen in your fetch history)"
echo

# =============================================================================
# Section C: unreachable commit tips
#
# A commit is "reachable" if you can get to it from a branch, tag or stash by
# following parent links. History rewrites (rebase, amend, reset --hard,
# filter-repo), deleted branches and dropped stashes leave commits that nothing
# points to. They stay in the object database until 'git gc' prunes them
# (default grace: 2 weeks unreachable; reflog entries keep them longer, 30-90
# days).
#
#   git fsck           : verifies the object database and can list orphaned
#                        objects.
#   --dangling         : print only objects that are unreachable AND not
#                        referenced by any other unreachable object - i.e. the
#                        TIP of each orphaned chain, not every commit in it.
#                        (Keeps the output short; the chain size is counted
#                        separately below.)
#   --no-reflogs       : do NOT treat reflog entries as "reachable". By default
#                        the reflog protects recent amended/rebased commits
#                        from showing up, but those are exactly the ones we
#                        want. We label reflog-protected ones separately.
#   --no-progress      : no progress meter (clean output when piped).
#   2>/dev/null        : hide informational stderr lines.
#   awk '/dangling commit/ {print $3}' : keep only commits (ignore dangling
#                        blobs/trees, which are just old staged file contents),
#                        print the hash column.
#
#   reflog_set = git rev-list --reflog --not --all
#       every commit reachable from some reflog entry but from no ref. If a tip
#       is in this set, 'git reflog' can still find it (easy recovery). If not,
#       the reflog already expired and only the object database remembers it.
#       --reflog : treat all reflog entries as starting points.
#
#   git rev-list --count <tip> --not --all : size of the orphaned chain (the
#       commits that exist only because of this tip).
#
#   Dropped stash heuristic: stash commits have subjects starting with
#       "WIP on ", "On " or "index on ". Those are flagged as probable dropped
#       stashes.
# =============================================================================
echo "================ C. Unreachable commit tips (rewritten / deleted history) ================"
tips=$(git fsck --dangling --no-reflogs --no-progress 2>/dev/null \
    | awk '/dangling commit/ {print $3}')

if [ -z "$tips" ]; then
    echo "(none)"
else
    reflog_set=$(git rev-list --reflog --not --all 2>/dev/null)
    # One two-line record per orphaned tip (order = fsck's order, not sorted).
    {
        for tip in $tips; do
            n=$(git rev-list --count "$tip" --not --all 2>/dev/null || echo "?")
            if printf '%s\n' "$reflog_set" | grep -qx "$tip"; then
                where="in reflog"
            else
                where="object-db only"
            fi
            subject=$(git log -1 --format='%s' "$tip" 2>/dev/null)
            case "$subject" in
                "WIP on "* | "On "* | "index on "*) flag=" [probably a dropped stash]" ;;
                *) flag="" ;;
            esac
            printf '%s  [%s commits, %s]%s\n      full hash: %s\n' \
                "$(describe "$tip")" "$n" "$where" "$flag" "$tip"
        done
    }
    echo
    echo "Legend: 'in reflog'      = still listed by 'git reflog', expires on its own."
    echo "        'object-db only' = reflog forgot it; 'git gc' may delete it any time."
    echo "Inspect:  git show <hash>        git log --oneline --graph <hash>"
    echo "Rescue :  git branch rescue/<name> <hash>      (run this yourself; the script does not)"
fi
echo

# =============================================================================
# Section D: history that is gone from every ref but still FETCHABLE on GitHub
#
# Why sections A-C cannot see this: after a force-push or a branch deletion,
# GitHub keeps the old commits and serves them to anyone who knows the hash.
# Your clone does not contain them, so no local scan can find them. GitHub has no
# "list unreachable objects" call, but it does record the EVENTS that create
# them, and those can be queried:
#   Activity API  : every force-push and branch deletion with the commit the
#                   branch pointed to BEFORE (= the overwritten / deleted tip).
#   Events feed   : recent pushes (roughly the last 90 days) with before/head SHAs.
#   commit lookup : GET /commits/<sha> answers 200 while GitHub still serves a
#                   commit = proof that it is still fetchable.
#   ls-remote     : hidden refs like refs/pull/N/head: pull requests keep their
#                   commits alive even after the branch is deleted.
#   repo info     : visibility and fork count (every fork keeps its own copy).
# Everything is a read-only request: nothing is written locally or on GitHub.
#
# LIMITS: there is no complete list. This finds commits that were created by a
#   force-push, a branch deletion, a recent push or a pull request, which is how
#   hidden history normally arises. Copies held by forks or other clones cannot
#   be enumerated from here. Needs curl + jq. Unauthenticated API calls are
#   limited to 60/hour: set GITHUB_TOKEN (e.g. GITHUB_TOKEN=$(gh auth token))
#   for more, and for private repositories.
#
# ENV: GH_REPO=owner/repo (override auto-detection from 'origin'),
#      GH_API=<url> (default https://api.github.com), NO_NET=1 (skip section D).
# =============================================================================
echo "================ D. Leftovers still served by GitHub (gone from refs, fetchable by hash) ================"

srv_fetch=""; srv_tips=""; srv_only=""; scratch=""
gh_slug="${GH_REPO:-}"
remote_url=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$gh_slug" ] && printf '%s' "$remote_url" | grep -qi github; then
    # Reduce any remote URL form (https, git@host:owner/repo.git, ssh alias) to
    # 'owner/repo': strip a trailing .git, then keep the last two path parts.
    gh_slug=$(printf '%s' "$remote_url" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')
fi
gh_api="${GH_API:-https://api.github.com}"

# gh_get URL : one GET request. Sets GH_STATUS (HTTP code), GH_BODY, GH_NEXT /
# GH_LAST (pagination links) and GH_REMAINING (calls left in the rate limit).
#   curl -sS -i : silent but show errors, include response headers in the output.
#   --max-time 30 : never hang on a dead connection.
#   The auth header is added only if GITHUB_TOKEN is set (never printed).
GH_STATUS=""; GH_BODY=""; GH_NEXT=""; GH_LAST=""; GH_REMAINING=""
gh_get() {
    local resp hdr auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    GH_STATUS="000"; GH_BODY=""; GH_NEXT=""; GH_LAST=""
    resp=$(curl -sS -i --max-time 30 -H 'Accept: application/vnd.github+json' \
        ${auth[@]+"${auth[@]}"} "$1" 2>/dev/null) || return 1
    hdr=${resp%%$'\r\n\r\n'*}
    GH_BODY=${resp#*$'\r\n\r\n'}
    GH_STATUS=$(printf '%s\n' "$hdr" | grep -i '^HTTP/' | tail -n1 | awk '{print $2}')
    GH_NEXT=$(printf '%s\n' "$hdr" | grep -i '^link:' | grep -o '<[^>]*>; rel="next"' | sed -E 's/^<([^>]*)>.*/\1/')
    GH_LAST=$(printf '%s\n' "$hdr" | grep -i '^link:' | grep -o '<[^>]*>; rel="last"' | sed -E 's/.*[?&]page=([0-9]+).*/\1/')
    GH_REMAINING=$(printf '%s\n' "$hdr" | grep -i '^x-ratelimit-remaining:' | tr -dc '0-9')
}

# gh_all URL : print the JSON of up to 5 pages (follows the 'next' link).
gh_all() {
    local url="$1" n=0
    while [ -n "$url" ] && [ "$n" -lt 5 ]; do
        gh_get "$url" || break
        [ "$GH_STATUS" = "200" ] || break
        printf '%s\n' "$GH_BODY"
        url="$GH_NEXT"; n=$((n + 1))
    done
}

if [ -n "${NO_NET:-}" ]; then
    echo "(NO_NET set - section D skipped)"
elif [ -z "$gh_slug" ]; then
    echo "(origin is not a GitHub remote - set GH_REPO=owner/repo to force this section)"
elif ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "curl and jq are required for section D:  sudo apt install curl jq"
else
    gh_get "$gh_api/repos/$gh_slug"
    if [ "$GH_STATUS" != "200" ]; then
        echo "GitHub API answered HTTP $GH_STATUS for '$gh_slug' (404 = private or wrong name, 403 = rate limit: set GITHUB_TOKEN)."
    else
        echo "repo: $gh_slug   visibility: $(printf '%s' "$GH_BODY" | jq -r '.visibility // (if .private then "private" else "public" end)')   forks: $(printf '%s' "$GH_BODY" | jq -r '.forks_count // "?"')   API calls left: ${GH_REMAINING:-?}"
        echo

        # ---- D1: candidate old tips, then ask GitHub whether it still serves them
        # jq filter 'ok' keeps real 40-hex SHAs and drops the all-zero SHA that
        # GitHub uses for "branch did not exist before".
        echo "-- D1. Overwritten/deleted branch tips and recent push tips, checked against GitHub --"
        okdef='def ok: . != null and test("^[0-9a-f]{40}$") and (test("^0+$") | not);'
        act="$gh_api/repos/$gh_slug/activity?per_page=100"
        cand=$( {
            gh_all "$act&activity_type=force_push"     | jq -r "$okdef"' .[] | select(.before | ok) | [.before, "force-push", .timestamp, .ref] | @tsv'
            gh_all "$act&activity_type=branch_deletion" | jq -r "$okdef"' .[] | select(.before | ok) | [.before, "branch-deleted", .timestamp, .ref] | @tsv'
            gh_all "$gh_api/repos/$gh_slug/events?per_page=100" | jq -r "$okdef"' .[] | select(.type == "PushEvent") | . as $e
                | ([$e.payload.before, "push-before", $e.created_at, $e.payload.ref], [$e.payload.head, "push-head", $e.created_at, $e.payload.ref])
                | select(.[0] | ok) | @tsv'
        } )

        # Skip SHAs that are still reachable from a local ref (those are not
        # hidden) and duplicates; ask GitHub about the rest.
        reach=$(git rev-list --all 2>/dev/null)
        seen=" "; checked=0; fetchable=0
        while IFS=$'\t' read -r sha src when ref; do
            [ -z "$sha" ] && continue
            case "$seen" in *" $sha "*) continue ;; esac
            seen="$seen$sha "
            printf '%s\n' "$reach" | grep -qx "$sha" && continue
            if [ "$checked" -ge 30 ] || { [ -n "$GH_REMAINING" ] && [ "$GH_REMAINING" -lt 5 ]; }; then
                echo "(stopped: 30-candidate cap or API rate limit reached - set GITHUB_TOKEN)"
                break
            fi
            checked=$((checked + 1))
            gh_get "$gh_api/repos/$gh_slug/commits/$sha"
            case "$GH_STATUS" in
                200)
                    fetchable=$((fetchable + 1)); srv_fetch="$srv_fetch $sha"
                    subj=$(printf '%s' "$GH_BODY" | jq -r '(.commit.message | split("\n")[0])[0:70]')
                    # commits reachable from this tip = number of pages when asking
                    # for 1 commit per page (the 'last' page number).
                    gh_get "$gh_api/repos/$gh_slug/commits?sha=$sha&per_page=1"
                    n="${GH_LAST:-1}"
                    printf 'FETCHABLE  %s  %s  %-14s %s  [%s commits reachable from this tip]  "%s"\n' \
                        "${sha:0:12}" "${when:0:10}" "$src" "$ref" "$n" "$subj"
                    echo "      full hash: $sha"
                    ;;
                404 | 422)
                    printf 'gone       %s  %s  %-14s %s  (not served)\n' "${sha:0:12}" "${when:0:10}" "$src" "$ref"
                    ;;
                *)
                    printf 'HTTP %-5s  %s  %s  %s  (could not check)\n' "$GH_STATUS" "${sha:0:12}" "${when:0:10}" "$src"
                    ;;
            esac
        done <<< "$cand"
        [ "$checked" -eq 0 ] && echo "(no candidate tips found: no force-pushes, deletions or unseen pushes in GitHub's records)"
        echo
        if [ "$fetchable" -gt 0 ]; then
            echo "RESULT: $fetchable commit(s) are on no ref anymore but GitHub still serves them to anyone with the hash."
            echo "  Only GitHub can purge them: contact GitHub Support with these hashes, or delete + recreate the repo."
            echo "  Their content is downloaded to a temporary folder OUTSIDE your repo and included in the"
            echo "  secret and personal-data sections below, tagged SERVER (NO_SERVER_FETCH=1 to skip)."
        else
            echo "RESULT: none of the $checked candidate commit(s) is still served by GitHub."
        fi
        echo
        # ---- Make the GitHub-only commits visible to the content scans below ----
        # The commits found above are not in this clone, so the secret and
        # personal-data sections could not read them. They are downloaded into a
        # TEMPORARY bare repository outside your repo and made readable through
        # GIT_ALTERNATE_OBJECT_DIRECTORIES (git then also looks for objects in that
        # folder). Your repo is never written; the folder is deleted when the
        # script exits.
        #   umask 077              : only you can read the temp folder (it holds the leaked data).
        #   mktemp -d              : a new unique folder, never reuses or overwrites one.
        #   git init --bare        : empty repository that receives the objects.
        #   git fetch --no-tags URL SHA... : GitHub allows fetching a commit by its full hash.
        #   GIT_TERMINAL_PROMPT=0  : fail instead of waiting for a password prompt.
        if [ "$fetchable" -gt 0 ] && [ -z "${NO_SERVER_FETCH:-}" ]; then
            fetch_url="$remote_url"; [ -z "$fetch_url" ] && fetch_url="https://github.com/$gh_slug.git"
            scratch=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/histscan.XXXXXX")
            trap 'rm -rf "$scratch"' EXIT
            git init -q --bare "$scratch/repo"
            # Commits this clone already knows, taken BEFORE borrowing the scratch objects.
            local_all=$( { git rev-list --all --reflog; [ -n "$tips" ] && git rev-list $tips; } 2>/dev/null | sort -u )
            if GIT_TERMINAL_PROMPT=0 git -C "$scratch/repo" fetch -q --no-tags "$fetch_url" $srv_fetch 2>/dev/null; then
                export GIT_ALTERNATE_OBJECT_DIRECTORIES="$scratch/repo/objects"
                srv_tips="$srv_fetch"
                #   comm -13 A B : lines only in B = commits reachable from the fetched
                #   tips that this clone has never had.
                srv_only=$(comm -13 <(printf '%s\n' "$local_all") <(git rev-list $srv_tips 2>/dev/null | sort -u))
                echo "Downloaded the GitHub-only commits to a temporary folder (deleted on exit): $(printf '%s\n' "$srv_only" | grep -c .) commit(s) exist only on GitHub."
                echo "They are included in the secret and personal-data sections below (tag SERVER)."
            else
                echo "WARNING: could not download those commits (offline, or the remote refuses fetch-by-hash)."
                echo "         Their CONTENT is NOT scanned below; the findings above still stand."
            fi
            echo
        fi
    fi

    # ---- D2: hidden refs on the server ---------------------------------------
    #   git ls-remote origin : lists every ref the server advertises, including
    #       refs/pull/N/head that 'git clone' and 'git fetch' never download.
    #   Branches and tags are filtered out; what remains is the hidden part.
    echo "-- D2. Hidden refs on the server (pull requests and other non-branch, non-tag refs) --"
    lsr=$(git ls-remote origin 2>&1); lsrc=$?
    if [ "$lsrc" -ne 0 ]; then
        echo "git ls-remote failed: $lsr"
    else
        hiddenrefs=$(printf '%s\n' "$lsr" | grep -vE $'\trefs/(heads|tags)/|\tHEAD$')
        if [ -z "$hiddenrefs" ]; then
            echo "(none)"
        else
            printf '%s\n' "$hiddenrefs" | awk -F'\t' '{ split($2, p, "/"); n[p[1] "/" p[2]]++ } END { for (k in n) printf "%6d refs under %s/\n", n[k], k }'
            echo "First 15:"
            printf '%s\n' "$hiddenrefs" | head -n 15 | awk -F'\t' '{ print "  " substr($1, 1, 12) "  " $2 }'
            echo "Commits behind these refs stay fetchable even if every branch is deleted."
        fi
    fi
    echo
fi

# =============================================================================
# Section E: potential secret leaks across ALL history, including hidden commits
#
# Why a dedicated step: standard secret scanners walk 'git log --all', which
# covers only commits reachable from refs. Everything found in sections B and C
# (rebased/amended commits, dropped stashes, old force-pushed tips) is invisible
# to them. Here the scanner is explicitly handed those commits as well.
#
# WHAT IS SCANNED (the 'scan_opts' string, passed to 'git log' by the scanner):
#   --all      : every ref (branches, tags, remotes, refs/agents/*, stash, ...)
#   --reflog   : every commit any reflog entry points to (amended/rebased/reset
#                history that is still remembered)
#   $tips      : the unreachable tips found in section C. 'git log' walks from
#                them to their parents, so whole orphaned chains are covered,
#                including 'object-db only' ones the reflog already forgot.
#   $srv_tips  : tips of commits that exist only on GitHub (section D), downloaded
#                into a temporary folder and read via GIT_ALTERNATE_OBJECT_DIRECTORIES,
#                so this repo is not touched.
#
# WRITES: none. Output goes to stdout only (no report file), so no secret-laden
#   file is left lying around. Values are masked with --redact.
# =============================================================================
echo "================ E. Potential secret leaks (all refs + reflogs + unreachable + GitHub-only commits) ================"

scan_opts="--all --reflog ${tips:-} ${srv_tips:-}"
# Repo root: gitleaks wants the repo path, and we may be run from a subfolder.
#   rev-parse --show-toplevel : absolute path of the work tree root.
top=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# tag_findings: reads TSV on stdin (commit, date, author, rule, file:line) and
# prints one line per finding with a tag:
#   visible : the commit is reachable from some ref (branch, tag, remote).
#   HIDDEN  : the commit is in THIS clone but no ref reaches it (rewritten /
#             dropped history, found by sections B and C).
#   SERVER  : the commit is not even in this clone: it exists only on GitHub and
#             was downloaded by section D just for this scan.
# How: 'git rev-list --all' = commits reachable from refs, '$srv_only' = commits
#   that exist only on GitHub. Both are fed to awk through process substitution
#   ('<(...)'); awk tells the three inputs apart by FILENAME (argument 1 = reach,
#   argument 2 = server-only, anything else = the findings on stdin).
#   LC_ALL=C sort -k1,1 -k2,2r : byte-wise sort (HIDDEN, SERVER, visible), within
#   a tag newest date first (r = reverse).
tag_findings() {
    awk -F'\t' '
        FILENAME == ARGV[1] { reach[$1] = 1; next }
        FILENAME == ARGV[2] { srv[$1] = 1; next }
        { tag = ($1 in reach) ? "visible" : (($1 in srv) ? "SERVER" : "HIDDEN")
          printf "%-7s %s %s  %s  %s  %s\n", tag, $2, substr($1, 1, 9), $3, $4, $5 }
    ' <(git rev-list --all) <(printf '%s\n' "${srv_only:-}") - | LC_ALL=C sort -k1,1 -k2,2r
}

rows=""
scanner_ok=1

if command -v gitleaks >/dev/null 2>&1; then
    # ---- Preferred path: gitleaks (hundreds of maintained detection rules) ---
    # jq turns gitleaks' JSON report into TSV rows (needed for the HIDDEN tag).
    if ! command -v jq >/dev/null 2>&1; then
        echo "jq is required to parse gitleaks output:  sudo apt install jq"
        scanner_ok=0
    else
        # Flags (same meaning for both subcommands):
        #   --no-banner            : no ASCII logo in the output.
        #   --redact               : replace secret values with REDACTED in the
        #                            report - safe to paste anywhere.
        #   --exit-code 0          : exit 0 even when leaks are found, so a
        #                            non-zero code means a REAL error (bad flag,
        #                            crash) and not "found something".
        #   --report-format json   : machine-readable, parsed by jq below.
        #   --report-path /dev/stdout : write the report to stdout instead of a
        #                            file (nothing left on disk). Logs go to
        #                            stderr, which is discarded (2>/dev/null).
        #   --log-opts "..."       : extra arguments for the internal 'git log';
        #                            this is how hidden commits get included.
        # 'gitleaks git' exists in v8.19+; older versions use 'gitleaks detect'.
        if gitleaks git --help >/dev/null 2>&1; then
            json=$(gitleaks git --no-banner --redact --exit-code 0 \
                --report-format json --report-path /dev/stdout \
                --log-opts "$scan_opts" "$top" 2>/dev/null); rc=$?
        else
            json=$(gitleaks detect --no-banner --redact --exit-code 0 \
                --report-format json --report-path /dev/stdout \
                --source "$top" --log-opts "$scan_opts" 2>/dev/null); rc=$?
        fi

        if [ "$rc" -ne 0 ]; then
            echo "gitleaks failed (exit $rc). Re-run it by hand without 2>/dev/null to see why."
            scanner_ok=0
        else
            # jq: '(. // [])[]' iterates the findings array, treating a JSON
            # null (no findings) as an empty array. -r = raw output (no quotes),
            # @tsv = tab-separated row. Date[0:10] cuts the timestamp to YYYY-MM-DD.
            rows=$(printf '%s' "$json" | jq -r '(. // [])[]
                | [.Commit, .Date[0:10], .Author, .RuleID, "\(.File):\(.StartLine)"]
                | @tsv')
        fi
    fi
else
    # ---- Fallback path: plain regex, coarse and noisy ------------------------
    echo "gitleaks not found - using a coarse regex fallback (install gitleaks for real coverage)."
    # git log -p      : print the patch of every commit.
    # -U0             : zero context lines, only changed lines (less to scan).
    # --format='@@C ' : marker line per commit so awk knows which commit a hit
    #                   belongs to. --date=short = YYYY-MM-DD.
    # LC_ALL=C grep -aE : byte-wise matching (fast, no locale errors), -a treat
    #                   binary data as text, -E extended regex. Keeps: commit
    #                   markers, file headers ('+++ b/path') and ADDED lines
    #                   ('^\+') matching a secret-looking pattern.
    # awk             : remembers current commit and file, and for every hit
    #                   prints a TSV row. The matched line itself is dropped, so
    #                   no secret value is ever printed.
    rows=$(git log $scan_opts -p -U0 --format='@@C %H %ad' --date=short 2>/dev/null \
        | LC_ALL=C grep -aE '^@@C |^\+\+\+ b/|^\+([^+].*)?(-----BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[baprs]-[A-Za-z0-9-]{10,}|[Pp]ass(word|wd)?[A-Za-z_]*[ ]*[:=][ ]*[^ ]{6,}|[Ss]ecret[A-Za-z_]*[ ]*[:=][ ]*[^ ]{6,}|[Tt]oken[A-Za-z_]*[ ]*[:=][ ]*[^ ]{8,}|[Aa]pi_?[Kk]ey[A-Za-z_]*[ ]*[:=][ ]*[^ ]{8,})' \
        | awk 'BEGIN { OFS = "\t" }
               /^@@C /       { c = $2; d = $3; next }
               /^\+\+\+ b\// { f = substr($0, 7); next }
               { print c, d, "-", "regex-hit", f }' \
        | sort -u)
fi

if [ "$scanner_ok" -eq 1 ]; then
    if [ -z "$rows" ]; then
        echo "(no findings)"
    else
        res=$(printf '%s\n' "$rows" | tag_findings)
        total=$(printf '%s\n' "$res" | wc -l)
        hid=$(printf '%s\n' "$res" | grep -c '^HIDDEN')
        srvn=$(printf '%s\n' "$res" | grep -c '^SERVER')
        # Cap the output PER TAG (first 100 HIDDEN + first 100 visible), not
        # overall. A single 'head -n 200' would let hundreds of HIDDEN findings
        # push every 'visible' finding off the screen, and visible ones are the
        # ones that matter most for a public release.
        #   awk: n[$1] counts lines per tag (first column); prints a line only
        #   while its tag's counter is <= 100; END reports what was cut.
        printf '%s\n' "$res" | awk '
            { n[$1]++; if (n[$1] <= 100) print }
            END { for (t in n) if (n[t] > 100) printf "... %s: %d more findings not shown\n", t, n[t] - 100 }'
        echo
        echo "Findings: $total total = $hid HIDDEN + $srvn SERVER + $((total - hid - srvn)) visible."
        echo "HIDDEN = in this clone, no ref reaches it; SERVER = only on GitHub (not in this clone); visible = on a branch/tag/remote."
        echo "Inspect: git show <hash>:<file>   (values are masked above)"
        echo "Any real secret must be ROTATED: removing it from history does not un-leak it."
    fi
fi
echo

# =============================================================================
# Section F: personal data across ALL history, including hidden commits
#
# Two different problems, handled separately:
#   F1. Identities: every commit stores author + committer NAME and EMAIL, and
#       publishing the history publishes all of them. Listed in full.
#   F2. Patterns and terms: emails, phone numbers, IBANs, private IPs and your
#       own term list, searched in added file lines, file names and commit
#       messages. Findings use the same HIDDEN / SERVER / visible tag as section E.
#
# CANNOT be found by pattern: free-form names and street addresses. Those are
# only found through the terms file you supply, so it finds what you list.
#
# WRITES: none. 'git log' output is streamed through awk, nothing goes to disk.
# PERFORMANCE: F2 reads every patch of every commit once; on a big repo this
#   can take several minutes.
# =============================================================================
echo "================ F. Personal data (identities, patterns, your term list) ================"

terms="${1:-${TERMS_FILE:-}}"
if [ -n "$terms" ] && [ ! -r "$terms" ]; then
    echo "WARNING: terms file '$terms' not readable - term search skipped." >&2
    terms=""
fi

# ---- F1: identities ---------------------------------------------------------
#   git log --format='%an <%ae>%n%cn <%ce>' : author name+email, then committer
#       name+email, one per line, for every commit in the scan set.
#   sort | uniq -c | sort -rn : count per identity, most frequent first.
#   comm -13 A B : lines only in B. A = identities on reachable history
#       ('--all'), B = identities in the whole scan set, so the result is the
#       identities that appear ONLY in hidden commits.
#   git for-each-ref refs/tags --format='%(taggername) %(taggeremail)' : who made
#       annotated tags (lightweight tags have none, empty lines are dropped).
echo "-- F1. Identities in history (real names/emails: do not paste publicly) --"
git log $scan_opts --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort | uniq -c | sort -rn
only_hidden=$(comm -13 \
    <(git log --all --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u) \
    <(git log $scan_opts --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u))
if [ -n "$only_hidden" ]; then
    echo "-- identities that appear ONLY in hidden commits --"
    printf '%s\n' "$only_hidden"
fi
taggers=$(git for-each-ref refs/tags --format='%(taggername) %(taggeremail)' 2>/dev/null \
    | grep -v '^ *$' | sort | uniq -c | sort -rn)
if [ -n "$taggers" ]; then
    echo "-- annotated tag authors --"
    printf '%s\n' "$taggers"
fi
echo

# ---- F2: patterns and terms --------------------------------------------------
# The awk program lives in a variable so it can be written without shell quoting
# problems (quoted heredoc = no expansion at all). It is mawk-compatible (the
# default awk on Ubuntu): no regex intervals like {3}, no gawk-only functions.
IFS= read -r -d '' awk_prog <<'AWK' || true
function okstart(s, p) { return (p <= 1) || (substr(s, p - 1, 1) !~ /[A-Za-z0-9_]/) }
function ndigits(s,   t) { t = s; gsub(/[^0-9]/, "", t); return length(t) }

# IBAN check: move the first 4 chars to the end, turn letters into numbers
# (A=10..Z=35) and compute the number mod 97 digit by digit; valid IBANs give 1.
# This removes almost all false positives of a plain letters+digits pattern.
function iban_ok(s,   t, i, ch, v, r) {
    t = substr(s, 5) substr(s, 1, 4); r = 0
    for (i = 1; i <= length(t); i++) {
        ch = substr(t, i, 1)
        if (ch ~ /[0-9]/) r = (r * 10 + ch) % 97
        else {
            v = index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ch) + 9
            r = (r * 10 + int(v / 10)) % 97
            r = (r * 10 + v % 10) % 97
        }
    }
    return r == 1
}

# One output row per (kind, commit, place[, value]); values only with show=1.
# Row format (TSV): commit, date, "-", kind, place[  => value]
function emit(kind, where, val,   key) {
    key = kind SUBSEP where (show ? SUBSEP val : "")
    if (key in seen) return
    seen[key] = 1
    if (++cnt[kind] > 50000) { over[kind]++; return }
    printf "%s\t%s\t-\t%s\t%s%s\n", c, d, kind, where, (show ? "  => " val : "")
}

function scan(s, where,   rest, m, o, t, cc, cand, i, low, gotintl) {
    gotintl = 0
    if (index(s, "@") > 0) {
        rest = s
        while (match(rest, /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/)) {
            emit("email", where, substr(rest, RSTART, RLENGTH))
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    if (index(s, "+") > 0 || index(s, "00") > 0) {
        rest = s
        while (match(rest, /(\+|00)[1-9][0-9]*([ .\/()-]*[0-9]+)+/)) {
            m = substr(rest, RSTART, RLENGTH)
            if (okstart(rest, RSTART) && ndigits(m) >= 9 && ndigits(m) <= 15) { emit("phone-intl", where, m); gotintl = 1 }
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    if (!gotintl && s ~ /[2-9][0-9][0-9][ -][0-9][0-9][0-9][ -][0-9][0-9][0-9]/) {
        rest = s
        while (match(rest, /[2-9][0-9][0-9][ -][0-9][0-9][0-9][ -][0-9][0-9][0-9]/)) {
            if (okstart(rest, RSTART) && substr(rest, RSTART + RLENGTH, 1) !~ /[0-9]/) emit("phone-local", where, substr(rest, RSTART, RLENGTH))
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    if (s ~ /(CZ|SK|DE|AT|PL|GB|FR|ES|IT|NL|CH|BE|HU) ?[0-9][0-9]/) {
        t = s; gsub(/ /, "", t); rest = t
        while (match(rest, /(CZ|SK|DE|AT|PL|GB|FR|ES|IT|NL|CH|BE|HU)[0-9][0-9][A-Z0-9]+/)) {
            cc = substr(rest, RSTART, 2); cand = substr(rest, RSTART, ilen[cc])
            if (length(cand) == ilen[cc] && okstart(rest, RSTART) && iban_ok(cand)) emit("iban", where, cand)
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    if (index(s, ".") > 0) {
        rest = s
        while (match(rest, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            m = substr(rest, RSTART, RLENGTH); split(m, o, ".")
            if (okstart(rest, RSTART) && o[1] <= 255 && o[2] <= 255 && o[3] <= 255 && o[4] <= 255 && (o[1] == 10 || (o[1] == 192 && o[2] == 168) || (o[1] == 172 && o[2] >= 16 && o[2] <= 31))) emit("ip-private", where, m)
            rest = substr(rest, RSTART + RLENGTH)
        }
    }
    if (nt > 0) {
        low = tolower(s)
        for (i = 1; i <= nt; i++) if (index(low, term[i]) > 0) emit("term:" tname[i], where, term[i])
    }
}

BEGIN {
    ilen["CZ"] = 24; ilen["SK"] = 24; ilen["DE"] = 22; ilen["AT"] = 20; ilen["PL"] = 28
    ilen["GB"] = 22; ilen["FR"] = 27; ilen["ES"] = 24; ilen["IT"] = 27; ilen["NL"] = 18
    ilen["CH"] = 21; ilen["BE"] = 16; ilen["HU"] = 28
    if (tf != "") {
        while ((getline line < tf) > 0) {
            gsub(/\r/, "", line)
            if (line == "" || line ~ /^#/ || length(line) < 3) continue
            nt++; term[nt] = tolower(line); tname[nt] = line; gsub(/[ \t]/, "_", tname[nt])
        }
        close(tf)
    }
}
/^@@C /  { c = $2; d = $3; inmsg = 0; f = ""; split("", seen); next }
/^@@M$/  { inmsg = 1; next }
/^@@Z/   { inmsg = 0; next }
inmsg    { scan($0, "commit message"); next }
/^\+\+\+ / { if ($0 ~ /^\+\+\+ b\//) { f = substr($0, 7); scan(f, f " (file name)") } else f = ""; next }
/^@@ /   { split($0, h, "+"); split(h[2], h2, /[ ,]/); ln = h2[1] - 1; next }
/^\+/    { if (f != "") { ln++; scan(substr($0, 2), f ":" ln) }; next }
END { for (k in over) printf "NOTE: %d more '%s' findings not listed (cap 50000 per kind)\n", over[k], k > "/dev/stderr" }
AWK

echo "-- F2. Patterns and terms in file contents, file names, commit messages --"
[ -n "$terms" ] && echo "(term list: $terms)" || echo "(no terms file given: only built-in patterns; pass one as first argument)"
echo "(reading all patches, this can take a few minutes...)"

#   git log -p -U0     : every patch with zero context lines (only changed lines).
#   --no-color         : no escape codes in the stream.
#   --format='@@C %H %ad%n@@M%n%B@@Z' : marker line with full hash and date, then
#       the raw commit message between @@M and @@Z, so awk can tell message
#       lines from diff lines and knows which commit every line belongs to.
#   LC_ALL=C awk -v show=.. -v tf=.. : byte-wise processing (fast, no locale
#       errors); 'show' and 'tf' (terms file) are passed in as awk variables.
rowsE=$(git log $scan_opts -p -U0 --no-color --date=short --format='@@C %H %ad%n@@M%n%B@@Z' 2>/dev/null \
    | LC_ALL=C awk -v show="${SHOW_VALUES:-0}" -v tf="$terms" "$awk_prog")

if [ -z "$rowsE" ]; then
    echo "(no findings)"
else
    resE=$(printf '%s\n' "$rowsE" | tag_findings)
    totalE=$(printf '%s\n' "$resE" | wc -l)
    hidE=$(printf '%s\n' "$resE" | grep -c '^HIDDEN')
    srvE=$(printf '%s\n' "$resE" | grep -c '^SERVER')
    echo
    echo "Summary (count, tag, kind):"
    printf '%s\n' "$resE" | awk '{ n[$1 " " $5]++ } END { for (k in n) printf "%7d  %s\n", n[k], k }' | LC_ALL=C sort -k2,2 -k3,3
    echo
    echo "Samples (first 15 per tag+kind; newest first):"
    printf '%s\n' "$resE" | awk '{ k = $1 SUBSEP $5; n[k]++; if (n[k] <= 15) print }'
    echo
    echo "Findings: $totalE total = $hidE HIDDEN + $srvE SERVER + $((totalE - hidE - srvE)) visible."
    echo "Kinds: email, phone-intl (+420.., 00420..), phone-local (3-3-3 digit groups, NOISY in"
    echo "       firmware data tables), iban (checksum-verified), ip-private, term:<your term>."
    echo "Format: tag date hash  -  kind  file:line   (matched text hidden unless SHOW_VALUES=1)"
fi
echo

echo "Scan finished. Nothing in the repository was modified."