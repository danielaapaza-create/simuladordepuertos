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
   INIT — autenticación (Supabase Auth) + carga de datos, luego arranca
   en la pestaña Panel General.
   ===================================================================== */
let appStarted = false;

async function startApp(){
  document.getElementById('loginScreen').hidden = true;
  document.getElementById('app').hidden = false;
  try{
    await bootstrapData();
  }catch(err){
    toast('No se pudieron cargar los datos: ' + (err.message||'error desconocido'));
    return;
  }
  document.getElementById('sidebarUserName').textContent = CURRENT_PROFILE?.nombre || '';
  if(CURRENT_PROFILE?.role !== 'admin'){
    document.querySelector('.nav button[data-tab="maestros"]')?.remove();
  }
  render('dashboard');
}

function showLogin(){
  appStarted = false;
  document.getElementById('app').hidden = true;
  document.getElementById('loginScreen').hidden = false;
}

const SIGNUP_EMAIL_DOMAIN = '@san-fernando.com.pe';

let loginMode = 'signin'; // 'signin' | 'signup'
function setLoginMode(mode){
  loginMode = mode;
  const isSignup = mode === 'signup';
  document.getElementById('loginNameField').hidden = !isSignup;
  document.getElementById('loginTitle').textContent = isSignup ? 'Crea tu cuenta' : 'Ingresa a tu cuenta';
  document.getElementById('loginSubtitle').textContent = isSignup
    ? `Solo correos ${SIGNUP_EMAIL_DOMAIN}. La cuenta se crea con rol analista; un administrador puede darte más permisos después.`
    : 'Acceso restringido — solicita tu cuenta al administrador.';
  document.getElementById('loginEmail').placeholder = isSignup ? `nombre${SIGNUP_EMAIL_DOMAIN}` : '';
  document.getElementById('btnLogin').textContent = isSignup ? 'Crear cuenta' : 'Ingresar';
  document.getElementById('loginSwitchText').textContent = isSignup ? '¿Ya tienes cuenta?' : '¿No tienes cuenta?';
  document.getElementById('btnToggleMode').textContent = isSignup ? 'Inicia sesión' : 'Crear cuenta';
  document.getElementById('loginError').textContent = '';
  document.getElementById('loginInfo').hidden = true;
}
document.getElementById('btnToggleMode').addEventListener('click', ()=> setLoginMode(loginMode==='signin' ? 'signup' : 'signin'));

document.getElementById('btnLogin').addEventListener('click', async ()=>{
  const email = document.getElementById('loginEmail').value.trim();
  const password = document.getElementById('loginPassword').value;
  const nombre = document.getElementById('loginNombre').value.trim();
  const errEl = document.getElementById('loginError');
  const infoEl = document.getElementById('loginInfo');
  errEl.textContent = ''; infoEl.hidden = true;

  if(loginMode === 'signup'){
    if(!nombre){ errEl.textContent = 'Indica tu nombre completo.'; return; }
    if(!email.toLowerCase().endsWith(SIGNUP_EMAIL_DOMAIN)){
      errEl.textContent = `Solo se permiten cuentas nuevas con dominio ${SIGNUP_EMAIL_DOMAIN}.`;
      return;
    }
    const { data, error } = await supa.auth.signUp({ email, password, options: { data: { nombre } } });
    if(error){ errEl.textContent = error.message || 'No se pudo crear la cuenta.'; return; }
    if(!data.session){
      infoEl.hidden = false;
      infoEl.textContent = 'Cuenta creada. Revisa tu correo para confirmarla antes de ingresar.';
      setLoginMode('signin');
    }
    return;
  }

  const { error } = await supa.auth.signInWithPassword({ email, password });
  if(error) errEl.textContent = 'Credenciales inválidas o cuenta no habilitada.';
});
document.getElementById('loginPassword').addEventListener('keydown', e=>{
  if(e.key==='Enter') document.getElementById('btnLogin').click();
});
document.getElementById('btnLogout').addEventListener('click', ()=> supa.auth.signOut());

supa.auth.onAuthStateChange((event, session)=>{
  if(session && !appStarted){ appStarted = true; startApp(); }
  else if(!session){ showLogin(); }
});

/* =====================================================================
   6. DASHBOARD
   ===================================================================== */
