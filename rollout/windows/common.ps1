# Shared helpers for the spellbook 1440 rollout scripts.
# Written for Windows PowerShell 5.1 (built into Windows 10/11). ASCII only on purpose.

$ErrorActionPreference = 'Stop'

# The patcher lives in tools\patcher of this repository (two folders up from here).
$Script:PatcherDir = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') (Join-Path 'tools' 'patcher')
$Script:Latin1 = [Text.Encoding]::GetEncoding(28591)

function Say([string]$Text, [string]$Color = 'White') { Write-Host $Text -ForegroundColor $Color }
function Step([string]$Text) { Write-Host ''; Write-Host ('=== ' + $Text) -ForegroundColor Cyan }
function Warn([string]$Text) { Write-Host ('WARNING: ' + $Text) -ForegroundColor Yellow }

function Fail([string]$Text) {
    Write-Host ''
    Write-Host ('STOPPED: ' + $Text) -ForegroundColor Red
    Write-Host ''
    [void](Read-Host 'Press Enter to close this window')
    exit 1
}

function Confirm-Typed([string]$Prompt, [string]$Word) {
    Write-Host ''
    $answer = Read-Host ($Prompt + ' Type ' + $Word + ' to continue, or anything else to stop')
    if ($answer -cne $Word) { Fail 'Cancelled. Nothing was changed by this step.' }
}

function Q([string]$Text) { return ('"' + $Text + '"') }

# ---------------------------------------------------------------- settings

function Select-SettingsFile {
    $files = @(Get-ChildItem -Path $PSScriptRoot -Filter 'settings-*.ps1' |
        Where-Object { $_.Name -notlike 'settings-EXAMPLE*' } | Sort-Object Name)
    if ($files.Count -eq 0) {
        Fail ('No settings file found. Copy settings-EXAMPLE.ps1 to settings-yourservername.ps1 (in the same folder), fill it in, and run this again.')
    }
    if ($files.Count -eq 1) { return $files[0].FullName }
    Say 'More than one server is set up here. Which one is this for?'
    for ($i = 0; $i -lt $files.Count; $i++) { Say ('  ' + ($i + 1) + ') ' + $files[$i].Name) }
    $n = Read-Host 'Type the number'
    $idx = 0
    if (-not [int]::TryParse($n, [ref]$idx) -or $idx -lt 1 -or $idx -gt $files.Count) { Fail 'That is not one of the choices.' }
    return $files[$idx - 1].FullName
}

function Initialize-Settings {
    foreach ($name in @('ServerName', 'ServerDir', 'BackupRoot', 'DbName', 'DbUser')) {
        $v = Get-Variable -Name $name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
        if (-not $v) { Fail ("Your settings file is missing '" + $name + "'. Open it and fill it in.") }
    }
    if (-not $Script:DbHost) { $Script:DbHost = '127.0.0.1' }
    if (-not $Script:DbPort) { $Script:DbPort = '3306' }
    if (-not $Script:DbPass) { $Script:DbPass = '' }
    if ($Script:DbPass) { $env:MYSQL_PWD = $Script:DbPass }
    if (-not (Test-Path -LiteralPath $Script:ServerDir -PathType Container)) { Fail ('ServerDir does not exist: ' + $Script:ServerDir) }
    if (-not (Test-Path -LiteralPath (Join-Path $Script:ServerDir 'eqemu_config.json'))) {
        Warn ('There is no eqemu_config.json in ' + $Script:ServerDir + '. Is ServerDir the folder the server runs from?')
        Confirm-Typed 'Continue anyway?' 'YES'
    }
}

# ---------------------------------------------------------------- database

function Get-MysqlExe([string[]]$Names) {
    foreach ($name in $Names) {
        if ($Script:MysqlBinDir) {
            $p = Join-Path $Script:MysqlBinDir $name
            foreach ($c in @($p, ($p + '.exe'))) {
                if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
            }
        } else {
            $cmd = Get-Command $name -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
        }
    }
    Fail ("Could not find '" + $Names[0] + "'. Set MysqlBinDir in your settings file to the folder that contains mysql.exe and mysqldump.exe.")
}

function Get-ConnArgs {
    return ('--host=' + $Script:DbHost + ' --port=' + $Script:DbPort + ' --user=' + $Script:DbUser)
}

# Run one SQL statement and return its output as text.
function Invoke-Sql([string]$Sql) {
    $exe = Get-MysqlExe @('mysql', 'mariadb')
    $a = @(('--host=' + $Script:DbHost), ('--port=' + $Script:DbPort), ('--user=' + $Script:DbUser),
           '--batch', '--skip-column-names', ('--execute=' + $Sql), $Script:DbName)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $exe $a 2>&1
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $text = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
    if ($rc -ne 0) { throw ('The database said: ' + $text) }
    return $text.Trim()
}

