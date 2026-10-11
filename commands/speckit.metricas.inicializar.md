---
description: "Crear la carpeta metricas/ con la configuracion y el registro de sesiones"
---

# Inicializar metricas

Crea `metricas/` en la raiz del repositorio con `config.json`, `factores-cocomo.csv` y
`sesiones/historico.csv`, y agrega al `.gitignore` el estado de sesion y las salidas. No
sobrescribe archivos existentes.

## Entrada del usuario

```text
$ARGUMENTS
```

## Ejecucion

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/inicializar.ps1 [-Proyecto <nombre>]`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/inicializar.ps1 [-Proyecto <nombre>]`

## Despues de ejecutar

Ayude al usuario a completar `metricas/config.json`, inferiendo lo posible del README o del
documento de vision y preguntando lo demas:

- `descripcion`, `dominio` (p. ej. `salud`, `educacion`, `finanzas`), `tipo_aplicacion`
  (p. ej. `web`, `movil`, `api`, `web-xr`), `tamano_equipo`.
- `moneda` y `costo_hora_humano` (tarifa por hora de la persona; 0 si no se quiere calcular costo).
- `extensiones_codigo` y `rutas_excluidas` segun el stack del proyecto.

Recuerde al usuario:

1. Los commits llevan el numero de funcionalidad como ambito: `feat(001): ...`, `fix(001): ...`.
2. Los commits que eliminan o reescriben codigo llevan el trailer `Causa: requisito|defecto|refactor`.
3. Calificar los factores de escala del proyecto (fila `000-proyecto` de `factores-cocomo.csv`)
   y, al terminar cada `/speckit-plan`, los multiplicadores de esa funcionalidad.
