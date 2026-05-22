param(
  [string]$GNewsApiKey = $env:GNEWS_API_KEY,
  [string]$LarkCli = $env:LARK_CLI,
  [string]$ImageApiUrl = $env:IMAGE_API_URL,
  [string]$ImageApiKey = $env:IMAGE_API_KEY,
  [string]$ImageModel = $env:IMAGE_MODEL,
  [string]$ImageSize = $env:IMAGE_SIZE,
  [string]$ImageOutputFormat = $env:IMAGE_OUTPUT_FORMAT,
  [string]$PythonExe = $env:PYTHON_EXE,
  [switch]$NoPersist,
  [switch]$SkipDryRun,
  [switch]$AssumeYes
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

function Confirm-YesNo {
  param(
    [string]$Question,
    [bool]$DefaultYes = $true
  )

  if ($AssumeYes) {
    return $true
  }

  $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "$Question $suffix"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $DefaultYes
  }

  return $answer.Trim().ToLowerInvariant().StartsWith("y")
}

function Resolve-LarkCli {
  param([string]$PathFromUser)

  if ($PathFromUser -and (Test-Path -LiteralPath $PathFromUser)) {
    return (Resolve-Path -LiteralPath $PathFromUser).Path
  }

  $cmd = Get-Command lark-cli -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $cmd = Get-Command lark-cli.cmd -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $cmd = Get-Command lark-cli.ps1 -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  return $null
}

function Resolve-Python {
  param([string]$PathFromUser)

  if ($PathFromUser -and (Test-Path -LiteralPath $PathFromUser)) {
    return (Resolve-Path -LiteralPath $PathFromUser).Path
  }

  $candidates = @(
    "python",
    "py",
    "C:\Users\AS\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
  )

  foreach ($candidate in $candidates) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
    if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  return $null
}

Write-Host "NewsCatch first-time setup"
Write-Host ""
Write-Host "Before continuing, please make sure:"
Write-Host "  1. larksuite/cli is installed: https://github.com/larksuite/cli"
Write-Host "  2. lark-cli is logged in and has write access to the target Base."
Write-Host "  3. You have a free GNews API key from https://gnews.io/."
Write-Host "  4. If you want image upload, you have an image API URL/key and a Python runtime with Pillow WebP support."
Write-Host ""

if (-not (Confirm-YesNo -Question "Have you completed the larksuite/cli and GNews prerequisites?")) {
  Write-Host ""
  Write-Host "Setup stopped. Install larksuite/cli, get a GNews API key, then rerun:"
  Write-Host "  .\scripts\setup.ps1"
  exit 1
}

if (-not $GNewsApiKey) {
  $secureKey = Read-Host "Paste your GNews API key" -AsSecureString
  $keyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  try {
    $GNewsApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPtr)
  } finally {
    if ($keyPtr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPtr)
    }
  }
}

if (-not $GNewsApiKey) {
  throw "GNews API key is required. Get one at https://gnews.io/."
}

$env:GNEWS_API_KEY = $GNewsApiKey

if (-not $NoPersist) {
  [Environment]::SetEnvironmentVariable("GNEWS_API_KEY", $GNewsApiKey, "User")
  Write-Host "Saved GNEWS_API_KEY to your user environment variables."
  Write-Host "Open a new PowerShell window after setup if another shell cannot see it yet."
} else {
  Write-Host "Set GNEWS_API_KEY for this PowerShell session only."
}

