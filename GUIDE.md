# Spellbook 1440: Server Owner Rollout Guide

## Summary

This change raises the spellbook from 720 to 1440 slots (90 to 180 pages). It needs a one-line server change and a patched client `eqgame.exe` for every player, and the two must be rolled out together. Everything is in this repository, including one-click scripts for the backup, the install and the rollback.

- **Existing characters keep every spell.** Slots 0 to 719 are untouched; new slots start empty.
- **No database change.** `character_spells.slot_id` is already `smallint unsigned`, which holds up to 65535.
- **An unpatched client cannot log in to a 1440 server.** The server cannot tell old and new clients apart, so every player must be on the patched `eqgame.exe` before the server is switched.
- **You patch your own client.** The repository contains no EverQuest files. A patcher turns your `eqgame.exe` into the 1440-slot version and never changes your original.
- **Tested in a live client** on a sandbox server (see [What was tested](#what-was-tested)). Not yet run on a live server.

## What you need

Four parts, all in this repository.

| Piece | Where | Notes |
| --- | --- | --- |
| Server change | [`server/common/patches/rof2_limits.h`](server/common/patches/rof2_limits.h) (or apply [`server/server-changes.diff`](server/server-changes.diff)) | One line: `SPELLBOOK_SIZE = 1440` (was 720). Replaces `common/patches/rof2_limits.h` in the server source. |
| Client patcher | [`tools/patcher/`](tools/patcher/) | Patches your own `eqgame.exe`. Two options, below. |
| Page label fix | [`client/ui/fix-spellbook-page-labels.ps1`](client/ui/fix-spellbook-page-labels.ps1) | Run once per UI skin on `EQUI_SpellBookWnd.xml`. Without it, pages 100 and up show two digits (page 179 reads "17"). Cosmetic only. |
| One-click scripts | [`rollout/`](rollout/) | Backup, install and rollback, for Windows and Linux. Optional: the manual checklist below does the same. |

### Making the 1440-slot client

The patcher writes a new `eqgame_1440.exe` next to the file you give it. Your original is never changed. Pick the option that matches your client:

| Your `eqgame.exe` | Use | Windows (drag the exe onto it) | Any OS with Node.js |
| --- | --- | --- | --- |
| The normal (stock) RoF2 client | **Option 1**: adds the 4GB patch **and** the spellbook patch | `Patch-1-STOCK-exe-add-4GB-and-1440.bat` | `node patch-eqgame.js --stock eqgame.exe` |
| A client that already has the 4GB patch | **Option 2**: adds **only** the spellbook patch; the 4GB flag stays as it is | `Patch-2-4GB-exe-add-1440-only.bat` | `node patch-eqgame.js --4gb eqgame.exe` |

- **It checks before it changes anything.** It verifies all 115 byte patches and 2 code hooks, and refuses if the file is not the RoF2 client the patch was made for, already has the spellbook patch, or has other changes in the same places. Option 2 also refuses an exe without the 4GB patch.
- **It is built for the stock RoF2 `eqgame.exe`**, MD5 `240c80800112ada825c146d7349ce85b`, with or without the 4GB flag. A client with other patches elsewhere is not checked and is untested, so test it before you release it.
- **It cannot go through `patches.txt`**: the patch adds a new section to the executable, and that format only does in-place byte edits.

More detail: [`tools/patcher/README.md`](tools/patcher/README.md).

The repository is licensed GPLv3 for `server/` and MIT everywhere else, matching the NMS release (see [Licensing in the README](README.md#7-licensing)).

## Cutover

There are two ways to do it: the one-click scripts, or the manual checklist. Both start with a backup, and the backup is the only way back if something goes wrong.

### With the one-click scripts

The scripts are in [`rollout/windows`](rollout/windows) (double-click the `.bat` files) and [`rollout/linux`](rollout/linux) (run the `.sh` files). Full instructions: [`rollout/README.md`](rollout/README.md).

1. **Set up once.** Copy `settings-EXAMPLE` to `settings-yourservername` in the same folder and fill it in: the server folder, the source folder, the database login and a backup folder. Optional: your build command, and the path to the `eqgame.exe` your players use today. Running two servers? Make one settings file each; the scripts ask which to use.
2. **Run `1-BACKUP`** when the server is quiet. It saves the database, the server programs, the config files, the one source file that changes and your current client, and ends with BACKUP COMPLETE. It only reads from your server.
3. **Run `2-INSTALL`.** It refuses to start without a good backup, patches a copy of your client (keeping your 4GB patch exactly as it is), and then asks you to confirm that all players have the new client. Only then does it stop the server, change the source line, rebuild, copy the new programs in and start the server. You type a word to confirm each risky step.
4. **Test** with a character on the new client, as in step 7 of the manual list.

The scripts cannot release the client update to your players: that is yours to do. Do a dry run first, pointing the settings at a test copy of your server and database. They were tested against stand-in database programs and not on a real server (see [What was tested](#what-was-tested)).

### Manual checklist

- [ ] **1. Back up the live database.** Spells scribed into slots 720 and up are invisible to the old server and client, so a backup is the rollback.
- [ ] **2. Prepare a test first, if you have not.** Build the server with the change and run it against a copy of the database with its own ports. Never point a test build at the live database.
- [ ] **3. Make the 1440-slot client** with the patcher, and add the page label fix to every UI skin players use.
- [ ] **4. Release the client update** to your players, through your installer or patcher.
- [ ] **5. Confirm players have updated.** The server cannot tell the clients apart, and an unpatched client fails to enter the world once the server flips.
- [ ] **6. Replace `rof2_limits.h`, rebuild `world` and `zone`, and restart.** Nothing else in the server source is hard-coded to 720.
- [ ] **7. Verify with a test character:** log in, scribe a spell above slot 719, `/book 179`, memorize a high-slot spell, camp and log back in.

Existing characters need nothing done to them. Each character object in the client is about 11 KB larger (`0x9950` to `0xAFD0`). The `<char>_spellbook=` line in a character's ini file can now hold up to 1440 entries, which fits its 32 KB buffer.

## Rollback

Run `3-ROLLBACK` from the same scripts folder. It puts the old server programs and source file back, restores your old client file if you staged one, and fixes the database in one of two ways that you choose.

| Database rollback | What it does | What you lose |
| --- | --- | --- |
| **Light** (recommended) | Keeps everything players did since the backup: levels, items, quests. Removes only the spells saved in slots 720 and up. | Only the spells in slots 720 and up. They are saved to a file first, so they can be put back. |
| **Full restore** | Puts the whole database back exactly as it was at the backup. | **Everything every player did since the backup.** The script saves a copy of the current database first. |

Both ways need a typed confirmation word, and the full restore needs a second, stronger one.

- **The spells in slots 720 and up must go either way.** The old 720-slot server reads a spell saved in slot 720 one entry past the end of its spellbook array, which is an existing off-by-one in the server. That is why the light rollback is not optional housekeeping.
- **Players need the old `eqgame.exe` back.** A patched client cannot log in to a 720-slot server, and the reverse is true after the server flips. Rolling back only the server, or only the client, leaves players unable to enter the world.
- **By hand,** restore three things together: the old server build, the old `eqgame.exe`, and the database backup from step 1 of the checklist.

## What was tested

Every spellbook check passed on a sandbox server (fresh database from `release-peq.zip`, built with only the one-line change) with the patched client, with no spellbook crashes. Full details are in the [README](README.md), section 6.

| Check | Result |
| --- | --- |
| Log in, create a character, zone in | Passed |
| Scribe every spell on a 3-class character | 1440 learned; the next scribe was refused because the book was full; database held slots 0 to 1439 |
| Page to the last page (`/book 179`) and back | Passed; pages show different spells |
| Memorize and cast a spell from page 160 (slot 1272 and up) | Passed; correct spell in the gem |
| Camp and log back in, twice | Passed; spell stayed in the same slot |
| Zone between zones, once with the book open | Passed |
| Swap two spells in a high slot | Passed; saved immediately and survived a relog |
| Delete a spell in a high slot | Passed; slot removed from the database |
| Scribe again after the delete | Passed; spell went into the first free slot |
| Character with an old 720-spell book | Passed; slots 0 to 719 unchanged, page 91 empty, next scribe went to slot 720 |

To swap spells in the book, the client's own help text says to left-click one spell and right-click another slot; Delete removes the selected spell.

### The patcher and the scripts

- **Patcher:** the Windows (PowerShell) and Node versions produce byte-identical files in both options, and match the 1440-slot clients tested above. A real-world 4GB-patched client (MD5 `389709ec0e456c3dae881a61218aab3f`) became the tested 4GB 1440-slot client (MD5 `f10534e3ae4ebe64f6dc9d56459c8ecd`) exactly. Refusals were tested: a damaged patch site, a file that is not a program, an already-patched exe, an existing output file, a missing file, and Option 2 on an exe without the 4GB patch.
- **Scripts:** run against stand-in database programs and fake server folders: backup, install, light and full rollback, wrong confirmation words, a damaged database column, a failed dump, a damaged client file (it stops before the server is touched), and two servers' settings files. Testing found and fixed several bugs in the Windows scripts.

**Not tested:** several characters at once, the cutover itself on a live database, and anything on a real Windows machine (the Windows scripts and patcher were run under PowerShell 7 on Linux; they are written for Windows PowerShell 5.1). Do a dry run on a test copy first.
