# Puntos de Tarea SDD (PTS)

> Propuesta de medida de tamaño para proyectos desarrollados con Spec-Driven Development.
> Versión de la propuesta: 1.0 (pesos iniciales, sin calibrar).

## 1. Motivación

COCOMO II necesita una medida de tamaño: líneas de código (KSLOC) o puntos de función. En el
desarrollo asistido por IA ambas tienen problemas:

- **Líneas de código:** el agente genera código barato y abundante; las líneas dejan de reflejar
  el esfuerzo humano, que se desplaza a especificar, revisar y verificar.
- **Puntos de función (IFPUG, COSMIC):** son estándares ISO y miden la funcionalidad desde el
  usuario, pero contarlos exige un especialista y no forma parte del flujo SDD.

En Spec Kit, `/speckit-tasks` produce `tasks.md`: una descomposición explícita y estructurada del
trabajo (identificador, paralelismo `[P]`, historia `[USn]`, fase y archivos afectados) **antes
de implementar**. PTS propone usar ese artefacto como base de la medida de tamaño.

## 2. Estado del arte

| Medida | Estándar | Base | Comparable entre equipos |
|---|---|---|---|
| Puntos de función IFPUG | ISO/IEC 20926 | Requisitos funcionales | Sí |
| COSMIC | ISO/IEC 19761 | Movimientos de datos | Sí |
| Use Case Points (Karner, 1993) | No (publicado) | Casos de uso y actores | Parcial |
| Object / Application Points (COCOMO II) | No (parte del modelo) | Pantallas, reportes, componentes | Parcial |
| Story points | No | Juicio relativo del equipo | No |
| **PTS (esta propuesta)** | **No** | **Tareas de `tasks.md` clasificadas** | **Por validar** |

Trabajos recientes relacionados: ACEM (arXiv:2608.02582) modela el costo de la ingeniería con
agentes a partir de tokens, intervención humana e infraestructura; SDAD (arXiv:2608.20341)
plantea que en SDD la estimación debe desplazarse a la especificación y la verificación. Hasta
donde se revisó, ninguno usa la descomposición de tareas del plan como medida de tamaño. Antes de
publicar resultados debe hacerse una revisión sistemática de la literatura.

## 3. Reglas de conteo

1. **Unidad:** cada tarea de `tasks.md` con formato `- [ ] T### ...`.
2. **Tipo** según lo que la tarea produce (no según las palabras que usa):
   `configuracion`, `datos`, `logica`, `interfaz`, `integracion`, `prueba`, `documentacion`.
3. **Complejidad:**
   - `baja`: un archivo, patrón conocido, sin dependencias ni decisiones de diseño.
   - `media`: dos o tres archivos, o depende de otras tareas, o requiere decisiones locales.
   - `alta`: cuatro o más archivos, algoritmo o protocolo no trivial, tecnología nueva, hardware
     o rendimiento crítico.
4. **Peso** según la matriz:

   | Tipo | Baja | Media | Alta |
   |---|---|---|---|
   | configuracion | 1 | 2 | 3 |
   | datos | 2 | 3 | 5 |
   | logica | 3 | 5 | 8 |
   | interfaz | 3 | 5 | 8 |
   | integracion | 4 | 6 | 10 |
   | prueba | 1 | 2 | 4 |
   | documentacion | 1 | 1 | 2 |

5. **PTS** = suma de los pesos de las tareas vigentes.
6. **Línea base:** la primera clasificación, al terminar `/speckit-tasks`, define `PTS_plan`. Las
   tareas agregadas o eliminadas después se registran por separado:
   - `PTS_final` = tareas vigentes al cierre.
   - Volatilidad = (puntos agregados + puntos eliminados) / `PTS_plan`.

`PTS_plan` es la medida útil para **estimar** (se conoce antes de implementar); `PTS_final` sirve
para **explicar** el esfuerzo real.

## 4. Hipótesis a validar

| # | Hipótesis | Cómo se contrasta |
|---|---|---|
| P1 | PTS es **reproducible** | Dos evaluadores (personas o agentes) clasifican el mismo `tasks.md`; concordancia con κ de Cohen ponderado ≥ 0.6 y diferencia de PTS < 15 % |
| P2 | PTS **predice el esfuerzo** mejor que KSLOC y que el conteo de requisitos | MMRE y PRED(25) en validación cruzada con datos de varios proyectos (`calibrar`) |
| P3 | Ponderar **mejora** sobre contar tareas | Comparar `puntos_tarea` contra `tareas` en la calibración |
| P4 | Los pesos iniciales son **mejorables** | Regresión del esfuerzo por tarea sobre el tipo y la complejidad cuando haya suficientes datos |

## 5. Amenazas a la validez

- **Granularidad dependiente del modelo de IA:** distintos modelos o versiones descomponen el
  trabajo con distinto detalle. Por eso se registra el modelo en cada sesión: analice PTS por
  modelo y considere normalizar.
- **Dependencia de la plantilla de tareas** de Spec Kit; un cambio de plantilla cambia la medida.
- **Clasificación por el mismo agente que generó las tareas:** puede introducir sesgo; contrastar
  con clasificación humana en una muestra.
- **Pocos proyectos al inicio:** los resultados son exploratorios hasta reunir datos de muchos.

## 6. Cómo citar

Si usa PTS o los datos de esta extensión en un trabajo académico, cite el repositorio y la versión
de la propuesta (`datos/puntos-tarea.json`, campo `version`).
