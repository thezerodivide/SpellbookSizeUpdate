# 2-INSTALL: switches the server to a 1440-slot spellbook.
# It will NOT start unless a good backup exists, and it stops to ask before anything risky.
. "$PSScriptRoot\common.ps1"

Show-Header 'INSTALL'
$settingsFile = Select-SettingsFile
. $settingsFile
Initialize-Settings
Say ('Server: ' + $Script:ServerName)

Step 'Checking the backup'
$backupDir = Select-BackupFolder
$bad = Test-BackupFolder $backupDir
if ($bad) { Fail ('That backup is not usable: ' + $bad + '. Run 1-BACKUP again.') }
$info = Read-Info $backupDir
Say ('Using backup: ' + (Split-Path -Leaf $backupDir)) 'Green'
Say ('  taken: ' + $info['created'] + '   spells saved: ' + $info['spell_rows'])
$created = [datetime]::MinValue
if ([datetime]::TryParseExact($info['created'], 'yyyy-MM-dd HH:mm:ss', $null, 'None', [ref]$created)) {
    $hours = ((Get-Date) - $created).TotalHours
    if ($hours -gt 24) {
        Warn ('This backup is ' + [Math]::Round($hours, 0) + ' hours old. A full restore would undo everything players did since then.')
        Confirm-Typed 'Use this older backup anyway?' 'YES'
    }
}

Step 'Checking the database'
try { $null = Invoke-Sql 'SELECT 1' } catch { Fail ('Could not talk to the database. ' + $_.Exception.Message) }
$colType = Invoke-Sql ("SELECT DATA_TYPE FROM information_schema.columns WHERE table_schema = '" + $Script:DbName + "' AND table_name = 'character_spells' AND column_name = 'slot_id'")
if (-not $colType) { Fail 'Could not find the character_spells.slot_id column. Is DbName the right database?' }
if ($colType -eq 'tinyint') { Fail ('character_spells.slot_id is a tinyint, which cannot hold slot numbers above 255. It needs to be smallint or bigger before this change.') }
Say ('character_spells.slot_id is ' + $colType + ': large enough for 1440 slots.') 'Green'

Step 'Checking the files for this change'
$patchedClient = ''
if ($Script:ClientSourceExe) {
    if (-not (Test-Path -LiteralPath $Script:ClientSourceExe -PathType Leaf)) { Fail ('ClientSourceExe does not exist: ' + $Script:ClientSourceExe) }
    $patchedClient = Join-Path (Join-Path $backupDir 'client-1440') 'eqgame.exe'
    Say ('Patching your client file: ' + $Script:ClientSourceExe)
    $r = New-PatchedClient $Script:ClientSourceExe $patchedClient
    Say ('Original MD5: ' + $r.InMd5)
    Say ('Patched MD5:  ' + $r.OutMd5) 'Green'
    if ($r.HadLaa) { Say 'Your client has the 4GB patch, and the new one keeps it.' } else { Say 'Your client does not have the 4GB patch, and the new one does not add it.' }
    Say ('New client saved to: ' + $patchedClient) 'Green'
} else {
    Warn 'ClientSourceExe is not set, so no new client file is prepared here. Patch your own eqgame.exe with the patcher in tools\patcher before releasing the client update.'
}

$hdr = Get-HeaderPath
if (-not $hdr) { Fail 'SourceDir is not set in your settings file. The install needs your server source folder.' }
if (-not (Test-Path -LiteralPath $hdr)) { Fail ('Could not find ' + $hdr + '. Check SourceDir in your settings file.') }
$current = Get-SpellbookSize $hdr
if (-not $current) { Fail 'Could not find exactly one SPELLBOOK_SIZE line in rof2_limits.h. This file is different from what the script expects, so it will not guess. Use the manual guide.' }
Say ('rof2_limits.h: SPELLBOOK_SIZE is currently ' + $current)
if ($current -ne 720 -and $current -ne 1440) { Fail ('SPELLBOOK_SIZE is ' + $current + ', not 720 or 1440. This script only handles 720 -> 1440.') }

