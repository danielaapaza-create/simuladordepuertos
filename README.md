# Muelle — Ecosistema de Datos de Costos Logísticos (Prototipo)

Prototipo web que reemplaza el consolidado `Resumen de gastos Puerto Chancay.xlsx`.
Cubre 2 puertos (Callao, Chancay), 3 plantas (Chancay 5003, GH Chancay 5029, Lurín
5001) y 3 transportistas (TOSA E.I.R.L., TRANSJIBAJA S.A.C., Vilma Rojas).

## Cómo probarlo
Es un único archivo estático, no requiere build ni backend:

```bash
# opción rápida
open index.html            # o doble clic en el archivo

# o, para simular un servidor:
python3 -m http.server 8000
# abrir http://localhost:8000
```

## Cómo publicarlo en tu repo de GitHub
```bash
git clone https://github.com/danielaapaza-create/simuladordepuertos.git
cp index.html README.md simuladordepuertos/
cd simuladordepuertos
git add .
git commit -m "Prototipo v0.1: panel de costos logísticos"
git push origin main
```
Luego, en **Settings → Pages** del repo, activa GitHub Pages sobre la rama `main`
(carpeta raíz) para tener una URL pública en minutos.

## Qué resuelve este prototipo (Fase 1 del objetivo planteado)

| Objetivo del brief | Cómo se resuelve aquí |
|---|---|
| Centralizar información de costos logísticos | Un solo objeto `DATA` (maestros: puertos, plantas, transportistas, tarifas de flete, tarifas de descarga, almacenamiento) alimenta **todas** las pantallas — nada se copia/pega entre hojas. |
| Automatizar cálculos | `calcDescarga`, `calcTransporte`, `calcAlmacenamiento` y `calcTotal` reemplazan las fórmulas dispersas en 18 hojas del Excel. |
| Trazabilidad de las simulaciones | Cada corrida del Simulador se guarda con analista, fecha/hora, parámetros y resultado, exportable a CSV — pestaña "Trazabilidad". Además queda enlazada al **ID de la versión de tarifas** con la que se calculó. |
| Reglas de gobierno de datos | Pestaña "Maestros & Gobierno": las tarifas **nunca se sobrescriben**. Cada cambio se edita como borrador y se publica como una **nueva versión con fecha de vigencia, responsable y nota**; las versiones anteriores quedan en un historial consultable y reutilizable ("Usar de nuevo"). |
| Capacidades analíticas | Panel General: gasto real por puerto, distribución de flete por transportista, top desviaciones presupuestarias. |
| Base para modelos predictivos/prescriptivos (fase 2) | Ver pestaña "Hoja de Ruta" dentro de la app. |

## Modelo de datos (semilla)

Los valores de arranque salen directamente del Excel:

- **Tarifas de flete Puerto Chancay → planta** (hoja `Gastos de Transporte` / `tarifas`):
  S/9.50–50.00 por TN según planta y transportista.
- **Tarifas de flete Puerto Callao → planta** (hoja `Gastos APM`): promedios de
  S/23.96–31.51 por TN (no discriminados por transportista en el Excel original —
  quedan editables).
- **Costos de descarga por puerto** (hoja `Gastos de descarga BI`): balanza,
  comisión de agente, gastos de área operativa y A&G, en S//TN.
- **Tipo de cambio**: S/3.35 por US$ (editable).
- **Histórico de 23 naves 2026** (hoja `Comparativo`): puerto, tonelaje, producto,
  gasto presupuestado vs. gasto real (COSCO/APM).

Los datos de almacenamiento por producto y las tarifas de flete desde Callao por
transportista son **estimaciones** marcadas explícitamente en la interfaz —
deben validarse contra contrato antes de usarse para decisiones reales.

## Qué falta para producción

1. Reemplazar `localStorage` por una base de datos real (Postgres/Supabase) y una
   API — hoy la "capa de datos" vive en el navegador para efectos del prototipo.
2. Importar la hoja `BD` (~990 registros de balanza/APM) para calcular transporte
   desde el peso real por viaje, no solo por simulación manual.
3. Autenticación y roles (analista / jefe de logística / finanzas) para el
   gobierno de datos formal.
4. Conectar `Laytime2024` / `Laytime2025` para dispatch/demurrage automático.

## Stack
HTML + CSS + JavaScript vanilla, [Chart.js](https://www.chartjs.org/) vía CDN.
Sin dependencias de build — pensado para iterar rápido y luego migrar a
React/Next si el equipo lo prefiere para la Fase 2.
