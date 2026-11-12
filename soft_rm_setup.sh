#!/usr/bin/env bash
# =============================================================================
# soft_rm_setup.sh - soft-delete wrapper for `rm` with audit trail
# =============================================================================
#
# PURPOSE
#   Installs a standalone `srm` soft-delete command. Optionally, system `rm`
#   can later be diverted to use the same wrapper.
#
# EXPECTED BEHAVIOR
#   1. `srm dir/file.ext` does NOT delete. It renames the file in place to
#          dir/.file.ext.<UTC timestamp>.delete
#      e.g. dir/.file.ext.20261013T142501Z.delete
#      Directories are renamed the same way (contents untouched).
#   2. Every action is written to the audit log /var/log/rm-audit.log
#      (UTC time, user, sudo user, pid, tty, cwd, arguments, file, new name,
#       status, and the chain of up to 6 parent processes = who called rm).
#   3. Every soft delete is also appended to the index /var/log/rm-softdeleted.log
#      as:  <epoch> TAB <UTC timestamp> TAB <user> TAB <new full path>
#   4. A cron job runs weekly (Sunday 03:00) and permanently deletes
#      soft-deleted items whose index entry is older than 30 days.
#   5. `srm` on something already named .*.<ts>.delete deletes it for real
#      (this is how you purge by hand), and is logged as PURGED.
#   6. rm-style flags are accepted but ignored (-r -f -i -v ...), except:
#      -f silences "no such file" errors, -v prints "removed 'x'",
#      -d / no -r behave like GNU rm for directories (error unless -r/-d).
#
# USAGE
#   bash soft_rm_setup.sh install      install `srm`, logs, and weekly cron
#   bash soft_rm_setup.sh use-srm-for-rm    replace system `rm` with `srm`
#   bash soft_rm_setup.sh restore-system-rm  restore the original system `rm`
#   bash soft_rm_setup.sh uninstall    remove setup (logs/deleted files kept)
#   bash soft_rm_setup.sh status       show what is installed
#   bash soft_rm_setup.sh purge        run the 30-day purge right now
#
#   Restore a file:     mv .file.ext.<ts>.delete file.ext
#   Real delete now:    srm .file.ext.<ts>.delete (or /usr/bin/rm.real file)
#   Who deleted what:   sudo grep 'file=.*name' /var/log/rm-audit.log
#   Change retention:   edit RM_SOFTDELETE_DAYS in /etc/cron.d/rm-purge
#
# REQUIREMENTS
#   Debian/Ubuntu (dpkg-divert, apt). Works in WSL Ubuntu. Needs sudo.
#
# KNOWN LIMITS
#   - Only traces invocations of `srm` (and `rm` if interception is enabled).
#     Programs calling unlink()
#     directly (find -delete, apt/dpkg, git, Python os.remove) are not seen.
#   - Logs are world-appendable (so every user's rm can write), hence forgeable.
#   - In WSL, cron runs only while the WSL VM is up.
#   - Names near the 255-byte limit cannot be renamed (~27 chars are added).
#
# SAFETY
#   Nothing is overwritten without a backup. Backups go to
#   /usr/local/share/rm-wrapper-backups/<name>.<nanosecond timestamp>,
#   which is unique per call, so no backup ever replaces another.
# =============================================================================

set -euo pipefail   # stop on any error, undefined variable, or failed pipe

# ---- Paths used by the setup (all in one place) -----------------------------
RM_BIN=/usr/bin/rm                          # the path of the system rm
RM_REAL=/usr/bin/rm.real                    # where dpkg-divert moves the original
SRM_BIN=/usr/local/bin/srm                  # standalone soft-remove command
AUDIT_LOG=/var/log/rm-audit.log             # detailed trace of every rm call
INDEX_LOG=/var/log/rm-softdeleted.log       # list of soft-deleted files (for purge)
LOCK=/var/lib/rm-softdelete.lock            # serializes writes to the index
PURGE_BIN=/usr/local/sbin/rm-purge.sh       # script run weekly by cron
CRON_FILE=/etc/cron.d/rm-purge              # cron schedule
BACKUPS=/usr/local/share/rm-wrapper-backups # every replaced file is copied here

# ---- Become root (the setup writes to /usr/bin, /etc, /var) -----------------
# If not root, re-run this same script via sudo with the same arguments.
if [ "$(id -u)" -ne 0 ]; then exec sudo -- bash "$0" "$@"; fi

