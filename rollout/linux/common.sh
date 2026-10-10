#!/usr/bin/env bash
# Shared helpers for the spellbook 1440 rollout scripts (Linux / bash).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHER_DIR="$(cd "$SCRIPT_DIR/../../tools/patcher" 2>/dev/null && pwd || true)"

if [ -t 1 ]; then
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RST=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; RST=''
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s%s%s\n' "$GREEN" "$*" "$RST"; }
step() { printf '\n%s=== %s%s\n' "$CYAN" "$*" "$RST"; }
warn() { printf '%sWARNING: %s%s\n' "$YELLOW" "$*" "$RST"; }
fail() { printf '\n%sSTOPPED: %s%s\n\n' "$RED" "$*" "$RST"; exit 1; }
pause_for() { printf '%s' "$1"; read -r _ || true; }

confirm_typed() {
    local prompt="$1" word="$2" ans=""
    printf '\n%s Type %s to continue, or anything else to stop: ' "$prompt" "$word"
    read -r ans || ans=""
    [ "$ans" = "$word" ] || fail "Cancelled. Nothing was changed by this step."
}

show_header() {
    printf '%s============================================================\n' "$CYAN"
    printf '  Spellbook 720 -> 1440 : %s\n' "$1"
    printf '============================================================%s\n' "$RST"
}

# ---------------------------------------------------------------- settings

# Defaults for everything optional (a settings file may override them).
SOURCE_DIR=""; BUILD_COMMAND=""; BUILD_OUTPUT_DIR=""; MYSQL_BIN_DIR=""
STOP_COMMAND=""; START_COMMAND=""; CLIENT_STAGE_DIR=""; CLIENT_SOURCE_EXE=""
DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_PASS=""
PROGRAMS=(world zone ucs queryserv loginserver eqlaunch shared_memory export_client_files import_client_files hc)

select_settings() {
    local files=() f
    for f in "$SCRIPT_DIR"/settings-*.conf; do
        [ -e "$f" ] || continue
        case "$(basename "$f")" in settings-EXAMPLE*) continue;; esac
        files+=("$f")
    done
    [ "${#files[@]}" -gt 0 ] || fail "No settings file found. Copy settings-EXAMPLE.conf to settings-yourservername.conf (in the same folder), fill it in, and run this again."
    if [ "${#files[@]}" -eq 1 ]; then SETTINGS_FILE="${files[0]}"; return; fi
    say "More than one server is set up here. Which one is this for?"
    local i=1
    for f in "${files[@]}"; do say "  $i) $(basename "$f")"; i=$((i+1)); done
    local n=""
    printf 'Type the number: '; read -r n || n=""
    case "$n" in ''|*[!0-9]*) fail "That is not one of the choices.";; esac
    [ "$n" -ge 1 ] && [ "$n" -le "${#files[@]}" ] || fail "That is not one of the choices."
    SETTINGS_FILE="${files[$((n-1))]}"
}

load_settings() {
    # shellcheck disable=SC1090
    . "$SETTINGS_FILE"
    local v
    for v in SERVER_NAME SERVER_DIR BACKUP_ROOT DB_NAME DB_USER; do
        [ -n "${!v:-}" ] || fail "Your settings file is missing '$v'. Open it and fill it in."
    done
    [ -n "$DB_PASS" ] && export MYSQL_PWD="$DB_PASS"
    [ -d "$SERVER_DIR" ] || fail "SERVER_DIR does not exist: $SERVER_DIR"
    if [ ! -f "$SERVER_DIR/eqemu_config.json" ]; then
        warn "There is no eqemu_config.json in $SERVER_DIR. Is SERVER_DIR the folder the server runs from?"
        confirm_typed "Continue anyway?" "YES"
    fi
}

# ---------------------------------------------------------------- database

find_tool() {
    local name
    for name in "$@"; do
        if [ -n "$MYSQL_BIN_DIR" ]; then
            [ -x "$MYSQL_BIN_DIR/$name" ] && { printf '%s' "$MYSQL_BIN_DIR/$name"; return 0; }
        elif command -v "$name" >/dev/null 2>&1; then
            command -v "$name"; return 0
        fi
    done
    fail "Could not find '$1'. Set MYSQL_BIN_DIR in your settings file to the folder that contains mysql and mysqldump."
}

conn_args() { printf '%s\n' "--host=$DB_HOST" "--port=$DB_PORT" "--user=$DB_USER"; }

sql() {
    local exe; exe="$(find_tool mysql mariadb)"
    local out rc
    out="$("$exe" "--host=$DB_HOST" "--port=$DB_PORT" "--user=$DB_USER" --batch --skip-column-names "--execute=$1" "$DB_NAME" 2>&1)"; rc=$?
    [ $rc -eq 0 ] || { printf '%s\n' "The database said: $out" >&2; return 1; }
    printf '%s' "$out"
}

# save_dump <outfile> <tables or -> [extra mysqldump args...]
save_dump() {
    local out="$1" tables="$2"; shift 2
    local exe; exe="$(find_tool mysqldump mariadb-dump)"
    local t=()
    [ "$tables" = "-" ] || t=("$tables")
    "$exe" "--host=$DB_HOST" "--port=$DB_PORT" "--user=$DB_USER" --single-transaction --quick "$@" "$DB_NAME" "${t[@]}" > "$out" \
        || fail "The database dump failed. Check the database name, user and password in your settings file."
    [ -s "$out" ] && [ "$(wc -c < "$out")" -ge 200 ] || fail "The database dump file is empty."
    tail -n 5 "$out" | grep -q "Dump completed" || fail 'The database dump looks incomplete (no "Dump completed" line at the end).'
}

