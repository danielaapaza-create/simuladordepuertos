/* calc.js — Motor de cálculo de costos de descarga, transporte,
   almacenamiento y total. Depende de store.js (getActiveVersion, etc). */

/* =====================================================================
   3. MOTOR DE CÁLCULO — recibe explícitamente qué versión de tarifas usar
   ===================================================================== */
function calcDescarga(tn, puerto, v){
  const c = v.descarga[puerto];
  const cu = c.balanza + c.comision + c.operativa + c.ayg;
  return {cu, soles: cu*tn, dolares: (cu*tn)/v.tipoCambio, detalle:c};
}
function calcTransporte(tn, puertoOrigen, plantaId, transportista, v){
  const cu = v.flete[puertoOrigen][plantaId][transportista];
  return {cu, soles: cu*tn, dolares:(cu*tn)/v.tipoCambio};
}
function calcAlmacenamiento(tn, producto, v){
  const cu = v.almacenamiento[producto] || 0;
  return {cu, soles: cu*tn, dolares:(cu*tn)/v.tipoCambio};
}
function calcTotal(tn, puerto, plantaId, transportista, producto, v){
  v = v || getActiveVersion();
  const d = calcDescarga(tn, puerto, v);
  const t = calcTransporte(tn, puerto, plantaId, transportista, v);
  const a = calcAlmacenamiento(tn, producto, v);
  const soles = d.soles + t.soles + a.soles;
  return {descarga:d, transporte:t, almacen:a, soles, dolares: soles/v.tipoCambio, cuTotal: soles/tn};
}

/* =====================================================================
   3b. DISTRIBUCIÓN MULTI-DESTINO — una nave reparte su carga entre varias
   plantas (y, opcionalmente, gastos de puerto/almacén fuera de planta)
   antes de decidir si conviene descargarla por Chancay o por Callao.
   ===================================================================== */
function calcLineaTransporte(tn, puerto, plantaId, transportista, v){
  if(!(tn>0)) return null;
  const planta = CATALOGOS.plantas.find(p=>p.id===plantaId);
  const t = calcTransporte(tn, puerto, plantaId, transportista, v);
  return {destino:plantaId, label:'Transporte '+(planta?planta.nombre:plantaId), tn, cu:t.cu, soles:t.soles};
}
function calcLineaExtra(label, tn, cu){
  if(!(tn>0)) return null;
  return {label, tn, cu:cu||0, soles:(cu||0)*tn};
}
// plantasTn: [{plantaId, tn}]. extra: {transporte:{enabled,label,tn,cu}, almacen:{enabled,label,tn,cu}}.
// ajustes: {dispatch, cambioMuelle} en S/.
function calcEscenarioPuerto(puerto, plantasTn, transportista, producto, extra, ajustes, v){
  const lineas = plantasTn.map(p=>calcLineaTransporte(p.tn, puerto, p.plantaId, transportista, v)).filter(Boolean);
  if(extra?.transporte?.enabled){ const l=calcLineaExtra(extra.transporte.label, extra.transporte.tn, extra.transporte.cu); if(l) lineas.push(l); }
  if(extra?.almacen?.enabled){ const l=calcLineaExtra(extra.almacen.label, extra.almacen.tn, extra.almacen.cu); if(l) lineas.push(l); }

  const totalTn = plantasTn.reduce((s,p)=>s+(p.tn||0),0);
  const descarga = calcDescarga(totalTn, puerto, v);
  const almacen = calcAlmacenamiento(totalTn, producto, v);
  const subtotalTransporte = lineas.reduce((s,l)=>s+l.soles,0);
  const dispatch = ajustes?.dispatch || 0;
  const cambioMuelle = ajustes?.cambioMuelle || 0;
  const soles = descarga.soles + subtotalTransporte + almacen.soles + dispatch + cambioMuelle;
  return {puerto, lineas, totalTn, descarga, almacen, subtotalTransporte, dispatch, cambioMuelle,
          soles, dolares: soles/v.tipoCambio, cuTotal: totalTn>0 ? soles/totalTn : 0};
}

/* helpers de formato */
const fmtS = n => 'S/ ' + Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtD = n => '$ ' + Number(n).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtN = n => Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtTn = n => Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2}) + ' TN';
