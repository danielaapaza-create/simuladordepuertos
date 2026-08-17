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
   5. TERMINAL BOARD (KPIs)
   ===================================================================== */

function updateBoard(){
  const totalTn = NAVES_HISTORICO.reduce((s,n)=>s+n.tn,0);
  const totalReal = NAVES_HISTORICO.reduce((s,n)=>s+n.apm,0);
  const totalPresupuesto = NAVES_HISTORICO.reduce((s,n)=>s+n.presupuesto,0);
  const ahorro = totalPresupuesto - totalReal;
  const naves = NAVES_HISTORICO.length;

  document.getElementById('flapRow').innerHTML = `
    <div class="flap"><div class="label">TN descargadas 2026</div><div class="value">${fmtN(totalTn)}</div><div class="delta">${naves} naves registradas</div></div>
    <div class="flap"><div class="label">Gasto real acumulado</div><div class="value amber">${fmtS(totalReal)}</div><div class="delta">vs. presupuesto ${fmtS(totalPresupuesto)}</div></div>
    <div class="flap"><div class="label">Ahorro vs. presupuesto</div><div class="value ${ahorro>=0?'ok':''}" style="${ahorro<0?'color:#FF8A73':''}">${fmtS(Math.abs(ahorro))}</div><div class="delta">${ahorro>=0?'bajo presupuesto':'sobre presupuesto'}</div></div>
    <div class="flap"><div class="label">Tarifas vigentes</div><div class="value" style="font-size:19px">${getActiveVersion().id}</div><div class="delta">${DATA.versions.length} versión(es) en historial</div></div>
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
