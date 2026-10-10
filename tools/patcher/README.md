# eqgame.exe patcher: 1440-slot spellbook

Patches **your own** RoF2 `eqgame.exe` so its spellbook has 1440 slots (180 pages) instead of 720. No client files are
included here: you supply the exe, and the patcher writes a **new** file, `eqgame_1440.exe`, next to it. Your original is never changed.

The server needs the matching one-line change (`SPELLBOOK_SIZE = 1440`), and players need the new client before the server
is switched. See the main README and `rollout/`.

## Which one do I use?

| What your `eqgame.exe` is | Use | Windows | Any OS with Node.js |
|---|---|---|---|
| The normal (stock) RoF2 client | **Option 1**: adds the 4GB patch **and** the spellbook patch | `Patch-1-STOCK-exe-add-4GB-and-1440.bat` | `node patch-eqgame.js --stock eqgame.exe` |
| A client that already has the 4GB patch | **Option 2**: adds **only** the spellbook patch; the 4GB flag stays as it is | `Patch-2-4GB-exe-add-1440-only.bat` | `node patch-eqgame.js --4gb eqgame.exe` |

Not sure whether yours has the 4GB patch? Option 1 is safe either way (it keeps the 4GB flag if it is already there).
Option 2 refuses an exe without the 4GB patch, so it can never add it by accident.

### On Windows

Drag your `eqgame.exe` onto the `.bat` file, or double-click it and type the path when asked. Nothing needs installing:
it uses Windows PowerShell, which is part of Windows 10 and 11.

### On Linux or Mac

Install [Node.js](https://nodejs.org/), then run the command in the table from this folder.

## What it checks before changing anything

It checks all 115 byte patches and 2 code hooks against the exact bytes it expects, and it refuses if:

- the file is not a Windows program, or is not the RoF2 `eqgame.exe` this patch was made for,
- any spot holds something other than what is expected (for example another patch in the same place),
- the exe already has the spellbook patch,
- (Option 2) the exe does not have the 4GB patch,
- `eqgame_1440.exe` already exists in that folder (it never overwrites).

When it refuses, it tells you why and writes nothing.

## What it does

- Raises the 720-slot limits to 1440 in the places the client uses them (about 64 sites).
- Moves the spellbook array to a larger area past the end of the character object.
- Raises the spellbook window's page limit from 90 to 180.
- Adds a small new section to the exe holding two code caves that read the server's profile up to 1440 entries.
- Recomputes the file's PE checksum (and sets the 4GB flag in Option 1).

Every change is listed in `patch-table.json`. The full story of how it works is in the main README and `evidence/`.

## Tested

- Both modes produce **byte-identical** output in the PowerShell and Node versions, and the same result as the original builder.
- A real-world 4GB-patched client (MD5 `389709ec0e456c3dae881a61218aab3f`) was checked: either option turns it into the tested
  4GB 1440-slot client (MD5 `f10534e3ae4ebe64f6dc9d56459c8ecd`). A stock client gives MD5 `03b11a34694500b2c38d8aea746d1ae0`
  with the 4GB flag not set (Option 1 sets it).
- Refusals tested: a damaged patch site, a file that is not a program, an already-patched exe, an existing output file, a missing file,
  and Option 2 on an exe without the 4GB patch.
- The patched client was run in a live game against a test server (see the main README, section 6).

The PowerShell version was tested under PowerShell 7 on Linux. It is written for Windows PowerShell 5.1 but has not been run on a real Windows machine.
