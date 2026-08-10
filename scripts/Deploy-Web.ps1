[CmdletBinding()]
param(
    [switch]$Preview,
    [string]$Project = "zawarudo"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot "build\web"

& (Join-Path $PSScriptRoot "Export-Web.ps1")

$vercelCommand = Get-Command vercel.cmd -CommandType Application -ErrorAction SilentlyContinue
if (-not $vercelCommand) {
    throw "Vercel CLI no esta instalado. Ejecuta: npm install -g vercel"
}

$ErrorActionPreference = "Continue"
& $vercelCommand.Source project inspect $Project 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creando el proyecto '$Project' en el scope actual de Vercel..."
    & $vercelCommand.Source project add $Project 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo crear el proyecto '$Project' en Vercel."
    }
}

$arguments = @(
    "--cwd", $outputDirectory,
    "deploy",
    "--yes",
    "--project", $Project
)
if (-not $Preview) {
    $arguments += "--prod"
}

$target = if ($Preview) { "preview" } else { "produccion" }
Write-Host "Publicando '$Project' en Vercel ($target)..."
& $vercelCommand.Source @arguments 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    throw "Vercel no pudo completar el deploy (codigo $LASTEXITCODE)."
}
