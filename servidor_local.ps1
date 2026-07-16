$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
$port = 8787
$url = "http://127.0.0.1:$port/"
$server = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $port)

$mime = @{
  '.html'='text/html; charset=utf-8'; '.js'='text/javascript; charset=utf-8'; '.mjs'='text/javascript; charset=utf-8';
  '.wasm'='application/wasm'; '.css'='text/css; charset=utf-8'; '.json'='application/json; charset=utf-8';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.svg'='image/svg+xml'; '.ico'='image/x-icon'
}

function Send-TextResponse($stream, [int]$status, [string]$statusText, [string]$text) {
  $body = [Text.Encoding]::UTF8.GetBytes($text)
  $header = "HTTP/1.1 $status $statusText`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
  $h = [Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($h,0,$h.Length)
  $stream.Write($body,0,$body.Length)
}

try {
  $server.Start()
} catch {
  Write-Host "No fue posible iniciar el servidor local en $url" -ForegroundColor Red
  Write-Host $_.Exception.Message
  Read-Host "Pulse Enter para cerrar"
  exit 1
}

Write-Host "NORMALIZADOR DE VIDEO" -ForegroundColor Cyan
Write-Host "La aplicación está disponible en $url" -ForegroundColor Green
Write-Host "No cierre esta ventana mientras use la aplicación." -ForegroundColor Yellow
Start-Process $url

try {
  while ($true) {
    $client = $server.AcceptTcpClient()
    $stream = $client.GetStream()
    try {
      $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 4096, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }
      do { $line = $reader.ReadLine() } while ($null -ne $line -and $line -ne '')

      $parts = $requestLine.Split(' ')
      if ($parts.Length -lt 2 -or ($parts[0] -ne 'GET' -and $parts[0] -ne 'HEAD')) {
        Send-TextResponse $stream 405 'Method Not Allowed' 'Método no permitido'
        continue
      }

      $rawPath = $parts[1].Split('?')[0]
      $path = [Uri]::UnescapeDataString($rawPath.TrimStart('/'))
      if ([string]::IsNullOrWhiteSpace($path)) { $path = 'index.html' }
      $candidate = [IO.Path]::GetFullPath((Join-Path $root $path.Replace('/', [IO.Path]::DirectorySeparatorChar)))

      if (-not $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        Send-TextResponse $stream 403 'Forbidden' 'Ruta no permitida'
        continue
      }
      if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        Send-TextResponse $stream 404 'Not Found' 'Archivo no encontrado'
        continue
      }

      $info = Get-Item -LiteralPath $candidate
      $ext = $info.Extension.ToLowerInvariant()
      $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $header = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($info.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
      $h = [Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($h,0,$h.Length)

      if ($parts[0] -eq 'GET') {
        $fileStream = [IO.File]::OpenRead($candidate)
        try { $fileStream.CopyTo($stream) } finally { $fileStream.Dispose() }
      }
    } catch {
      try { Send-TextResponse $stream 500 'Internal Server Error' $_.Exception.Message } catch {}
    } finally {
      try { $stream.Dispose() } catch {}
      try { $client.Close() } catch {}
    }
  }
} finally {
  $server.Stop()
}
