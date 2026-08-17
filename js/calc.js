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

/* helpers de formato */
const fmtS = n => 'S/ ' + Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtD = n => '$ ' + Number(n).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtN = n => Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtTn = n => Number(n).toLocaleString('es-PE',{minimumFractionDigits:2,maximumFractionDigits:2}) + ' TN';
