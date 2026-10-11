---
description: "Cerrar la sesion activa y registrar horas y lineas de codigo generadas/eliminadas"
---

# Cerrar sesion de metricas

Cierra la sesion activa y la guarda en `metricas/sesiones/` (un archivo por sesion) con las horas, el
modelo de IA y las lineas de codigo agregadas y eliminadas (clasificadas por causa).

## Entrada del usuario

```text
$ARGUMENTS
```

## Antes de cerrar

1. Solo se cuentan cambios **confirmados**. Si hay cambios sin commit de la sesion, ofrezca
   hacer commit primero.
2. **Causa de las eliminaciones.** Todo commit que elimina o reescribe codigo debe llevar al
   final del mensaje el trailer `Causa: requisito|defecto|refactor`:
   - `requisito`: la especificacion cambio y el codigo ya no sirve (desperdicio).
   - `defecto`: el codigo estaba mal hecho o el agente lo genero incorrectamente (desperdicio).
   - `refactor`: mejora interna sin cambio de comportamiento.
   Al generar commits de correccion usted mismo, incluya siempre este trailer.
3. Convencion para codigo generado por IA: haga commit de lo que genero el agente **antes** de
   corregirlo, y las correcciones en commits aparte con `Causa: defecto`.

## Datos a pedir o inferir

- `-Actividad`: descripcion breve de lo realizado (inferirla de la conversacion).
- `-PausaMinutos` o `-Horas`: pregunte al usuario cuanto tiempo efectivo dedico si el lapso
  incluye pausas; si no responde, use el calculo automatico.
- `-Tokens` y `-CostoUsd`: solo si la herramienta los informa con certeza.
- `-Retrabajo`: si la sesion corrigio algo ya dado por terminado.

## Ejecucion

- **Windows**: `powershell -NoProfile -ExecutionPolicy Bypass -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 cerrar -Actividad "<texto>" [-PausaMinutos N | -Horas H] [-Tokens N] [-CostoUsd X] [-Retrabajo]`
- **Linux/macOS**: `pwsh -NoProfile -File .specify/extensions/metricas/scripts/powershell/sesion.ps1 cerrar ...`

No interpole texto del usuario sin comillas; escape las comillas dobles del texto de actividad.

Muestre al usuario el resumen que imprime el script (lineas generadas, eliminadas por causa y
desperdicio). Si hay eliminaciones "sin clasificar", sugiera corregir los mensajes de commit.
