#Requires -Version 5.1
<#
.SYNOPSIS
    Crea la carpeta de datos de metricas (metricas/) en el repositorio actual.

.DESCRIPTION
    Copia las plantillas config.json y factores-cocomo.csv, crea sesiones/historico.csv vacio
    y agrega al .gitignore el estado de sesion local y las salidas regenerables.
    No sobrescribe archivos existentes.

.EXAMPLE
    pwsh -File .specify/extensions/metricas/scripts/powershell/inicializar.ps1 -Proyecto MiApp
#>
[CmdletBinding()]
param(
    [string]$Proyecto
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$repoRoot = Get-RepoRoot
$dataDir = Get-DataDir $repoRoot
$templates = Join-Path $script:ExtensionRoot 'plantillas'
if (-not $Proyecto) { $Proyecto = Split-Path -Leaf $repoRoot }

$sddTool = 'GitHub Spec Kit'
$initOptions = Join-Path $repoRoot '.specify/init-options.json'
if (Test-Path -LiteralPath $initOptions) {
    $options = Get-Content -LiteralPath $initOptions -Raw | ConvertFrom-Json
    if ($options.speckit_version) { $sddTool = "GitHub Spec Kit $($options.speckit_version)" }
}

if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Copy-Template([string]$name) {
    $target = Join-Path $dataDir $name
    if (Test-Path -LiteralPath $target) { Write-Host "Se conserva $name existente"; return }
    $text = [System.IO.File]::ReadAllText((Join-Path $templates $name), [System.Text.Encoding]::UTF8)
    $text = $text.Replace('__PROYECTO__', $Proyecto).Replace('__HERRAMIENTA_SDD__', $sddTool)
    [System.IO.File]::WriteAllText($target, $text, $utf8)
    Write-Host "Creado $name"
}

Copy-Template 'config.json'
Copy-Template 'factores-cocomo.csv'

$sessionsDir = Get-SessionsDir $dataDir
if (-not (Test-Path -LiteralPath $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir | Out-Null
    # Plantilla para registrar a mano sesiones previas o sin Git (una fila por sesion).
    [System.IO.File]::WriteAllText((Join-Path $sessionsDir 'historico.csv'), ($script:LogColumns -join ',') + "`n", $utf8)
    Write-Host 'Creado sesiones/historico.csv'
}

$relative = (Resolve-Path -LiteralPath $dataDir).Path.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
$ignoreFile = Join-Path $repoRoot '.gitignore'
$ignoreLines = @("$relative/.sesion-activa.json", "$relative/.ultima-actividad", "$relative/salidas/")
$existing = if (Test-Path -LiteralPath $ignoreFile) { Get-Content -LiteralPath $ignoreFile } else { @() }
$missing = @($ignoreLines | Where-Object { $existing -notcontains $_ })
if ($missing.Count -gt 0) {
    $block = "`n# speckit-metricas: estado de sesion local y salidas regenerables`n" + ($missing -join "`n") + "`n"
    [System.IO.File]::AppendAllText($ignoreFile, $block, $utf8)
    Write-Host 'Actualizado .gitignore'
}

Write-Host "Metricas inicializadas en $relative/. Complete descripcion, dominio, costo_hora_humano en config.json."
