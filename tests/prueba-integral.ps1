#Requires -Version 5.1
<#
.SYNOPSIS
    Prueba integral: simula dos proyectos SDD y recorre todo el flujo de la extension.

.DESCRIPTION
    Crea repositorios temporales, registra sesiones con commits (incluidas eliminaciones con
    "Causa:"), recolecta, exporta, consolida, calibra y estima. Falla con codigo 1 si algun
    valor esperado no coincide.

.EXAMPLE
    pwsh -File tests/prueba-integral.ps1
#>
[CmdletBinding()]
param([switch]$Conservar)

$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/powershell'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "speckit-metricas-prueba-$PID"
New-Item -ItemType Directory -Path $work | Out-Null
$failures = 0

function Assert-Equal($actual, $expected, [string]$label) {
    if ("$actual" -ne "$expected") {
        Write-Host "FALLA  $label : esperado '$expected', obtenido '$actual'" -ForegroundColor Red
        $script:failures++
    } else {
        Write-Host "OK     $label = $actual" -ForegroundColor Green
    }
}

function Invoke-Kit([string]$script) {
    $params = $args
    & (Join-Path $scripts $script) @params
}

function Write-Lines([string]$path, [string]$prefix, [int]$count) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = 1..$count | ForEach-Object { "$prefix $_" }
    [System.IO.File]::WriteAllText($path, ($lines -join "`n") + "`n")
}

function Commit([string]$message) {
    git add -A | Out-Null
    git commit -q -m $message | Out-Null
}

function New-Feature([string]$name, [int]$requirements) {
    $dir = "specs/$name"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $spec = (1..$requirements | ForEach-Object { "- **FR-{0:000}**: El sistema MUST hacer algo $_" -f $_ }) -join "`n"
    [System.IO.File]::WriteAllText("$dir/spec.md", "### User Story 1 - x (Priority: P1)`n1. **Given** a, **When** b, **Then** c`n$spec`n")
    # 1 tarea de configuracion (1 PTS) + requisitos/2 de logica (5 PTS c/u) + 1 prueba (2 PTS).
    $tasks = New-Object System.Collections.Generic.List[string]
    $tasks.Add('## Phase 1: Setup')
    $tasks.Add('- [x] T001 Configurar estructura del proyecto')
    $tasks.Add('## Phase 3: User Story 1')
    $id = 2
    foreach ($i in 1..([int]($requirements / 2))) { $tasks.Add(("- [x] T{0:000} [P] [US1] Implementar servicio {1} en src/s{1}.js" -f $id++, $i)) }
    $tasks.Add(("- [x] T{0:000} [US1] Prueba de integracion en tests/t.test.js" -f $id))
    [System.IO.File]::WriteAllText("$dir/tasks.md", ($tasks -join "`n") + "`n")
}

function New-Project([string]$name, [object[]]$features) {
    $repo = Join-Path $work $name
    New-Item -ItemType Directory -Path $repo | Out-Null
    Set-Location $repo
    [Environment]::CurrentDirectory = $repo
    git init -q; git config user.email "dev@$name.test"; git config user.name "Dev $name"; git config core.autocrlf false
    git checkout -q -b main
    [System.IO.File]::WriteAllText((Join-Path $repo 'README.md'), "# $name`n")
    Commit 'chore: inicio'
    Invoke-Kit 'inicializar.ps1' -Proyecto $name | Out-Null
    $config = Get-Content metricas/config.json -Raw | ConvertFrom-Json
    $config.costo_hora_humano = 20
    $config | ConvertTo-Json -Depth 5 | Set-Content metricas/config.json -Encoding UTF8
    Commit 'chore: metricas'

    Invoke-Kit 'sesion.ps1' iniciar -Fase vision -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium | Out-Null
    Invoke-Kit 'sesion.ps1' cerrar -Actividad 'Vision' -Horas 2 | Out-Null

    foreach ($f in $features) {
        $number = $f.nombre.Substring(0, 3)
        git checkout -q -b $f.nombre
        Invoke-Kit 'sesion.ps1' cambiar -Evento before_specify -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium | Out-Null
        New-Feature $f.nombre $f.requisitos
        Invoke-Kit 'puntos.ps1' | Out-Null
        Commit "docs($number): especificacion"
        Invoke-Kit 'sesion.ps1' cambiar -Evento before_implement -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium -Horas $f.horas_spec | Out-Null
        Write-Lines "src/$number.js" 'codigo' $f.loc
        Write-Lines "tests/$number.test.js" 'prueba' 5
        Commit "feat($number): implementacion generada"
        Write-Lines "src/$number.js" 'codigo' ($f.loc - $f.defecto)
        if ($number -eq '003') {
            # Tarea agregada durante la implementacion: cambia el tamano final, no la linea base.
            Add-Content "specs/$($f.nombre)/tasks.md" '- [x] T099 Documentar README.md'
            Invoke-Kit 'puntos.ps1' | Out-Null
        }
        Commit "fix($number): corrige`n`nCausa: defecto"
        Invoke-Kit 'sesion.ps1' cerrar -Actividad "Implementa $number" -Horas $f.horas_impl -CostoUsd $f.ia | Out-Null
        git checkout -q main
        git merge -q --no-ff $f.nombre -m "Merge $($f.nombre)" | Out-Null
    }
    Invoke-Kit 'exportar.ps1' -Anonimizar | Out-Null
    return $repo
}

