#Requires -Version 5.1
<#
.SYNOPSIS
    Calibra un modelo de estimacion de esfuerzo, tiempo y costo tipo COCOMO II con datos SDD.

.DESCRIPTION
    Esfuerzo : PM   = A * Size^E * prod(EM)      (A y E se ajustan por regresion log-log)
    Tiempo   : TDEV = C * PM^F                    (C y F se ajustan por regresion log-log)
    Costo    : PM * horas_por_PM * tarifa  +  costo_IA_por_PM * PM

    Se ajusta una ecuacion por cada medida de tamano (KSLOC entregadas, Puntos de Tarea SDD finales
    y del plan, requisitos funcionales,
    escenarios de aceptacion, historias de usuario, tareas) y se elige la de menor error en
    validacion cruzada (dejando uno fuera). Tambien se compara con COCOMO II.2000 estandar.

    Con menos de 3 puntos el exponente E no se ajusta: se toma de COCOMO II (B + 0.01*sum(SF)).

    -Datos apunta a una carpeta consolidada (consolidar.ps1). Sin -Datos se usan los datos del
    proyecto actual (metricas/salidas y metricas/factores-cocomo.csv).

    Salidas: modelo-estimacion.json y reporte-calibracion.md en -Salida (por defecto metricas/salidas).
