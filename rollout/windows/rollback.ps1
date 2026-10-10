# 3-ROLLBACK: puts the server back to the 720-slot spellbook, using a backup made by 1-BACKUP.
#
# Two ways to roll back the database:
#   LIGHT: keeps everything players did since the backup. Removes only the spells saved in
#          slots 720 and up (they are saved to a file first, so nothing is truly lost).
#   FULL : replaces the whole database with the backup. ALL player progress since the backup is lost.
#
# Either way the spells in slots 720+ must go: an old 720-slot server reads a spell saved in
# slot 720 one entry past the end of its spellbook array (an existing off-by-one in the server).
. "$PSScriptRoot\common.ps1"

Show-Header 'ROLLBACK'
$settingsFile = Select-SettingsFile
. $settingsFile
Initialize-Settings
Say ('Server: ' + $Script:ServerName)

Step 'Choosing the backup'
$backupDir = Select-BackupFolder
$bad = Test-BackupFolder $backupDir
if ($bad) { Fail ('That backup is not usable: ' + $bad + '.') }
$info = Read-Info $backupDir
Say ('Using backup: ' + (Split-Path -Leaf $backupDir)) 'Green'
Say ('  taken: ' + $info['created'] + '   spells saved then: ' + $info['spell_rows'])

try { $null = Invoke-Sql 'SELECT 1' } catch { Fail ('Could not talk to the database. ' + $_.Exception.Message) }
$high = Invoke-Sql 'SELECT COUNT(*) FROM character_spells WHERE slot_id >= 720'
Say ('Right now there are ' + $high + ' saved spells in slots 720 and up.')

Write-Host ''
Say 'How should the DATABASE be rolled back?' 'White'
Say ''
Say '  1) LIGHT  (recommended)' 'Green'
Say '     Keeps everything players have done since the backup (levels, items, quests...).'
Say '     Removes only the spells in slots 720 and up. They are saved to a file first.'
Say ''
Say '  2) FULL RESTORE' 'Yellow'
Say '     Puts the whole database back exactly as it was at the backup.'
Say '     EVERYTHING players did since the backup is lost, for every character.'
Say ''
Say '  3) Cancel'
$choice = Read-Host 'Type 1, 2 or 3'
if ($choice -eq '3' -or ($choice -ne '1' -and $choice -ne '2')) { Fail 'Cancelled. Nothing was changed.' }

$mode = 'LIGHT'
if ($choice -eq '2') {
    $mode = 'FULL'
    Warn 'A full restore undoes ALL player progress since the backup was taken.'
    Say ('The backup was taken: ' + $info['created'])
    Confirm-Typed 'Are you sure you want the FULL restore?' 'RESTORE ALL'
} else {
    Confirm-Typed 'Roll back with the LIGHT method?' 'ROLLBACK'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Stop-TheServer

# ---- database
if ($mode -eq 'LIGHT') {
    Step 'Saving the spells in slots 720 and up (so they can be put back later)'
    $keep = Join-Path $backupDir ('removed-high-slot-spells-' + $stamp + '.sql')
    Save-Dump $keep '--no-create-info --where="slot_id between 720 and 99999999"' 'character_spells'
    Say ('Saved to ' + $keep) 'Green'
    Step 'Removing the spells in slots 720 and up'
    [void](Invoke-Sql 'DELETE FROM character_spells WHERE slot_id >= 720')
    $left = Invoke-Sql 'SELECT COUNT(*) FROM character_spells WHERE slot_id >= 720'
    if ($left -ne '0') { Fail ('Some spells in slots 720+ are still there (' + $left + '). Do not start the old server. Ask for help.') }
    Say 'Done: no spells remain in slots 720 and up.' 'Green'
} else {
    Step 'Saving a copy of the CURRENT database first, just in case'
    $before = Join-Path $backupDir ('before-rollback-' + $stamp + '.sql')
    Save-Dump $before '--routines --triggers' ''
    Say ('Saved to ' + $before) 'Green'
    Step 'Restoring the database from the backup (this can take a few minutes)'
    Restore-Dump (Join-Path $backupDir 'db.sql')
    Say 'Database restored.' 'Green'
}

# ---- server programs and source
Step 'Putting the old server programs back'
$progDir = Join-Path $backupDir 'server-programs'
if (Test-Path -LiteralPath $progDir) {
    $n = Copy-Programs $progDir $Script:ServerDir
    Say ([string]$n + ' program files restored into ' + $Script:ServerDir) 'Green'
} else {
    Warn 'The backup has no server-programs folder. Restore your old programs yourself.'
}

$hdr = Get-HeaderPath
$savedHdr = Join-Path (Join-Path $backupDir 'source') 'rof2_limits.h'
if ($hdr -and (Test-Path -LiteralPath $savedHdr)) {
    Step 'Putting the old server source file back'
    Copy-Item -LiteralPath $savedHdr -Destination $hdr -Force
    Say ('rof2_limits.h restored. SPELLBOOK_SIZE is ' + (Get-SpellbookSize $hdr)) 'Green'
}

# ---- client
if ($Script:ClientStageDir) {
    $oldClient = Join-Path (Join-Path $backupDir 'client-stage') 'eqgame.exe'
    if (Test-Path -LiteralPath $oldClient) {
        Step 'Putting the old client file back in ClientStageDir'
        Copy-Item -LiteralPath $oldClient -Destination (Join-Path $Script:ClientStageDir 'eqgame.exe') -Force
        Say 'Done.' 'Green'
    }
}

Start-TheServer

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  ROLLBACK COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''
Write-Host ' PLAYERS STILL NEED THE OLD eqgame.exe BACK.' -ForegroundColor Yellow
Write-Host ' A client with the new eqgame.exe cannot log in to a 720-slot server.' -ForegroundColor Yellow
Write-Host ' Release the old client file to your players.' -ForegroundColor Yellow
Write-Host ''
if ($mode -eq 'LIGHT') { Say ('The spells that were in slots 720+ are saved in: ' + $keep) }
Say 'Test with a character on the old client before you tell players the server is back.'
Say ''
[void](Read-Host 'Press Enter to close this window')
