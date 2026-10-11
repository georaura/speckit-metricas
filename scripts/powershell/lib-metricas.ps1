# speckit-metricas - funciones compartidas por los scripts de la extension.
# Compatible con Windows PowerShell 5.1 y PowerShell 7 (Windows, Linux, macOS).
# Solo ASCII: Windows PowerShell 5.1 lee los scripts sin BOM como ANSI.

# Punto decimal en los CSV, independiente de la configuracion regional.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$script:KitVersion = '0.3.0'
$script:ExtensionRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Fases SDD estandar. Son fijas para que los datos de distintos proyectos sean comparables.
$script:Phases = @('vision', 'constitucion', 'especificar', 'aclarar', 'planificar', 'tareas',
                   'analizar', 'implementar', 'probar', 'verificar-dispositivo', 'integrar',
                   'infraestructura', 'gestion', 'aprendizaje')

# Fase que corresponde a cada evento de hook de Spec Kit.
$script:PhaseOfEvent = @{
    before_constitution = 'constitucion'; before_specify = 'especificar'; before_clarify = 'aclarar'
    before_plan = 'planificar'; before_tasks = 'tareas'; before_analyze = 'analizar'
    before_checklist = 'analizar'; before_implement = 'implementar'; before_taskstoissues = 'gestion'
}

# Causas validas del trailer "Causa:" en los commits que eliminan o reescriben codigo.
$script:Causes = @('requisito', 'defecto', 'refactor')

$script:LogColumns = @('proyecto', 'desarrollador', 'fecha', 'inicio', 'fin', 'horas_humano',
    'horas_agente', 'minutos_pausa', 'minutos_pausa_auto', 'funcionalidad', 'fase', 'actividad', 'herramienta', 'version_herramienta',
    'modelo_ia', 'nivel_razonamiento', 'commit_inicio', 'commit_fin', 'commits',
    'loc_agregadas', 'loc_eliminadas', 'loc_pruebas_agregadas', 'loc_pruebas_eliminadas',
    'loc_elim_requisito', 'loc_elim_defecto', 'loc_elim_refactor', 'loc_elim_sin_clasificar',
    'tokens', 'costo_usd', 'retrabajo', 'notas')

function Get-RepoRoot {
    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) { throw 'Este comando debe ejecutarse dentro de un repositorio Git.' }
    return ($root.Trim() -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-DataDir([string]$RepoRoot) {
    # Carpeta versionada con config.json, factores-cocomo.csv y sesiones/.
    if ($env:METRICAS_DIR) { return $env:METRICAS_DIR }
    return (Join-Path $RepoRoot 'metricas')
}

function Get-CurrentFeature([string]$RepoRoot) {
    # Funcionalidad activa segun SPECIFY_FEATURE o la rama NNN-nombre; si no, trabajo transversal.
    $candidate = $env:SPECIFY_FEATURE
    if (-not $candidate) { $candidate = git -C $RepoRoot branch --show-current 2>$null }
    if ($candidate) {
        $leaf = ($candidate -split '/')[-1]
        if ($leaf -match '^\d{3}-') { return $leaf }
    }
    return '000-proyecto'
}

function Import-MetricsConfig([string]$DataDir) {
    $path = Join-Path $DataDir 'config.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "No se encontro $path. Ejecute primero /speckit-metricas-inicializar (inicializar.ps1)."
    }
    $config = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:Config           = $config
    $script:ProjectName      = $config.proyecto
    $script:HoursPerPM       = [double]$config.horas_por_persona_mes
    $script:HourlyCost       = [double]$config.costo_hora_humano
    $script:MaxAutoHours     = [double]$config.max_horas_sesion_automatica
    $script:IdleMinutes      = if ($config.minutos_inactividad_pausa) { [double]$config.minutos_inactividad_pausa } else { 30.0 }
    $script:SpecsDirName     = $config.directorio_specs
    $script:ExcludedPrefixes = @($config.rutas_excluidas)
    $script:ExcludedFiles    = $config.archivos_excluidos
    $script:CodeExtensions   = '\.(' + ($config.extensiones_codigo -join '|') + ')\}?$'
    $script:TestPattern      = $config.patron_pruebas
}

