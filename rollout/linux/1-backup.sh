#!/usr/bin/env bash
# 1-backup: saves everything needed to roll back the spellbook change.
# It only READS from your server and database. It changes nothing except creating the backup folder.
set -uo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

show_header "BACKUP"
select_settings
load_settings
say "Server: $SERVER_NAME"
say "Settings: $(basename "$SETTINGS_FILE")"

step "Checking the database connection"
sql "SELECT 1" >/dev/null || fail "Could not talk to the database. Check the settings file."
rows="$(sql "SELECT COUNT(*) FROM character_spells")" || fail "Could not read character_spells."
max_slot="$(sql "SELECT IFNULL(MAX(slot_id), -1) FROM character_spells")" || fail "Could not read character_spells."
size_mb="$(sql "SELECT ROUND(SUM(data_length + index_length) / 1048576) FROM information_schema.tables WHERE table_schema = '$DB_NAME'")"
say "Database $DB_NAME: about $size_mb MB, $rows saved spells, highest spellbook slot used: $max_slot"

stamp="$(date +%Y%m%d-%H%M%S)"
safe_name="$(printf '%s' "$SERVER_NAME" | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')"
dir="$BACKUP_ROOT/spellbook-$safe_name-$stamp"
step "Creating backup folder: $dir"
mkdir -p "$dir" || fail "Could not create $dir"

step "Backing up the database (this can take a few minutes)"
save_dump "$dir/db.sql" - --routines --triggers
ok "Done: $(( $(wc -c < "$dir/db.sql") / 1048576 )) MB"

step "Backing up the server programs"
n="$(copy_programs "$SERVER_DIR" "$dir/server-programs")"
ok "$n program files copied."
[ "$n" -gt 0 ] || warn "None of the programs in PROGRAMS were found in SERVER_DIR. Is SERVER_DIR the folder the server runs from?"

step "Backing up the server configuration"
mkdir -p "$dir/server-config"
for f in eqemu_config.json login.json; do
    if [ -f "$SERVER_DIR/$f" ]; then cp -p "$SERVER_DIR/$f" "$dir/server-config/"; say "Copied $f"; fi
done

hdr_value=""
if hdr="$(header_path)"; then
    step "Backing up the server source file that gets changed"
    [ -f "$hdr" ] || fail "Could not find $hdr. Check SOURCE_DIR in your settings file."
    mkdir -p "$dir/source"; cp -p "$hdr" "$dir/source/"
    hdr_value="$(get_spellbook_size "$hdr")"
    say "rof2_limits.h copied. SPELLBOOK_SIZE is currently $hdr_value"
else
    say "SOURCE_DIR is not set, so the server source file is not backed up."
fi

stage_md5=""
if [ -n "$CLIENT_STAGE_DIR" ] && [ -f "$CLIENT_STAGE_DIR/eqgame.exe" ]; then
    step "Backing up the current client file from CLIENT_STAGE_DIR"
    mkdir -p "$dir/client-stage"; cp -p "$CLIENT_STAGE_DIR/eqgame.exe" "$dir/client-stage/"
    stage_md5="$(get_md5 "$CLIENT_STAGE_DIR/eqgame.exe")"
    say "Copied eqgame.exe (md5 $stage_md5)"
fi

if [ -n "$CLIENT_SOURCE_EXE" ] && [ -f "$CLIENT_SOURCE_EXE" ]; then
    step "Backing up your current client file (CLIENT_SOURCE_EXE)"
    mkdir -p "$dir/client-source"; cp -p "$CLIENT_SOURCE_EXE" "$dir/client-source/"
    say "Copied eqgame.exe (md5 $(get_md5 "$CLIENT_SOURCE_EXE"))"
fi

step "Writing the backup summary"
{
    echo "server=$SERVER_NAME"
    echo "created=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "database=$DB_NAME"
    echo "spell_rows=$rows"
    echo "max_slot=$max_slot"
    echo "source_spellbook_size=$hdr_value"
    echo "client_stage_md5=$stage_md5"
} > "$dir/backup-info.txt"
basename "$dir" > "$BACKUP_ROOT/LATEST.txt"

printf '\n%s============================================================\n  BACKUP COMPLETE\n============================================================%s\n' "$GREEN" "$RST"
say "Saved to: $dir"
say ""
say "Tip: take the backup when the server is quiet. Anything players do after this"
say "moment is NOT in the backup, and a full restore would undo it."
