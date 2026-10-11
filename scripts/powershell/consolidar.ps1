#Requires -Version 5.1
<#
.SYNOPSIS
    Une los datasets exportados de varios proyectos en un solo conjunto de datos.

.DESCRIPTION
    Recibe archivos dataset-*.zip (o carpetas ya descomprimidas) generados por exportar.ps1 y
    escribe en -Salida:
      proyectos.csv        una fila por proyecto (resumen + metadatos)
      funcionalidades.csv  todas las funcionalidades de todos los proyectos
      sesiones.csv         todas las sesiones de trabajo
      factores.csv         todas las calificaciones de factores COCOMO
    Las columnas se unen; un dato ausente en un proyecto queda vacio.

.EXAMPLE
    ./consolidar.ps1 -Entradas datasets/*.zip -Salida consolidado
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Entradas,
    [Parameter(Mandatory)]
    [string]$Salida
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib-metricas.ps1')

function Get-Columns($rows) {
    $columns = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        foreach ($name in $row.PSObject.Properties.Name) { if (-not $columns.Contains($name)) { $columns.Add($name) } }
    }
    return $columns.ToArray()
}

$paths = @($Entradas | ForEach-Object { Get-Item -Path $_ } | Select-Object -ExpandProperty FullName)
if ($paths.Count -eq 0) { throw 'No se encontraron datasets.' }

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "consolidar-metricas-$PID"
New-Item -ItemType Directory -Path $temp | Out-Null
$collected = @{ proyectos = @(); funcionalidades = @(); sesiones = @(); factores = @() }
$names = @{}

try {
    $index = 0
    foreach ($path in $paths) {
        $dir = $path
        if ($path -like '*.zip') {
            $dir = Join-Path $temp ("d{0}" -f $index++)
            Expand-Archive -LiteralPath $path -DestinationPath $dir
        }
        $metadata = Get-Content -LiteralPath (Join-Path $dir 'proyecto.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $name = $metadata.proyecto
        if ($names.ContainsKey($name)) { throw "El proyecto '$name' aparece dos veces ($path y $($names[$name]))." }
        $names[$name] = $path

        foreach ($summary in (Import-CsvSafe (Join-Path $dir 'resumen-proyecto.csv'))) {
            foreach ($property in $metadata.PSObject.Properties) {
                if (-not $summary.PSObject.Properties[$property.Name]) {
                    $summary | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                }
            }
            $collected.proyectos += $summary
        }
        $collected.funcionalidades += Import-CsvSafe (Join-Path $dir 'resumen-funcionalidades.csv')
        $collected.sesiones        += Import-CsvSafe (Join-Path $dir 'registro-esfuerzo.csv')
        foreach ($factor in (Import-CsvSafe (Join-Path $dir 'factores-cocomo.csv'))) {
            if (-not $factor.proyecto) { $factor.proyecto = $name }
            $collected.factores += $factor
        }
        Write-Host "Incluido: $name ($path)"
    }

    if (-not (Test-Path -LiteralPath $Salida)) { New-Item -ItemType Directory -Path $Salida | Out-Null }
    foreach ($key in $collected.Keys) {
        $rows = $collected[$key]
        if ($rows.Count -eq 0) { continue }
        Write-CsvFile (Join-Path $Salida "$key.csv") $rows (Get-Columns $rows)
    }
    Write-Host ("Consolidado: {0} proyectos, {1} funcionalidades, {2} sesiones en {3}" -f
        $collected.proyectos.Count, $collected.funcionalidades.Count, $collected.sesiones.Count, $Salida)
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
