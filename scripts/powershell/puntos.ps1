#Requires -Version 5.1
<#
.SYNOPSIS
    Calcula los Puntos de Tarea SDD (PTS) de una funcionalidad a partir de su tasks.md.

.DESCRIPTION
    Crea o actualiza specs/NNN-*/puntos-tarea.csv:
      - la primera ejecucion fija la linea base del plan (origen = plan) con una clasificacion
        heuristica de tipo y complejidad, que el agente o la persona debe revisar;
      - las ejecuciones siguientes conservan la clasificacion existente, agregan las tareas nuevas
        (origen = agregada), marcan las desaparecidas (eliminada = si) y recalculan los puntos.
    Para corregir una clasificacion, edite las columnas tipo y complejidad, ponga
    clasificado_por = agente o humano, y vuelva a ejecutar este script.

.EXAMPLE
    ./puntos.ps1                       # funcionalidad de la rama actual
    ./puntos.ps1 -Funcionalidad 002-catalogo
#>
[CmdletBinding()]
param(
    [string]$Funcionalidad
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$repoRoot = Get-RepoRoot
$specsName = 'specs'
$configPath = Join-Path (Get-DataDir $repoRoot) 'config.json'
if (Test-Path -LiteralPath $configPath) { Import-MetricsConfig (Get-DataDir $repoRoot); $specsName = $script:SpecsDirName }

if (-not $Funcionalidad) { $Funcionalidad = Get-CurrentFeature $repoRoot }
if ($Funcionalidad -eq '000-proyecto') { throw 'No hay una funcionalidad activa: indique -Funcionalidad NNN-nombre.' }
$featureDir = Join-Path (Join-Path $repoRoot $specsName) $Funcionalidad
if (-not (Test-Path -LiteralPath (Join-Path $featureDir 'tasks.md'))) { throw "No existe $featureDir/tasks.md." }

$rows = Merge-TaskPoints $featureDir
Write-CsvFile (Join-Path $featureDir 'puntos-tarea.csv') $rows $script:TaskPointColumns
$summary = Get-TaskPointsSummary $rows

$rows | Where-Object { $_.eliminada -eq 'no' } | ForEach-Object { [pscustomobject]$_ } |
    Format-Table tarea, tipo, complejidad, puntos, clasificado_por, origen, descripcion -AutoSize | Out-Host
Write-Host ("PTS {0}: {1} (plan {2}, agregados {3}, eliminados {4})" -f $Funcionalidad, $summary.puntos_tarea,
    $summary.puntos_tarea_plan, $summary.puntos_agregados, $summary.puntos_eliminados)
if ($summary.tareas_heuristicas -gt 0) {
    Write-Warning "$($summary.tareas_heuristicas) tareas tienen clasificacion heuristica: revise tipo y complejidad en puntos-tarea.csv."
}