function Get-FileKind([string]$path) {
    # Devuelve 'codigo', 'prueba' o $null si el archivo no cuenta como producto.
    $file = $path -replace '\\', '/'
    foreach ($prefix in $script:ExcludedPrefixes) { if ($file.StartsWith($prefix)) { return $null } }
    if ($file -match $script:ExcludedFiles -or $file -notmatch $script:CodeExtensions) { return $null }
    if ($file -match $script:TestPattern) { return 'prueba' }
    return 'codigo'
}

function New-LocSummary {
    [ordered]@{
        commits = 0
        loc_agregadas = 0; loc_eliminadas = 0
        loc_pruebas_agregadas = 0; loc_pruebas_eliminadas = 0
        loc_elim_requisito = 0; loc_elim_defecto = 0; loc_elim_refactor = 0
        loc_elim_sin_clasificar = 0
    }
}

function Get-LocSummary([string]$RepoRoot, [string[]]$LogArgs) {
    # Suma lineas agregadas/eliminadas commit a commit (sin merges) y clasifica las
    # eliminaciones de codigo de produccion segun el trailer "Causa:" del commit.
    $summary = New-LocSummary
    $gitArgs = @('-C', $RepoRoot, '-c', 'core.quotepath=off', 'log', '--no-merges', '--numstat',
                 '--format=@@COMMIT%n%B%n@@END') + $LogArgs
    $lines = & git @gitArgs
    $inBody = $false
    $cause = $null
    foreach ($line in $lines) {
        if ($line -eq '@@COMMIT') { $summary.commits++; $inBody = $true; $cause = $null; continue }
        if ($line -eq '@@END') { $inBody = $false; continue }
        if ($inBody) {
            if ($line -match '^Causa:\s*([a-z]+)') { $cause = $Matches[1].ToLower() }
            continue
        }
        $parts = $line -split "`t"
        if ($parts.Count -lt 3 -or $parts[0] -eq '-') { continue }
        $kind = Get-FileKind $parts[2]
        if (-not $kind) { continue }
        $added = [int]$parts[0]; $deleted = [int]$parts[1]
        if ($kind -eq 'prueba') {
            $summary.loc_pruebas_agregadas += $added; $summary.loc_pruebas_eliminadas += $deleted
            continue
        }
        $summary.loc_agregadas += $added; $summary.loc_eliminadas += $deleted
        if ($script:Causes -contains $cause) {
            $summary["loc_elim_$cause"] += $deleted
        } else {
            $summary.loc_elim_sin_clasificar += $deleted
        }
    }
    return $summary
}

