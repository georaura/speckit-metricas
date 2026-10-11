#Requires -Version 5.1
<#
.SYNOPSIS
    Registra sesiones de trabajo: esfuerzo, modelo de IA y lineas de codigo generadas/eliminadas.

.DESCRIPTION
    iniciar  : abre una sesion (hora, commit de partida, herramienta y modelo de IA)
    cambiar  : cierra la sesion activa (si existe) y abre otra; lo usan los hooks before_* de Spec Kit
    estado   : muestra la sesion activa y las lineas acumuladas
    cerrar   : cuenta lineas commit a commit desde el inicio, clasifica las eliminaciones por el
               trailer "Causa:" y guarda la sesion en metricas/sesiones/ (un archivo por sesion)
    cancelar : descarta la sesion activa sin registrarla
    pausar   : detiene el conteo de tiempo de la sesion activa (la persona deja de trabajar)
    reanudar : vuelve a contar el tiempo; las pausas se descuentan de las horas al cerrar.
    actividad: registra actividad (lo llaman los hooks del agente). Si desde la ultima actividad paso
               mas que minutos_inactividad_pausa (config.json, 30 por defecto), ese hueco se descuenta
               como pausa automatica (p. ej. se agoto el limite de uso del agente).
               Cerrar o cambiar de sesion estando en pausa termina la pausa en ese momento.

    La funcionalidad se toma de la rama NNN-nombre (o SPECIFY_FEATURE); fuera de una rama de
    funcionalidad se usa 000-proyecto. Solo se cuentan cambios confirmados (commits).
    Herramienta, modelo, nivel de razonamiento y version pueden fijarse con METRICAS_HERRAMIENTA,
    METRICAS_MODELO_IA, METRICAS_NIVEL_RAZONAMIENTO y
    METRICAS_VERSION_HERRAMIENTA.

.EXAMPLE
    ./sesion.ps1 iniciar -Fase implementar -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium
    ./sesion.ps1 cambiar -Evento before_plan -Herramienta antigravity -ModeloIA gemini-3-pro
    ./sesion.ps1 cerrar -Actividad "Visor equirectangular" -PausaMinutos 15 -Tokens 180000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('iniciar', 'cambiar', 'cerrar', 'estado', 'cancelar', 'pausar', 'reanudar', 'actividad')]
    [string]$Accion,
    [string]$Funcionalidad,
    [string]$Fase,
    [string]$Evento,
    [string]$Herramienta = $env:METRICAS_HERRAMIENTA,
    [string]$ModeloIA = $env:METRICAS_MODELO_IA,
    [string]$NivelRazonamiento = $env:METRICAS_NIVEL_RAZONAMIENTO,
    [string]$VersionHerramienta = $env:METRICAS_VERSION_HERRAMIENTA,
    [string]$Actividad,
    [double]$Horas = -1,
    [int]$PausaMinutos = 0,
    [double]$HorasAgente = -1,
    [long]$Tokens = -1,
    [double]$CostoUsd = -1,
    [switch]$Retrabajo,
    [string]$Notas
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

$repoRoot  = Get-RepoRoot
$dataDir   = Get-DataDir $repoRoot
if ($Evento -and -not (Test-Path -LiteralPath (Join-Path $dataDir 'config.json'))) {
    # Invocado por un hook en un proyecto sin metricas inicializadas: no bloquear el flujo SDD.
    Write-Warning 'speckit-metricas no esta inicializado (falta metricas/config.json); no se registra la sesion.'
    return
}
Import-MetricsConfig $dataDir
$stateFile = Join-Path $dataDir '.sesion-activa.json'
$activityFile = Join-Path $dataDir '.ultima-actividad'

function Get-Head { (git -C $repoRoot rev-parse HEAD).Trim() }

function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) { return $null }
    $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    # Sesiones abiertas con versiones anteriores no tienen los campos de pausa ni de actividad.
    foreach ($name in @('minutos_pausa', 'pausa_desde', 'minutos_pausa_auto', 'ultima_actividad')) {
        if (-not $state.PSObject.Properties[$name]) { $state | Add-Member -NotePropertyName $name -NotePropertyValue $null }
    }
    return $state
}

