# Contribuir

## Con datos

El valor de este proyecto crece con cada dataset. Para compartir el suyo:

1. Ejecute `/speckit-metricas-exportar` con anonimización (`exportar.ps1 -Anonimizar`).
2. Revise el contenido del `dataset-*.zip` antes de enviarlo.
3. Abra un issue con la etiqueta `dataset` y adjunte el archivo, indicando si autoriza su
   publicación en el conjunto de datos abierto del repositorio.

## Con código

- Los scripts deben funcionar en Windows PowerShell 5.1 y PowerShell 7 y contener solo ASCII.
- Ejecute `pwsh -File tests/prueba-integral.ps1` antes de abrir un pull request.
- Los cambios en las columnas de datos o en los pesos de PTS requieren nueva versión menor y
  una nota en `CHANGELOG.md`, porque afectan la comparabilidad entre proyectos.
