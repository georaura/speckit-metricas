#Requires -Version 5.1
<#
.SYNOPSIS
    Recolecta metricas de tamano, duracion, esfuerzo, costo y desperdicio del proyecto.

.DESCRIPTION
    Escribe en metricas/salidas/:
      resumen-funcionalidades.csv  una fila por funcionalidad (000-proyecto y specs/NNN-*)
      resumen-proyecto.csv         una fila con los totales del proyecto

    Por funcionalidad calcula:
      - tamano de especificacion (historias, FR, SC, escenarios, aclaraciones)
      - tamano de plan (tareas, completadas, paralelas, contratos)
      - lineas generadas y eliminadas por causa (commits con ambito "(NNN)")
      - lineas sobrevivientes en HEAD (git blame) y desperdicio total
      - duracion calendario (primer y ultimo commit)
      - esfuerzo humano por fase, modelos de IA usados y costo (metricas/sesiones/)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$repoRoot = Get-RepoRoot
$dataDir  = Get-DataDir $repoRoot
Import-MetricsConfig $dataDir
$specsDir = Join-Path $repoRoot $script:SpecsDirName
$outDir   = Join-Path $dataDir 'salidas'
$daysPerMonth = 30.42

function Count-Matches([string]$text, [string]$pattern) {
    if (-not $text) { return 0 }
    return ([regex]::Matches($text, $pattern, 'Multiline, IgnoreCase')).Count
}

function Read-Text([string]$path) {
    if (Test-Path -LiteralPath $path) {
        return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }
    return ''
}

function Get-FeatureOfCommit {
    # Mapa sha -> numero de funcionalidad segun el ambito "(NNN)" del asunto del commit.
    $map = @{}
    foreach ($line in (git -C $repoRoot log --all --format='%H %s')) {
        $sha, $subject = $line -split ' ', 2
        $map[$sha] = if ($subject -match '^\w+\((\d{3})\)') { $Matches[1] } else { '000' }
    }
    return $map
}

function Get-SurvivingLines($featureOfCommit) {
    # Cuenta, por funcionalidad, las lineas de codigo de produccion presentes en HEAD.
    $surviving = @{}
    foreach ($file in (git -C $repoRoot -c core.quotepath=off ls-files)) {
        if ((Get-FileKind $file) -ne 'codigo') { continue }
        foreach ($line in (git -C $repoRoot blame --line-porcelain HEAD -- $file)) {
            if ($line -match '^([0-9a-f]{40}) \d+ \d+') {
                $feature = $featureOfCommit[$Matches[1]]
                if (-not $feature) { $feature = '000' }
                $surviving[$feature] = 1 + [int]$surviving[$feature]
            }
        }
    }
    return $surviving
}

function Get-CalendarStats([string[]]$dates) {
    $dates = @($dates | Where-Object { $_ } | Sort-Object -Unique)
    if ($dates.Count -eq 0) { return [ordered]@{ primer_commit = ''; ultimo_commit = ''; dias_calendario = 0 } }
    return [ordered]@{
        primer_commit   = $dates[0]
        ultimo_commit   = $dates[-1]
        dias_calendario = ([datetime]$dates[-1] - [datetime]$dates[0]).Days + 1
    }
}

function Add-WasteColumns([System.Collections.IDictionary]$row, $loc, [int]$survivingLines) {
    foreach ($key in $loc.Keys) { $row[$key] = $loc[$key] }
    $row['loc_desperdicio_declarado'] = $loc.loc_elim_requisito + $loc.loc_elim_defecto
    $row['loc_sobrevivientes'] = $survivingLines
    $row['loc_desperdicio_total'] = [math]::Max(0, $loc.loc_agregadas - $survivingLines)
    $row['tasa_desperdicio'] = if ($loc.loc_agregadas -gt 0) {
        [math]::Round($row['loc_desperdicio_total'] / $loc.loc_agregadas, 4)
    } else { '' }
}

