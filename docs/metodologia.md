# Metodología de medición

> Objetivo: reunir datos comparables de proyectos SDD asistidos por IA para calibrar un modelo de
> estimación de **esfuerzo, tiempo y costo** tipo COCOMO II.
>
> Regla de oro: **el esfuerzo que no se registra el mismo día se pierde.** El tamaño y la
> duración se reconstruyen desde Git; las horas no.

## 1. Modelo de referencia

COCOMO II.2000 (Post-Architecture):

```
PM   = A × Size^E × Π EMᵢ        E = B + 0.01 × Σ SFⱼ
TDEV = C × PM^F                   F = D + 0.2 × (E − B)
```

- `PM`: esfuerzo en persona-mes (`horas_por_persona_mes`, 152 por defecto).
- `Size`: tamaño. Aquí se prueban varias medidas (§4).
- `SF`: 5 factores de escala; `EM`: 17 multiplicadores de esfuerzo + 4 candidatos SDD (§5).
- `A, B, C, D`: constantes que se recalibran con los datos.
- Costo = `PM × horas_por_PM × tarifa` + `costo_IA_por_PM × PM`.

### Hipótesis

| # | Hipótesis |
|---|---|
| H1 | En SDD con IA las **líneas de código no son buen predictor** del esfuerzo humano. |
| H2 | El tamaño del **plan** (Puntos de Tarea SDD) o de la **especificación** predice mejor. |
| H3 | El esfuerzo se **desplaza a especificar y verificar** frente a la distribución clásica. |
| H4 | Hacen falta **multiplicadores propios de SDD** (§5). |
| H5 | La **tasa de desperdicio** de código (por cambio de requisitos o por defectos) difiere por modelo de IA y por madurez de la especificación. |

## 2. Unidades de análisis

- **Funcionalidad** (`specs/NNN-nombre/`): un punto de datos por funcionalidad.
- **Proyecto**: un punto de datos por proyecto (totales).
- `000-proyecto` agrupa el trabajo transversal (visión, constitución, infraestructura, gestión);
  su proporción sobre el trabajo de funcionalidades es la **sobrecarga transversal** que el
  estimador agrega al estimar proyectos completos.

## 3. Esfuerzo: sesiones

Cada sesión es un archivo en `metricas/sesiones/` con estas columnas:

| Columna | Contenido |
|---|---|
| `proyecto`, `desarrollador` | Identificación (el desarrollador se anonimiza al exportar) |
| `fecha`, `inicio`, `fin` | `AAAA-MM-DD`, `HH:MM` |
| `horas_humano` | Dedicación efectiva de la persona. **Es el esfuerzo de COCOMO.** |
| `horas_agente` | Tiempo de trabajo autónomo del agente (opcional) |
| `minutos_pausa` | Minutos en pausa (`pausetask` / `resumetask`) descontados de `horas_humano` |
| `minutos_pausa_auto` | Minutos de inactividad mayores al umbral (p. ej. límite de uso del agente agotado), descontados de `horas_humano` |
| `funcionalidad`, `fase` | `NNN-nombre` y fase SDD |
| `actividad` | Descripción breve |
| `herramienta`, `version_herramienta` | Agente o IDE y su versión |
| `modelo_ia` | Identificador exacto del modelo con su versión (p. ej. `claude-opus-5-5`) |
| `nivel_razonamiento` | Nivel de esfuerzo o razonamiento del modelo (p. ej. `medium`); el mismo modelo con otro nivel es otra configuración |
| `commit_inicio`, `commit_fin`, `commits` | Rango de commits de la sesión |
| `loc_agregadas`, `loc_eliminadas` | Líneas de código de producción |
| `loc_pruebas_agregadas`, `loc_pruebas_eliminadas` | Líneas de código de pruebas |
| `loc_elim_requisito`, `loc_elim_defecto`, `loc_elim_refactor`, `loc_elim_sin_clasificar` | Eliminaciones por causa |
| `tokens`, `costo_usd` | Consumo de IA, si la herramienta lo informa |
| `retrabajo` | `si` si corrige algo ya dado por terminado |
| `notas` | Libre |

