/* main.js — router de pestañas, reloj del tablero y arranque de la app.
   Debe cargarse DESPUÉS de todos los demás módulos js/*.js. */

const content = document.getElementById('content');
document.getElementById('nav').addEventListener('click', e=>{
  const btn = e.target.closest('button[data-tab]');
  if(!btn) return;
  document.querySelectorAll('.nav button').forEach(b=>b.classList.remove('active'));
  btn.classList.add('active');
  render(btn.dataset.tab);
});

function toast(msg){
  const t = document.getElementById('toast');
  document.getElementById('toastMsg').textContent = msg;
  t.classList.add('show');
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(()=>t.classList.remove('show'), 2400);
}

function render(tab){
  if(tab==='dashboard') return renderDashboard();
  if(tab==='naves') return renderNaves();
  if(tab==='simulador') return renderSimulador();
  if(tab==='trazabilidad') return renderTrazabilidad();
  if(tab==='maestros') return renderMaestros();
  if(tab==='roadmap') return renderRoadmap();
}

/* =====================================================================
   5. TABLERO DE KPIs (tarjetas ejecutivas)
   ===================================================================== */

/* Iconos de línea, discretos, reutilizados por cada tarjeta KPI */
const KPI_ICONS = {
  tn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/></svg>',
  gasto: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M9 9.3c0-1 1-1.6 3-1.6s3 .6 3 1.6c0 2.2-6 1.6-6 3.8 0 1 1 1.6 3 1.6s3-.6 3-1.6"/><path d="M12 6v1.7M12 15.7V17"/></svg>',
  ahorro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 17l6-6 4 4 8-8"/><path d="M15 7h6v6"/></svg>',
  tarifas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13.5l2 2 4-4.5"/></svg>',
};

function updateBoard(){
  const totalTn = NAVES_HISTORICO.reduce((s,n)=>s+n.tn,0);
  const totalReal = NAVES_HISTORICO.reduce((s,n)=>s+n.apm,0);
  const totalPresupuesto = NAVES_HISTORICO.reduce((s,n)=>s+n.presupuesto,0);
  const ahorro = totalPresupuesto - totalReal;
  const naves = NAVES_HISTORICO.length;
  // Variación de gasto real vs. presupuesto — derivada de los mismos totales ya calculados arriba.
  const pctReal = totalPresupuesto ? (totalReal-totalPresupuesto)/totalPresupuesto*100 : 0;
  const sobrePresupuesto = pctReal > 0;

  document.getElementById('flapRow').innerHTML = `
    <div class="flap">
      <div class="flap-head"><span class="label">TN descargadas 2026</span><span class="flap-icon">${KPI_ICONS.tn}</span></div>
      <div class="flap-value-row"><span class="value">${fmtN(totalTn)}</span><span class="unit">TN</span></div>
      <div class="delta"><span class="trend neutral">●</span>${naves} naves registradas</div>
    </div>
    <div class="flap">
      <div class="flap-head"><span class="label">Gasto real acumulado</span><span class="flap-icon">${KPI_ICONS.gasto}</span></div>
      <div class="flap-value-row"><span class="value ${sobrePresupuesto?'pos':'neg'}">${fmtN(totalReal)}</span><span class="unit">S/</span></div>
      <div class="delta"><span class="trend ${sobrePresupuesto?'down':'up'}">${sobrePresupuesto?'▲':'▼'}</span>${Math.abs(pctReal).toFixed(1)}% ${sobrePresupuesto?'sobre':'bajo'} presupuesto</div>
    </div>
    <div class="flap">
      <div class="flap-head"><span class="label">Ahorro vs. presupuesto</span><span class="flap-icon">${KPI_ICONS.ahorro}</span></div>
      <div class="flap-value-row"><span class="value ${ahorro>=0?'neg':'pos'}">${fmtN(Math.abs(ahorro))}</span><span class="unit">S/</span></div>
      <div class="delta"><span class="trend ${ahorro>=0?'up':'down'}">${ahorro>=0?'▲':'▼'}</span>${ahorro>=0?'bajo presupuesto':'sobre presupuesto'}</div>
    </div>
    <div class="flap">
      <div class="flap-head"><span class="label">Tarifas vigentes</span><span class="flap-icon">${KPI_ICONS.tarifas}</span></div>
      <div class="flap-value-row"><span class="value sm">${getActiveVersion().id}</span></div>
      <div class="delta"><span class="trend neutral">●</span>${DATA.versions.length} versión(es) en historial</div>
    </div>
  `;
}
function tickClock(){
  const el = document.getElementById('clock');
  const d = new Date();
  el.textContent = d.toLocaleDateString('es-PE',{weekday:'short',day:'2-digit',month:'short',year:'numeric'}).toUpperCase() + '  ·  ' + d.toLocaleTimeString('es-PE');
}
setInterval(tickClock,1000); tickClock();

/* =====================================================================
   INIT — arranca en la pestaña Panel General
   ===================================================================== */
render('dashboard');

/* =====================================================================
   6. DASHBOARD
   ===================================================================== */