function Save-State($state) {
    $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
}

function Get-LastActivity($state) {
    # La actividad mas reciente: la del estado o la del archivo que escriben los hooks del agente
    # (.ultima-actividad, milisegundos desde 1970).
    $last = if ($state.ultima_actividad) { [datetime]$state.ultima_actividad } else { [datetime]$state.inicio }
    if (Test-Path -LiteralPath $activityFile) {
        $raw = (Get-Content -LiteralPath $activityFile -Raw).Trim()
        $ms = 0L
        if ([long]::TryParse($raw, [ref]$ms)) {
            $fromFile = [DateTimeOffset]::FromUnixTimeMilliseconds($ms).LocalDateTime
            if ($fromFile -gt $last) { $last = $fromFile }
        }
    }
    return $last
}

function Add-InactivityPause($state, [datetime]$now) {
    # Si desde la ultima actividad paso mas que el umbral (p. ej. se agoto el limite de uso del
    # agente o la persona se fue sin pausetask), ese hueco cuenta como pausa automatica.
    # Durante una pausa pedida por la persona no se aplica: ese tiempo ya se descuenta.
    if ($state.pausa_desde) { return 0.0 }
    $gap = ($now - (Get-LastActivity $state)).TotalMinutes
    $state.ultima_actividad = $now.ToString('s')
    if ($gap -le $script:IdleMinutes) { return 0.0 }
    $previous = if ($state.minutos_pausa_auto) { [double]$state.minutos_pausa_auto } else { 0.0 }
    $state.minutos_pausa_auto = [math]::Round($previous + $gap, 1)
    return $gap
}

function Get-PausedMinutes($state, [datetime]$now) {
    # Minutos en pausa acumulados, mas la pausa en curso si la hay.
    $minutes = if ($state.minutos_pausa) { [double]$state.minutos_pausa } else { 0.0 }
    if ($state.pausa_desde) { $minutes += ($now - [datetime]$state.pausa_desde).TotalMinutes }
    return $minutes
}

function Write-Summary($summary) {
    $wasted = $summary.loc_elim_requisito + $summary.loc_elim_defecto
    Write-Host ("Commits: {0} | Codigo +{1} -{2} | Pruebas +{3} -{4}" -f $summary.commits,
        $summary.loc_agregadas, $summary.loc_eliminadas,
        $summary.loc_pruebas_agregadas, $summary.loc_pruebas_eliminadas)
    Write-Host ("Eliminado por requisito: {0} | por defecto: {1} | refactor: {2} | sin clasificar: {3} | desperdicio: {4}" -f
        $summary.loc_elim_requisito, $summary.loc_elim_defecto, $summary.loc_elim_refactor,
        $summary.loc_elim_sin_clasificar, $wasted)
    if ($summary.loc_elim_sin_clasificar -gt 0) {
        Write-Warning 'Hay eliminaciones sin trailer "Causa:". Corrija el mensaje del commit o anote la causa en -Notas.'
    }
}

function Start-Session {
    if (-not $Funcionalidad) { $Funcionalidad = Get-CurrentFeature $repoRoot }
    if ($Funcionalidad -notmatch '^\d{3}-') {
        throw 'La funcionalidad debe tener formato NNN-nombre (000-proyecto para trabajo transversal).'
    }
    if ($Evento -and -not $Fase) { $Fase = $script:PhaseOfEvent[$Evento] }
    if ($script:Phases -notcontains $Fase) {
        throw "Fase no valida. Valores: $($script:Phases -join ', ')"
    }
    if (-not $Herramienta) { $Herramienta = 'manual' }
    if ($Herramienta -ne 'manual' -and -not $ModeloIA) {
        throw 'Indique -ModeloIA con el identificador exacto y la version del modelo (p. ej. claude-opus-5-5).'
    }
    $state = [ordered]@{
        inicio              = (Get-Date).ToString('s')
        commit_inicio       = Get-Head
        funcionalidad       = $Funcionalidad
        fase                = $Fase
        herramienta         = $Herramienta
        version_herramienta = $VersionHerramienta
        modelo_ia           = if ($Herramienta -eq 'manual') { 'ninguno' } else { $ModeloIA }
        nivel_razonamiento  = if ($Herramienta -eq 'manual') { '' } else { $NivelRazonamiento }
        automatica          = [bool]$Evento
        minutos_pausa       = 0
        pausa_desde         = $null
        minutos_pausa_auto  = 0
        ultima_actividad    = (Get-Date).ToString('s')
    }
    Save-State $state
    $shownModel = if ($state.nivel_razonamiento) { "$($state.modelo_ia), $($state.nivel_razonamiento)" } else { $state.modelo_ia }
    Write-Host ("Sesion iniciada: {0} / {1} con {2} ({3}) desde {4}" -f $Funcionalidad, $Fase,
        $Herramienta, $shownModel, $state.commit_inicio.Substring(0, 7))
}