# ---- Helper: back up a file before it is replaced ---------------------------
# Copies $1 into $BACKUPS as <basename>.<nanoseconds>. Does nothing if $1 does
# not exist. -p keeps mode/owner/times. The nanosecond suffix guarantees a
# new unique name, so an existing backup is never overwritten.
backup() {
  [ -e "$1" ] || return 0
  install -d -m 755 "$BACKUPS"
  cp -p -- "$1" "$BACKUPS/$(basename "$1").$(date +%s%N)"
}

# ---- Helper: is /usr/bin/rm already diverted by dpkg? -----------------------
is_diverted() { dpkg-divert --list "$RM_BIN" | grep -q .; }

# ---- Add soft-deleted names to this user's global Git excludes ---------------
configure_git_excludes() {
  local git_user git_home excludes_file
  git_user=${SUDO_USER:-$(id -un)}
  git_home=$(getent passwd "$git_user" | cut -d: -f6)
  [ -n "$git_home" ] || { echo "Cannot determine home directory for $git_user." >&2; return 1; }
  excludes_file=$(sudo -u "$git_user" env HOME="$git_home" git config --global --path core.excludesFile 2>/dev/null || true)
  [ -n "$excludes_file" ] || excludes_file="$git_home/.gitignore_global"
  case "$excludes_file" in
    /*) ;;
    *) excludes_file="$git_home/$excludes_file" ;;
  esac
  case "$excludes_file" in
    '~'*) excludes_file="$git_home/${excludes_file#\~}" ;;
  esac
  sudo -u "$git_user" env HOME="$git_home" mkdir -p -- "${excludes_file%/*}"
  sudo -u "$git_user" env HOME="$git_home" touch -- "$excludes_file"
  sudo -u "$git_user" env HOME="$git_home" git config --global core.excludesFile "$excludes_file"
  sudo -u "$git_user" env HOME="$git_home" bash -c 'grep -qxF "*.delete" "$1" 2>/dev/null || printf "%s\n" "*.delete" >>"$1"' _ "$excludes_file"
  echo "Git global excludes file: $excludes_file"
}

# =============================================================================
# install_wrapper: writes the wrapper that becomes /usr/bin/rm
# The heredoc delimiter is quoted ('WRAPPER_EOF') so nothing inside is expanded
# now; it is written to the file literally.
# =============================================================================
write_wrapper() {
cat > "$1" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# srm soft-delete wrapper. When rm is diverted, use the diverted original;
# otherwise use the untouched system rm.

REAL=/usr/bin/rm
[ -x /usr/bin/rm.real ] && REAL=/usr/bin/rm.real
L=/var/log/rm-audit.log
I=/var/log/rm-softdeleted.log
LOCK=/var/lib/rm-softdelete.lock

# --help / --version: pass straight to the real rm (before any "--").
for a in "$@"; do
  [ "$a" = "--" ] && break
  case "$a" in --help|--version) exec "$REAL" "$@";; esac
done

# ---- Parse arguments: collect file names, remember the flags that matter ----
files=(); end=0; force=0; rec=0; dflag=0; verb=0
for a in "$@"; do
  if [ $end -eq 0 ]; then
    # "--" ends option parsing; everything after it is a file name.
    [ "$a" = "--" ] && { end=1; continue; }
    # Long options: remember the few that change behavior, ignore the rest.
    if [[ "$a" == --* ]]; then
      case "$a" in
        --force) force=1;; --recursive) rec=1;; --dir) dflag=1;; --verbose) verb=1;;
      esac
      continue
    fi
    # Short options (possibly combined, e.g. -rf): look for the letters we need.
    if [[ "$a" == -?* ]]; then
      [[ "$a" == *f* ]] && force=1
      [[ "$a" == *[rR]* ]] && rec=1
      [[ "$a" == *d* ]] && dflag=1
      [[ "$a" == *v* ]] && verb=1
      continue
    fi
  fi
  files+=("$a")          # anything else is a file/dir to soft-delete
done

# No file given: like GNU rm, silent success with -f, error otherwise.
[ ${#files[@]} -eq 0 ] && { [ $force -eq 1 ] && exit 0; echo "rm: missing operand" >&2; exit 1; }

# ---- Trace who called us: walk up to 6 parent processes via /proc -----------
# Each entry is [pid:command line]. This shows script -> shell -> tool -> ...
chain=""; p=$PPID
for i in 1 2 3 4 5 6; do
  [ "${p:-0}" -gt 1 ] 2>/dev/null || break
  cm=$(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | cut -c1-200)
  chain="$chain [$p:$cm]"
  # Next parent = 4th field of /proc/<pid>/stat (after the "(comm)" part).
  p=$(sed 's/.*) //' /proc/$p/stat 2>/dev/null | cut -d' ' -f2)
done

me=$(id -un); rc=0
# Pattern of an already soft-deleted name: .<name>.<UTC ts>[-n].delete
pat='^\..+\.[0-9]{8}T[0-9]{6}Z(-[0-9]+)?\.delete$'

# Write one line to the audit log. Failure to log never blocks the delete.
log(){
  printf '%s user=%s uid=%s sudo_user=%s pid=%s tty=%s cwd=%q args=%q file=%q dest=%q status=%s parents=%s\n' \
    "$(date -u +%FT%TZ)" "$me" "$(id -u)" "${SUDO_USER:--}" "$$" \
    "$(readlink /proc/$$/fd/0 2>/dev/null)" "$PWD" "$*" "$abs" "$dst" "$st" "$chain" \
    >>"$L" 2>/dev/null || true
}

# ---- Process each file -------------------------------------------------------
for f in "${files[@]}"; do
  abs="$f"; dst="-"; st=OK
  # Strip trailing slashes ("dir/" -> "dir"); all-slashes becomes "/".
  f=${f%"${f##*[!/]}"}; [ -z "$f" ] && f=/
  # Absolute path without resolving symlinks (-s): we rename the link itself.
  abs=$(realpath -s -- "$f" 2>/dev/null || echo "$f"); base=${abs##*/}

  # Refuse "." and ".." like GNU rm.
  case "${f##*/}" in
    .|..) st=REFUSED; log "$@"
          echo "rm: refusing to remove '.' or '..' directory: skipping '$f'" >&2
          rc=1; continue;;
  esac
  # Refuse "/".
  if [ "$abs" = "/" ]; then
    st=REFUSED; log "$@"; echo "rm: it is dangerous to operate recursively on '/'" >&2
    rc=1; continue
  fi
  # Does not exist: log it, error unless -f.
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then
    st=MISSING; log "$@"
    [ $force -eq 0 ] && { echo "rm: cannot remove '$f': No such file or directory" >&2; rc=1; }
    continue
  fi
  # Already soft-deleted name: this is the manual "really delete" path.
  if [[ "$base" =~ $pat ]]; then
    st=PURGED; log "$@"; "$REAL" -rf -- "$f" || rc=1; continue
  fi
  # Directory without -r: mimic GNU rm (error; with -d only if empty).
  if [ -d "$f" ] && [ ! -L "$f" ] && [ $rec -eq 0 ]; then
    if [ $dflag -eq 0 ]; then
      st=ISDIR; log "$@"; echo "rm: cannot remove '$f': Is a directory" >&2; rc=1; continue
    fi
    if [ -n "$(ls -A -- "$f" 2>/dev/null)" ]; then
      st=NOTEMPTY; log "$@"; echo "rm: cannot remove '$f': Directory not empty" >&2; rc=1; continue
    fi
  fi

  # ---- The soft delete: rename file -> .file.<UTC>.delete in the same dir ----
  dir=${abs%/*}; [ -z "$dir" ] && dir=/
  ts=$(date -u +%Y%m%dT%H%M%SZ); epoch=$(date +%s)
  new=".${base}.${ts}.delete"; n=0
  # Same file deleted twice within one second: add -1, -2, ... so nothing is
  # ever overwritten.
  while [ -e "$dir/$new" ] || [ -L "$dir/$new" ]; do
    n=$((n+1)); new=".${base}.${ts}-${n}.delete"
  done
  dst="$dir/$new"
  # mv -T: treat the destination as a name, never "move into a directory".
  if err=$(mv -T -- "$f" "$dst" 2>&1); then
    st=SOFTDELETED
    # Append to the index under a lock so concurrent rm calls don't interleave.
    ( flock 9; printf '%s\t%s\t%s\t%s\n' "$epoch" "$ts" "$me" "$dst" >>"$I" ) 9>>"$LOCK" 2>/dev/null \
      || printf '%s\t%s\t%s\t%s\n' "$epoch" "$ts" "$me" "$dst" >>"$I" 2>/dev/null || true
    [ $verb -eq 1 ] && echo "removed '$f'"
  else
    st=FAILED; rc=1; echo "rm: cannot remove '$f': ${err##*: }" >&2
  fi
  log "$@"
done
exit $rc
WRAPPER_EOF
}

# =============================================================================
# write_purge: writes the weekly cron script that permanently deletes
# soft-deleted items older than RM_SOFTDELETE_DAYS (default 30).
# =============================================================================
write_purge() {
cat > "$1" <<'PURGE_EOF'
#!/usr/bin/env bash
# Weekly purge of soft-deleted files older than RM_SOFTDELETE_DAYS (default 30).
REAL=/usr/bin/rm
[ -x /usr/bin/rm.real ] && REAL=/usr/bin/rm.real
I=/var/log/rm-softdeleted.log
L=/var/log/rm-audit.log
LOCK=/var/lib/rm-softdelete.lock
DAYS=${RM_SOFTDELETE_DAYS:-30}
pat='^\..+\.[0-9]{8}T[0-9]{6}Z(-[0-9]+)?\.delete$'

# Take the same lock as the wrapper so the index is not modified mid-purge.
exec 9>>"$LOCK"; flock 9
[ -s "$I" ] || exit 0                       # empty/missing index: nothing to do

cutoff=$(( $(date +%s) - DAYS*86400 ))      # anything older than this is purged
keep=$(mktemp)                              # new index = entries we keep
cp -p -- "$I" "$I.bak.$(date +%s%N)"        # back up the index before rewriting it

log(){ printf '%s user=root pid=%s status=%s file=%q parents=[cron rm-purge.sh]\n' \
         "$(date -u +%FT%TZ)" "$$" "$1" "$2" >>"$L"; }

while IFS= read -r line; do
  IFS=$'\t' read -r ep ts usr path <<<"$line"
  # Young entry (or malformed epoch): keep it.
  if ! [[ "$ep" =~ ^[0-9]+$ ]] || [ "$ep" -gt "$cutoff" ]; then
    printf '%s\n' "$line" >>"$keep"; continue
  fi
  # Safety: only ever delete an absolute path whose name matches .x.<ts>.delete,
  # so a tampered index cannot make the purge delete arbitrary files.
  if [[ "$path" != /* ]] || ! [[ "${path##*/}" =~ $pat ]]; then
    printf '%s\n' "$line" >>"$keep"; log SKIPPED_BADNAME "$path"; continue
  fi
  if [ -e "$path" ] || [ -L "$path" ]; then
    if "$REAL" -rf -- "$path"; then log PURGED_BY_CRON "$path"
    else printf '%s\n' "$line" >>"$keep"; log PURGE_FAILED "$path"; fi   # retry next week
  else
    log ALREADY_GONE "$path"                # restored or removed manually: drop entry
  fi
