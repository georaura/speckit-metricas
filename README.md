# speckit-metricas

Extensión de [GitHub Spec Kit](https://github.com/github/spec-kit) para **medir el esfuerzo de
proyectos desarrollados con Spec-Driven Development (SDD) asistido por IA** y **calibrar un
modelo de estimación de esfuerzo, tiempo y costo tipo COCOMO II** con datos de varios proyectos.

> Estado: **0.3.0 experimental**. Los formatos de datos pueden cambiar antes de la 1.0.

## Qué mide

| Dimensión | Cómo se obtiene |
|---|---|
| **Esfuerzo humano por fase SDD** | Sesiones abiertas automáticamente por los hooks de cada `/speckit-*` |
| **Modelo de IA y herramienta** | El agente registra su identificador exacto, versión y nivel de razonamiento (p. ej. `claude-opus-5-5`, `medium`) |
| **Líneas generadas por sesión** | Commit a commit desde Git (código de producción y pruebas por separado) |
| **Líneas desperdiciadas** | Eliminaciones clasificadas por causa (`requisito`, `defecto`, `refactor`) y supervivencia final con `git blame` |
| **Tamaño de la especificación** | Historias, requisitos (`FR-`), criterios (`SC-`), escenarios, tareas |
| **Puntos de Tarea SDD (PTS)** | Medida de tamaño propuesta: tareas de `tasks.md` ponderadas por tipo y complejidad |
| **Duración y costo** | Calendario desde Git; costo = horas × tarifa + costo de IA |

Con esos datos, `calibrar` ajusta `PM = A·Size^E·ΠEM` y `TDEV = C·PM^F` para cada medida de
tamaño, informa MMRE, PRED(25) y validación cruzada, y lo compara con COCOMO II.2000.

## Requisitos

- Spec Kit (`specify-cli`) y un agente compatible (Claude Code, Antigravity, Copilot, Cursor…)
- Git
- PowerShell: Windows PowerShell 5.1 (incluido en Windows) o
  [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
  en Linux/macOS

## Instalación

```bash
# Desde una versión publicada
specify extension add metricas --from https://github.com/georaura/speckit-metricas/archive/refs/tags/v0.3.0.zip

# Desde una copia local (desarrollo)
specify extension add --dev /ruta/a/speckit-metricas
```

> Con `--dev`, Specify copia la carpeta completa. Si es un clon de Git, se copiaría también
> `.git` dentro de `.specify/extensions/metricas/` y una reinstalación fallaría en Windows
> (archivos de solo lectura). Instale desde el `.zip` del release o desde una copia sin `.git`.

Luego, en el chat del agente:

```
/speckit-metricas-inicializar
```

Esto crea `metricas/` en el repositorio con `config.json`, `factores-cocomo.csv` y `sesiones/`.
Complete en `config.json` la descripción, el dominio, la tarifa por hora y las extensiones de
código del proyecto.

## Uso diario

El registro es casi automático:

1. Cada `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-implement`… dispara un hook
   que **cierra la sesión anterior y abre la de la nueva fase**, con el modelo de IA del agente.
2. Al terminar `/speckit-tasks`, el hook `/speckit-metricas-puntos` fija la **línea base de PTS**.
3. Si deja de trabajar (almuerzo, reunión, fin del día), use `/speckit-metricas-pausetask` y al
   volver `/speckit-metricas-resumetask`: las pausas se descuentan solas de las horas.
4. **Pausa automática**: si entre dos actividades pasan más de `minutos_inactividad_pausa`
   (30 por defecto, en `metricas/config.json`), ese hueco se descuenta como pausa automática,
   aunque nadie haya pedido la pausa: por ejemplo, cuando se agota el límite de uso del agente o la
   persona se va sin avisar. Se registra aparte en `minutos_pausa_auto`. Para que funcione, el agente
   debe informar su actividad (ver «Hooks del agente»).
4. Para trabajo fuera de los comandos (pruebas en dispositivo, aprendizaje, integración) use
   `/speckit-metricas-sesion verificar-dispositivo` y `/speckit-metricas-cerrar`.

Dos convenciones de commits hacen posible medir el código:

```
feat(001): carga de panoramas            ← ámbito = número de funcionalidad

fix(001): corrige la orientación inicial

Causa: defecto                           ← trailer obligatorio si se elimina o reescribe código
```

| `Causa:` | Cuándo | ¿Desperdicio? |
|---|---|---|
| `requisito` | La especificación cambió y el código ya no sirve | Sí |
| `defecto` | El código estaba mal (incluida salida incorrecta del agente) | Sí |
| `refactor` | Mejora interna sin cambio de comportamiento | No |

Haga commit de lo que generó el agente **antes** de corregirlo; si no, ese desperdicio no queda
registrado.

## Comandos

| Comando | Qué hace |
|---|---|
| `/speckit-metricas-inicializar` | Crea `metricas/` y ayuda a completar la configuración |
| `/speckit-metricas-sesion` | Abre o cambia la sesión (fase, herramienta, modelo de IA) |
| `/speckit-metricas-cerrar` | Cierra la sesión y registra horas y líneas por causa |
| `/speckit-metricas-pausetask` | Pausa la sesión: el tiempo deja de contarse (dejé de trabajar) |
| `/speckit-metricas-resumetask` | Reanuda la sesión pausada |
| `/speckit-metricas-puntos` | Calcula los Puntos de Tarea SDD de la funcionalidad |
| `/speckit-metricas-recolectar` | Resume tamaño, duración, esfuerzo, costo y desperdicio |
| `/speckit-metricas-exportar` | Empaqueta el dataset del proyecto (opcionalmente anonimizado) |
| `/speckit-metricas-calibrar` | Consolida datasets y calibra el modelo |
| `/speckit-metricas-estimar` | Estima esfuerzo, tiempo y costo con el modelo calibrado |

Los scripts de `scripts/powershell/` también se pueden ejecutar directamente.

## Hooks

| Evento | Comando | Obligatorio |
|---|---|---|
| `before_constitution`, `before_specify`, `before_clarify`, `before_plan`, `before_tasks`, `before_analyze`, `before_checklist`, `before_implement` | `speckit.metricas.sesion` | Sí (no bloquea si las métricas no están inicializadas) |
| `after_tasks` | `speckit.metricas.puntos` | Sí |
| `after_implement` | `speckit.metricas.cerrar` | Opcional |

## Hooks del agente (pausa automática)

La extensión detecta la inactividad comparando la hora actual con la última actividad registrada.
En **Claude Code**, agregue a `.claude/settings.json` del proyecto:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 actividad" }] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "node -e \"try{require('fs').writeFileSync(require('path').join(process.env.CLAUDE_PROJECT_DIR||'.','metricas','.ultima-actividad'),String(Date.now()))}catch{}\"" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "node -e \"try{require('fs').writeFileSync(require('path').join(process.env.CLAUDE_PROJECT_DIR||'.','metricas','.ultima-actividad'),String(Date.now()))}catch{}\"" }] }
    ]
  }
}
```

- `UserPromptSubmit` (cada mensaje de la persona) descuenta el hueco si superó el umbral.
- `PostToolUse` y `Stop` (cada acción del agente) solo escriben la hora en
  `metricas/.ultima-actividad`; es rápido y evita que una tarea larga del agente cuente como
  inactividad. En Linux/macOS reemplace `powershell` por `pwsh`.

En otros agentes, configure un hook equivalente o ejecute `sesion.ps1 actividad` al retomar.

## Datos y privacidad

- `metricas/sesiones/` guarda **un archivo por sesión** para evitar conflictos entre ramas.
- Los datos se quedan en su repositorio. Nada se envía a ningún servicio.
- `exportar -Anonimizar` reemplaza el nombre del desarrollador por un hash y elimina el texto
  libre antes de compartir el dataset.

## Contribuir con datos

El objetivo es reunir datasets de muchos proyectos SDD para calibrar un modelo de estimación
útil para la comunidad. Si termina un proyecto con esta extensión, considere compartir su
`dataset-*.zip` anonimizado (vea [CONTRIBUTING.md](CONTRIBUTING.md)).

## Documentación

- [Metodología](docs/metodologia.md): definiciones, hipótesis, análisis y amenazas a la validez.
- [Puntos de Tarea SDD](docs/puntos-tarea-sdd.md): la medida de tamaño propuesta y cómo validarla.

## Pruebas

```powershell
pwsh -File tests/prueba-integral.ps1
```

## Licencia

[MIT](LICENSE)
