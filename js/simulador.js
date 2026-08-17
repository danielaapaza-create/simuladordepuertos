/* simulador.js — Pestaña 'Simulador': calcula Chancay vs. Callao para un
   escenario y permite guardarlo en trazabilidad. */

function renderSimulador(){
  const plantaOpts = CATALOGOS.plantas.map(p=>`<option value="${p.id}">${p.nombre} (${p.codigo})</option>`).join('');
  const transOpts = CATALOGOS.transportistas.map(t=>`<option value="${t}">${t}</option>`).join('');
  const prodOpts = CATALOGOS.productos.map(p=>`<option value="${p}">${p}</option>`).join('');
  const versionOpts = sortedVersions().map(v=>`<option value="${v.id}" ${v.id===getActiveVersion().id?'selected':''}>${versionLabel(v)}${v.id===getActiveVersion().id?' (vigente)':''}</option>`).join('');

  content.innerHTML = `
    <div class="section-head">
      <h1>Simulador de Costos</h1>
      <p>Calcula automáticamente el costo de descarga + transporte + almacenamiento para Callao y Chancay con un mismo escenario, y guarda la simulación en el registro de trazabilidad.</p>
    </div>
    <div class="grid-2">
      <div class="card">
        <h3>Parámetros del escenario</h3>
        <p class="hint">Elige con qué versión de tarifas simular — la vigente hoy, o cualquiera usada antes.</p>
        <div class="field"><label>Versión de tarifas</label><select id="simVersion">${versionOpts}</select></div>
        <div class="form-grid">
          <div class="field"><label>Referencia / Nave</label><input id="simNave" type="text" placeholder="Ej. MN NUEVA ESPERANZA"></div>
          <div class="field"><label>Analista</label><input id="simAnalista" type="text" placeholder="Tu nombre" value="${localStorage.getItem('muelle_user')||''}"></div>
          <div class="field"><label>Tonelaje (TN)</label><input id="simTn" type="number" min="1" value="25000"></div>
          <div class="field"><label>Producto</label><select id="simProducto">${prodOpts}</select></div>
          <div class="field"><label>Planta destino</label><select id="simPlanta">${plantaOpts}</select></div>
          <div class="field"><label>Transportista</label><select id="simTrans">${transOpts}</select></div>
        </div>
        <button class="btn amber" id="btnSimular" style="margin-top:6px">Calcular escenario</button>
      </div>
      <div class="card">
        <h3>Resultado</h3>
        <p class="hint">Comparación lado a lado. El puerto recomendado se resalta en verde.</p>
        <div id="simResult" class="empty">Define un escenario y presiona «Calcular escenario».</div>
      </div>
    </div>
  `;

  document.getElementById('btnSimular').addEventListener('click', runSim);
}

function runSim(){
  const tn = parseFloat(document.getElementById('simTn').value)||0;
  const producto = document.getElementById('simProducto').value;
  const plantaId = document.getElementById('simPlanta').value;
  const trans = document.getElementById('simTrans').value;
  const nave = document.getElementById('simNave').value || 'Escenario sin nombre';
  const analista = document.getElementById('simAnalista').value || 'Analista';
  const versionId = document.getElementById('simVersion').value;
  const v = getVersionById(versionId);
  localStorage.setItem('muelle_user', analista);

  if(tn<=0){ toast('Ingresa un tonelaje válido'); return; }

  const chancay = calcTotal(tn,'CHANCAY',plantaId,trans,producto,v);
  const callao = calcTotal(tn,'CALLAO',plantaId,trans,producto,v);
  const plantaNombre = CATALOGOS.plantas.find(p=>p.id===plantaId).nombre;
  const winner = chancay.soles<=callao.soles ? 'CHANCAY' : 'CALLAO';
  const ahorro = Math.abs(chancay.soles-callao.soles);

  const card = (title,r,isWin) => `
    <div class="port-card ${isWin?'winner':''}">
      <div class="pname">${title} ${isWin?'<span class="winner-pill">MENOR COSTO</span>':''}</div>
      <div class="line-item"><span>Descarga (CU ${fmtN(r.descarga.cu)}/TN)</span><span>${fmtS(r.descarga.soles)}</span></div>
      <div class="line-item"><span>Transporte (CU ${fmtN(r.transporte.cu)}/TN)</span><span>${fmtS(r.transporte.soles)}</span></div>
      <div class="line-item"><span>Almacenamiento (CU ${fmtN(r.almacen.cu)}/TN)</span><span>${fmtS(r.almacen.soles)}</span></div>
      <div class="line-item total"><span>Total</span><span>${fmtS(r.soles)}</span></div>
      <div class="line-item"><span>Equivalente USD</span><span>${fmtD(r.dolares)}</span></div>
      <div class="line-item"><span>Costo unitario</span><span>${fmtN(r.cuTotal)} S//TN</span></div>
    </div>`;

  document.getElementById('simResult').innerHTML = `
    <div class="badge-row">
      <span class="badge">${fmtTn(tn)}</span><span class="badge">${producto}</span>
      <span class="badge">Planta: ${plantaNombre}</span><span class="badge">${trans}</span>
      <span class="badge">Tarifas: ${v.id}</span>
    </div>
    <div class="compare-wrap">
      ${card('Puerto Chancay', chancay, winner==='CHANCAY')}
      ${card('Puerto Callao', callao, winner==='CALLAO')}
    </div>
    <div class="audit-note"><span class="dot"></span>${winner} resulta ${fmtS(ahorro)} más económico para este escenario (${fmtD(ahorro/v.tipoCambio)}), usando tarifas ${v.id}.</div>
    <button class="btn" id="btnGuardarSim" style="margin-top:14px">Guardar en trazabilidad</button>
  `;

  document.getElementById('btnGuardarSim').addEventListener('click', ()=>{
    SIMS.unshift({
      id: 'SIM-'+Date.now().toString(36).toUpperCase(),
      fecha: new Date().toISOString(),
      analista, nave, tn, producto, planta: plantaNombre, transportista: trans,
      versionTarifas: v.id,
      costoChancay: chancay.soles, costoCallao: callao.soles,
      puertoRecomendado: winner, ahorro
    });
    saveSims(SIMS);
    toast('Simulación guardada en trazabilidad');
    updateBoard();
  });
}

/* =====================================================================
   9. TRAZABILIDAD
   ===================================================================== */
