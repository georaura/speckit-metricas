---
description: "Estimar esfuerzo, tiempo y costo con el modelo calibrado"
---

# Estimar

Estima esfuerzo (persona-mes y horas), tiempo calendario y costo de una funcionalidad o de un
proyecto usando `modelo-estimacion.json`.

## Entrada del usuario

```text
$ARGUMENTS
```

## Datos necesarios

- `-Tamano` y `-Medida`: si hay una especificacion (`specs/NNN-*/spec.md`), cuente usted los
  requisitos funcionales (`FR-`), escenarios o historias segun la medida; si no, pida el tamano.
  Sin `-Medida` se usa la mejor del modelo.
- `-Factores`: calificaciones de multiplicadores, p. ej. `"CPLX=H;PCAP=VH;AIAS=VH"`.
- `-CostoHora`: tarifa; por defecto la de `metricas/config.json`.
- `-IncluirTransversal`: para estimar un proyecto completo (agrega el trabajo transversal).
- `-Modelo`: ruta del modelo si no es el del proyecto actual.

## Ejecucion

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/estimar.ps1 -Tamano <n> [-Medida <m>] [-Factores "<...>"] [-CostoHora <x>] [-IncluirTransversal]`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/estimar.ps1 ...`

Presente el resultado indicando el rango orientativo y el numero de puntos en que se basa.
