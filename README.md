# Muelle — Ecosistema de Datos de Costos Logísticos (Prototipo)

Prototipo web que reemplaza el consolidado `Resumen de gastos Puerto Chancay.xlsx`.
Cubre 2 puertos (Callao, Chancay), 3 plantas (Chancay 5003, GH Chancay 5029, Lurín
5001) y 3 transportistas (TOSA E.I.R.L., TRANSJIBAJA S.A.C., Vilma Rojas).

## Estructura del proyecto
```
simuladordepuertos/
├── index.html            # esqueleto de la página + orden de carga de scripts
├── css/
│   └── styles.css        # todos los tokens de diseño y estilos
├── js/
│   ├── data.js            # DATOS SEMILLA: catálogos y tarifas iniciales del Excel
│   ├── store.js           # persistencia (localStorage) y versionado de tarifas
│   ├── calc.js             # motor de cálculo: descarga, transporte, almacenamiento, total
│   ├── dashboard.js       # pestaña "Panel General"
│   ├── naves.js            # pestaña "Naves & Comparativo"
│   ├── simulador.js       # pestaña "Simulador"
│   ├── trazabilidad.js    # pestaña "Trazabilidad"
│   ├── maestros.js        # pestaña "Maestros & Gobierno" (edición/versionado de tarifas)
│   ├── roadmap.js         # pestaña "Hoja de Ruta"
│   └── main.js             # router de pestañas, reloj del tablero, arranque — se carga último
└── README.md
```
`js/data.js` es la única fuente de los valores semilla (nada de lógica). `js/store.js` y
`js/calc.js` son el "backend" del prototipo: manejan versionado de tarifas y cálculos, sin
tocar el DOM. Los archivos por pestaña solo hacen `render*()` e interacción con el usuario.
`main.js` debe cargarse último porque referencia funciones de todos los demás.

## Cómo probarlo
No requiere build ni backend — pero al usar módulos separados (`<script src="js/...">`),
el navegador bloquea `fetch` de archivos locales por seguridad, así que ábrelo con un
servidor simple en vez de doble clic:

```bash
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

## Backend (Supabase)

El esquema de base de datos vive en `supabase/migrations/` y traduce 1:1 el
modelo de `js/data.js` a tablas Postgres con Row Level Security:

- `20260820150147_init_schema.sql` — tablas (`plantas`, `transportistas`,
  `productos`, `tarifa_versiones` + tablas hijas, `naves_historico`,
  `simulaciones`, `profiles`), roles `admin`/`analista` vía Supabase Auth,
  y políticas RLS. Las tarifas quedan **inmutables a nivel de base de datos**:
  solo hay política de `INSERT` para admin, nunca de `UPDATE`/`DELETE` —
  corregir una tarifa exige crear una nueva versión, igual que en la UI.
- `20260820150149_seed_maestros.sql` — carga los mismos valores semilla que
  hoy están hardcodeados en `js/data.js` (catálogos, versión `V-2026-01`,
  histórico de 23 naves).

Validado localmente contra Postgres 16 (esquema, seed y políticas RLS
probadas con usuarios admin/analista simulados) antes de subirlas.

**Para aplicarlas a un proyecto Supabase real:**
```bash
npx supabase login
npx supabase link --project-ref <tu-project-ref>
npx supabase db push
```
o, más simple sin CLI: pega el contenido de ambos archivos, en orden, en el
**SQL Editor** del dashboard de Supabase.

## Qué falta para producción

1. ~~Reemplazar `localStorage` por una base de datos real~~ — esquema listo en
   `supabase/migrations/`; falta conectar el frontend (`js/store.js`) a
   `supabase-js` en lugar de `localStorage`.
2. Importar la hoja `BD` (~990 registros de balanza/APM) para calcular transporte
   desde el peso real por viaje, no solo por simulación manual.
3. Autenticación y roles (analista / jefe de logística / finanzas) — el esquema
   ya define `profiles.role` (`admin`/`analista`) y políticas RLS; falta
   activar Supabase Auth en el frontend (login) y asignar roles reales.
4. Conectar `Laytime2024` / `Laytime2025` para dispatch/demurrage automático.

## Stack
HTML + CSS + JavaScript vanilla, [Chart.js](https://www.chartjs.org/) vía CDN.
Sin dependencias de build — pensado para iterar rápido y luego migrar a
React/Next si el equipo lo prefiere para la Fase 2.