function ConvertTo-Number([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    return [double]::Parse($value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Sum-Column($entries, [string]$column) {
    $sum = 0.0
    foreach ($e in $entries) { $n = ConvertTo-Number $e.$column; if ($null -ne $n) { $sum += $n } }
    return $sum
}

function ConvertTo-CsvField($value) {
    $text = if ($null -eq $value) { '' } else { [string]$value }
    if ($text -match '[",\r\n]') { return '"' + ($text -replace '"', '""') + '"' }
    return $text
}

function Write-CsvFile([string]$Path, [object[]]$Rows, [string[]]$Columns) {
    # CSV en UTF-8 sin BOM, con encabezado fijo; tolera filas con columnas faltantes.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append(($Columns -join ',') + "`n")
    foreach ($row in $Rows) {
        $fields = foreach ($column in $Columns) {
            $value = if ($row -is [System.Collections.IDictionary]) { $row[$column] } else { $row.$column }
            ConvertTo-CsvField $value
        }
        [void]$builder.Append(($fields -join ',') + "`n")
    }
    [System.IO.File]::WriteAllText($Path, $builder.ToString(), $utf8)
}

function Import-CsvSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Import-Csv -LiteralPath $Path -Encoding UTF8)
}

# --- Puntos de Tarea SDD (PTS) ----------------------------------------------
# Medida de tamano propuesta: cada tarea de tasks.md se clasifica por tipo y complejidad y
# recibe un peso de datos/puntos-tarea.json. La clasificacion se guarda en
# specs/NNN-*/puntos-tarea.csv para conservar la linea base del plan.

$script:TaskPointColumns = @('tarea', 'completada', 'paralela', 'historia', 'seccion', 'descripcion',
    'tipo', 'complejidad', 'puntos', 'clasificado_por', 'origen', 'eliminada')

function Get-TaskPointsModel {
    $path = Join-Path $script:ExtensionRoot 'datos/puntos-tarea.json'
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Read-TaskList([string]$TasksPath) {
    # Extrae las tareas "- [ ] T001 [P] [US1] descripcion" con la seccion (## Phase ...) en que estan.
    if (-not (Test-Path -LiteralPath $TasksPath)) { return @() }
    $section = ''
    $tasks = foreach ($line in [System.IO.File]::ReadAllLines($TasksPath, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^#{2,3}\s+(.+?)\s*$') { $section = $Matches[1]; continue }
        if ($line -notmatch '^\s*-\s*\[([ xX])\]\s*(T\d+)\s*(.*)$') { continue }
        $done = $Matches[1] -ne ' '; $id = $Matches[2]; $rest = $Matches[3]
        $parallel = $rest -match '\[P\]'
        $story = if ($rest -match '\[(US\d+)\]') { $Matches[1] } else { '' }
        $text = ($rest -replace '\[P\]', '' -replace '\[US\d+\]', '').Trim()
        [pscustomobject]@{ tarea = $id; completada = $done; paralela = $parallel; historia = $story
                           seccion = $section; descripcion = $text }
    }
    return @($tasks)
}

function Get-HeuristicClass($task, $model) {
    # Borrador automatico; el agente o la persona lo revisa con los criterios de puntos-tarea.json.
    # Primero la descripcion de la tarea; la seccion (p. ej. "Phase 1: Setup") solo como respaldo.
    $type = $null
    foreach ($text in @(" $($task.descripcion) ", " $($task.seccion) ")) {
        $text = $text.ToLower()
        foreach ($candidate in $model.orden_heuristica) {
            $keywords = @($model.tipos.$candidate.palabras_clave)
            if ($keywords | Where-Object { $text.Contains($_.ToLower()) }) { $type = $candidate; break }
        }
        if ($type) { break }
    }
    if (-not $type) { $type = $model.tipo_por_defecto }
    $paths = ([regex]::Matches($task.descripcion, '[\w./-]+\.[a-z0-9]{1,5}\b')).Count
    $depends = $task.descripcion -match '(depends on|depende de)'
    $complexity = if ($paths -ge 4 -or ($depends -and $paths -ge 2)) { 'alta' }
                  elseif ($type -in @('configuracion', 'documentacion') -and $paths -le 1) { 'baja' }
                  else { 'media' }
    return @{ tipo = $type; complejidad = $complexity }
}

function Get-TaskWeight($model, [string]$type, [string]$complexity) {
    $definition = $model.tipos.$type
    $index = [array]::IndexOf(@($model.complejidades), $complexity)
    if (-not $definition -or $index -lt 0) {
        throw "Clasificacion no valida: tipo '$type', complejidad '$complexity'."
    }
    return [double]@($definition.pesos)[$index]
}

function Merge-TaskPoints([string]$FeatureDir) {
    # Combina tasks.md con la clasificacion guardada: conserva tipo/complejidad de las tareas ya
    # clasificadas, marca las nuevas como 'agregada' y las desaparecidas como eliminadas.
    $model = Get-TaskPointsModel
    $saved = @{}
    $savedOrder = New-Object System.Collections.Generic.List[string]
    foreach ($row in (Import-CsvSafe (Join-Path $FeatureDir 'puntos-tarea.csv'))) {
        $saved[$row.tarea] = $row; $savedOrder.Add($row.tarea)
    }
    $isBaseline = $saved.Count -eq 0
    $current = Read-TaskList (Join-Path $FeatureDir 'tasks.md')
    $seen = @{}
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($task in $current) {
        $seen[$task.tarea] = $true
        $old = $saved[$task.tarea]
        if ($old) {
            $type = $old.tipo; $complexity = $old.complejidad; $by = $old.clasificado_por; $origin = $old.origen
        } else {
            $class = Get-HeuristicClass $task $model
            $type = $class.tipo; $complexity = $class.complejidad; $by = 'heuristica'
            $origin = if ($isBaseline) { 'plan' } else { 'agregada' }
        }
        $rows.Add([ordered]@{
            tarea = $task.tarea; completada = if ($task.completada) { 'si' } else { 'no' }
            paralela = if ($task.paralela) { 'si' } else { 'no' }; historia = $task.historia
            seccion = $task.seccion; descripcion = $task.descripcion; tipo = $type; complejidad = $complexity
            puntos = Get-TaskWeight $model $type $complexity; clasificado_por = $by; origen = $origin; eliminada = 'no'
        })
    }
    foreach ($id in $savedOrder) {
        if ($seen[$id]) { continue }
        $old = $saved[$id]
        $rows.Add([ordered]@{
            tarea = $id; completada = $old.completada; paralela = $old.paralela; historia = $old.historia
            seccion = $old.seccion; descripcion = $old.descripcion; tipo = $old.tipo; complejidad = $old.complejidad
            puntos = Get-TaskWeight $model $old.tipo $old.complejidad; clasificado_por = $old.clasificado_por
            origen = $old.origen; eliminada = 'si'
        })
    }
    return $rows.ToArray()
}

function Get-TaskPointsSummary($rows) {
    $sum = { param($filter) [double](($rows | Where-Object $filter | ForEach-Object { [double]$_.puntos } | Measure-Object -Sum).Sum) }
    return [ordered]@{
        puntos_tarea       = & $sum { $_.eliminada -eq 'no' }
        puntos_tarea_plan  = & $sum { $_.origen -eq 'plan' }
        puntos_agregados   = & $sum { $_.origen -eq 'agregada' -and $_.eliminada -eq 'no' }
        puntos_eliminados  = & $sum { $_.eliminada -eq 'si' }
        tareas_heuristicas = @($rows | Where-Object { $_.clasificado_por -eq 'heuristica' -and $_.eliminada -eq 'no' }).Count
    }
}

# Cada sesion se guarda en su propio archivo dentro de metricas/sesiones/. Asi ningun archivo
# versionado se modifica en distintas ramas y no hay conflictos al cambiar de rama ni al hacer merge.
function Get-SessionsDir([string]$DataDir) { return (Join-Path $DataDir 'sesiones') }

function Save-Session([string]$DataDir, [System.Collections.IDictionary]$Row) {
    $dir = Get-SessionsDir $DataDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $seed = "$($Row.desarrollador)|$($Row.fecha)|$($Row.inicio)|$([guid]::NewGuid())"
    $suffix = (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))[0..1] |
                ForEach-Object { $_.ToString('x2') }) -join '')
    $name = '{0}-{1}-{2}-{3}.csv' -f ($Row.fecha -replace '-', ''), ($Row.inicio -replace ':', ''), $Row.fase, $suffix
    $path = Join-Path $dir $name
    Write-CsvFile $path @($Row) $script:LogColumns
    return $path
}

function Import-Sessions([string]$DataDir) {
    # Une todos los CSV de metricas/sesiones/ (uno por sesion, o historicos con varias filas).
    $dir = Get-SessionsDir $DataDir
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $rows = foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.csv' | Sort-Object Name)) {
        Import-CsvSafe $file.FullName
    }
    return @($rows)
}
