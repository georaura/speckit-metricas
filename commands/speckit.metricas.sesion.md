---
description: "Abrir o cambiar la sesion de trabajo registrando fase, herramienta y modelo de IA"
---

# Sesion de metricas

Registra el inicio de una sesion de trabajo de la metodologia SDD. Si ya hay una sesion activa,
la cierra (contando horas y lineas de codigo) y abre la nueva.

## Entrada del usuario

```text
$ARGUMENTS
```

## Comportamiento

1. **Fase.** Si este comando se invoca como hook, la fase sale del evento (`before_plan` ->
   `planificar`, etc.): pase el evento con `-Evento <evento>`. Si el usuario lo invoca
   directamente, tome la fase de `$ARGUMENTS`; valores validos: `vision`, `constitucion`,
   `especificar`, `aclarar`, `planificar`, `tareas`, `analizar`, `implementar`, `probar`,
   `verificar-dispositivo`, `integrar`, `infraestructura`, `gestion`, `aprendizaje`.
2. **Herramienta, modelo y version (obligatorio, no inventar).**
   - `-Herramienta`: el agente o IDE que esta ejecutando este comando, en minusculas
     (p. ej. `claude-code`, `antigravity`, `copilot`, `cursor`, `gemini-cli`, `codex`).
   - `-ModeloIA`: el identificador **exacto** del modelo con su version, tal como lo conoce
     usted por su configuracion o instrucciones de sistema (p. ej. `claude-opus-5-5`,
     `gemini-3-pro`, `gpt-5.1-codex`). No use nombres genericos ("Claude", "GPT").
   - `-NivelRazonamiento`: nivel de esfuerzo o razonamiento configurado para el modelo
     (p. ej. `low`, `medium`, `high`, `xhigh`, `max`), si la herramienta lo permite. Es una
     variable distinta de la version: el mismo modelo con otro nivel es otra configuracion.
   - `-VersionHerramienta`: version del agente/IDE si la conoce; si no, omitala.
   - Si no conoce con certeza el modelo o el nivel y no estan definidas las variables
     `METRICAS_MODELO_IA` / `METRICAS_NIVEL_RAZONAMIENTO` / `METRICAS_HERRAMIENTA`, pregunte al
     usuario antes de ejecutar.
3. La funcionalidad se detecta sola a partir de la rama `NNN-nombre`; no la pase salvo que el
   usuario indique otra.

## Ejecucion

Desde la raiz del repositorio:

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 cambiar [-Evento <evento> | -Fase <fase>] -Herramienta <herramienta> -ModeloIA <modelo> [-NivelRazonamiento <nivel>] [-VersionHerramienta <version>]`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 cambiar ...` (mismos parametros)

Para consultar la sesion activa use la accion `estado`; para descartarla, `cancelar`.

## Degradacion

- Si `metricas/config.json` no existe y el comando viene de un hook, el script avisa y no hace
  nada: continue con el comando principal sin bloquear el flujo.
- Si el script falla, informe el error al usuario y continue con el comando principal.
- Si el script indica que dejo `horas_humano` vacio (lapso muy largo entre comandos), recuerde al
  usuario que complete esas horas en el archivo de la sesion dentro de `metricas/sesiones/`.
