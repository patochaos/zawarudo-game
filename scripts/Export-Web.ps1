[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot "build\web"
$indexPath = Join-Path $outputDirectory "index.html"
$vercelConfig = Join-Path $projectRoot "deploy\vercel\vercel.json"
$orientationHeadPath = Join-Path $projectRoot "deploy\vercel\mobile-orientation-head.html"

$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
if ($godotCommand) {
    $godot = $godotCommand.Source
} elseif (Test-Path "D:\Godot\godot.cmd") {
    $godot = "D:\Godot\godot.cmd"
} else {
    throw "Godot no esta en PATH ni en D:\Godot\godot.cmd."
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Write-Host "Exportando ZAWARUDO para Web..."
& $godot --headless --path $projectRoot --export-release "Web" $indexPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot no pudo generar el export Web (codigo $LASTEXITCODE)."
}

$indexHtml = [IO.File]::ReadAllText($indexPath)
$orientationHead = [IO.File]::ReadAllText($orientationHeadPath)
if (-not $indexHtml.Contains("</head>")) {
    throw "El export Web no contiene una etiqueta </head> donde instalar la orientacion mobile."
}
$indexHtml = $indexHtml.Replace("</head>", "$orientationHead`r`n</head>")
[IO.File]::WriteAllText($indexPath, $indexHtml, [Text.UTF8Encoding]::new($false))

Copy-Item -LiteralPath $vercelConfig -Destination (Join-Path $outputDirectory "vercel.json") -Force

$requiredFiles = @("index.html", "index.js", "index.pck", "index.wasm")
foreach ($fileName in $requiredFiles) {
    $filePath = Join-Path $outputDirectory $fileName
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Falta un archivo requerido del export: $fileName"
    }
}

$vercelHobbyFileLimit = 100MB
$oversizedFiles = Get-ChildItem -LiteralPath $outputDirectory -File |
    Where-Object { $_.Length -gt $vercelHobbyFileLimit }
if ($oversizedFiles) {
    $names = ($oversizedFiles.Name -join ", ")
    throw "Estos archivos superan el limite de 100 MB de Vercel Hobby: $names"
}

$totalBytes = (Get-ChildItem -LiteralPath $outputDirectory -File |
    Measure-Object -Property Length -Sum).Sum
$totalMiB = [math]::Round($totalBytes / 1MB, 1)
$wasmMiB = [math]::Round((Get-Item -LiteralPath (Join-Path $outputDirectory "index.wasm")).Length / 1MB, 1)

Write-Host "Build web lista: $outputDirectory"
Write-Host "Tamano total: $totalMiB MiB (WASM: $wasmMiB MiB)"
