param(
  [string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = "Stop"

$required = @(
  "oh-package.json5",
  "build-profile.json5",
  "AppScope\app.json5",
  "entry\src\main\module.json5",
  "entry\src\main\ets\pages\Index.ets",
  "entry\src\main\ets\model\ImageLoader.ets",
  "entry\src\main\ets\model\FeatureExtractor.ets",
  "entry\src\main\ets\model\DiagnosisEngine.ets",
  "entry\src\main\ets\model\Gemma4Bridge.ets",
  "entry\src\main\cpp\napi_init.cpp"
)

foreach ($item in $required) {
  $path = Join-Path $ProjectRoot $item
  if (-not (Test-Path $path)) {
    throw "Missing required file: $item"
  }
}

$hits = Get-ChildItem -Path $ProjectRoot -Recurse -File |
  Where-Object {
    $_.FullName -notmatch "\\.git\\" -and
    $_.FullName -ne (Join-Path $ProjectRoot "scripts\static_check.ps1")
  } |
  Select-String -Pattern "gemma3"

if ($hits) {
  $hits | ForEach-Object { Write-Host $_.Path ":" $_.LineNumber ":" $_.Line }
  throw "Found Gemma3 references; all model references must be Gemma4 4B."
}

Write-Host "Static check passed for $ProjectRoot"
