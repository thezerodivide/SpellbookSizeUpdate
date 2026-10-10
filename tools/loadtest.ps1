# Loads an eqgame.exe image through the Windows loader (no code is run) to prove the PE edits are valid.
# Must run in 32-bit PowerShell:  & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -File loadtest.ps1 <exe> [<exe> ...]
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Paths)
$src = @"
using System; using System.Runtime.InteropServices;
public static class L {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint fl);
  [DllImport("kernel32.dll")] public static extern bool FreeLibrary(IntPtr h);
}
"@
Add-Type -TypeDefinition $src
foreach ($p in $Paths) {
  $h = [L]::LoadLibraryEx($p, [IntPtr]::Zero, 1)   # DONT_RESOLVE_DLL_REFERENCES
  $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  "{0}: handle=0x{1:X} err={2} ptrsize={3}" -f (Split-Path $p -Leaf), $h.ToInt32(), $err, [IntPtr]::Size
  if ($h -ne [IntPtr]::Zero) {
    $base = $h.ToInt32()
    "  image base 0x{0:X}" -f $base
    $sec = [IntPtr]($base + 0x12c3000)
    try {
      $first = [Runtime.InteropServices.Marshal]::ReadByte($sec)
      $fix = [Runtime.InteropServices.Marshal]::ReadInt32([IntPtr]($base + 0x12c3000 + 4))
      "  .sbook first byte 0x{0:X2}; fixup in cave_B = 0x{1:X}; expected (base+0x12c3200) = 0x{2:X}" -f $first, $fix, ($base + 0x12c3200)
    } catch { "  (no .sbook section: {0})" -f $_.Exception.Message }
    [void][L]::FreeLibrary($h)
  }
}
