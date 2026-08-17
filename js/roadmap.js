/* roadmap.js — Pestaña 'Hoja de Ruta'. */

/* Mismo contenido de fases que la versión anterior; solo cambia cómo se
   arma el marcado (timeline vertical) en vez de una lista plana. El único
   estado real disponible es "esta es la fase actual del prototipo" (antes
   codificado como la clase 'now' en la fase 1) — el resto se presenta de
   forma neutral como "Próximo", sin inventar avances o fechas. */
const ROADMAP_PHASES = [
  {
    n: '01',
    title: 'Centralizar & automatizar (este prototipo)',
    desc: 'Maestros únicos de puertos, plantas, transportistas y tarifas. Cálculo automático de descarga + transporte + almacenamiento. Simulador Callao vs. Chancay. Registro de trazabilidad de cada simulación con autor y fecha.',
    current: true,
  },
  {
    n: '02',
    title: 'Integrar fuentes operativas',
    desc: 'Conectar directamente con el sistema de balanza/APM (hoja "BD" del Excel: ~990 registros de ingreso/salida de camiones) para que el costo de transporte se calcule desde el peso real por viaje, no por simulación manual. Definir API/ETL en vez de copiar y pegar Excel.',
  },
  {
    n: '03',
    title: 'Gobierno de datos formal',
    desc: 'Roles y permisos por perfil (analista, jefe de logística, finanzas), versionado completo de tarifas, aprobación de cambios de maestros, y catálogo de datos con definiciones estándar (diccionario de datos).',
  },
  {
    n: '04',
    title: 'Analítica avanzada',
    desc: 'Tableros de laytime/demurrage (hojas "Laytime2024/2025"), estacionalidad de costos por producto, y benchmarking histórico Callao vs. Chancay por transportista y planta.',
  },
  {
    n: '05',
    title: 'Modelos predictivos y prescriptivos',
    desc: 'Predecir el costo total esperado de una nave según producto, tonelaje y temporada; recomendar automáticamente puerto + transportista óptimo sujeto a restricciones de capacidad de almacenamiento y ventanas de atraque.',
  },
];

function renderRoadmap(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Hoja de Ruta del Ecosistema</h1>
      <p>Este prototipo cubre la Fase 1. Así se conecta con las capacidades analíticas, predictivas y prescriptivas que sigue.</p>
    </div>
    <div class="card">
      <div class="timeline">
        ${ROADMAP_PHASES.map(p=>`
          <div class="timeline-item ${p.current?'is-current':''}">
            <div class="timeline-rail">
              <span class="timeline-node">${p.n}</span>
              <span class="timeline-line"></span>
            </div>
            <div class="timeline-body">
              <div class="timeline-top">
                <h4>${p.title}</h4>
                <span class="badge ${p.current?'badge-current':'badge-upcoming'}">${p.current?'En curso':'Próximo'}</span>
              </div>
              <p>${p.desc}</p>
            </div>
          </div>`).join('')}
      </div>
    </div>
  `;
}
