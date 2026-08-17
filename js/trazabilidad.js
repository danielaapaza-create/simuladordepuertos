/* trazabilidad.js — Pestaña 'Trazabilidad': historial de simulaciones
   guardadas, con export a CSV. */

function renderTrazabilidad(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Trazabilidad de Simulaciones</h1>
      <p>Cada simulación queda registrada con analista, fecha/hora, parámetros de entrada y resultado — el historial de auditoría que el Excel no podía ofrecer.</p>
    </div>
    <div class="card">
      <div class="flex-between wrap gap-8 mb-16">
        <h3 class="mt-0">${SIMS.length} simulación(es) registrada(s)</h3>
        <div class="flex gap-8">
          <button class="btn ghost sm" id="btnExport">Exportar CSV</button>
          <button class="btn ghost sm" id="btnClear">Vaciar registro</button>
        </div>
      </div>
      <div class="scroll-x"><table id="tblSims"></table></div>
    </div>
  `;
  drawSims();
  document.getElementById('btnExport').addEventListener('click', exportCSV);
  document.getElementById('btnClear').addEventListener('click', ()=>{
    if(confirm('¿Vaciar todo el historial de simulaciones? Esta acción no se puede deshacer.')){
      SIMS = []; saveSims(SIMS); drawSims(); updateBoard(); toast('Registro vaciado');
    }
  });
}
function drawSims(){
  const el = document.getElementById('tblSims');
  if(!SIMS.length){ el.innerHTML=''; el.parentElement.innerHTML = '<div class="empty">Aún no hay simulaciones. Ve a «Simulador» para crear la primera.</div>'; return; }
  el.innerHTML = `
    <thead><tr><th>ID</th><th>Fecha</th><th>Analista</th><th>Referencia</th><th>TN</th><th>Planta</th><th>Transportista</th><th>Tarifas</th><th>Chancay S/</th><th>Callao S/</th><th>Recomendado</th><th>Ahorro S/</th></tr></thead>
    <tbody>${SIMS.map(s=>`
      <tr>
        <td>${s.id}</td>
        <td>${new Date(s.fecha).toLocaleString('es-PE')}</td>
        <td class="txt">${s.analista}</td>
        <td class="txt">${s.nave}</td>
        <td>${fmtTn(s.tn)}</td>
        <td class="txt">${s.planta}</td>
        <td class="txt">${s.transportista}</td>
        <td><span class="badge">${s.versionTarifas||'—'}</span></td>
        <td>${fmtS(s.costoChancay)}</td>
        <td>${fmtS(s.costoCallao)}</td>
        <td><span class="tag ${s.puertoRecomendado.toLowerCase()}">${s.puertoRecomendado}</span></td>
        <td class="neg">${fmtS(s.ahorro)}</td>
      </tr>`).join('')}</tbody>`;
}
function exportCSV(){
  if(!SIMS.length){ toast('No hay datos para exportar'); return; }
  const headers = ['ID','Fecha','Analista','Referencia','TN','Producto','Planta','Transportista','VersionTarifas','CostoChancaySoles','CostoCallaoSoles','PuertoRecomendado','AhorroSoles'];
  const lines = [headers.join(',')].concat(SIMS.map(s=>[s.id,s.fecha,s.analista,s.nave,s.tn,s.producto,s.planta,s.transportista,s.versionTarifas||'',s.costoChancay.toFixed(2),s.costoCallao.toFixed(2),s.puertoRecomendado,s.ahorro.toFixed(2)].map(v=>`"${v}"`).join(',')));
  const blob = new Blob([lines.join('\n')],{type:'text/csv;charset=utf-8;'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = 'trazabilidad_simulaciones.csv'; a.click();
}

/* =====================================================================
   10. MAESTROS & GOBIERNO DE DATOS
   ===================================================================== */
// Borrador de edición en memoria (copia de la versión activa); no se guarda
// nada hasta pulsar "Guardar como nueva versión vigente".