**Fases** (fijas para que los proyectos sean comparables): `vision`, `constitucion`,
`especificar`, `aclarar`, `planificar`, `tareas`, `analizar`, `implementar`, `probar`,
`verificar-dispositivo`, `integrar`, `infraestructura`, `gestion`, `aprendizaje`.

Las horas son el lapso de la sesión menos las pausas registradas con `pausetask` /
`resumetask`. Las sesiones automáticas (hooks) calculan las horas como el lapso entre comandos. Si el lapso
supera `max_horas_sesion_automatica` (4 h por defecto), las horas quedan vacías para que la
persona las complete: un lapso largo casi siempre incluye pausas.

## 4. Tamaño

| Medida | Fuente | Momento en que se conoce |
|---|---|---|
| `requisitos` (FR), `historias`, `escenarios` | `spec.md` | Tras especificar |
| `tareas` | `tasks.md` | Tras planificar |
| `puntos_tarea_plan` (PTS) | `puntos-tarea.csv` (línea base) | Tras planificar |
| `puntos_tarea` (PTS final) | `tasks.md` + clasificación | Al cierre |
| `ksloc` | Líneas sobrevivientes en `HEAD` (`git blame`) / 1000 | Al cierre |

Las líneas se cuentan como **líneas físicas** de los archivos con las extensiones de
`config.json`, excluidas las rutas de documentación y herramientas SDD. Al cierre del proyecto
conviene contrastarlas con SLOC lógicas (p. ej. `cloc`).

### Desperdicio de código

Como el proyecto parte de cero, toda línea eliminada es código propio descartado. Se mide de dos
formas complementarias:

- **Declarado:** suma de eliminaciones en commits con `Causa: requisito` o `Causa: defecto`.
- **Total:** `loc_agregadas − loc_sobrevivientes`, con `git blame` sobre `HEAD`. Incluye el
  código de una funcionalidad eliminado más tarde por otra.

Las eliminaciones se atribuyen a la funcionalidad **que las causa** (el ámbito del commit que
borra).

## 5. Factores de costo (`factores-cocomo.csv`)

Se califican **al terminar `/speckit-plan` y antes de implementar**, para que conocer el esfuerzo
real no sesgue la calificación. En la misma fila se anota `horas_estimadas` (juicio experto) para
medir después el error de estimación.

- Escala `VL, L, N, H, VH, XH` (tablas de COCOMO II.2000 en `datos/cocomo-ii-2000.json`).
- Los 5 factores de escala se califican en la fila `000-proyecto`.
- Los multiplicadores se califican por funcionalidad; sin calificación valen `N`.

Multiplicadores candidatos propios de SDD (neutros, 1.00, hasta calibrarlos):

| Código | Nombre | Qué captura |
|---|---|---|
| `AIAS` | Asistencia IA | Proporción del código generada por el agente |
| `SPMA` | Madurez de la especificación | Requisitos completos y estables al iniciar el plan |
| `HWVR` | Verificación en hardware | Dependencia de pruebas manuales en dispositivos |
| `NOVT` | Novedad tecnológica | APIs poco maduras o sin experiencia previa |

## 6. Calibración (`calibrar`)

1. Por cada medida de tamaño con al menos 2 puntos, regresión
   `ln(PM / ΠEM) = ln(A) + E·ln(Size)`. Con menos de 3 puntos, `E` se fija en el valor de
   COCOMO II y solo se ajusta `A`.
2. Precisión: MMRE, PRED(25) y MMRE en validación cruzada dejando uno fuera (LOOCV). La medida
   con menor MMRE LOOCV se marca como la mejor.
3. Comparación con COCOMO II.2000 estándar sobre KSLOC.
4. Tiempo: regresión `ln(TDEV) = ln(C) + F·ln(PM)`; con datos insuficientes, valores estándar.
5. Costo de IA por persona-mes, distribución del esfuerzo por fase, tasas de desperdicio y
   sobrecarga transversal.

## 7. Amenazas a la validez

- Pocos puntos de datos al inicio: los modelos son exploratorios.
- Curva de aprendizaje: las primeras funcionalidades cuestan más.
- Cambios de modelo de IA o de nivel de razonamiento durante el proyecto (por eso se registran
  en cada sesión).
- Registro de horas incompleto o redondeado.
- Código descartado antes del commit no queda medido.
- Las líneas físicas incluyen formato y archivos de configuración.
