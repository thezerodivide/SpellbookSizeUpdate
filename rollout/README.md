# Spellbook 1440: one-click backup, install and rollback

See also the [Server Owner Rollout Guide](../GUIDE.md) for the whole picture.

Three scripts that do the work of the manual guide, for **Windows** (`rollout\windows`) and **Linux** (`rollout/linux`).
Use whichever set matches the machine the server runs on. Each does one job:

| Script | What it does | Changes anything? |
|---|---|---|
| `1-BACKUP` | Saves the database, the server programs, the config files, the one source file that changes, and the current client file, into a dated folder. | No. It only reads, and creates the backup folder. |
| `2-INSTALL` | Switches the server to 1440 slots: checks the backup, stages the new client file, stops the server, changes one line in the source, rebuilds, copies the new programs in, starts the server. | Yes. Asks you to type words to confirm before the risky parts. |
| `3-ROLLBACK` | Puts the old server programs and source file back and fixes the database. Offers a light or full database rollback. | Yes. Asks you to type words to confirm. |

Windows: double-click `1-BACKUP.bat`, `2-INSTALL.bat`, `3-ROLLBACK.bat`.
Linux: run `./1-backup.sh`, `./2-install.sh`, `./3-rollback.sh` (if they will not run, use `bash 1-backup.sh` and so on).

## Set up once per server

1. In the `windows` (or `linux`) folder, copy `settings-EXAMPLE.ps1` (or `.conf`) to `settings-yourservername.ps1` (or `.conf`).
2. Open it and fill in the lines. Every line has a note. The only ones you must fill in to take a backup are the server folder, the backup folder and the four database settings.
3. Running more than one server (for example two communities)? Make one settings file per server. When there is more than one, each script asks which to use.

The settings file holds your database password. It is excluded from git; do not share it.

## The order to use them

1. **Run `1-BACKUP`** when the server is quiet. Check it finishes with BACKUP COMPLETE.
2. **Run `2-INSTALL`.** It will stop and ask you to confirm that all players have the new client before it touches the server.
3. **Test** with a character on the new client (the script tells you what to check).
4. If something is wrong, **run `3-ROLLBACK`**.

## Things the scripts cannot do

- **They cannot update your players' clients.** `2-INSTALL` can copy the patched `eqgame.exe` into a folder you name (`ClientStageDir`), but you must release the update to players yourself. The server cannot tell old clients from new ones, and an old client cannot log in to a 1440 server. The same applies in reverse after a rollback: players need the old file back.
- **They patch your client; they do not ship one.** No EverQuest files are included. Point `ClientSourceExe` in your settings at the `eqgame.exe` your players use today, and `2-INSTALL` patches a copy of it with the same patcher as `tools/patcher` and saves the result in the backup folder (and in `ClientStageDir` if you set that). **Your 4GB patch is kept exactly as it is**: if your client has it, the new one has it; if not, it does not get added.
- **They refuse a client they do not recognise.** The patch is made for the stock RoF2 `eqgame.exe` (MD5 `240c80800112ada825c146d7349ce85b`), with or without the 4GB flag. If your client has other changes in the same places, `2-INSTALL` stops before it touches the server. A client with other changes elsewhere is not checked.
- **They do not install map files.** See the main README if zones crash when NPCs flee.

## The two rollback choices

- **Light (recommended).** Keeps everything players have done since the backup. Removes only the spells saved in slots 720 and up, and saves them to a file first (`removed-high-slot-spells-....sql` in the backup folder). This is needed because the old server reads a spell saved in slot 720 one entry past the end of its spellbook array.
- **Full restore.** Puts the whole database back as it was at the backup. **Everything every player did since then is lost.** The script saves a copy of the current database first (`before-rollback-....sql`).

## How this was tested

- The client-patching step needs Node.js on **Linux**; without it the script says so and carries on without a client file.
- The **Linux** scripts were run on Linux against stand-in `mysql` and `mysqldump` programs and fake server folders: backup, install, light rollback, full rollback, wrong confirmation words, a damaged database column, a failed dump, and two servers' settings files.
- The **Windows** scripts' logic (`.ps1`) was run under PowerShell 7 on Linux against the same stand-ins. The same cases passed, and testing found and fixed three bugs.
- **Not tested:** anything on a real Windows machine (the `.bat` launchers, `cmd.exe`), anything against a real database, and any real server build. The scripts are written for Windows PowerShell 5.1, which is built into Windows 10 and 11.

**Do a dry run first.** Point the settings at a test copy of the server and database, run all three scripts once, and only then use them on the real server.
