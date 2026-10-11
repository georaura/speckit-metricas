---
description: "Pausar la sesion de trabajo: el tiempo deja de contarse hasta reanudar"
---

# Pausar la sesion (pausetask)

La persona deja de trabajar en el aplicativo. Desde este momento el tiempo no se cuenta como
esfuerzo hasta que ejecute `/speckit-metricas-resumetask` (o `resumetask`).

## Ejecucion

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 pausar`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 pausar`

## Comportamiento

- Muestre al usuario el mensaje del script (fase en pausa y hora).
- **No continue con otro trabajo del aplicativo** mientras la sesion este en pausa. Si el usuario
  pide trabajo nuevo, primero reanude la sesion (`sesion.ps1 reanudar`) e informelo.
- Si no hay sesion activa, informelo; no hay nada que pausar.
- Si un hook de Spec Kit cambia de sesion estando en pausa, la pausa termina en ese momento y el
  tiempo en pausa se descuenta igual.
