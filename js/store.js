/* store.js — Capa de datos sobre Supabase (Postgres + RLS). Reemplaza el
   localStorage del prototipo: los maestros/tarifas/simulaciones viven en la
   BD y llegan aquí a los mismos objetos globales (CATALOGOS, DATA, SIMS,
   NAVES_HISTORICO) que ya consumen dashboard.js/naves.js/simulador.js/
   trazabilidad.js/maestros.js — así esos archivos no cambian de forma.
   Depende de data.js (para las formas/objetos base) y de supabaseClient.js
   (variable global `supa`). */

/* =====================================================================
   2. ESTADO — objetos en memoria, poblados desde Supabase en bootstrapData()
   ===================================================================== */
let DATA = { versions: [] };
let SIMS = [];
let CURRENT_PROFILE = null;          // {id, nombre, role} del usuario logueado
let TRANSPORTISTA_ID_BY_NOMBRE = {}; // necesario para insertar FKs al publicar tarifas/simulaciones
let PRODUCTO_ID_BY_NOMBRE = {};

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

/* =====================================================================
   3. CARGA INICIAL — se ejecuta una vez, tras iniciar sesión
   ===================================================================== */
async function fetchVersions(){
  const { data: versions, error: eV } = await supa.from('tarifa_versiones').select('*');
  if(eV) throw eV;
  if(!versions.length) return [];
  const versionIds = versions.map(v=>v.id);

  const [{data:fletes,error:eF}, {data:descargas,error:eD}, {data:almacenes,error:eA}] = await Promise.all([
    supa.from('tarifa_flete').select('version_id,puerto,planta_id,valor,transportistas(nombre)').in('version_id', versionIds),
    supa.from('tarifa_descarga').select('*').in('version_id', versionIds),
    supa.from('tarifa_almacenamiento').select('version_id,valor,productos(nombre)').in('version_id', versionIds),
  ]);
  if(eF) throw eF; if(eD) throw eD; if(eA) throw eA;

  return versions.map(v=>{
    const flete = {CHANCAY:{}, CALLAO:{}};
    fletes.filter(f=>f.version_id===v.id).forEach(f=>{
      (flete[f.puerto][f.planta_id] ||= {})[f.transportistas.nombre] = Number(f.valor);
    });
    const descarga = {};
    descargas.filter(d=>d.version_id===v.id).forEach(d=>{
      descarga[d.puerto] = {balanza:Number(d.balanza), comision:Number(d.comision), operativa:Number(d.operativa), ayg:Number(d.ayg)};
    });
    const almacenamiento = {};
    almacenes.filter(a=>a.version_id===v.id).forEach(a=>{
      almacenamiento[a.productos.nombre] = Number(a.valor);
    });
    return {
      id: v.id, vigenteDesde: v.vigente_desde, autor: v.autor, creadoEn: v.creado_en,
      nota: v.nota, tipoCambio: Number(v.tipo_cambio), flete, descarga, almacenamiento
    };
  });
}

async function fetchNaves(){
  const { data, error } = await supa.from('naves_historico').select('*').order('id');
  if(error) throw error;
  return data.map(n=>({
    mes:n.mes, puerto:n.puerto, nave:n.nave, tn:Number(n.tn), producto:n.producto,
    presupuesto:Number(n.presupuesto), cosco:Number(n.cosco), apm:Number(n.apm)
  }));
}

async function fetchSims(){
  const { data, error } = await supa.from('simulaciones')
    .select('*, productos(nombre), plantas(nombre), transportistas(nombre)')
    .order('fecha', {ascending:false});
  if(error) throw error;
  return data.map(s=>({
    id: s.id, fecha: s.fecha, analista: s.analista_nombre, nave: s.nave, tn: Number(s.tn),
    producto: s.productos?.nombre || '', planta: s.plantas?.nombre || '', transportista: s.transportistas?.nombre || '',
    versionTarifas: s.version_tarifas_id, costoChancay: Number(s.costo_chancay), costoCallao: Number(s.costo_callao),
    puertoRecomendado: s.puerto_recomendado, ahorro: Number(s.ahorro)
  }));
}

