param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [int]$Seed = 1,
    [string]$FFmpeg = "ffmpeg",
    [ValidateSet(30, 60)][int]$FPS = 30,
    [ValidateSet("baseline", "candidate", "rail-exit")][string]$RiptideAI
)
# Windows PowerShell 5.1 / PowerShell 7. No installs, network access or account access.
$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Pass the full path to your Godot 4.x executable with -Godot."
}
$output = Join-Path $project "renders"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$name = "fight-{0:D4}-{1}" -f $Seed, (Get-Date -Format "yyyyMMdd-HHmmss-fff")
$avi = Join-Path $output ($name + ".avi")
$json = Join-Path $output ($name + ".json")
$mp4 = Join-Path $output ($name + ".mp4")
$log = Join-Path $output ($name + ".log")
$presentation = Get-Content -LiteralPath (Join-Path $project "config/presentation.json") -Raw | ConvertFrom-Json
$episode = $presentation.episode
# The limit is a watchdog. Godot stops as soon as the actual showcase ends.
$frameLimit = [int]([Math]::Ceiling(2 * $episode.intro_shot_seconds + $episode.fight_seconds + $episode.showcase_seconds + 5) * $FPS)
Write-Host "Recording seed $Seed. Keep the recording window open until it closes itself."
# Start-Process -Wait reliably waits for both GUI and console Godot executables.
$godotArguments = '--path "{0}" --resolution 720x1280 --write-movie "{1}" --fixed-fps {2} --quit-after {5} -- --autostop --seed={3} --report="{4}"' -f $project, $avi, $FPS, $Seed, $json, $frameLimit
if ($RiptideAI) { $godotArguments += " --riptide-ai=$RiptideAI" }
$process = Start-Process -FilePath $Godot -ArgumentList $godotArguments -PassThru -Wait -RedirectStandardOutput $log -RedirectStandardError ($log + ".errors")
if ($process.ExitCode -ne 0) { throw "Godot exited with code $($process.ExitCode). See $log.errors" }
if (-not (Test-Path -LiteralPath $json)) { throw "Fight did not complete: result JSON is missing. Check the logs." }
if (-not (Test-Path -LiteralPath $avi)) { throw "Godot did not create the AVI recording. Check the logs." }
$report = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
if (-not $report.winner) { throw "Result JSON has no winner/draw result." }
Write-Host "Result: $($report.winner) / $($report.reason)"
if (Get-Command $FFmpeg -ErrorAction SilentlyContinue) {
    & $FFmpeg -hide_banner -loglevel warning -n -i $avi -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $mp4
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed. Original AVI retained: $avi" }
    Write-Host "Finished: $mp4"
    Write-Host "AVI retained as a master; it can be large. Delete it manually once happy with the MP4."
} else {
    Write-Host "Recorded successfully: $avi"
    Write-Host "FFmpeg was not found. MP4 conversion is optional; pass -FFmpeg with its full executable path."
}
