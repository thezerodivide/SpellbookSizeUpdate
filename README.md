# Spellbook 720 → 1440 slots (RoF2 / NMS server)

Stock RoF2 has a 720-slot spellbook (90 pages of 8). This change raises it to **1440 slots (180 pages)**.
It needs a change on **both** sides, and the two must match exactly.

> **Status: built, statically verified, and smoke-tested in a live client on a sandbox server (section 6).**
> Still test on a separate server/database before rolling out to live players (section 4).

> **Server owner? Start with the [Server Owner Rollout Guide (GUIDE.md)](GUIDE.md).** It covers what to change, the
> cutover steps, the rollback, and what was tested, in the order you would do it.

> **This repository contains no EverQuest client files.** To get a 1440-slot client you patch your own `eqgame.exe`
> with the patcher in `tools/patcher/` (section 1). For server owners there are one-click backup, install and
> rollback scripts in `rollout/`.

## 1. What to change

### Server (EQEmu-based NMS server) — one line

Replace `Release-NMS-Server/common/patches/rof2_limits.h` with `server/common/patches/rof2_limits.h`
(or apply `server/server-changes.diff`). The only functional change:

```cpp
const int SPELLBOOK_SIZE = 1440;   // was 720
```

`EQ::spells::SPELLBOOK_SIZE` is an alias of this value, so the zone/world code that scribes, unscribes,
swaps, loads and saves the book, the `PlayerProfile_Struct` array and the RoF2 profile encoder
(`rof2.cpp` writes the count, then the entries) all follow automatically. Nothing else is hard-coded to 720 in
the server source. The comment edit in `rof2_structs.h` is cosmetic.

Rebuild world + zone. No database change is needed: `character_spells.slot_id` is `uint16` in the
repository code (confirm the column in your schema is `smallint unsigned` or wider; stock EQEmu is).
Existing characters keep slots 0–719 exactly as they are; slots 720+ start empty.

### Client — patch your own `eqgame.exe`

This repository does **not** contain any EverQuest client files. You patch your own copy of `eqgame.exe` with
the patcher in `tools/patcher/`, which writes a new `eqgame_1440.exe` next to it and never changes the original:

| You have | Use | Windows (double-click or drag the exe onto it) | Any OS with Node.js |
|---|---|---|---|
| The normal (stock) RoF2 `eqgame.exe` | Option 1: adds the 4GB patch **and** the spellbook patch | `Patch-1-STOCK-exe-add-4GB-and-1440.bat` | `node patch-eqgame.js --stock eqgame.exe` |
| An `eqgame.exe` that already has the 4GB patch | Option 2: adds only the spellbook patch | `Patch-2-4GB-exe-add-1440-only.bat` | `node patch-eqgame.js --4gb eqgame.exe` |

Before changing anything the patcher checks every spot it will modify (115 byte patches and 2 hooks). If the exe is not the
RoF2 client this patch was made for, already has the patch, or has other changes in the same places, it stops and says so.
Option 2 refuses an exe that does not have the 4GB patch. See `tools/patcher/README.md`.

* The patch is built for the stock RoF2 `eqgame.exe` (md5 `240c80800112ada825c146d7349ce85b`). Stock plus the 4GB flag also works.
  An exe with *other* patches in the same places will be refused; one with patches elsewhere is not checked and is untested.
* It cannot be delivered through `patches.txt` (the patch needs a new PE section, and that format only does
  in-place byte edits).
* A real-world 4GB-patched client (md5 `389709ec0e456c3dae881a61218aab3f`) was checked: the patcher turns it into the tested
  1440-slot 4GB client (md5 `f10534e3ae4ebe64f6dc9d56459c8ecd`) exactly.

### Client add-on source (`dinput8.dll`) — optional, only if you use these MQ2 features

The add-on reads the spellbook by struct offset. After the exe patch that old area is no longer used.
The only users in the NMS source are the MQ2 `/memspell` command and the `${Me.Book[...]}` TLO.
`client-dll/dll-changes.diff` (+ the three edited files) switch them to the new location
(`CHAR_SPELLBOOK(pc, n)` = `*(DWORD*)((BYTE*)pc + 0x9950 + n*4)`). Not compiled here (needs your VS2022 setup).
Skip it and those two things simply read stale data; the game itself is unaffected.