async function bootstrapData(){
  const { data: { user } } = await supa.auth.getUser();

  const [{data:plantas,error:ePl}, {data:transportistas,error:eTr}, {data:productos,error:ePr}, {data:profile}] = await Promise.all([
    supa.from('plantas').select('*').order('id'),
    supa.from('transportistas').select('*').order('nombre'),
    supa.from('productos').select('*').order('nombre'),
    supa.from('profiles').select('*').eq('id', user.id).maybeSingle(),
  ]);
  if(ePl) throw ePl; if(eTr) throw eTr; if(ePr) throw ePr;

  CATALOGOS.plantas.length = 0; CATALOGOS.plantas.push(...plantas);
  CATALOGOS.transportistas.length = 0; CATALOGOS.transportistas.push(...transportistas.map(t=>t.nombre));
  CATALOGOS.productos.length = 0; CATALOGOS.productos.push(...productos.map(p=>p.nombre));
  TRANSPORTISTA_ID_BY_NOMBRE = Object.fromEntries(transportistas.map(t=>[t.nombre, t.id]));
  PRODUCTO_ID_BY_NOMBRE = Object.fromEntries(productos.map(p=>[p.nombre, p.id]));
  CURRENT_PROFILE = profile || null;

  const versions = await fetchVersions();
  DATA.versions = versions.length ? versions : [seedVersion()];

  const naves = await fetchNaves();
  NAVES_HISTORICO.length = 0; NAVES_HISTORICO.push(...naves);

  const sims = await fetchSims();
  SIMS.length = 0; SIMS.push(...sims);
}

/* =====================================================================
   4. ESCRITURA — publicar una versión de tarifas nueva, guardar/borrar
      simulaciones. RLS decide quién puede hacer qué (ver migración SQL);
      estas funciones solo reportan el error si la BD lo rechaza.
   ===================================================================== */
async function persistDATA(){
  const v = DATA.versions[DATA.versions.length-1];
  const { data: { user } } = await supa.auth.getUser();

  const { error: eV } = await supa.from('tarifa_versiones').insert({
    id: v.id, vigente_desde: v.vigenteDesde, autor: v.autor, nota: v.nota,
    tipo_cambio: v.tipoCambio, creado_en: v.creadoEn, created_by: user?.id ?? null
  });
  if(eV) throw eV;

  const fleteRows = [];
  ['CHANCAY','CALLAO'].forEach(puerto=>{
    CATALOGOS.plantas.forEach(planta=>{
      CATALOGOS.transportistas.forEach(trans=>{
        fleteRows.push({
          version_id: v.id, puerto, planta_id: planta.id,
          transportista_id: TRANSPORTISTA_ID_BY_NOMBRE[trans],
          valor: v.flete[puerto][planta.id][trans]
        });
      });
    });
  });
  const { error: eF } = await supa.from('tarifa_flete').insert(fleteRows);
  if(eF) throw eF;

  const descargaRows = ['CHANCAY','CALLAO'].map(puerto=>({
    version_id: v.id, puerto, ...v.descarga[puerto]
  }));
  const { error: eD } = await supa.from('tarifa_descarga').insert(descargaRows);
  if(eD) throw eD;

  const almacenRows = CATALOGOS.productos.map(nombre=>({
    version_id: v.id, producto_id: PRODUCTO_ID_BY_NOMBRE[nombre], valor: v.almacenamiento[nombre]
  }));
  const { error: eA } = await supa.from('tarifa_almacenamiento').insert(almacenRows);
  if(eA) throw eA;
}

async function insertSim({ analista, nave, tn, producto, plantaId, plantaNombre, transportista, versionId, costoChancay, costoCallao, puertoRecomendado, ahorro }){
  const { data: { user } } = await supa.auth.getUser();
  const id = 'SIM-'+Date.now().toString(36).toUpperCase();
  const fecha = new Date().toISOString();

  const { error } = await supa.from('simulaciones').insert({
    id, fecha, analista_id: user?.id ?? null, analista_nombre: analista,
    nave, tn, producto_id: PRODUCTO_ID_BY_NOMBRE[producto], planta_id: plantaId,
    transportista_id: TRANSPORTISTA_ID_BY_NOMBRE[transportista], version_tarifas_id: versionId,
    costo_chancay: costoChancay, costo_callao: costoCallao,
    puerto_recomendado: puertoRecomendado, ahorro
  });
  if(error) throw error;

  const sim = { id, fecha, analista, nave, tn, producto, planta: plantaNombre, transportista, versionTarifas: versionId, costoChancay, costoCallao, puertoRecomendado, ahorro };
  SIMS.unshift(sim);
  return sim;
}

async function clearAllSims(){
  const { error } = await supa.from('simulaciones').delete().not('id', 'is', null);
  if(error) throw error;
  SIMS.length = 0;
}