try {
    $repoA = New-Project 'ProyectoA' @(
        @{ nombre = '001-login';    requisitos = 4;  loc = 40;  defecto = 10; horas_spec = 2; horas_impl = 6;  ia = 3 },
        @{ nombre = '002-catalogo'; requisitos = 8;  loc = 90;  defecto = 20; horas_spec = 3; horas_impl = 12; ia = 5 },
        @{ nombre = '003-pagos';    requisitos = 12; loc = 150; defecto = 30; horas_spec = 4; horas_impl = 20; ia = 8 })
    $repoB = New-Project 'ProyectoB' @(
        @{ nombre = '001-perfil';   requisitos = 6;  loc = 60;  defecto = 15; horas_spec = 2; horas_impl = 9;  ia = 4 },
        @{ nombre = '002-reportes'; requisitos = 10; loc = 120; defecto = 25; horas_spec = 3; horas_impl = 16; ia = 6 })

    Write-Host "`n--- Verificaciones ProyectoA ---"
    $rows = Import-Csv (Join-Path $repoA 'metricas/salidas/resumen-funcionalidades.csv')
    $f3 = $rows | Where-Object funcionalidad -eq '003-pagos'
    Assert-Equal $f3.requisitos_funcionales 12 'requisitos 003'
    Assert-Equal $f3.loc_agregadas 150 'loc agregadas 003'
    Assert-Equal $f3.loc_elim_defecto 30 'loc eliminadas por defecto 003'
    Assert-Equal $f3.loc_sobrevivientes 120 'loc sobrevivientes 003'
    Assert-Equal $f3.loc_desperdicio_total 30 'desperdicio total 003'
    Assert-Equal $f3.loc_pruebas_agregadas 5 'loc pruebas 003'
    Assert-Equal $f3.h_implementar 20 'horas implementar 003'
    Assert-Equal $f3.h_especificar 4 'horas especificar 003'
    Assert-Equal $f3.modelos_ia 'claude-opus-5-5:medium' 'modelo IA y nivel 003'
    Assert-Equal $f3.puntos_tarea_plan 33 'PTS plan 003 (1 + 6*5 + 2)'
    Assert-Equal $f3.puntos_tarea 34 'PTS final 003 (+1 documentacion)'
    Assert-Equal $f3.puntos_agregados 1 'PTS agregados 003'
    $classified = Import-Csv (Join-Path $repoA 'specs/003-pagos/puntos-tarea.csv')
    Assert-Equal (($classified | Where-Object tarea -eq 'T001').tipo) 'configuracion' 'tipo T001'
    Assert-Equal (($classified | Where-Object tarea -eq 'T099').origen) 'agregada' 'origen T099'
    $project = Import-Csv (Join-Path $repoA 'metricas/salidas/resumen-proyecto.csv')
    Assert-Equal $project.h_humano_total 49 'horas totales A'
    Assert-Equal $project.costo_total 996 'costo total A (49 h * 20 + 16 IA)'
    $log = Get-ChildItem (Join-Path $repoA 'metricas/sesiones') -Filter *.csv | ForEach-Object { Import-Csv $_.FullName }
    Assert-Equal (@($log | Where-Object { $_.loc_elim_defecto -eq '30' }).Count) 1 'sesion con 30 lineas por defecto'

    Write-Host "`n--- Pausa y reanudacion ---"
    Set-Location $repoA
    [Environment]::CurrentDirectory = $repoA
    Invoke-Kit 'sesion.ps1' iniciar -Fase probar -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium | Out-Null
    Invoke-Kit 'sesion.ps1' pausar | Out-Null
    # Simula una sesion iniciada hace 2 h con una pausa iniciada hace 1 h.
    $stateFile = Join-Path $repoA 'metricas/.sesion-activa.json'
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $state.inicio = (Get-Date).AddMinutes(-120).ToString('s')
    $state.pausa_desde = (Get-Date).AddMinutes(-60).ToString('s')
    $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    Invoke-Kit 'sesion.ps1' reanudar | Out-Null
    Invoke-Kit 'sesion.ps1' cerrar -Actividad 'Prueba de pausa' | Out-Null
    $paused = Get-ChildItem (Join-Path $repoA 'metricas/sesiones') -Filter '*-probar-*.csv' | ForEach-Object { Import-Csv $_.FullName }
    Assert-Equal $paused.horas_humano 1 'horas efectivas con 1 h de pausa'
    Assert-Equal $paused.minutos_pausa 60 'minutos de pausa registrados'

    Write-Host "`n--- Pausa automatica por inactividad ---"
    Invoke-Kit 'sesion.ps1' iniciar -Fase integrar -Herramienta claude-code -ModeloIA claude-opus-5-5 -NivelRazonamiento medium | Out-Null
    # Sesion de 2 h cuya ultima actividad fue hace 90 min (p. ej. se agoto el limite de uso).
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $state.inicio = (Get-Date).AddMinutes(-120).ToString('s')
    $state.ultima_actividad = (Get-Date).AddMinutes(-90).ToString('s')
    $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    $mensaje = Invoke-Kit 'sesion.ps1' actividad 6>&1 | Out-String
    if ($mensaje -notmatch 'Pausa automatica') { Write-Host 'FALLA  actividad no informo la pausa automatica' -ForegroundColor Red; $failures++ }
    # Una actividad reciente registrada por un hook del agente no genera otra pausa.
    $ms = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    Set-Content (Join-Path $repoA 'metricas/.ultima-actividad') $ms
    Invoke-Kit 'sesion.ps1' cerrar -Actividad 'Prueba de inactividad' | Out-Null
    $idle = Get-ChildItem (Join-Path $repoA 'metricas/sesiones') -Filter '*-integrar-*.csv' | ForEach-Object { Import-Csv $_.FullName }
    Assert-Equal $idle.horas_humano 0.5 'horas efectivas con 90 min inactivos'
    Assert-Equal $idle.minutos_pausa_auto 90 'minutos de pausa automatica'
    Assert-Equal $idle.minutos_pausa 0 'sin pausa manual'

    Write-Host "`n--- Consolidar y calibrar ---"
    $datasets = Join-Path $work 'datasets'
    New-Item -ItemType Directory -Path $datasets | Out-Null
    Copy-Item (Join-Path $repoA 'metricas/salidas/dataset-*.zip'), (Join-Path $repoB 'metricas/salidas/dataset-*.zip') $datasets
    $consolidated = Join-Path $work 'consolidado'
    Set-Location $work
    Invoke-Kit 'consolidar.ps1' -Entradas (Join-Path $datasets '*.zip') -Salida $consolidated | Out-Null
    $sessions = Import-Csv (Join-Path $consolidated 'sesiones.csv')
    Assert-Equal (@($sessions | Where-Object { $_.desarrollador -match '^Dev Proyecto' }).Count) 0 'desarrolladores anonimizados'
    Assert-Equal (@(Import-Csv (Join-Path $consolidated 'funcionalidades.csv') | Where-Object funcionalidad -ne '000-proyecto').Count) 5 'funcionalidades consolidadas'

    Invoke-Kit 'calibrar.ps1' -Datos $consolidated | Out-Null
    $model = Get-Content (Join-Path $consolidated 'modelo-estimacion.json') -Raw | ConvertFrom-Json
    Assert-Equal $model.puntos 5 'puntos de calibracion'
    Assert-Equal ([bool]$model.esfuerzo.requisitos) $true 'ecuacion por requisitos'
    if ($model.esfuerzo.requisitos.E -le 0) { Write-Host 'FALLA  exponente E debe ser positivo' -ForegroundColor Red; $failures++ }

    $estimate = Invoke-Kit 'estimar.ps1' -Tamano 8 -Medida requisitos -Modelo (Join-Path $consolidated 'modelo-estimacion.json') -CostoHora 20 6>&1 | Out-String
    if ($estimate -notmatch 'Esfuerzo') { Write-Host 'FALLA  estimar no produjo resultado' -ForegroundColor Red; $failures++ }
    else { Write-Host $estimate }
} finally {
    Set-Location ([System.IO.Path]::GetTempPath())
    if (-not $Conservar) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "Archivos de prueba conservados en $work" }
}

if ($failures -gt 0) { Write-Host "$failures verificaciones fallaron" -ForegroundColor Red; exit 1 }
Write-Host 'Todas las verificaciones pasaron' -ForegroundColor Green
