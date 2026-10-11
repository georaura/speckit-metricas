---
description: "Reanudar la sesion pausada: el tiempo vuelve a contarse"
---

# Reanudar la sesion (resumetask)

La persona vuelve a trabajar en el aplicativo. El tiempo vuelve a contarse; las pausas se
descuentan de las horas al cerrar la sesion y quedan en la columna `minutos_pausa`.

## Ejecucion

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 reanudar`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 reanudar`

Muestre al usuario el mensaje del script (minutos de esta pausa y total). Si no habia sesion
activa, ofrezca iniciar una con `/speckit-metricas-sesion <fase>`.
