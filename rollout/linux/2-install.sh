#!/usr/bin/env bash
# 2-install: switches the server to a 1440-slot spellbook.
# It will NOT start unless a good backup exists, and it stops to ask before anything risky.
set -uo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

show_header "INSTALL"
select_settings
load_settings
say "Server: $SERVER_NAME"


step "Checking the backup"
select_backup
bad="$(check_backup_folder "$BACKUP_DIR")"
[ -z "$bad" ] || fail "That backup is not usable: $bad. Run 1-backup.sh again."
created="$(info_get "$BACKUP_DIR" created)"
ok "Using backup: $(basename "$BACKUP_DIR")"
say "  taken: $created   spells saved: $(info_get "$BACKUP_DIR" spell_rows)"
if created_ts="$(date -d "$created" +%s 2>/dev/null)"; then
    hours=$(( ( $(date +%s) - created_ts ) / 3600 ))
    if [ "$hours" -gt 24 ]; then
        warn "This backup is $hours hours old. A full restore would undo everything players did since then."
        confirm_typed "Use this older backup anyway?" "YES"
    fi
fi

step "Checking the database"
sql "SELECT 1" >/dev/null || fail "Could not talk to the database. Check the settings file."
col_type="$(sql "SELECT DATA_TYPE FROM information_schema.columns WHERE table_schema = '$DB_NAME' AND table_name = 'character_spells' AND column_name = 'slot_id'")"
[ -n "$col_type" ] || fail "Could not find the character_spells.slot_id column. Is DB_NAME the right database?"
[ "$col_type" != "tinyint" ] || fail "character_spells.slot_id is a tinyint, which cannot hold slot numbers above 255. It needs to be smallint or bigger before this change."
ok "character_spells.slot_id is $col_type: large enough for 1440 slots."

step "Checking the files for this change"
patched_client=""
if [ -n "$CLIENT_SOURCE_EXE" ]; then
    [ -f "$CLIENT_SOURCE_EXE" ] || fail "CLIENT_SOURCE_EXE does not exist: $CLIENT_SOURCE_EXE"
    patched_client="$BACKUP_DIR/client-1440/eqgame.exe"
    say "Patching your client file: $CLIENT_SOURCE_EXE"
    patch_client "$CLIENT_SOURCE_EXE" "$patched_client"; rc=$?
    if [ "$rc" -eq 2 ]; then
        warn "Node.js is not installed, so the client file cannot be patched here. Patch your own eqgame.exe with tools/patcher (needs Node.js, or use the Windows patcher on a Windows PC) before releasing the client update."
        patched_client=""
    elif [ "$rc" -ne 0 ]; then
        fail "Could not patch $CLIENT_SOURCE_EXE (see the message above). Your file was not changed."
    else
        ok "New client saved to: $patched_client"
    fi
else
    warn "CLIENT_SOURCE_EXE is not set, so no new client file is prepared here. Patch your own eqgame.exe with tools/patcher before releasing the client update."
fi

hdr="$(header_path)" || fail "SOURCE_DIR is not set in your settings file. The install needs your server source folder."
[ -f "$hdr" ] || fail "Could not find $hdr. Check SOURCE_DIR in your settings file."
current="$(get_spellbook_size "$hdr")"
[ -n "$current" ] || fail "Could not find exactly one SPELLBOOK_SIZE line in rof2_limits.h. This file is different from what the script expects, so it will not guess. Use the manual guide."
say "rof2_limits.h: SPELLBOOK_SIZE is currently $current"
{ [ "$current" = "720" ] || [ "$current" = "1440" ]; } || fail "SPELLBOOK_SIZE is $current, not 720 or 1440. This script only handles 720 -> 1440."

say ""
say "This will:"
say "  1. (if set up) put the new client file where players get it"
say "  2. stop the server"
say "  3. change SPELLBOOK_SIZE from 720 to 1440 in the server source"
say "  4. rebuild the server and copy the new programs into place"
say "  5. start the server again"
confirm_typed "Ready to begin?" "INSTALL"

if [ -n "$CLIENT_STAGE_DIR" ] && [ -n "$patched_client" ]; then
    step "Putting the new client file in CLIENT_STAGE_DIR"
    mkdir -p "$CLIENT_STAGE_DIR"
    if [ -f "$CLIENT_STAGE_DIR/eqgame.exe" ] && [ ! -f "$CLIENT_STAGE_DIR/eqgame.exe.before-1440" ]; then
        cp -p "$CLIENT_STAGE_DIR/eqgame.exe" "$CLIENT_STAGE_DIR/eqgame.exe.before-1440"
    fi
    cp "$patched_client" "$CLIENT_STAGE_DIR/eqgame.exe"
    ok "Copied to $CLIENT_STAGE_DIR/eqgame.exe"
    say "The old file was kept as eqgame.exe.before-1440 in the same folder."
fi
printf '\n%s------------------------------------------------------------\n' "$YELLOW"
printf ' IMPORTANT: PLAYERS MUST HAVE THE NEW eqgame.exe FIRST.\n'
printf ' The server cannot tell old clients from new ones. An old client\n'
printf ' cannot log in to a 1440 server. Release the client update now\n'
printf ' and wait until players have it.\n'
printf '------------------------------------------------------------%s\n' "$RST"
confirm_typed "Have ALL players been given the new client?" "YES"

stop_server

step "Changing the server source"
if [ "$current" = "720" ]; then
    set_spellbook_size "$hdr" 720 1440
    [ "$(get_spellbook_size "$hdr")" = "1440" ] || fail "The source file did not change as expected. Run 3-rollback.sh to restore the original."
    ok "SPELLBOOK_SIZE is now 1440."
else
    say "SPELLBOOK_SIZE was already 1440. Leaving it as it is."
fi

step "Building the server"
if [ -n "$BUILD_COMMAND" ]; then
    say "Running (in $SOURCE_DIR): $BUILD_COMMAND"
    ( cd "$SOURCE_DIR" && bash -c "$BUILD_COMMAND" ) || fail "The build failed. The server is still stopped and your old programs are untouched. Run 3-rollback.sh to put the source file back, or fix the build and run this again."
    [ -n "$BUILD_OUTPUT_DIR" ] || fail "BUILD_OUTPUT_DIR is not set in your settings file, so the new programs cannot be copied."
    [ -d "$BUILD_OUTPUT_DIR" ] || fail "BUILD_OUTPUT_DIR does not exist: $BUILD_OUTPUT_DIR"
    n="$(copy_programs "$BUILD_OUTPUT_DIR" "$SERVER_DIR")"
    [ "$n" -gt 0 ] || fail "The build produced none of the programs in PROGRAMS in BUILD_OUTPUT_DIR. Nothing was copied."
    ok "$n program files copied into $SERVER_DIR"
else
    say "Build the server now with your usual method, using the changed source."
    say "Then copy the new programs into: $SERVER_DIR"
    pause_for "Press Enter when the new programs are in place: "
fi

start_server

printf '\n%s============================================================\n  INSTALL COMPLETE - NOW CHECK IT WORKS\n============================================================%s\n' "$GREEN" "$RST"
say "With a test character on the NEW client:"
say "  1. Log in and enter the world."
say "  2. Open the spellbook and type /book 179 (the last pages)."
say "  3. Scribe a spell and check it saves after you camp and log back in."
say ""
say "If anything is wrong, run 3-rollback.sh."