function Stop-Session($state, [string]$activity, [bool]$automatic) {
    if (git -C $repoRoot status --porcelain -- . ":(exclude)$((Split-Path -Leaf $dataDir))/") {
        Write-Warning 'Hay cambios sin commit: no se incluyen en esta sesion.'
    }
    $start = [datetime]$state.inicio
    $end = Get-Date
    $notes = $Notas
    $hours = $Horas
    [void](Add-InactivityPause $state $end)
    $pausedMinutes = [math]::Round((Get-PausedMinutes $state $end) + $PausaMinutos)
    $autoMinutes = [math]::Round([double]$state.minutos_pausa_auto)
    if ($hours -lt 0) {
        $raw = (($end - $start).TotalMinutes - $pausedMinutes - $autoMinutes) / 60
        if ($automatic -and $raw -gt $script:MaxAutoHours) {
            # Un lapso largo entre comandos suele incluir pausas: lo completa la persona.
            $hours = $null
            $notes = ("COMPLETAR horas_humano: lapso de {0:N1} h entre comandos. {1}" -f $raw, $notes).Trim()
        } else {
            $hours = [math]::Max(0.25, [math]::Round($raw * 4) / 4)
        }
    }
    $head = Get-Head
    $summary = Get-LocSummary $repoRoot @("$($state.commit_inicio)..HEAD")

    $row = [ordered]@{
        proyecto            = $script:ProjectName
        desarrollador       = (git -C $repoRoot config user.name)
        fecha               = $start.ToString('yyyy-MM-dd')
        inicio              = $start.ToString('HH:mm')
        fin                 = $end.ToString('HH:mm')
        horas_humano        = $hours
        horas_agente        = if ($HorasAgente -ge 0) { $HorasAgente } else { $null }
        minutos_pausa       = $pausedMinutes
        minutos_pausa_auto  = $autoMinutes
        funcionalidad       = $state.funcionalidad
        fase                = $state.fase
        actividad           = $activity
        herramienta         = $state.herramienta
        version_herramienta = $state.version_herramienta
        modelo_ia           = $state.modelo_ia
        nivel_razonamiento  = $state.nivel_razonamiento
        commit_inicio       = $state.commit_inicio.Substring(0, 7)
        commit_fin          = $head.Substring(0, 7)
        tokens              = if ($Tokens -ge 0) { $Tokens } else { $null }
        costo_usd           = if ($CostoUsd -ge 0) { $CostoUsd } else { $null }
        retrabajo           = if ($Retrabajo) { 'si' } else { 'no' }
        notas               = $notes
    }
    foreach ($key in $summary.Keys) { $row[$key] = $summary[$key] }

    $saved = Save-Session $dataDir $row
    Remove-Item -LiteralPath $stateFile
    $shown = if ($null -eq $hours) { 'sin' } else { $hours }
    Write-Host ("Sesion cerrada ({0} / {1}): {2} h registradas en {3}" -f $state.funcionalidad, $state.fase, $shown, (Split-Path -Leaf $saved))
    Write-Summary $summary
}