done <"$I"

cat "$keep" >"$I"                           # replace index with surviving entries
  "$REAL" -f "$keep"
PURGE_EOF
}

# =============================================================================
# Install the standalone srm command. This does not alter /usr/bin/rm.
# =============================================================================
do_install() {
  tmp_w=$(mktemp); tmp_p=$(mktemp)          # scratch files for the new scripts
  write_wrapper "$tmp_w"; write_purge "$tmp_p"
  configure_git_excludes

  # Create logs and lock only if missing. 622 = everyone can append (needed so
  # any user's rm can log), only root can read. Existing logs are never touched.
  [ -e "$AUDIT_LOG" ] || install -m 622 /dev/null "$AUDIT_LOG"
  [ -e "$INDEX_LOG" ] || install -m 622 /dev/null "$INDEX_LOG"
  [ -e "$LOCK" ]      || install -m 666 /dev/null "$LOCK"

  # Install srm separately; the system rm remains untouched until use-srm-for-rm.
  backup "$SRM_BIN"; backup "$PURGE_BIN"; backup "$CRON_FILE"
  install -m 755 "$tmp_w" "$SRM_BIN"
  if is_diverted; then
    backup "$RM_BIN"
    install -m 755 "$SRM_BIN" "$RM_BIN"
  fi
  install -m 755 "$tmp_p" "$PURGE_BIN"      # the weekly purge script

  # Cron schedule: Sundays 03:00 as root. RM_SOFTDELETE_DAYS sets retention.
  printf 'SHELL=/bin/bash\nPATH=/usr/sbin:/usr/bin:/sbin:/bin\nRM_SOFTDELETE_DAYS=30\n0 3 * * 0 root %s\n' \
    "$PURGE_BIN" > "$tmp_p"
  install -m 644 "$tmp_p" "$CRON_FILE"

  # Make sure cron exists and is running.
  command -v cron >/dev/null || apt-get install -y cron >/dev/null
  if [ "$(ps -p 1 -o comm=)" = systemd ]; then systemctl enable --now cron
  else service cron start; echo "NOTE: no systemd, so cron will not auto-start with WSL"; fi

  real_rm=$RM_BIN; is_diverted && real_rm=$RM_REAL
  "$real_rm" -f "$tmp_w" "$tmp_p"

  # Self-test only through srm; no system rm interception is required.
  t=$(mktemp -d); touch "$t/selftest"
  "$SRM_BIN" "$t/selftest"
  echo "--- self-test: expect .selftest.<ts>.delete below ---"; ls -a "$t"
  tail -n1 "$AUDIT_LOG"
  "$real_rm" -rf -- "$t"
  echo "Installed $SRM_BIN. System rm is unchanged; test with: srm <path>"
}