restore_dump() {
    local exe; exe="$(find_tool mysql mariadb)"
    "$exe" "--host=$DB_HOST" "--port=$DB_PORT" "--user=$DB_USER" "$DB_NAME" < "$1" \
        || fail "Restoring the database failed. Your backup files are untouched."
}

# ---------------------------------------------------------------- files

header_path() { [ -n "$SOURCE_DIR" ] && printf '%s' "$SOURCE_DIR/common/patches/rof2_limits.h"; }

SIZE_RE='SPELLBOOK_SIZE[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*;'

# prints the number, or nothing if there is not exactly one SPELLBOOK_SIZE line
get_spellbook_size() {
    [ "$(grep -cE "$SIZE_RE" "$1")" = "1" ] || return 0
    sed -nE 's/.*SPELLBOOK_SIZE[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*;.*/\1/p' "$1"
}

set_spellbook_size() { # file old new
    sed -i -E "s/(SPELLBOOK_SIZE[[:space:]]*=[[:space:]]*)$2([[:space:]]*;)/\1__NEWSIZE__\2/" "$1"
    sed -i "s/__NEWSIZE__/$3/" "$1"
}

copy_programs() { # from to  -> prints count
    local from="$1" to="$2" p n=0
    mkdir -p "$to"
    for p in "${PROGRAMS[@]}"; do
        if [ -f "$from/$p" ]; then cp -p "$from/$p" "$to/$p"; n=$((n+1)); fi
    done
    printf '%s' "$n"
}

# patch_client <source exe> <output exe>: applies the spellbook patch to the owner's own client (4GB flag kept as is)
patch_client() {
    command -v node >/dev/null 2>&1 || return 2
    [ -f "$PATCHER_DIR/spellbook-patch.js" ] || fail "The patcher files are missing from tools/patcher. Keep this folder inside the full package."
    mkdir -p "$(dirname "$2")"
    node "$PATCHER_DIR/../build-spellbook-patch.js" "$1" "$PATCHER_DIR/patch-table.json" "$2"
}

get_md5() { md5sum "$1" | cut -d' ' -f1; }

# ---------------------------------------------------------------- server control

stop_server() {
    step "Stopping the server"
    if [ -n "$STOP_COMMAND" ]; then
        say "Running: $STOP_COMMAND"
        bash -c "$STOP_COMMAND" || warn "The stop command reported a problem."
        sleep 3
        pause_for "Check that the server is really stopped, then press Enter: "
    else
        say "Stop the server now: world, zone, login server, and anything else that uses the database."
        pause_for "Press Enter when it is fully stopped: "
    fi
}

start_server() {
    step "Starting the server"
    if [ -n "$START_COMMAND" ]; then
        say "Running: $START_COMMAND"
        ( cd "$SERVER_DIR" && nohup bash -c "$START_COMMAND" >/dev/null 2>&1 & )
    else
        say "Start the server now, the way you normally do."
        pause_for "Press Enter when it is running: "
    fi
}

# ---------------------------------------------------------------- backups

info_get() { grep "^$2=" "$1/backup-info.txt" 2>/dev/null | head -n 1 | cut -d= -f2-; }

check_backup_folder() { # prints a problem, or nothing when fine
    local d="$1"
    [ -f "$d/db.sql" ] || { printf 'db.sql is missing'; return; }
    [ "$(wc -c < "$d/db.sql")" -ge 200 ] || { printf 'db.sql is empty'; return; }
    tail -n 5 "$d/db.sql" | grep -q "Dump completed" || { printf 'db.sql looks incomplete'; return; }
    [ -f "$d/backup-info.txt" ] || { printf 'backup-info.txt is missing'; return; }
}

select_backup() { # sets BACKUP_DIR
    [ -d "$BACKUP_ROOT" ] || fail "No backup folder yet: $BACKUP_ROOT. Run 1-backup.sh first."
    local dirs=() d
    while IFS= read -r d; do dirs+=("$d"); done < <(ls -1d "$BACKUP_ROOT"/spellbook-*/ 2>/dev/null | sed 's#/$##' | sort -r | head -n 9)
    [ "${#dirs[@]}" -gt 0 ] || fail "No backups found in $BACKUP_ROOT. Run 1-backup.sh first."
    local latest=""; [ -f "$BACKUP_ROOT/LATEST.txt" ] && latest="$(head -n 1 "$BACKUP_ROOT/LATEST.txt" | tr -d '\r')"
    say "Backups found (newest first):"
    local i=1 mark
    for d in "${dirs[@]}"; do
        mark=""; [ "$(basename "$d")" = "$latest" ] && mark="   <- most recent"
        say "  $i) $(basename "$d")$mark"; i=$((i+1))
    done
    local n=""
    printf 'Type the number of the backup to use (just press Enter for 1): '; read -r n || n=""
    [ -n "$n" ] || n=1
    case "$n" in *[!0-9]*) fail "That is not one of the choices.";; esac
    [ "$n" -ge 1 ] && [ "$n" -le "${#dirs[@]}" ] || fail "That is not one of the choices."
    BACKUP_DIR="${dirs[$((n-1))]}"
}