$state = Read-State
switch ($Accion) {
    'iniciar' {
        if ($state) { throw 'Ya hay una sesion activa. Use "cerrar", "cambiar" o "cancelar".' }
        Start-Session
    }

    'cambiar' {
        if ($state) {
            $activity = if ($Actividad) { $Actividad } else { "Sesion automatica: fase $($state.fase)" }
            Stop-Session $state $activity ([bool]$state.automatica)
        }
        Start-Session
    }

    'pausar' {
        if (-not $state) { Write-Host 'No hay una sesion activa; no hay nada que pausar.'; return }
        if ($state.pausa_desde) {
            Write-Host ("La sesion ya esta en pausa desde las {0:HH:mm}." -f [datetime]$state.pausa_desde); return
        }
        [void](Add-InactivityPause $state (Get-Date))
        $state.pausa_desde = (Get-Date).ToString('s')
        Save-State $state
        Write-Host ("Sesion en pausa ({0} / {1}) desde las {2:HH:mm}. El tiempo no se cuenta hasta reanudar." -f
            $state.funcionalidad, $state.fase, (Get-Date))
    }

    'reanudar' {
        if (-not $state) { Write-Host 'No hay una sesion activa; use "iniciar".'; return }
        if (-not $state.pausa_desde) { Write-Host 'La sesion no estaba en pausa.'; return }
        $now = Get-Date
        $paused = ($now - [datetime]$state.pausa_desde).TotalMinutes
        $state.minutos_pausa = [math]::Round((Get-PausedMinutes $state $now), 1)
        $state.pausa_desde = $null
        $state.ultima_actividad = $now.ToString('s')
        Save-State $state
        Write-Host ("Sesion reanudada ({0} / {1}) tras {2:N0} min de pausa ({3:N0} min de pausa en total)." -f
            $state.funcionalidad, $state.fase, $paused, $state.minutos_pausa)
    }

    'actividad' {
        # Lo llaman los hooks del agente (p. ej. al enviar la persona un mensaje). Silencioso salvo
        # que descuente un hueco de inactividad.
        if (-not $state) { return }
        $gap = Add-InactivityPause $state (Get-Date)
        Save-State $state
        if ($gap -gt 0) {
            Write-Host ("Pausa automatica: {0:N0} min sin actividad no se cuentan como esfuerzo ({1} / {2})." -f
                $gap, $state.funcionalidad, $state.fase)
        }
    }

    'estado' {
        if (-not $state) { Write-Host 'No hay una sesion activa.'; return }
        $now = Get-Date
        $gap = Add-InactivityPause $state $now
        Save-State $state
        $paused = Get-PausedMinutes $state $now
        $auto = [double]$state.minutos_pausa_auto
        $effective = (($now - [datetime]$state.inicio).TotalMinutes - $paused - $auto) / 60
        $pauseText = if ($state.pausa_desde) { (" | EN PAUSA desde las {0:HH:mm}" -f [datetime]$state.pausa_desde) } else { '' }
        Write-Host ("Sesion activa: {0} / {1} con {2} ({3}), {4:N2} h efectivas, {5:N0} min de pausa, {6:N0} min de pausa automatica{7}" -f
            $state.funcionalidad, $state.fase, $state.herramienta, $state.modelo_ia, $effective, $paused, $auto, $pauseText)
        if ($gap -gt 0) { Write-Host ("Se acaban de descontar {0:N0} min sin actividad." -f $gap) }
        Write-Summary (Get-LocSummary $repoRoot @("$($state.commit_inicio)..HEAD"))
        if (git -C $repoRoot status --porcelain) { Write-Warning 'Hay cambios sin commit: no se cuentan hasta confirmarlos.' }
    }

    'cancelar' {
        if (-not $state) { Write-Host 'No hay una sesion activa.'; return }
        Remove-Item -LiteralPath $stateFile
        Write-Host 'Sesion cancelada; no se registro nada.'
    }

    'cerrar' {
        if (-not $state) { throw 'No hay una sesion activa.' }
        if (-not $Actividad) { throw 'Indique -Actividad con una descripcion breve.' }
        Stop-Session $state $Actividad $false
    }
}