# Run a command line through cmd.exe so that "> file" and "< file" copy bytes untouched.
function Invoke-Cmd([string]$Line) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ((Test-Path variable:IsLinux) -and $IsLinux) { & bash -c $Line | Out-Null }
        else { & cmd.exe /c ('"' + $Line + '"') | Out-Null }
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

function Save-Dump([string]$OutFile, [string]$Extra, [string]$Tables) {
    $dump = Get-MysqlExe @('mysqldump', 'mariadb-dump')
    $line = (Q $dump) + ' ' + (Get-ConnArgs) + ' --single-transaction --quick ' + $Extra + ' ' + $Script:DbName + ' ' + $Tables + ' > ' + (Q $OutFile)
    $rc = Invoke-Cmd $line
    if ($rc -ne 0) { Fail ('The database dump failed (exit code ' + $rc + '). Check the database name, user and password in your settings file.') }
    if (-not (Test-Path -LiteralPath $OutFile) -or (Get-Item -LiteralPath $OutFile).Length -lt 200) { Fail 'The database dump file is empty.' }
    $tail = @(Get-Content -LiteralPath $OutFile -Tail 5 | Where-Object { $_ -match 'Dump completed' })
    if ($tail.Count -eq 0) { Fail 'The database dump looks incomplete (no "Dump completed" line at the end).' }
}

function Restore-Dump([string]$InFile) {
    $mysql = Get-MysqlExe @('mysql', 'mariadb')
    $line = (Q $mysql) + ' ' + (Get-ConnArgs) + ' ' + $Script:DbName + ' < ' + (Q $InFile)
    $rc = Invoke-Cmd $line
    if ($rc -ne 0) { Fail ('Restoring the database failed (exit code ' + $rc + '). Your backup files are untouched.') }
}

# ---------------------------------------------------------------- files

function Get-HeaderPath {
    if (-not $Script:SourceDir) { return $null }
    return (Join-Path (Join-Path (Join-Path $Script:SourceDir 'common') 'patches') 'rof2_limits.h')
}

function Get-SpellbookSize([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, $Script:Latin1)
    $m = [regex]::Matches($text, 'SPELLBOOK_SIZE\s*=\s*(\d+)\s*;')
    if ($m.Count -ne 1) { return $null }
    return [int]$m[0].Groups[1].Value
}

function Set-SpellbookSize([string]$Path, [int]$OldValue, [int]$NewValue) {
    $text = [IO.File]::ReadAllText($Path, $Script:Latin1)
    $pattern = '(SPELLBOOK_SIZE\s*=\s*)' + $OldValue + '(\s*;)'
    $result = [regex]::Replace($text, $pattern, ('${1}' + $NewValue + '${2}'))
    if ($result -eq $text) { Fail 'Could not change the SPELLBOOK_SIZE line.' }
    [IO.File]::WriteAllText($Path, $result, $Script:Latin1)
}

