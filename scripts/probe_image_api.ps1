param(
  [string]$ImageApiUrl = $env:IMAGE_API_URL,
  [string]$ImageApiKey = $env:IMAGE_API_KEY,
  [string]$ImageModel = "gpt-image-2",
  [string]$ImageSize = "1536x1024",
  [string]$Prompt = "Professional editorial photograph of a rocket launch at dusk, 16:9, no text, no watermark, no logo."
)

$ErrorActionPreference = "Stop"

if (-not $ImageApiUrl -or $ImageApiUrl -notmatch "^https?://") {
  throw "Image API URL is required. Set IMAGE_API_URL or pass -ImageApiUrl."
}

$headers = @{
  "Content-Type" = "application/json"
}
if ($ImageApiKey) {
  $headers["Authorization"] = "Bearer $ImageApiKey"
}

$body = @{
  model = $ImageModel
  prompt = $Prompt
  size = $ImageSize
} | ConvertTo-Json -Depth 5

try {
  $response = Invoke-WebRequest -Uri $ImageApiUrl -Method Post -Headers $headers -Body $body -TimeoutSec 120
  Write-Output $response.Content
} catch {
  if ($_.Exception.Response) {
    $stream = $_.Exception.Response.GetResponseStream()
    if ($stream) {
      $reader = New-Object System.IO.StreamReader($stream)
      try {
        $content = $reader.ReadToEnd()
        if ($content) {
          Write-Output $content
        }
      } finally {
        $reader.Close()
      }
    }
  }
  throw
}
