#Requires -Version 5.1
<#
.SYNOPSIS
    Empaqueta el dataset de metricas del proyecto para compartirlo y consolidarlo con otros.

.DESCRIPTION
    Ejecuta recolectar.ps1 y genera metricas/salidas/dataset-<proyecto>-<fecha>.zip con:
      proyecto.json               metadatos de config.json (sin rutas ni patrones)
      resumen-proyecto.csv, resumen-funcionalidades.csv, factores-cocomo.csv
      registro-esfuerzo.csv        todas las sesiones de metricas/sesiones/ en un solo archivo

    -Anonimizar reemplaza el nombre del desarrollador por un hash y elimina las columnas de texto
    libre (actividad, notas) y la descripcion del proyecto.
#>
[CmdletBinding()]
param(
    [switch]$Anonimizar
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$repoRoot = Get-RepoRoot
$dataDir  = Get-DataDir $repoRoot
Import-MetricsConfig $dataDir

& (Join-Path $PSScriptRoot 'recolectar.ps1') | Out-Null

function Get-ShortHash([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:ProjectName + '|' + $text))
    return 'dev-' + (($bytes[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
}

$stamp = (Get-Date).ToString('yyyyMMdd')
$safeName = $script:ProjectName -replace '[^A-Za-z0-9_-]', '_'
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "dataset-$safeName-$stamp-$PID"
New-Item -ItemType Directory -Path $staging | Out-Null

try {
    $metadata = [ordered]@{
        proyecto        = $script:ProjectName
        descripcion     = if ($Anonimizar) { '' } else { $script:Config.descripcion }
        dominio         = $script:Config.dominio
        tipo_aplicacion = $script:Config.tipo_aplicacion
        metodologia     = $script:Config.metodologia
        herramienta_sdd = $script:Config.herramienta_sdd
        tamano_equipo   = $script:Config.tamano_equipo
        moneda          = $script:Config.moneda
        costo_hora_humano     = $script:HourlyCost
        horas_por_persona_mes = $script:HoursPerPM
        kit_version     = $script:KitVersion
        anonimizado     = [bool]$Anonimizar
        fecha_exportacion = (Get-Date).ToString('yyyy-MM-dd')
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $staging 'proyecto.json') -Encoding UTF8

    foreach ($name in @('resumen-proyecto.csv', 'resumen-funcionalidades.csv')) {
        Copy-Item -LiteralPath (Join-Path $dataDir "salidas/$name") -Destination $staging
    }
    $factors = Join-Path $dataDir 'factores-cocomo.csv'
    if (Test-Path -LiteralPath $factors) { Copy-Item -LiteralPath $factors -Destination $staging }

    $sessions = Import-Sessions $dataDir
    if ($Anonimizar) {
        foreach ($s in $sessions) {
            $s.desarrollador = Get-ShortHash $s.desarrollador
            $s.actividad = ''
            $s.notas = ''
        }
    }
    Write-CsvFile (Join-Path $staging 'registro-esfuerzo.csv') $sessions $script:LogColumns

    $outDir = Join-Path $dataDir 'salidas'
    $zip = Join-Path $outDir "dataset-$safeName-$stamp.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
    Write-Host "Dataset exportado: $zip"
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
