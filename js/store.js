/* store.js — Persistencia local y versionado de tarifas (vigencia en el
   tiempo). Depende de data.js (DEFAULT_DATA). */

/* =====================================================================
   2. ESTADO — persistencia local (localStorage simula la base de datos
      central del ecosistema; en producción sería una API + BD real)
   ===================================================================== */
const LS_MAESTROS = 'muelle_maestros_v2';
const LS_SIM = 'muelle_simulaciones_v1';

function loadMaestros(){
  try{
    const raw = localStorage.getItem(LS_MAESTROS);
    if(raw){
      const parsed = JSON.parse(raw);
      if(parsed.versions && parsed.versions.length) return parsed;
    }
  }catch(e){}
  return JSON.parse(JSON.stringify(DEFAULT_DATA));
}
function persistDATA(){ localStorage.setItem(LS_MAESTROS, JSON.stringify(DATA)); }
function loadSims(){
  try{ return JSON.parse(localStorage.getItem(LS_SIM) || '[]'); }catch(e){ return []; }
}
function saveSims(arr){ localStorage.setItem(LS_SIM, JSON.stringify(arr)); }

let DATA = loadMaestros();
let SIMS = loadSims();

/* Versiones de tarifas — ordenadas de más reciente a más antigua por vigencia */
function sortedVersions(){
  return [...DATA.versions].sort((a,b)=> new Date(b.vigenteDesde) - new Date(a.vigenteDesde));
}
// La versión activa "hoy": la de mayor vigenteDesde que ya empezó; si todas son futuras, la más próxima.
function getActiveVersion(){
  const sv = sortedVersions();
  const today = new Date();
  const started = sv.find(v => new Date(v.vigenteDesde) <= today);
  return started || sv[sv.length-1] || sv[0];
}
function getVersionById(id){ return DATA.versions.find(v=>v.id===id) || getActiveVersion(); }
function versionLabel(v){
  return `${v.id} · vigente desde ${new Date(v.vigenteDesde+'T00:00:00').toLocaleDateString('es-PE')}`;
}
function nextVersionId(){
  const n = DATA.versions.length + 1;
  return 'V-' + new Date().getFullYear() + '-' + String(n).padStart(2,'0');
}
