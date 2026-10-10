# Widens the two spellbook page-number labels so 3-digit page numbers (100-180) are not cut off.
# Stock labels are 20px wide (fits 2 digits). New: 40px wide, moved left by 10px to stay centred.
# Usage (PowerShell):  .\fix-spellbook-page-labels.ps1 "C:\path\to\client\uifiles\default\EQUI_SpellBookWnd.xml"
# Run once per skin folder you use. A .orig backup is made if none exists.
param([Parameter(Mandatory = $true)][string]$Path)

if (-not (Test-Path "$Path.orig")) { Copy-Item $Path "$Path.orig" }
$e = [Text.Encoding]::GetEncoding(28591)   # byte-preserving
$t = [IO.File]::ReadAllText($Path, $e)
$n = $t -replace '(<StaticText item="SBW_LeftPageNum">[\s\S]*?<X>)137(</X>[\s\S]*?<CX>)20(</CX>)', '${1}127${2}40${3}'
$n = $n -replace '(<StaticText item="SBW_RightPageNum">[\s\S]*?<X>)350(</X>[\s\S]*?<CX>)20(</CX>)', '${1}340${2}40${3}'
if ($n -eq $t) { 'NO CHANGE - pattern not found (already patched, or a different skin layout)' }
else { [IO.File]::WriteAllText($Path, $n, $e); 'Edited OK' }