function Copy-Programs([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
    $files = @(Get-ChildItem -LiteralPath $From -File | Where-Object { $_.Extension -in @('.exe', '.dll') })
    foreach ($f in $files) { Copy-Item -LiteralPath $f.FullName -Destination $To -Force }
    return $files.Count
}

# Patches the owner's own eqgame.exe with the 1440-slot spellbook patch and writes the result to $OutFile.
# The 4GB flag is left exactly as the owner's exe has it. Returns a hashtable with the details.
function New-PatchedClient([string]$SourceExe, [string]$OutFile) {
    $cs = Join-Path $Script:PatcherDir 'SpellbookPatcher.cs'
    $tbl = Join-Path $Script:PatcherDir 'patch-table.json'
    if (-not (Test-Path -LiteralPath $cs) -or -not (Test-Path -LiteralPath $tbl)) {
        Fail ('The patcher files are missing from ' + $Script:PatcherDir + '. Keep this folder inside the full package.')
    }
    if (-not ('SpellbookPatcher' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText($cs)) -Language CSharp }
    $table = @(Get-Content -LiteralPath $tbl -Raw | ConvertFrom-Json)
    [string[]]$vas = $table | ForEach-Object { $_.va }
    [string[]]$expects = $table | ForEach-Object { $_.expect }
    [string[]]$replaces = $table | ForEach-Object { $_.replace }
    $bytes = [IO.File]::ReadAllBytes($SourceExe)
    $hadLaa = $false
    try {
        $hadLaa = [SpellbookPatcher]::HasLaa($bytes)
        $patched = [SpellbookPatcher]::Build($bytes, $vas, $expects, $replaces, $false)
    } catch {
        $m = $_.Exception.Message
        if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
        Fail ('Could not patch ' + $SourceExe + '. ' + $m)
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    [IO.File]::WriteAllBytes($OutFile, $patched)
    return @{ HadLaa = $hadLaa; InMd5 = (Get-Md5 $SourceExe); OutMd5 = (Get-Md5 $OutFile) }
}

function Get-Md5([string]$Path) { return (Get-FileHash -Algorithm MD5 -LiteralPath $Path).Hash.ToLower() }

# ---------------------------------------------------------------- server control

function Stop-TheServer {
    Step 'Stopping the server'
    if ($Script:StopCommand) {
        Say ('Running: ' + $Script:StopCommand)
        $rc = Invoke-Cmd $Script:StopCommand
        if ($rc -ne 0) { Warn ('The stop command returned ' + $rc + '.') }
        Start-Sleep -Seconds 3
        [void](Read-Host 'Check that the server is really stopped, then press Enter')
    } else {
        Say 'Stop the server now: world, zone, login server, and anything else that uses the database.'
        [void](Read-Host 'Press Enter when it is fully stopped')
    }
}

function Start-TheServer {
    Step 'Starting the server'
    if ($Script:StartCommand) {
        Say ('Running: ' + $Script:StartCommand)
        if ((Test-Path variable:IsLinux) -and $IsLinux) {
            Start-Process -FilePath 'bash' -ArgumentList @('-c', $Script:StartCommand) -WorkingDirectory $Script:ServerDir
        } else {
            Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', $Script:StartCommand) -WorkingDirectory $Script:ServerDir
        }
    } else {
        Say 'Start the server now, the way you normally do.'
        [void](Read-Host 'Press Enter when it is running')
    }
}

# ---------------------------------------------------------------- backups

function Read-Info([string]$Dir) {
    $info = @{}
    $f = Join-Path $Dir 'backup-info.txt'
    if (Test-Path -LiteralPath $f) {
        foreach ($l in (Get-Content -LiteralPath $f)) {
            $i = $l.IndexOf('=')
            if ($i -gt 0) { $info[$l.Substring(0, $i)] = $l.Substring($i + 1) }
        }
    }
    return $info
}

function Test-BackupFolder([string]$Dir) {
    $sql = Join-Path $Dir 'db.sql'
    if (-not (Test-Path -LiteralPath $sql)) { return 'db.sql is missing' }
    if ((Get-Item -LiteralPath $sql).Length -lt 200) { return 'db.sql is empty' }
    $tail = @(Get-Content -LiteralPath $sql -Tail 5 | Where-Object { $_ -match 'Dump completed' })
    if ($tail.Count -eq 0) { return 'db.sql looks incomplete' }
    if (-not (Test-Path -LiteralPath (Join-Path $Dir 'backup-info.txt'))) { return 'backup-info.txt is missing' }
    return ''
}

function Select-BackupFolder {
    if (-not (Test-Path -LiteralPath $Script:BackupRoot)) { Fail ('No backup folder yet: ' + $Script:BackupRoot + '. Run 1-BACKUP first.') }
    $dirs = @(Get-ChildItem -LiteralPath $Script:BackupRoot -Directory | Where-Object { $_.Name -like 'spellbook-*' } | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { Fail ('No backups found in ' + $Script:BackupRoot + '. Run 1-BACKUP first.') }
    $latest = ''
    $lf = Join-Path $Script:BackupRoot 'LATEST.txt'
    if (Test-Path -LiteralPath $lf) { $latest = (Get-Content -LiteralPath $lf -TotalCount 1).Trim() }
    Say 'Backups found (newest first):'
    $max = [Math]::Min($dirs.Count, 9)
    for ($i = 0; $i -lt $max; $i++) {
        $mark = ''
        if ($dirs[$i].Name -eq $latest) { $mark = '   <- most recent' }
        Say ('  ' + ($i + 1) + ') ' + $dirs[$i].Name + $mark)
    }
    $n = Read-Host 'Type the number of the backup to use (just press Enter for 1)'
    if (-not $n) { $n = '1' }
    $idx = 0
    if (-not [int]::TryParse($n, [ref]$idx) -or $idx -lt 1 -or $idx -gt $max) { Fail 'That is not one of the choices.' }
    return $dirs[$idx - 1].FullName
}

function Show-Header([string]$Title) {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ('  Spellbook 720 -> 1440 : ' + $Title) -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
}
