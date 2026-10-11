# Changelog

## 0.2.0 - 2026-10-11

- Nuevos comandos `pausetask` y `resumetask`: el tiempo en pausa no se cuenta como esfuerzo y se
  registra en la nueva columna `minutos_pausa` de cada sesión.
- Las sesiones abiertas con la 0.1.0 se pueden pausar sin perder datos.

## 0.1.0 - 2026-10-11

Primera versión experimental.

- Sesiones por fase SDD abiertas automáticamente por hooks, con herramienta, versión, modelo de IA
  y nivel de razonamiento.
- Líneas generadas y eliminadas por sesión, clasificadas por causa (`requisito`, `defecto`,
  `refactor`), y supervivencia final con `git blame`.
- Puntos de Tarea SDD (PTS) 1.0 con línea base del plan y volatilidad.
- Recolección por funcionalidad y por proyecto, exportación anonimizable y consolidación
  multiproyecto.
- Calibración de esfuerzo, tiempo y costo tipo COCOMO II con MMRE, PRED(25) y LOOCV, y estimador.
