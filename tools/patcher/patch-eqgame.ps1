# Applies the 1440-slot spellbook patch to a RoF2 eqgame.exe. Never changes the original: it writes a NEW file.
#
#   -Mode stock : the exe is the normal (stock) one. Applies the 4GB patch AND the spellbook patch.
#   -Mode 4gb   : the exe already has the 4GB patch. Applies ONLY the spellbook patch (4GB flag stays as it is).
#
# Before changing anything it checks every spot it will modify. If the exe is not the RoF2 client this patch was
# made for, or already has the spellbook patch, it stops and says so.
# Written for Windows PowerShell 5.1. ASCII only on purpose.
param(
    [Parameter(Mandatory = $true)][ValidateSet('stock', '4gb')][string]$Mode,
    [string]$InputPath = ''
)
$ErrorActionPreference = 'Stop'

function Stop-Here([string]$Text) {
    Write-Host ''
    Write-Host ('STOPPED: ' + $Text) -ForegroundColor Red
    Write-Host 'Your original file was not changed.'
    Write-Host ''
    [void](Read-Host 'Press Enter to close this window')
    exit 1
}

$sourcePath = Join-Path $PSScriptRoot 'SpellbookPatcher.cs'
if (-not (Test-Path -LiteralPath $sourcePath)) { Stop-Here 'SpellbookPatcher.cs is missing. Keep all the files in this folder together.' }
$source = [IO.File]::ReadAllText($sourcePath)

Add-Type -TypeDefinition $source -Language CSharp

Write-Host '============================================================' -ForegroundColor Cyan
if ($Mode -eq 'stock') { Write-Host '  eqgame.exe patcher: stock exe -> 4GB patch + 1440 spellbook' -ForegroundColor Cyan }
else { Write-Host '  eqgame.exe patcher: exe that already has the 4GB patch -> 1440 spellbook' -ForegroundColor Cyan }
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

if (-not $InputPath) {
    Write-Host 'Drag your eqgame.exe onto this program next time, or type its full path now.'
    $InputPath = Read-Host 'Path to eqgame.exe'
}
$InputPath = $InputPath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { Stop-Here ('Could not find the file: ' + $InputPath) }
$InputPath = (Resolve-Path -LiteralPath $InputPath).Path

$tablePath = Join-Path $PSScriptRoot 'patch-table.json'
if (-not (Test-Path -LiteralPath $tablePath)) { Stop-Here 'patch-table.json is missing. Keep it in the same folder as this program.' }
$table = @(Get-Content -LiteralPath $tablePath -Raw | ConvertFrom-Json)
[string[]]$vas = $table | ForEach-Object { $_.va }
[string[]]$expects = $table | ForEach-Object { $_.expect }
[string[]]$replaces = $table | ForEach-Object { $_.replace }

$bytes = [IO.File]::ReadAllBytes($InputPath)
Write-Host ('File:  ' + $InputPath)
Write-Host ('Size:  ' + $bytes.Length + ' bytes')
Write-Host ('MD5:   ' + (Get-FileHash -Algorithm MD5 -LiteralPath $InputPath).Hash.ToLower())
Write-Host ''

try {
    $hasLaa = [SpellbookPatcher]::HasLaa($bytes)
    if ($Mode -eq '4gb' -and -not $hasLaa) {
        Stop-Here 'This exe does NOT have the 4GB patch, and this option needs it. Use the other option (stock exe: 4GB patch + spellbook) instead.'
    }
    if ($Mode -eq 'stock' -and $hasLaa) {
        Write-Host 'Note: this exe already has the 4GB patch. That is fine; it will keep it.' -ForegroundColor Yellow
    }
    $patched = [SpellbookPatcher]::Build($bytes, $vas, $expects, $replaces, ($Mode -eq 'stock'))
} catch {
    $m = $_.Exception.Message
    if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
    Stop-Here $m
}

$dir = Split-Path -Parent $InputPath
$outPath = Join-Path $dir 'eqgame_1440.exe'
if (Test-Path -LiteralPath $outPath) { Stop-Here ('There is already a file named eqgame_1440.exe in that folder. Move or rename it first, so nothing is overwritten.') }
[IO.File]::WriteAllBytes($outPath, $patched)
$outMd5 = (Get-FileHash -Algorithm MD5 -LiteralPath $outPath).Hash.ToLower()
$verify = [IO.File]::ReadAllBytes($outPath)
if (-not [SpellbookPatcher]::HasSpellbookSection($verify)) { Stop-Here 'The new file did not come out as expected. Do not use it.' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host '  DONE' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('New file: ' + $outPath)
Write-Host ('MD5:      ' + $outMd5)
if ($outMd5 -eq 'f10534e3ae4ebe64f6dc9d56459c8ecd') { Write-Host 'This is identical to the tested 4GB 1440-slot client.' -ForegroundColor Green }
elseif ($outMd5 -eq '03b11a34694500b2c38d8aea746d1ae0') { Write-Host 'This is identical to the tested standard 1440-slot client (no 4GB flag).' -ForegroundColor Green }
Write-Host ''
Write-Host 'Your original eqgame.exe was NOT changed. To use the new one, rename it to eqgame.exe'
Write-Host 'where the game expects it. Keep the original somewhere safe.'
Write-Host ''
Write-Host 'Remember: the server needs the matching one-line change, and players need this new'
Write-Host 'client before the server is switched. See the rollout guide.'
Write-Host ''
[void](Read-Host 'Press Enter to close this window')
