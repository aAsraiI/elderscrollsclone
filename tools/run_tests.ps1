# Runs every gameplay test suite in test/ (4 at a time) and prints one line per suite.
# From a terminal in the project folder:
#     powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
#     powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1 -Only stage1,phase2
# -Only keeps the suites whose file name contains one of the words.
# The quick content checks in tests/ run inside the editor instead (Godot AI test runner).
param(
	[string[]]$Only = @(),
	[int]$Parallel = 4,
	[string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
)

$project = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $env:TEMP "elderscrolls_test_logs"
New-Item -ItemType Directory -Force $logs | Out-Null

$suites = @(Get-ChildItem (Join-Path $project "test") -Filter "test_*.gd")
$words = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })  # -File passes "a,b" as one word
if ($words.Count -gt 0) {
	$suites = @($suites | Where-Object { $name = $_.BaseName; @($words | Where-Object { $name -like "*$_*" }).Count -gt 0 })
}
if ($suites.Count -eq 0) {
	"No suites in test/ match: $($words -join ', ')"
	exit 1
}

# Start up to $Parallel Godot processes at a time
$running = @()
$started = @{}
foreach ($s in $suites) {
	while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Parallel) { Start-Sleep -Milliseconds 500 }
	$log = Join-Path $logs ($s.BaseName + ".log")
	$p = Start-Process -FilePath $Godot -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + ".err") `
		-ArgumentList "--headless", "--fixed-fps", "60", "--path", "`"$project`"", "-s", "res://test/$($s.Name)"
	$running += $p
	$started[$s.BaseName] = $log
}
$running | ForEach-Object { $_.WaitForExit() }

# One line per suite, failures first
$failed = 0
$rows = @(foreach ($name in ($started.Keys | Sort-Object)) {
	$result = Select-String -Path $started[$name] -Pattern "^RESULT:" | Select-Object -Last 1
	$line = if ($result) { $result.Line } else { "RESULT: did not finish (see $($started[$name]))" }
	$bad = $line -notmatch " 0 failed"
	if ($bad) { $failed++ }
	[pscustomobject]@{ Bad = $bad; Text = "{0,-22} {1}" -f $name, $line }
})
$rows | Sort-Object -Property @{ Expression = "Bad"; Descending = $true }, Text | ForEach-Object { $_.Text }
""
if ($failed -eq 0) { "All $($rows.Count) suites passed." } else { "$failed suite(s) failed. Logs: $logs" }
