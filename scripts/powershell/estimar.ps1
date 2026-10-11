#Requires -Version 5.1
<#
.SYNOPSIS
    Estima esfuerzo, tiempo y costo de una funcionalidad o proyecto con un modelo calibrado.

.EXAMPLE
    ./estimar.ps1 -Tamano 12 -Medida requisitos -Factores "CPLX=H;PCAP=VH;AIAS=VH" -CostoHora 25
    ./estimar.ps1 -Tamano 60 -Medida requisitos -IncluirTransversal -Modelo consolidado/modelo-estimacion.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [double]$Tamano,
    [string]$Medida,
    [string]$Modelo,
    [string]$Factores = '',
    [double]$CostoHora = -1,
    [switch]$IncluirTransversal
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

if (-not $Modelo -or $CostoHora -lt 0) {
    $dataDir = Get-DataDir (Get-RepoRoot)
    if (-not $Modelo) { $Modelo = Join-Path $dataDir 'salidas/modelo-estimacion.json' }
    if ($CostoHora -lt 0) { Import-MetricsConfig $dataDir; $CostoHora = $script:HourlyCost }
}
if (-not (Test-Path -LiteralPath $Modelo)) { throw "No se encontro el modelo $Modelo. Ejecute calibrar.ps1." }
$model = Get-Content -LiteralPath $Modelo -Raw -Encoding UTF8 | ConvertFrom-Json
$cocomo = Get-Content -LiteralPath (Join-Path $script:ExtensionRoot 'datos/cocomo-ii-2000.json') -Raw | ConvertFrom-Json
$levels = @($cocomo.niveles)

if (-not $Medida) { $Medida = $model.mejor_medida }
$equation = $model.esfuerzo.$Medida
if (-not $equation) {
    throw "El modelo no tiene la medida '$Medida'. Disponibles: $($model.esfuerzo.PSObject.Properties.Name -join ', ')"
}

$em = 1.0
foreach ($pair in ($Factores -split '[;,]' | Where-Object { $_.Trim() })) {
    $name, $rating = $pair.Split('=') | ForEach-Object { $_.Trim().ToUpper() }
    $table = if ($cocomo.multiplicadores.PSObject.Properties[$name]) { $cocomo.multiplicadores }
             elseif ($cocomo.multiplicadores_sdd.PSObject.Properties[$name]) { $cocomo.multiplicadores_sdd }
             else { throw "Multiplicador desconocido: $name" }
    $value = @($table.$name)[[array]::IndexOf($levels, $rating)]
    if ($null -eq $value -or [array]::IndexOf($levels, $rating) -lt 0) { throw "Calificacion no valida: $name=$rating" }
    $em *= [double]$value
}

$pm = $equation.A * [math]::Pow($Tamano, $equation.E) * $em
if ($IncluirTransversal) { $pm *= 1 + $model.sobrecarga_transversal }
$hours = $pm * $model.horas_por_persona_mes
$tdev = $model.tiempo.C * [math]::Pow($pm, $model.tiempo.F)
$humanCost = $hours * $CostoHora
$aiCost = $pm * $model.costo_ia_por_pm
$relError = if ($null -ne $equation.mmre_loocv) { $equation.mmre_loocv } else { $equation.mmre }

Write-Host ("Modelo: {0} | medida {1} (n = {2}, MMRE {3})" -f $Modelo, $Medida, $equation.n, $relError)
Write-Host ("Tamano: {0} {1} | producto EM: {2:N3}" -f $Tamano, $Medida, $em)
Write-Host ''
Write-Host ("Esfuerzo : {0:N3} PM  ({1:N1} h)   rango orientativo {2:N1} - {3:N1} h" -f $pm, $hours,
    ($hours * [math]::Max(0.0, 1.0 - $relError)), ($hours * (1 + $relError)))
Write-Host ("Tiempo   : {0:N2} meses calendario" -f $tdev)
Write-Host ("Costo    : {0:N2} humano + {1:N2} IA = {2:N2}" -f $humanCost, $aiCost, ($humanCost + $aiCost))
Write-Host ''
Write-Host 'Horas por fase:'
foreach ($phase in $model.distribucion_fases.PSObject.Properties) {
    if ($phase.Value -gt 0) { Write-Host ("  {0,-22} {1,8:N1} h" -f $phase.Name, ($hours * $phase.Value)) }
}