# =============================================================================
# Enable/disable system rm interception.
# =============================================================================
do_use_srm_for_rm() {
  [ -x "$SRM_BIN" ] || { echo "Run 'install' first to create $SRM_BIN." >&2; return 1; }
  if is_diverted; then
    [ -x "$RM_REAL" ] || { echo "Original rm missing at $RM_REAL." >&2; return 1; }
  else
    [ -x "$RM_BIN" ] || { echo "System rm missing at $RM_BIN." >&2; return 1; }
    dpkg-divert --local --rename --divert "$RM_REAL" --add "$RM_BIN"
  fi
  backup "$RM_BIN"
  install -m 755 "$SRM_BIN" "$RM_BIN"
  echo "System rm now uses srm. Restore with: bash $0 restore-system-rm"
}

do_restore_system_rm() {
  is_diverted || { echo "System rm is not intercepted."; return 0; }
  [ -x "$RM_REAL" ] || { echo "Original rm missing at $RM_REAL; refusing to proceed." >&2; return 1; }
  "$RM_REAL" -f -- "$RM_BIN"
  dpkg-divert --local --rename --divert "$RM_REAL" --remove "$RM_BIN"
  echo "System rm restored. The standalone srm command remains installed."
}

restore_latest() {
  target=$1; name=${target##*/}; matches=("$BACKUPS/$name".*)
  [ -e "${matches[0]}" ] || return 0
  install -d -m 755 "${target%/*}"
  cp -p -- "${matches[-1]}" "$target"
}

do_status() {
  if [ -x "$SRM_BIN" ]; then echo "srm: installed at $SRM_BIN"; else echo "srm: not installed"; fi
  if is_diverted; then echo "rm: routed through srm (original at $RM_REAL)"; else echo "rm: using system rm directly"; fi
  [ -e "$PURGE_BIN" ] && echo "purge: installed at $PURGE_BIN" || echo "purge: not installed"
  [ -e "$CRON_FILE" ] && echo "cron: installed at $CRON_FILE" || echo "cron: not installed"
}

do_purge() {
  [ -x "$PURGE_BIN" ] || { echo "Purge script is not installed; run 'install' first." >&2; return 1; }
  "$PURGE_BIN"
}

do_uninstall() {
  do_restore_system_rm
  /usr/bin/rm -f -- "$SRM_BIN" "$PURGE_BIN" "$CRON_FILE"
  restore_latest "$SRM_BIN"
  restore_latest "$PURGE_BIN"
  restore_latest "$CRON_FILE"
  echo "srm setup removed. Audit logs and soft-deleted files are kept."
}

usage() {
  printf 'Usage: %s {install|use-srm-for-rm|restore-system-rm|status|purge|uninstall}\n' "$0"
}

case "${1:-}" in
  install)     do_install ;;
  use-srm-for-rm)   do_use_srm_for_rm ;;
  restore-system-rm) do_restore_system_rm ;;
  status)      do_status ;;
  purge)       do_purge ;;
  uninstall)   do_uninstall ;;
  *)           usage; exit 2 ;;
esac