function Add-EffortColumns([System.Collections.IDictionary]$row, $entries) {
    $total = 0.0
    foreach ($phase in $script:Phases) {
        $hours = Sum-Column @($entries | Where-Object { $_.fase -eq $phase }) 'horas_humano'
        $row["h_$phase"] = $hours
        $total += $hours
    }
    $aiCost = Sum-Column $entries 'costo_usd'
    $row['h_humano_total']     = $total
    $row['h_retrabajo']        = Sum-Column @($entries | Where-Object { $_.retrabajo -eq 'si' }) 'horas_humano'
    $row['h_agente_total']     = Sum-Column $entries 'horas_agente'
    $row['tokens']             = Sum-Column $entries 'tokens'
    $row['persona_mes']        = [math]::Round($total / $script:HoursPerPM, 4)
    $row['tdev_meses']         = [math]::Round($row['dias_calendario'] / $daysPerMonth, 3)
    $row['costo_humano']       = [math]::Round($total * $script:HourlyCost, 2)
    $row['costo_ia']           = [math]::Round($aiCost, 2)
    $row['costo_total']        = [math]::Round($total * $script:HourlyCost + $aiCost, 2)
    # Modelo y nivel de razonamiento juntos: el mismo modelo con otro nivel es otra configuracion.
    $row['modelos_ia']         = (@($entries | Where-Object { $_.modelo_ia -and $_.modelo_ia -ne 'ninguno' } |
                                    ForEach-Object { if ($_.nivel_razonamiento) { "$($_.modelo_ia):$($_.nivel_razonamiento)" } else { $_.modelo_ia } } |
                                    Select-Object -Unique) -join ';')
    $row['sesiones']           = $entries.Count
    $row['sesiones_sin_horas'] = @($entries | Where-Object { [string]::IsNullOrWhiteSpace($_.horas_humano) }).Count
}

# --- Esfuerzo registrado ---------------------------------------------------
$effort = Import-Sessions $dataDir
$unknownPhases = @($effort | Where-Object { $_.fase -and ($script:Phases -notcontains $_.fase) } |
                   Select-Object -ExpandProperty fase -Unique)
if ($unknownPhases.Count -gt 0) {
    Write-Warning "Fases no reconocidas en el registro: $($unknownPhases -join ', ')"
}

# --- Por funcionalidad -----------------------------------------------------
$features = @('000-proyecto')
if (Test-Path -LiteralPath $specsDir) {
    $features += @(Get-ChildItem -LiteralPath $specsDir -Directory |
                   Where-Object { $_.Name -match '^\d{3}-' } |
                   Sort-Object Name | Select-Object -ExpandProperty Name)
}

$surviving = Get-SurvivingLines (Get-FeatureOfCommit)

$rows = @(foreach ($feature in $features) {
    $number = $feature.Substring(0, 3)
    $dir = Join-Path $specsDir $feature
    $spec  = Read-Text (Join-Path $dir 'spec.md')
    $tasks = Read-Text (Join-Path $dir 'tasks.md')
    $contractsDir = Join-Path $dir 'contracts'

    $row = [ordered]@{
        proyecto               = $script:ProjectName
        funcionalidad          = $feature
        historias_usuario      = Count-Matches $spec '^#{2,4}\s*(User Story|Historia de usuario)\s*\d+'
        requisitos_funcionales = Count-Matches $spec '^\s*-\s*\*\*FR-\d+'
        criterios_exito        = Count-Matches $spec '^\s*-\s*\*\*SC-\d+'
        escenarios_aceptacion  = Count-Matches $spec '\*\*(Given|Dado)\*\*'
        aclaraciones_abiertas  = Count-Matches $spec 'NEEDS CLARIFICATION'
        tareas                 = Count-Matches $tasks '^\s*-\s*\[[ xX]\]\s*T\d+'
        tareas_completadas     = Count-Matches $tasks '^\s*-\s*\[[xX]\]\s*T\d+'
        tareas_paralelas       = Count-Matches $tasks '^\s*-\s*\[[ xX]\]\s*T\d+\s*\[P\]'
        contratos              = if (Test-Path -LiteralPath $contractsDir) { @(Get-ChildItem -LiteralPath $contractsDir -File).Count } else { 0 }
    }
    $taskPoints = Get-TaskPointsSummary @(if ($tasks) { Merge-TaskPoints $dir })
    foreach ($key in $taskPoints.Keys) { $row[$key] = $taskPoints[$key] }

    $dates = @(git -C $repoRoot log --all -F "--grep=($number)" --format=%ad --date=short)
    $dates += @(git -C $repoRoot log --all --format=%ad --date=short -- "$($script:SpecsDirName)/$number-*")
    $calendar = Get-CalendarStats $dates
    foreach ($key in $calendar.Keys) { $row[$key] = $calendar[$key] }

    Add-WasteColumns $row (Get-LocSummary $repoRoot @('--all', '-F', "--grep=($number)")) ([int]$surviving[$number])
    Add-EffortColumns $row @($effort | Where-Object { $_.funcionalidad -eq $feature })
    $row
})

