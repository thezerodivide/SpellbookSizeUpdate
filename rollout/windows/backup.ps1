# 1-BACKUP: saves everything needed to roll back the spellbook change.
# It only READS from your server and database. It changes nothing except creating the backup folder.
. "$PSScriptRoot\common.ps1"

Show-Header 'BACKUP'
$settingsFile = Select-SettingsFile
. $settingsFile
Initialize-Settings
Say ('Server: ' + $Script:ServerName) 'White'
Say ('Settings: ' + (Split-Path -Leaf $settingsFile))

Step 'Checking the database connection'
try { $ping = Invoke-Sql 'SELECT 1' } catch { Fail ('Could not talk to the database. ' + $_.Exception.Message) }
$rows = Invoke-Sql 'SELECT COUNT(*) FROM character_spells'
$maxSlot = Invoke-Sql 'SELECT IFNULL(MAX(slot_id), -1) FROM character_spells'
$sizeMb = Invoke-Sql ("SELECT ROUND(SUM(data_length + index_length) / 1048576) FROM information_schema.tables WHERE table_schema = '" + $Script:DbName + "'")
Say ('Database ' + $Script:DbName + ': about ' + $sizeMb + ' MB, ' + $rows + ' saved spells, highest spellbook slot used: ' + $maxSlot)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safeName = ($Script:ServerName -replace '[^A-Za-z0-9]+', '-').Trim('-')
$dir = Join-Path $Script:BackupRoot ('spellbook-' + $safeName + '-' + $stamp)
Step ('Creating backup folder: ' + $dir)
New-Item -ItemType Directory -Force -Path $dir | Out-Null

Step 'Backing up the database (this can take a few minutes)'
Save-Dump (Join-Path $dir 'db.sql') '--routines --triggers' ''
Say ('Done: ' + [Math]::Round((Get-Item (Join-Path $dir 'db.sql')).Length / 1MB, 1) + ' MB') 'Green'

Step 'Backing up the server programs'
$n = Copy-Programs $Script:ServerDir (Join-Path $dir 'server-programs')
Say ([string]$n + ' program files (.exe and .dll) copied.') 'Green'
if ($n -eq 0) { Warn 'No .exe or .dll files were found in ServerDir. Is ServerDir the folder the server runs from?' }

Step 'Backing up the server configuration'
$cfgDir = Join-Path $dir 'server-config'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
foreach ($f in @('eqemu_config.json', 'login.json')) {
    $p = Join-Path $Script:ServerDir $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $cfgDir -Force; Say ('Copied ' + $f) }
}

$hdrValue = ''
$hdr = Get-HeaderPath
if ($hdr) {
    Step 'Backing up the server source file that gets changed'
    if (-not (Test-Path -LiteralPath $hdr)) { Fail ('Could not find ' + $hdr + '. Check SourceDir in your settings file.') }
    $srcDir = Join-Path $dir 'source'
    New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
    Copy-Item -LiteralPath $hdr -Destination $srcDir -Force
    $v = Get-SpellbookSize $hdr
    if ($v) { $hdrValue = [string]$v }
    Say ('rof2_limits.h copied. SPELLBOOK_SIZE is currently ' + $hdrValue)
} else {
    Say 'SourceDir is not set, so the server source file is not backed up.' 'Yellow'
}

$stageExe = ''
if ($Script:ClientStageDir) {
    $existing = Join-Path $Script:ClientStageDir 'eqgame.exe'
    if (Test-Path -LiteralPath $existing) {
        Step 'Backing up the current client file from ClientStageDir'
        $cd = Join-Path $dir 'client-stage'
        New-Item -ItemType Directory -Force -Path $cd | Out-Null
        Copy-Item -LiteralPath $existing -Destination $cd -Force
        $stageExe = Get-Md5 $existing
        Say ('Copied eqgame.exe (md5 ' + $stageExe + ')')
    }
}

if ($Script:ClientSourceExe -and (Test-Path -LiteralPath $Script:ClientSourceExe)) {
    Step 'Backing up your current client file (ClientSourceExe)'
    $cs = Join-Path $dir 'client-source'
    New-Item -ItemType Directory -Force -Path $cs | Out-Null
    Copy-Item -LiteralPath $Script:ClientSourceExe -Destination $cs -Force
    Say ('Copied eqgame.exe (md5 ' + (Get-Md5 $Script:ClientSourceExe) + ')')
}

Step 'Writing the backup summary'
$info = @(
    ('server=' + $Script:ServerName),
    ('created=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    ('database=' + $Script:DbName),
    ('spell_rows=' + $rows),
    ('max_slot=' + $maxSlot),
    ('source_spellbook_size=' + $hdrValue),
    ('client_stage_md5=' + $stageExe)
)
[IO.File]::WriteAllText((Join-Path $dir 'backup-info.txt'), (($info -join "`r`n") + "`r`n"), $Script:Latin1)
[IO.File]::WriteAllText((Join-Path $Script:BackupRoot 'LATEST.txt'), ((Split-Path -Leaf $dir) + "`r`n"), $Script:Latin1)

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  BACKUP COMPLETE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Say ('Saved to: ' + $dir)
Say ''
Say 'Tip: take the backup when the server is quiet. Anything players do after this'
Say 'moment is NOT in the backup, and a full restore would undo it.'
Say ''
[void](Read-Host 'Press Enter to close this window')
