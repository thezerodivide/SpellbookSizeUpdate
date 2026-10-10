# SETTINGS FOR ONE SERVER.
#
# 1. Copy this file and rename the copy to  settings-<yourservername>.ps1
#    (for example settings-serverone.ps1 or settings-servertwo.ps1). Keep it in this same folder.
#    If you run more than one server, make one settings file per server; the scripts will ask which to use.
# 2. Fill in the lines below. Keep the single quotes. Lines starting with # are notes.
# 3. Do not share the finished file: it contains your database password.

# ---- Required -----------------------------------------------------------
$ServerName = 'My Server'                 # any label; used in backup folder names
$ServerDir  = 'C:\EQServer'               # the folder your server runs from (it has eqemu_config.json in it)
$BackupRoot = 'D:\Backups\spellbook'      # where backups are kept. A different drive is best.

$DbName = 'peq'                           # the database name from eqemu_config.json
$DbUser = 'eqemu'                         # the database user from eqemu_config.json
$DbPass = 'password'                      # the database password from eqemu_config.json
$DbHost = '127.0.0.1'                     # usually leave as is
$DbPort = '3306'                          # usually leave as is

# ---- Needed by 2-INSTALL --------------------------------------------------
$SourceDir = 'C:\EQServerSource'          # your server SOURCE folder (it has common\patches\rof2_limits.h in it)

# Build: easiest is to let the script build for you. Leave BuildCommand empty to build by hand instead.
$BuildCommand   = ''                      # example: 'cmake --build Build --config Release'
$BuildOutputDir = ''                      # folder the build puts the .exe/.dll files in, example: 'C:\EQServerSource\Build\bin\Release'

# ---- Optional -------------------------------------------------------------
# The eqgame.exe your players use TODAY (a copy of it is fine). If set, 2-INSTALL patches it with the
# 1440-slot spellbook patch and saves the result in the backup folder. Your 4GB patch (or lack of it) is kept as is.
# If it is not the stock RoF2 client plus at most the 4GB patch, the patch refuses and tells you.
$ClientSourceExe = ''                     # example: 'D:\ClientPatch\files\eqgame.exe'

# Commands to stop and start your server. Leave empty and the scripts will ask you to do it by hand.
# If a path has spaces, wrap the whole command in double quotes inside the single quotes.
$StopCommand  = ''                        # example: 'C:\EQServer\stop-server.bat'
$StartCommand = ''                        # example: 'C:\EQServer\start-server.bat'

# A folder where you put the client file for players (for example your installer's files folder).
# If set (and ClientSourceExe is set), 2-INSTALL copies the new eqgame.exe there (keeping the old one as
# eqgame.exe.before-1440) and 3-ROLLBACK puts the old one back.
$ClientStageDir = ''                      # example: 'D:\ClientPatch\files'