$resolvedLarkCli = Resolve-LarkCli -PathFromUser $LarkCli
if ($resolvedLarkCli) {
  $env:LARK_CLI = $resolvedLarkCli
  if (-not $NoPersist) {
    [Environment]::SetEnvironmentVariable("LARK_CLI", $resolvedLarkCli, "User")
  }
  Write-Host "Found lark-cli: $resolvedLarkCli"
} else {
  Write-Warning "Could not find lark-cli on PATH."
  Write-Host "Install it from https://github.com/larksuite/cli, then run its login/auth command."
  Write-Host "If it is installed in a custom location, rerun setup with:"
  Write-Host "  .\scripts\setup.ps1 -LarkCli `"C:\path\to\lark-cli.cmd`""
}

$resolvedPython = Resolve-Python -PathFromUser $PythonExe
if ($resolvedPython) {
  $env:PYTHON_EXE = $resolvedPython
  if (-not $NoPersist) {
    [Environment]::SetEnvironmentVariable("PYTHON_EXE", $resolvedPython, "User")
  }
  Write-Host "Found Python: $resolvedPython"
} else {
  Write-Warning "Could not find a Python runtime. WebP conversion will fail until PYTHON_EXE points to a working Python with Pillow."
}

if (-not $ImageApiUrl -and (Confirm-YesNo -Question "Do you want to configure the image API now?" -DefaultYes $false)) {
  $ImageApiUrl = Read-Host "Image API URL"
}
if (-not $ImageApiKey -and $ImageApiUrl) {
  $secureImageKey = Read-Host "Paste your image API key" -AsSecureString
  $imageKeyPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureImageKey)
  try {
    $ImageApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($imageKeyPtr)
  } finally {
    if ($imageKeyPtr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($imageKeyPtr)
    }
  }
}
if (-not $ImageModel -and $ImageApiUrl) {
  $ImageModel = Read-Host "Image model (for example gpt-image-2)"
}
if (-not $ImageSize -and $ImageApiUrl) {
  $ImageSize = Read-Host "Image size (default 1792x1024)"
  if (-not $ImageSize) { $ImageSize = "1792x1024" }
}
if (-not $ImageOutputFormat -and $ImageApiUrl) {
  $ImageOutputFormat = Read-Host "Image output format (png/webp, default webp)"
  if (-not $ImageOutputFormat) { $ImageOutputFormat = "webp" }
}

if ($ImageApiUrl) {
  $env:IMAGE_API_URL = $ImageApiUrl
  if (-not $NoPersist) { [Environment]::SetEnvironmentVariable("IMAGE_API_URL", $ImageApiUrl, "User") }
}
if ($ImageApiKey) {
  $env:IMAGE_API_KEY = $ImageApiKey
  if (-not $NoPersist) { [Environment]::SetEnvironmentVariable("IMAGE_API_KEY", $ImageApiKey, "User") }
}
if ($ImageModel) {
  $env:IMAGE_MODEL = $ImageModel
  if (-not $NoPersist) { [Environment]::SetEnvironmentVariable("IMAGE_MODEL", $ImageModel, "User") }
}
if ($ImageSize) {
  $env:IMAGE_SIZE = $ImageSize
  if (-not $NoPersist) { [Environment]::SetEnvironmentVariable("IMAGE_SIZE", $ImageSize, "User") }
}
if ($ImageOutputFormat) {
  $env:IMAGE_OUTPUT_FORMAT = $ImageOutputFormat
  if (-not $NoPersist) { [Environment]::SetEnvironmentVariable("IMAGE_OUTPUT_FORMAT", $ImageOutputFormat, "User") }
}

if (-not $SkipDryRun) {
  $setupCheckDir = Join-Path $repoRoot "processed\setup-check"
  Write-Host ""
  Write-Host "Running request-plan dry run..."
  & (Join-Path $scriptDir "fetch-gnews.ps1") -DryRun -OutputDir $setupCheckDir
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "Next run fetches, filters, scores, and creates processed\generation-input.json:"
Write-Host "  .\scripts\run_pipeline.ps1"
Write-Host ""
Write-Host "Then let the model generate records.normalized.json from that input."
Write-Host "Dry-run the Lark payload after generation:"
Write-Host "  .\scripts\run_pipeline.ps1 -WriteExistingRecords"
Write-Host ""
Write-Host "Publish only after reviewing records.normalized.json:"
Write-Host "  .\scripts\run_pipeline.ps1 -WriteExistingRecords -Publish"