## 2. How the client patch works

The client keeps the book as a fixed array of 720 dwords inside the character object, with other fields right
after it, so it cannot simply be made longer. The patch moves it.

| Change | Count | Where |
|---|---|---|
| Spellbook base `+0x2520` → `+0x9950` (new array past the end of the object) | 46 sites | scribe/memorize/unscribe/swap/refresh in the spellbook window and the character code |
| Slot bound `720`/`719` → `1440`/`1439` | 64 sites | same functions, ini save/load, object ctor/copy, serialize/deserialize |
| Allocation of the character object `0x9950`/`0x3488` → `0xAFD0` | 3 sites | the only places the object is created |
| Spellbook window page limit 90 → 180 (`/book N` and page buttons) | 1 block | `0x75d570` |
| Profile read from the server raises its cap to 1440 entries | new code | reads into a staging array, then the copy to the character picks slots ≥720 from it |
| New PE section `.sbook` (0x2000 bytes) holding that code + array, 6 relocation fixups | — | needed because the image is rebased at load (Windows already moves this exe) |

Every changed byte is listed in `evidence/patch-list.txt`. A before/after disassembly diff of the whole executable
(not included in this repository) showed 127 changed instructions, all intended, and nothing else in the 5.9 MB of code changed.

Deliberately **not** changed: the snapshot structure used for stat calculation copies only the first 720 slots
(it never looks at spells above that). `0x2d0` constants that are UI ids / window sizes are untouched.

## 3. Verification done

* Original and patched exe disassembled in full and diffed: no remaining reference to the old array
  (`+0x2520`) except an unrelated UI id; every remaining `720` is one of the intentionally untouched UI ids or snapshot loops.
* Patched exe loaded through the Windows loader (32-bit, no code run): image accepted, rebased, and the new
  absolute fixup resolved correctly (`tools/loadtest.ps1`).
* PE checksum and the 4GB-flag procedure reproduce the byte-for-byte installed `eqgame.exe` from the stock one.
* The PowerShell and Node patchers produce byte-identical output for every mode (stock or 4GB input), and refuse a damaged, already-patched or non-exe file.
* **Not done:** running the game. There is no way to do that without a server and client data.

## 4. Test plan (do this before anything live)

1. Separate machine/folder for a **test** world+zone build with the one-line change, its own database
   (e.g. `nms_test` from `release-peq.zip`), own ports. Never point it at the live DB.
2. Copy of the game folder with your patched client (made with `tools/patcher`) as `eqgame.exe`; `eqhost.txt` → test server.
3. Create a fresh character, `#scribespells`-style fill (or scribe tomes) past 720 and to 1440:
   page forward to the last page (`/book 179`), open/close the book, memorize a spell from slot ≥720,
   swap/delete a spell, zone, camp and log back in, relog twice. Slots must persist across relogs.
4. Same character in an **unpatched** client against the test server is expected to break (see below), don't be alarmed.
5. Existing character with a full 720 book: nothing changes, nothing lost.
6. Watch for client crashes (look for a crash in `eqgame.exe` right at zone-in or when opening the spellbook).

## 5. Things to know

* **Both sides must match.** A client without the patch connecting to a 1440 server gets a profile it cannot parse
  (the unpatched client stops reading after 720 and loses its place) — it will fail to enter the world or
  misbehave. Everyone has to be on the new `eqgame.exe` before the server flips. The server cannot tell the
  clients apart.
* **Rollback:** restore the server build and `eqgame.exe` and your DB backup. Spells scribed into slots ≥720 are
  not visible to the old server/client, so back up the database before the cutover.
* Memory: each character object is ~11 KB larger (0x9950 → 0xAFD0).
* The ini cache of the book (`<char>_spellbook=` in the character ini) grows to up to 1440 entries; it is built in a 32 KB buffer, fine.
* MQ2-style plugins that read the book by offset need the same change as the add-on source above.

## 6. Live test results (sandbox server, patched `eqgame.exe` with 4GB flag)

Server built from the community NMS source with only the one-line change; fresh DB from `release-peq.zip`.