# --- Proyecto completo -----------------------------------------------------
$project = [ordered]@{
    proyecto          = $script:ProjectName
    dominio           = $script:Config.dominio
    tipo_aplicacion   = $script:Config.tipo_aplicacion
    metodologia       = $script:Config.metodologia
    herramienta_sdd   = $script:Config.herramienta_sdd
    tamano_equipo     = $script:Config.tamano_equipo
    moneda            = $script:Config.moneda
    costo_hora_humano = $script:HourlyCost
    horas_por_persona_mes = $script:HoursPerPM
    fecha_corte       = (Get-Date).ToString('yyyy-MM-dd')
    kit_version       = $script:KitVersion
    funcionalidades   = @($rows | Where-Object { $_.funcionalidad -ne '000-proyecto' }).Count
}
foreach ($column in @('historias_usuario', 'requisitos_funcionales', 'criterios_exito', 'escenarios_aceptacion',
                      'puntos_tarea', 'puntos_tarea_plan', 'puntos_agregados', 'puntos_eliminados',
                      'tareas', 'tareas_completadas', 'contratos')) {
    $project[$column] = ($rows | ForEach-Object { $_[$column] } | Measure-Object -Sum).Sum
}
$calendar = Get-CalendarStats @(git -C $repoRoot log --all --format=%ad --date=short)
foreach ($key in $calendar.Keys) { $project[$key] = $calendar[$key] }
$totalSurviving = [int](($surviving.Values | Measure-Object -Sum).Sum)
Add-WasteColumns $project (Get-LocSummary $repoRoot @('--all')) $totalSurviving
Add-EffortColumns $project $effort

# --- Salidas ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
Write-CsvFile (Join-Path $outDir 'resumen-funcionalidades.csv') $rows @($rows[0].Keys)
Write-CsvFile (Join-Path $outDir 'resumen-proyecto.csv') @($project) @($project.Keys)

$rows | ForEach-Object { [pscustomobject]$_ } |
    Format-Table funcionalidad, requisitos_funcionales, tareas, puntos_tarea, loc_agregadas, loc_sobrevivientes,
                 loc_desperdicio_total, h_humano_total, costo_total, modelos_ia -AutoSize | Out-Host
Write-Host ("Proyecto {0}: {1} PM, {2} meses, {3} {4}, {5} lineas entregadas" -f $project.proyecto,
    $project.persona_mes, $project.tdev_meses, $project.costo_total, $project.moneda, $project.loc_sobrevivientes)
Write-Host "Resumenes escritos en $outDir"

if ($project.sesiones_sin_horas -gt 0) {
    Write-Warning "$($project.sesiones_sin_horas) sesiones del registro no tienen horas_humano. Completarlas en los archivos de metricas/sesiones/."
}
