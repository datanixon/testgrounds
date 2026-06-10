#requires -version 5
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # godot/tests -> godot
$gargs = @('--headless','--path',$root,'--script','res://tests/run_tests.gd')

# Resolve the Godot console executable.
# On Windows with the WinGet Mono build, 'godot' shim points to the GUI exe
# which does not write to stdout/stderr and doesn't propagate exit codes.
# We prefer the _console.exe sibling in the same install folder.
function Find-GodotConsole {
  $shim = Get-Command godot -ErrorAction SilentlyContinue
  if ($shim) {
    $guiExe = (Get-Item $shim.Source -ErrorAction SilentlyContinue)?.Target
    if (-not $guiExe) { $guiExe = $shim.Source }
    $dir = Split-Path -Parent $guiExe
    $console = Join-Path $dir ($([System.IO.Path]::GetFileNameWithoutExtension($guiExe)) + '_console.exe')
    if (Test-Path $console) { return $console }
    return $shim.Source   # fall back to shim (non-Windows or already console)
  }
  if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
  throw "Godot not found. Put 'godot' on PATH or set `$env:GODOT to the Godot executable."
}

$godot = Find-GodotConsole
& $godot @gargs
exit $LASTEXITCODE
