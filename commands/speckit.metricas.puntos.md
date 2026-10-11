---
description: "Calcular los Puntos de Tarea SDD (PTS) de la funcionalidad a partir de tasks.md"
---

# Puntos de Tarea SDD

Mide el tamano de la funcionalidad ponderando cada tarea de `tasks.md` por **tipo** y
**complejidad**, de forma analoga a los puntos de funcion. La primera ejecucion fija la linea base
del plan; las siguientes registran tareas agregadas y eliminadas (volatilidad).

## Entrada del usuario

```text
$ARGUMENTS
```

## Pasos

1. Genere o actualice el borrador:
   - **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/puntos.ps1 [-Funcionalidad NNN-nombre]`
   - **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/puntos.ps1 [-Funcionalidad NNN-nombre]`
2. Abra `specs/NNN-*/puntos-tarea.csv` y **revise cada fila con `clasificado_por = heuristica`**.
   Asigne `tipo` y `complejidad` segun las tablas de abajo, ponga `clasificado_por = agente` y no
   modifique las demas columnas. Clasifique por lo que la tarea **produce**, no por las palabras
   que usa.
3. Vuelva a ejecutar el script para recalcular los puntos y muestre el resumen al usuario.

## Tipos

| Tipo | Que produce |
|---|---|
| `configuracion` | Estructura del proyecto, dependencias, herramientas, CI, entorno |
| `datos` | Modelos, entidades, esquemas, migraciones, formatos de archivo |
| `logica` | Servicios, reglas de negocio, algoritmos, gestion de estado |
| `interfaz` | Pantallas, componentes, vistas, escenas, interaccion de usuario |
| `integracion` | APIs, endpoints, contratos, protocolos, servicios externos, dispositivos |
| `prueba` | Pruebas automatizadas (contrato, integracion, unidad, extremo a extremo) |
| `documentacion` | Documentacion, limpieza, pulido, refactorizacion menor |

## Complejidad

| Nivel | Criterio |
|---|---|
| `baja` | Un archivo, patron conocido, sin dependencias de otras tareas ni decisiones de diseno |
| `media` | Dos o tres archivos, o depende de otras tareas, o requiere decisiones de diseno locales |
| `alta` | Cuatro o mas archivos, algoritmo o protocolo no trivial, tecnologia nueva, hardware o rendimiento critico |

## Pesos (version 1.0)

| Tipo | Baja | Media | Alta |
|---|---|---|---|
| configuracion | 1 | 2 | 3 |
| datos | 2 | 3 | 5 |
| logica | 3 | 5 | 8 |
| interfaz | 3 | 5 | 8 |
| integracion | 4 | 6 | 10 |
| prueba | 1 | 2 | 4 |
| documentacion | 1 | 1 | 2 |

Los pesos estan en `.specify/extensions/metricas/datos/puntos-tarea.json` y son una hipotesis
inicial que se recalibra con datos.
