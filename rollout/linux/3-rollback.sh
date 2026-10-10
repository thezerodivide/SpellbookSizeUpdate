#!/usr/bin/env bash
# 3-rollback: puts the server back to the 720-slot spellbook, using a backup made by 1-backup.sh.
#
# Two ways to roll back the database:
#   LIGHT: keeps everything players did since the backup. Removes only the spells saved in
#          slots 720 and up (they are saved to a file first, so nothing is truly lost).
#   FULL : replaces the whole database with the backup. ALL player progress since the backup is lost.
#
# Either way the spells in slots 720+ must go: an old 720-slot server reads a spell saved in
# slot 720 one entry past the end of its spellbook array (an existing off-by-one in the server).
set -uo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

show_header "ROLLBACK"
select_settings
load_settings
say "Server: $SERVER_NAME"

step "Choosing the backup"
select_backup
bad="$(check_backup_folder "$BACKUP_DIR")"
[ -z "$bad" ] || fail "That backup is not usable: $bad."
ok "Using backup: $(basename "$BACKUP_DIR")"
say "  taken: $(info_get "$BACKUP_DIR" created)   spells saved then: $(info_get "$BACKUP_DIR" spell_rows)"

sql "SELECT 1" >/dev/null || fail "Could not talk to the database. Check the settings file."
high="$(sql "SELECT COUNT(*) FROM character_spells WHERE slot_id >= 720")"
say "Right now there are $high saved spells in slots 720 and up."

printf '\nHow should the DATABASE be rolled back?\n\n'
printf '%s  1) LIGHT  (recommended)%s\n' "$GREEN" "$RST"
say "     Keeps everything players have done since the backup (levels, items, quests...)."
say "     Removes only the spells in slots 720 and up. They are saved to a file first."
say ""
printf '%s  2) FULL RESTORE%s\n' "$YELLOW" "$RST"
say "     Puts the whole database back exactly as it was at the backup."
say "     EVERYTHING players did since the backup is lost, for every character."
say ""
say "  3) Cancel"
printf 'Type 1, 2 or 3: '; read -r choice || choice=""
case "$choice" in
    1) mode="LIGHT"; confirm_typed "Roll back with the LIGHT method?" "ROLLBACK";;
    2) mode="FULL"
       warn "A full restore undoes ALL player progress since the backup was taken."
       say "The backup was taken: $(info_get "$BACKUP_DIR" created)"
       confirm_typed "Are you sure you want the FULL restore?" "RESTORE ALL";;
    *) fail "Cancelled. Nothing was changed.";;
esac

stamp="$(date +%Y%m%d-%H%M%S)"
stop_server

if [ "$mode" = "LIGHT" ]; then
    step "Saving the spells in slots 720 and up (so they can be put back later)"
    keep="$BACKUP_DIR/removed-high-slot-spells-$stamp.sql"
    save_dump "$keep" character_spells --no-create-info "--where=slot_id between 720 and 99999999"
    ok "Saved to $keep"
    step "Removing the spells in slots 720 and up"
    sql "DELETE FROM character_spells WHERE slot_id >= 720" >/dev/null || fail "The delete failed. Do not start the old server. Ask for help."
    left="$(sql "SELECT COUNT(*) FROM character_spells WHERE slot_id >= 720")"
    [ "$left" = "0" ] || fail "Some spells in slots 720+ are still there ($left). Do not start the old server. Ask for help."
    ok "Done: no spells remain in slots 720 and up."
else
    step "Saving a copy of the CURRENT database first, just in case"
    before="$BACKUP_DIR/before-rollback-$stamp.sql"
    save_dump "$before" - --routines --triggers
    ok "Saved to $before"
    step "Restoring the database from the backup (this can take a few minutes)"
    restore_dump "$BACKUP_DIR/db.sql"
    ok "Database restored."
fi

step "Putting the old server programs back"
if [ -d "$BACKUP_DIR/server-programs" ]; then
    n="$(copy_programs "$BACKUP_DIR/server-programs" "$SERVER_DIR")"
    ok "$n program files restored into $SERVER_DIR"
else
    warn "The backup has no server-programs folder. Restore your old programs yourself."
fi

if hdr="$(header_path)" && [ -f "$BACKUP_DIR/source/rof2_limits.h" ]; then
    step "Putting the old server source file back"
    cp -p "$BACKUP_DIR/source/rof2_limits.h" "$hdr"
    ok "rof2_limits.h restored. SPELLBOOK_SIZE is $(get_spellbook_size "$hdr")"
fi

if [ -n "$CLIENT_STAGE_DIR" ] && [ -f "$BACKUP_DIR/client-stage/eqgame.exe" ]; then
    step "Putting the old client file back in CLIENT_STAGE_DIR"
    cp -p "$BACKUP_DIR/client-stage/eqgame.exe" "$CLIENT_STAGE_DIR/eqgame.exe"
    ok "Done."
fi

start_server

printf '\n%s============================================================\n  ROLLBACK COMPLETE\n============================================================%s\n\n' "$GREEN" "$RST"
printf '%s PLAYERS STILL NEED THE OLD eqgame.exe BACK.\n' "$YELLOW"
printf ' A client with the new eqgame.exe cannot log in to a 720-slot server.\n'
printf ' Release the old client file to your players.%s\n\n' "$RST"
[ "$mode" = "LIGHT" ] && say "The spells that were in slots 720+ are saved in: $keep"
say "Test with a character on the old client before you tell players the server is back."