| Test | Result |
|---|---|
| Login, character select, create character, zone in | OK |
| `#scribespells 255` on a 3-class character | "You have learned 1440 new spells!"; next scribe refused ("Spell Book is full") |
| `character_spells` after scribing | 1440 rows, `slot_id` 0..1439 |
| `/book 179` (last page) | Opens, spells shown, no crash; pages differ when paging back |
| Memorize a spell from page 160 (slot 1272+) | OK, correct spell in gem |
| Cast it | OK, correct spell effect |
| Camp and relog (twice) | Spell still on page 160 in the same slot, still memorized and castable, no crash |
| Zoning (`#zone`, twice, with the book open once) | Book intact, spell castable, no client issue |
| Swap two spells in a high slot (page 159: left-click one, right-click the other) | Swapped on screen; DB updated immediately; persisted across camp/relog |
| Delete a spell in a high slot (select, Delete key, confirm) | Slot removed from `character_spells`, empty slot shown |
| `#scribespell <id>` after the delete | Spell re-added in the first free slot (1271) |

| Pre-change character (720 spells, slots 0-719 only; slots 720+ removed from `character_spells`) | Logs in normally; page 90 full, page 91 empty, page 1 unchanged; a new scribe lands in slot 720; slots 0-719 untouched |

Notes on the swap/delete UI in this client: the book's own help text says *left-click a spell to select it, right-click another slot to swap, Delete key to remove*.
A memorized spell cannot be moved. `/book N` opens with page N on the **right** (page N-1 on the left); page 160 starts at slot 1272.

**Zone-server crash seen during testing (not related to the spellbook):** a test server without map files crashed the zone intermittently,
~1 minute after boot. With a symbolized build the trace was `NPC::Attack -> Mob::CheckFlee -> Mob::CalculateNewFearpoint -> Map::FindCeiling`:
`fearpath.cpp` calls `zone->zonemap->FindCeiling(...)` with no check that a map is loaded, so a fleeing NPC dereferences a null map.
Fix: install the standard maps (`https://github.com/EQEmu/maps`: copy `base`, `water`, `nav` into `Maps\base`, `Maps\water`, `Maps\nav`). After that the zone log shows the map, water map and navmesh loading and the crash no longer applies.

**Still untested:** several characters at once, and a patched client against a server that has been through a real cutover (back up the DB first).

**Cosmetic bug found:** the page-number labels in `EQUI_SpellBookWnd.xml` are 20px wide, so page 100+ shows only
two digits (179 appeared as "17"). Paging itself was correct. `client/ui/fix-spellbook-page-labels.ps1` widens the
labels (run it once per skin you use). The skin file is not part of this repo; the script edits it in place and keeps a `.orig` backup.

### Server build notes (Windows) learned during the test

* Use **Visual Studio 2022** (a machine with only VS 2026 fails: the script asks for the "Visual Studio 17 2022" generator).
* Use **Strawberry Perl 5.32.1.1**. Perl 5.42 compiled but `zone.exe` failed to link (`Perl_switch_locale_context` unresolved).
* After the build, copy `Build\libs\zlibng\Release\zlib-ng1.dll` next to the programs (`zone.exe` needs it; it is not copied automatically).
* Quests ship their Lua modules in `quests\lua_modules`; set `"lua_modules": "quests/lua_modules/"` under `directories` in `eqemu_config.json`, or `zone.exe` stops with "Incompatible quest plugins detected".
* The `export` folder must exist before `export_client_files.exe` is run.
* The login server's `login.json` `security.mode` must be **14** (scrypt). The CLI password tool and the shipped accounts use scrypt; a different mode makes every login fail.
* Order: `world.exe database:updates --skip-backup`, then `shared_memory.exe`, then loginserver, world, `eqlaunch.exe zone`.

## 7. Licensing

This repository mirrors the licensing of the NMS release it was built against:

| Folder | License | Why |
|---|---|---|
| `server/` | GNU GPL v3 (`server/LICENSE`) | Modified files from the EQEmu-derived server. |
| `client-dll/` | MIT, original notice kept (`client-dll/LICENSE`) | Edited copies of files from the NMS client add-on. |
| everything else (`tools/`, `rollout/`, `client/`, `evidence/`, this README) | MIT (`LICENSE`) | Original work for this change. |

EverQuest is a registered trademark of Daybreak Game Company. This project is not affiliated with or endorsed by
Daybreak, and contains no EverQuest client files: you patch your own copy with the patcher in `tools/patcher/`.