#>
[CmdletBinding()]
param(
    [string]$Datos,
    [ValidateSet('funcionalidad', 'proyecto')]
    [string]$Nivel = 'funcionalidad',
    [string]$Salida
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$cocomo = Get-Content -LiteralPath (Join-Path $script:ExtensionRoot 'datos/cocomo-ii-2000.json') -Raw | ConvertFrom-Json
$levels = @($cocomo.niveles)

# --- Carga de datos --------------------------------------------------------
if ($Datos) {
    $features = Import-CsvSafe (Join-Path $Datos 'funcionalidades.csv')
    $projects = Import-CsvSafe (Join-Path $Datos 'proyectos.csv')
    $factors  = Import-CsvSafe (Join-Path $Datos 'factores.csv')
    if (-not $Salida) { $Salida = $Datos }
} else {
    $dataDir = Get-DataDir (Get-RepoRoot)
    $features = Import-CsvSafe (Join-Path $dataDir 'salidas/resumen-funcionalidades.csv')
    $projects = Import-CsvSafe (Join-Path $dataDir 'salidas/resumen-proyecto.csv')
    $factors  = Import-CsvSafe (Join-Path $dataDir 'factores-cocomo.csv')
    if (-not $Salida) { $Salida = Join-Path $dataDir 'salidas' }
    if ($features.Count -eq 0) { throw 'No hay resumenes. Ejecute primero recolectar.ps1.' }
}

function Get-FactorRow([string]$project, [string]$feature) {
    return $factors | Where-Object { $_.proyecto -eq $project -and $_.funcionalidad -eq $feature } | Select-Object -First 1
}

function Get-Rating($row, $fallback, [string]$name) {
    foreach ($candidate in @($row, $fallback)) {
        if ($candidate -and $candidate.PSObject.Properties[$name] -and $candidate.$name) {
            return $candidate.$name.Trim().ToUpper()
        }
    }
    return 'N'
}

function Get-TableValue($table, [string]$name, [string]$rating) {
    $index = [array]::IndexOf($levels, $rating)
    $values = @($table.$name)
    if ($index -lt 0 -or $null -eq $values[$index]) {
        Write-Warning "Calificacion '$rating' no valida para $name; se usa N."
        $index = 2
    }
    return [double]$values[$index]
}

function Get-Drivers([string]$project, [string]$feature) {
    # Devuelve la suma de factores de escala y el producto de multiplicadores de un punto.
    $own = Get-FactorRow $project $feature
    $base = Get-FactorRow $project '000-proyecto'
    $sfSum = 0.0
    foreach ($name in $cocomo.factores_escala.PSObject.Properties.Name) {
        $sfSum += Get-TableValue $cocomo.factores_escala $name (Get-Rating $own $base $name)
    }
    $emProduct = 1.0
    foreach ($table in @($cocomo.multiplicadores, $cocomo.multiplicadores_sdd)) {
        foreach ($name in ($table.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' })) {
            # Los multiplicadores son propios de cada funcionalidad; sin calificacion valen N.
            $emProduct *= Get-TableValue $table $name (Get-Rating $own $null $name)
        }
    }
    return @{ sf = $sfSum; em = $emProduct; calificado = [bool]($own -or $base) }
}

# --- Puntos de datos -------------------------------------------------------
$sizeMeasures = [ordered]@{
    ksloc      = { param($r) (ConvertTo-Number $r.loc_sobrevivientes) / 1000 }
    requisitos = { param($r) ConvertTo-Number $r.requisitos_funcionales }
    escenarios = { param($r) ConvertTo-Number $r.escenarios_aceptacion }
    historias  = { param($r) ConvertTo-Number $r.historias_usuario }
    tareas     = { param($r) ConvertTo-Number $r.tareas }
    puntos_tarea      = { param($r) ConvertTo-Number $r.puntos_tarea }
    puntos_tarea_plan = { param($r) ConvertTo-Number $r.puntos_tarea_plan }
}

$source = if ($Nivel -eq 'proyecto') { $projects } else { @($features | Where-Object { $_.funcionalidad -ne '000-proyecto' }) }
$points = foreach ($row in $source) {
    $pm = ConvertTo-Number $row.persona_mes
    if (-not $pm -or $pm -le 0) { continue }
    $feature = if ($Nivel -eq 'proyecto') { '000-proyecto' } else { $row.funcionalidad }
    $drivers = Get-Drivers $row.proyecto $feature
    $point = [ordered]@{
        id = "$($row.proyecto)/$feature"; pm = $pm; tdev = ConvertTo-Number $row.tdev_meses
        costo_ia = ConvertTo-Number $row.costo_ia; sf = $drivers.sf; em = $drivers.em
    }
    foreach ($measure in $sizeMeasures.Keys) { $point[$measure] = & $sizeMeasures[$measure] $row }
    $point
}
$points = @($points)
Write-Host "Puntos de datos ($Nivel): $($points.Count)"
if ($points.Count -lt 2) { throw 'Se necesitan al menos 2 puntos con esfuerzo registrado para calibrar.' }

# --- Utilidades estadisticas -----------------------------------------------
function Fit-Line([double[]]$x, [double[]]$y) {
    $n = $x.Count
    $mx = ($x | Measure-Object -Average).Average
    $my = ($y | Measure-Object -Average).Average
    $sxy = 0.0; $sxx = 0.0; $syy = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sxy += ($x[$i] - $mx) * ($y[$i] - $my); $sxx += [math]::Pow($x[$i] - $mx, 2); $syy += [math]::Pow($y[$i] - $my, 2)
    }
    if ($sxx -eq 0) { return $null }
    $slope = $sxy / $sxx
    $r2 = if ($syy -gt 0) { [math]::Pow($sxy, 2) / ($sxx * $syy) } else { $null }
    return @{ intercept = $my - $slope * $mx; slope = $slope; r2 = $r2 }
}

function Fit-Effort($pts, [string]$measure, [double]$fixedE) {
    # Ajusta ln(PM/EM) = ln(A) + E*ln(Size). Con < 3 puntos fija E y solo ajusta A.
    $x = [double[]]@($pts | ForEach-Object { [math]::Log($_[$measure]) })
    $y = [double[]]@($pts | ForEach-Object { [math]::Log($_.pm / $_.em) })
    if ($pts.Count -ge 3) {
        $line = Fit-Line $x $y
        if ($line) { return @{ A = [math]::Exp($line.intercept); E = $line.slope; r2 = $line.r2; metodo = 'regresion' } }
    }
    $lnA = 0.0
    for ($i = 0; $i -lt $x.Count; $i++) { $lnA += $y[$i] - $fixedE * $x[$i] }
    return @{ A = [math]::Exp($lnA / $x.Count); E = $fixedE; r2 = $null; metodo = 'E fijo (COCOMO II)' }
}

function Get-Accuracy([double[]]$actual, [double[]]$predicted) {
    $mre = for ($i = 0; $i -lt $actual.Count; $i++) { [math]::Abs($actual[$i] - $predicted[$i]) / $actual[$i] }
    $mre = @($mre)
    return @{
        mmre   = [math]::Round(($mre | Measure-Object -Average).Average, 4)
        pred25 = [math]::Round(@($mre | Where-Object { $_ -le 0.25 }).Count / $mre.Count, 4)
    }
}

$c = $cocomo.constantes
$meanSf = ($points | ForEach-Object { $_.sf } | Measure-Object -Average).Average
$standardE = $c.B + 0.01 * $meanSf

# --- Esfuerzo: una ecuacion por medida de tamano ---------------------------
$effortModels = [ordered]@{}
foreach ($measure in $sizeMeasures.Keys) {
    $pts = @($points | Where-Object { $_[$measure] -gt 0 })
    if ($pts.Count -lt 2) { continue }
    $fit = Fit-Effort $pts $measure $standardE
    $actual = [double[]]@($pts | ForEach-Object { $_.pm })
    $predicted = [double[]]@($pts | ForEach-Object { $fit.A * [math]::Pow($_[$measure], $fit.E) * $_.em })
    $accuracy = Get-Accuracy $actual $predicted

    $loo = $null
    if ($pts.Count -ge 3) {
        $looPredicted = for ($i = 0; $i -lt $pts.Count; $i++) {
            $train = @(for ($j = 0; $j -lt $pts.Count; $j++) { if ($j -ne $i) { $pts[$j] } })
            $f = Fit-Effort $train $measure $standardE
            $f.A * [math]::Pow($pts[$i][$measure], $f.E) * $pts[$i].em
        }
        $loo = (Get-Accuracy $actual ([double[]]@($looPredicted))).mmre
    }
    $effortModels[[string]$measure] = [ordered]@{
        n = $pts.Count; A = [math]::Round($fit.A, 6); E = [math]::Round($fit.E, 4)
        r2 = if ($null -ne $fit.r2) { [math]::Round([double]$fit.r2, 4) } else { $null }
        metodo = $fit.metodo; mmre = $accuracy.mmre; pred25 = $accuracy.pred25; mmre_loocv = $loo
    }
}
if ($effortModels.Count -eq 0) { throw 'Ninguna medida de tamano tiene al menos 2 puntos con valor > 0.' }

$best = $effortModels.Keys | Sort-Object {
    $m = $effortModels[$_]; if ($null -ne $m.mmre_loocv) { $m.mmre_loocv } else { 10 + $m.mmre }
} | Select-Object -First 1

# COCOMO II.2000 estandar sobre KSLOC, como referencia.
$standard = $null
$ptsK = @($points | Where-Object { $_.ksloc -gt 0 })
if ($ptsK.Count -gt 0) {
    $actual = [double[]]@($ptsK | ForEach-Object { $_.pm })
    $predicted = [double[]]@($ptsK | ForEach-Object { $c.A * [math]::Pow($_.ksloc, $c.B + 0.01 * $_.sf) * $_.em })
    $standard = Get-Accuracy $actual $predicted
}

# --- Tiempo ----------------------------------------------------------------
$ptsT = @($points | Where-Object { $_.tdev -gt 0 })
$schedule = [ordered]@{ n = $ptsT.Count }
$line = if ($ptsT.Count -ge 3) {
    Fit-Line ([double[]]@($ptsT | ForEach-Object { [math]::Log($_.pm) })) ([double[]]@($ptsT | ForEach-Object { [math]::Log($_.tdev) }))
} else { $null }
if ($line) {
    $schedule.C = [math]::Round([math]::Exp($line.intercept), 4); $schedule.F = [math]::Round($line.slope, 4)
    $schedule.r2 = if ($null -ne $line.r2) { [math]::Round($line.r2, 4) } else { $null }; $schedule.metodo = 'regresion'
} else {
    $schedule.C = $c.C; $schedule.F = [math]::Round($c.D + 0.2 * ($effortModels[$best].E - $c.B), 4)
    $schedule.r2 = $null; $schedule.metodo = 'COCOMO II estandar (datos insuficientes)'
}
if ($ptsT.Count -gt 0) {
    $accuracy = Get-Accuracy ([double[]]@($ptsT | ForEach-Object { $_.tdev })) ([double[]]@($ptsT | ForEach-Object { $schedule.C * [math]::Pow($_.pm, $schedule.F) }))
    $schedule.mmre = $accuracy.mmre; $schedule.pred25 = $accuracy.pred25
}

# --- Costo, fases, desperdicio y sobrecarga transversal --------------------
$totalPm = ($points | ForEach-Object { $_.pm } | Measure-Object -Sum).Sum
$totalAi = ($points | ForEach-Object { [double]$_.costo_ia } | Measure-Object -Sum).Sum
$hoursPerPm = if ($projects.Count -gt 0) {
    ($projects | ForEach-Object { ConvertTo-Number $_.horas_por_persona_mes } | Where-Object { $_ } | Measure-Object -Average).Average
} else { $null }
if (-not $hoursPerPm) { $hoursPerPm = $c.horas_por_persona_mes }

$allHours = Sum-Column $features 'h_humano_total'
$phaseShare = [ordered]@{}
foreach ($phase in $script:Phases) {
    $phaseShare[[string]$phase] = if ($allHours -gt 0) { [math]::Round((Sum-Column $features "h_$phase") / $allHours, 4) } else { 0 }
}

$added = Sum-Column $features 'loc_agregadas'
$waste = [ordered]@{
    tasa_total     = if ($added -gt 0) { [math]::Round((Sum-Column $features 'loc_desperdicio_total') / $added, 4) } else { $null }
    tasa_requisito = if ($added -gt 0) { [math]::Round((Sum-Column $features 'loc_elim_requisito') / $added, 4) } else { $null }
    tasa_defecto   = if ($added -gt 0) { [math]::Round((Sum-Column $features 'loc_elim_defecto') / $added, 4) } else { $null }
}

$overheads = foreach ($group in ($features | Group-Object proyecto)) {
    $transversal = Sum-Column @($group.Group | Where-Object { $_.funcionalidad -eq '000-proyecto' }) 'h_humano_total'
    $own = Sum-Column @($group.Group | Where-Object { $_.funcionalidad -ne '000-proyecto' }) 'h_humano_total'
    if ($own -gt 0) { $transversal / $own }
}
$overhead = if (@($overheads).Count -gt 0) { [math]::Round((@($overheads) | Measure-Object -Average).Average, 4) } else { 0 }

$model = [ordered]@{
    generado            = (Get-Date).ToString('s')
    kit_version         = $script:KitVersion
    nivel               = $Nivel
    proyectos           = @($points | ForEach-Object { ($_.id -split '/')[0] } | Sort-Object -Unique)
    puntos              = $points.Count
    horas_por_persona_mes = [math]::Round($hoursPerPm, 2)
    esfuerzo            = $effortModels
    mejor_medida        = $best
    cocomo_ii_estandar  = $standard
    tiempo              = $schedule
    costo_ia_por_pm     = if ($totalPm -gt 0) { [math]::Round($totalAi / $totalPm, 2) } else { 0 }
    sobrecarga_transversal = $overhead
    distribucion_fases  = $phaseShare
    desperdicio         = $waste
}

# --- Salidas ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Salida)) { New-Item -ItemType Directory -Path $Salida | Out-Null }
$jsonPath = Join-Path $Salida 'modelo-estimacion.json'
$model | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Reporte de calibracion')
$md.Add('')
$md.Add("Generado: $($model.generado) | Nivel: $Nivel | Puntos: $($points.Count) | Proyectos: $($model.proyectos -join ', ')")
$md.Add('')
$md.Add('## Esfuerzo: PM = A * Size^E * prod(EM)')
$md.Add('')
$md.Add('| Medida | n | A | E | R2 | MMRE | PRED(25) | MMRE LOOCV | Metodo |')
$md.Add('|---|---|---|---|---|---|---|---|---|')
foreach ($m in $effortModels.Keys) {
    $e = $effortModels[$m]
    $mark = if ($m -eq $best) { " **(mejor)**" } else { '' }
    $md.Add("| $m$mark | $($e.n) | $($e.A) | $($e.E) | $($e.r2) | $($e.mmre) | $($e.pred25) | $($e.mmre_loocv) | $($e.metodo) |")
}
if ($standard) { $md.Add(''); $md.Add("COCOMO II.2000 estandar sobre KSLOC: MMRE $($standard.mmre), PRED(25) $($standard.pred25).") }
$md.Add('')
$md.Add("## Tiempo: TDEV = $($schedule.C) * PM^$($schedule.F)  ($($schedule.metodo), n = $($schedule.n))")
$md.Add('')
$md.Add('## Costo')
$md.Add('')
$md.Add("Costo = PM * $($model.horas_por_persona_mes) h * tarifa + $($model.costo_ia_por_pm) * PM (IA)")
$md.Add("Sobrecarga transversal (000-proyecto / funcionalidades): $overhead")
$md.Add('')
$md.Add('## Distribucion del esfuerzo por fase')
$md.Add('')
$md.Add('| Fase | % |')
$md.Add('|---|---|')
foreach ($p in $phaseShare.Keys) { if ($phaseShare[$p] -gt 0) { $md.Add("| $p | $([math]::Round($phaseShare[$p] * 100, 1)) |") } }
$md.Add('')
$md.Add("## Desperdicio de codigo: total $($waste.tasa_total), por requisito $($waste.tasa_requisito), por defecto $($waste.tasa_defecto)")
$md.Add('')
if ($points.Count -lt 10) { $md.Add('> Advertencia: menos de 10 puntos de datos; el modelo es exploratorio.') }
$mdPath = Join-Path $Salida 'reporte-calibracion.md'
[System.IO.File]::WriteAllText($mdPath, ($md -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))

$md | Out-Host
Write-Host "Modelo: $jsonPath"