Say ''
Say 'This will:' 'White'
Say '  1. (if set up) put the new client file where players get it'
Say '  2. stop the server'
Say '  3. change SPELLBOOK_SIZE from 720 to 1440 in the server source'
Say '  4. rebuild the server and copy the new programs into place'
Say '  5. start the server again'
Confirm-Typed 'Ready to begin?' 'INSTALL'

# ---- client file
if ($Script:ClientStageDir -and $patchedClient) {
    Step 'Putting the new client file in ClientStageDir'
    New-Item -ItemType Directory -Force -Path $Script:ClientStageDir | Out-Null
    $dest = Join-Path $Script:ClientStageDir 'eqgame.exe'
    $keep = Join-Path $Script:ClientStageDir 'eqgame.exe.before-1440'
    if ((Test-Path -LiteralPath $dest) -and -not (Test-Path -LiteralPath $keep)) { Copy-Item -LiteralPath $dest -Destination $keep -Force }
    Copy-Item -LiteralPath $patchedClient -Destination $dest -Force
    Say ('Copied to ' + $dest) 'Green'
    Say 'The old file was kept as eqgame.exe.before-1440 in the same folder.'
}
Write-Host ''
Write-Host '------------------------------------------------------------' -ForegroundColor Yellow
Write-Host ' IMPORTANT: PLAYERS MUST HAVE THE NEW eqgame.exe FIRST.' -ForegroundColor Yellow
Write-Host ' The server cannot tell old clients from new ones. An old client' -ForegroundColor Yellow
Write-Host ' cannot log in to a 1440 server. Release the client update now' -ForegroundColor Yellow
Write-Host ' and wait until players have it.' -ForegroundColor Yellow
Write-Host '------------------------------------------------------------' -ForegroundColor Yellow
Confirm-Typed 'Have ALL players been given the new client?' 'YES'

# ---- server
Stop-TheServer

Step 'Changing the server source'
if ($current -eq 720) {
    Set-SpellbookSize $hdr 720 1440
    $check = Get-SpellbookSize $hdr
    if ($check -ne 1440) { Fail 'The source file did not change as expected. Run 3-ROLLBACK to restore the original.' }
    Say 'SPELLBOOK_SIZE is now 1440.' 'Green'
} else {
    Say 'SPELLBOOK_SIZE was already 1440. Leaving it as it is.'
}

Step 'Building the server'
if ($Script:BuildCommand) {
    Say ('Running (in ' + $Script:SourceDir + '): ' + $Script:BuildCommand)
    Push-Location $Script:SourceDir
    try { $rc = Invoke-Cmd $Script:BuildCommand } finally { Pop-Location }
    if ($rc -ne 0) { Fail ('The build failed (exit code ' + $rc + '). The server is still stopped and your old programs are untouched. Run 3-ROLLBACK to put the source file back, or fix the build and run this again.') }
    if (-not $Script:BuildOutputDir) { Fail 'BuildOutputDir is not set in your settings file, so the new programs cannot be copied.' }
    if (-not (Test-Path -LiteralPath $Script:BuildOutputDir)) { Fail ('BuildOutputDir does not exist: ' + $Script:BuildOutputDir) }
    $n = Copy-Programs $Script:BuildOutputDir $Script:ServerDir
    Say ([string]$n + ' program files copied into ' + $Script:ServerDir) 'Green'
    if ($n -eq 0) { Fail 'The build produced no .exe or .dll files in BuildOutputDir. Nothing was copied.' }
} else {
    Say 'Build the server now with your usual method, using the changed source.'
    Say ('Then copy the new programs into: ' + $Script:ServerDir)
    [void](Read-Host 'Press Enter when the new programs are in place')
}

Start-TheServer

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  INSTALL COMPLETE - NOW CHECK IT WORKS' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Say 'With a test character on the NEW client:'
Say '  1. Log in and enter the world.'
Say '  2. Open the spellbook and type /book 179 (the last pages).'
Say '  3. Scribe a spell and check it saves after you camp and log back in.'
Say ''
Say 'If anything is wrong, run 3-ROLLBACK.'
Say ''
[void](Read-Host 'Press Enter to close this window')
