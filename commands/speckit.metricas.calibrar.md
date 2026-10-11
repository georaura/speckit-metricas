---
description: "Consolidar datasets y calibrar el modelo de esfuerzo, tiempo y costo"
---

# Calibrar el modelo de estimacion

Ajusta `PM = A * Size^E * prod(EM)`, `TDEV = C * PM^F` y el costo de IA por persona-mes, y
reporta MMRE, PRED(25) y validacion cruzada por cada medida de tamano.

## Entrada del usuario

```text
$ARGUMENTS
```

## Ejecucion

1. **Solo este proyecto**: ejecute primero `recolectar.ps1` y luego `calibrar.ps1` sin `-Datos`.
2. **Varios proyectos**: consolide los `dataset-*.zip` y calibre sobre la carpeta resultante:
   - `.../consolidar.ps1 -Entradas <ruta>/*.zip -Salida <carpeta>`
   - `.../calibrar.ps1 -Datos <carpeta> [-Nivel funcionalidad|proyecto]`

Los scripts estan en `.specify/extensions/metricas/scripts/powershell/`. En Windows invoquelos
con `powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...`; en Linux/macOS con
`pwsh -NoProfile -File <script> ...`.

## Despues de ejecutar

Explique el reporte `reporte-calibracion.md`: medida de tamano con mejor capacidad predictiva,
coeficientes, error (MMRE, PRED(25)), comparacion con COCOMO II estandar y distribucion del
esfuerzo por fase. Advierta que con menos de 10 puntos el modelo es exploratorio.
