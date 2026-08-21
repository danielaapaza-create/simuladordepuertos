/* simulador.js — Pestaña 'Simulador': reparte la carga de una nave entre
   varias plantas (+ opcionalmente gastos de puerto/almacén) y calcula
   Chancay vs. Callao para ese mismo reparto, guardable en trazabilidad. */

const EXTRA_LABELS = {
  CHANCAY: {transporte:'Transporte Puerto', almacen:'Almacenamiento AT'},
  CALLAO:  {transporte:'Transporte Ransa', almacen:'Almacenamiento PT'},
};

function renderSimulador(){
  const transOpts = CATALOGOS.transportistas.map(t=>`<option value="${t}">${t}</option>`).join('');
  const prodOpts = CATALOGOS.productos.map(p=>`<option value="${p}">${p}</option>`).join('');
  const versionOpts = sortedVersions().map(v=>`<option value="${v.id}" ${v.id===getActiveVersion().id?'selected':''}>${versionLabel(v)}${v.id===getActiveVersion().id?' (vigente)':''}</option>`).join('');
  const plantaFields = CATALOGOS.plantas.map(p=>`
    <div class="field"><label>${p.nombre} (${p.codigo})</label><input class="sim-planta-tn" data-planta="${p.id}" type="number" min="0" value="0"></div>
  `).join('');
  const extraFields = puerto => `
    <div class="form-grid">
      <div class="field"><label>TN ${EXTRA_LABELS[puerto].transporte}</label><input id="ex_${puerto}_transp_tn" type="number" min="0" value="0"></div>
      <div class="field"><label>CU ${EXTRA_LABELS[puerto].transporte} (S//TN)</label><input id="ex_${puerto}_transp_cu" type="number" min="0" step="0.01" value="0"></div>
      <div class="field"><label>TN ${EXTRA_LABELS[puerto].almacen}</label><input id="ex_${puerto}_almacen_tn" type="number" min="0" value="0"></div>
      <div class="field"><label>CU ${EXTRA_LABELS[puerto].almacen} (S//TN)</label><input id="ex_${puerto}_almacen_cu" type="number" min="0" step="0.01" value="0"></div>
    </div>`;

  content.innerHTML = `
    <div class="section-head">
      <h1>Simulador de Costos</h1>
      <p>Reparte la carga de una nave entre las plantas destino y calcula automáticamente el costo total de descargarla por Chancay o por Callao con ese mismo reparto — guarda la simulación en el registro de trazabilidad.</p>
    </div>
    <div class="card">
      <h3>Datos generales</h3>
      <div class="form-grid">
        <div class="field"><label>Versión de tarifas</label><select id="simVersion">${versionOpts}</select></div>
        <div class="field"><label>Referencia / Nave</label><input id="simNave" type="text" placeholder="Ej. MN NUEVA ESPERANZA"></div>
        <div class="field"><label>Analista</label><input id="simAnalista" type="text" placeholder="Tu nombre" value="${CURRENT_PROFILE?.nombre || localStorage.getItem('muelle_user') || ''}"></div>
        <div class="field"><label>Producto</label><select id="simProducto">${prodOpts}</select></div>
        <div class="field"><label>Transportista</label><select id="simTrans">${transOpts}</select></div>
      </div>
    </div>
    <div class="card">
      <h3>Reparto de carga por planta (TN)</h3>
      <p class="hint">El mismo reparto se evalúa para ambos puertos de origen — solo cambian las tarifas de flete y descarga.</p>
      <div class="form-grid">${plantaFields}</div>
      <div class="line-item total"><span>Total repartido</span><span id="simTotalTn">0.00 TN</span></div>
    </div>
    <div class="card">
      <div class="flex-between wrap gap-8">
        <h3 class="mt-0">Gastos adicionales de puerto (opcional)</h3>
        <label class="field inline" style="margin-bottom:0;"><span>Habilitar</span><input type="checkbox" id="simExtraToggle"></label>
      </div>
      <p class="hint">Actívalo si, además del flete a planta, hay transporte hasta un operador de puerto (Puerto/Ransa) y almacenamiento en terminal (AT/PT).</p>
      <div id="simExtraWrap" class="grid-2" style="display:none;">
        <div><div class="pname">Chancay</div>${extraFields('CHANCAY')}</div>
        <div><div class="pname">Callao</div>${extraFields('CALLAO')}</div>
      </div>
    </div>
    <div class="card">
      <h3>Otros ajustes (opcional)</h3>
      <div class="grid-2">
        <div><div class="pname">Chancay</div><div class="form-grid">
          <div class="field"><label>Dispatch/Demurrage (S/)</label><input id="adj_CHANCAY_dispatch" type="number" value="0"></div>
          <div class="field"><label>Cambio de muelle (S/)</label><input id="adj_CHANCAY_cambio" type="number" value="0"></div>
        </div></div>
        <div><div class="pname">Callao</div><div class="form-grid">
          <div class="field"><label>Dispatch/Demurrage (S/)</label><input id="adj_CALLAO_dispatch" type="number" value="0"></div>
          <div class="field"><label>Cambio de muelle (S/)</label><input id="adj_CALLAO_cambio" type="number" value="0"></div>
        </div></div>
      </div>
      <button class="btn amber mt-8" id="btnSimular">Calcular escenario</button>
    </div>
    <div class="card">
      <h3>Resultado</h3>
      <p class="hint">Comparación lado a lado. El puerto recomendado se resalta en verde.</p>
      <div id="simResult" class="empty">Define un escenario y presiona «Calcular escenario».</div>
    </div>
  `;

  document.querySelectorAll('.sim-planta-tn').forEach(el=>el.addEventListener('input', updateTotalTn));
  document.getElementById('simExtraToggle').addEventListener('change', e=>{
    document.getElementById('simExtraWrap').style.display = e.target.checked ? 'grid' : 'none';
  });
  document.getElementById('btnSimular').addEventListener('click', runSim);
  updateTotalTn();
}

function updateTotalTn(){
  const total = [...document.querySelectorAll('.sim-planta-tn')].reduce((s,el)=>s+(parseFloat(el.value)||0),0);
  document.getElementById('simTotalTn').textContent = fmtTn(total);
}

function readExtra(puerto, enabled){
  return {
    transporte: {enabled, label: EXTRA_LABELS[puerto].transporte,
      tn: parseFloat(document.getElementById(`ex_${puerto}_transp_tn`).value)||0,
      cu: parseFloat(document.getElementById(`ex_${puerto}_transp_cu`).value)||0},
    almacen: {enabled, label: EXTRA_LABELS[puerto].almacen,
      tn: parseFloat(document.getElementById(`ex_${puerto}_almacen_tn`).value)||0,
      cu: parseFloat(document.getElementById(`ex_${puerto}_almacen_cu`).value)||0},
  };
}

function runSim(){
  const plantasTn = [...document.querySelectorAll('.sim-planta-tn')].map(el=>({
    plantaId: el.dataset.planta, tn: parseFloat(el.value)||0
  }));
  const totalTn = plantasTn.reduce((s,p)=>s+p.tn,0);
  const producto = document.getElementById('simProducto').value;
  const trans = document.getElementById('simTrans').value;
  const nave = document.getElementById('simNave').value || 'Escenario sin nombre';
  const analista = document.getElementById('simAnalista').value || 'Analista';
  const versionId = document.getElementById('simVersion').value;
  const v = getVersionById(versionId);
  const extraEnabled = document.getElementById('simExtraToggle').checked;
  localStorage.setItem('muelle_user', analista);

  if(totalTn<=0){ toast('Ingresa el tonelaje de al menos una planta'); return; }

  const extra = {CHANCAY: readExtra('CHANCAY', extraEnabled), CALLAO: readExtra('CALLAO', extraEnabled)};
  const ajustes = {
    CHANCAY: {dispatch: parseFloat(document.getElementById('adj_CHANCAY_dispatch').value)||0, cambioMuelle: parseFloat(document.getElementById('adj_CHANCAY_cambio').value)||0},
    CALLAO:  {dispatch: parseFloat(document.getElementById('adj_CALLAO_dispatch').value)||0, cambioMuelle: parseFloat(document.getElementById('adj_CALLAO_cambio').value)||0},
  };

  const chancay = calcEscenarioPuerto('CHANCAY', plantasTn, trans, producto, extra.CHANCAY, ajustes.CHANCAY, v);
  const callao = calcEscenarioPuerto('CALLAO', plantasTn, trans, producto, extra.CALLAO, ajustes.CALLAO, v);
  const winner = chancay.soles<=callao.soles ? 'CHANCAY' : 'CALLAO';
  const ahorro = Math.abs(chancay.soles-callao.soles);
  const plantasResumen = plantasTn.filter(p=>p.tn>0)
    .map(p=>`${CATALOGOS.plantas.find(pl=>pl.id===p.plantaId)?.nombre||p.plantaId} (${fmtTn(p.tn)})`).join(', ');

  const rowsHtml = lineas => lineas.map(l=>`<div class="line-item"><span>${l.label} (CU ${fmtN(l.cu)}/TN, ${fmtTn(l.tn)})</span><span>${fmtS(l.soles)}</span></div>`).join('');
  const card = (title,r,isWin) => `
    <div class="port-card ${isWin?'winner':''}">
      <div class="pname">${title} ${isWin?'<span class="winner-pill">MENOR COSTO</span>':''}</div>
      <div class="line-item"><span>Descarga (CU ${fmtN(r.descarga.cu)}/TN)</span><span>${fmtS(r.descarga.soles)}</span></div>
      ${rowsHtml(r.lineas)}
      <div class="line-item total"><span>Subtotal transporte</span><span>${fmtS(r.subtotalTransporte)}</span></div>
      <div class="line-item"><span>Almacenamiento planta (${producto})</span><span>${fmtS(r.almacen.soles)}</span></div>
      ${r.dispatch ? `<div class="line-item"><span>Dispatch/Demurrage</span><span>${fmtS(r.dispatch)}</span></div>` : ''}
      ${r.cambioMuelle ? `<div class="line-item"><span>Cambio de muelle</span><span>${fmtS(r.cambioMuelle)}</span></div>` : ''}
      <div class="line-item total"><span>Gastos totales</span><span>${fmtS(r.soles)}</span></div>
      <div class="line-item"><span>Equivalente USD</span><span>${fmtD(r.dolares)}</span></div>
      <div class="line-item"><span>Costo unitario</span><span>${fmtN(r.cuTotal)} S//TN</span></div>
    </div>`;

  document.getElementById('simResult').innerHTML = `
    <div class="badge-row">
      <span class="badge">${fmtTn(totalTn)}</span><span class="badge">${producto}</span>
      <span class="badge">${trans}</span><span class="badge">Tarifas: ${v.id}</span>
    </div>
    <div class="compare-wrap">
      ${card('Puerto Chancay', chancay, winner==='CHANCAY')}
      ${card('Puerto Callao', callao, winner==='CALLAO')}
    </div>
    <div class="audit-note"><span class="dot"></span>${winner} resulta ${fmtS(ahorro)} más económico para este reparto (${fmtD(ahorro/v.tipoCambio)}), usando tarifas ${v.id}.</div>
    <button class="btn mt-16" id="btnGuardarSim">Guardar en trazabilidad</button>
  `;

  document.getElementById('btnGuardarSim').addEventListener('click', async ()=>{
    try{
      await insertSim({
        analista, nave, tn: totalTn, producto, plantaNombre: plantasResumen || 'Sin reparto', transportista: trans,
        versionId: v.id, costoChancay: chancay.soles, costoCallao: callao.soles,
        puertoRecomendado: winner, ahorro,
        distribucion: {plantas: plantasTn, extraHabilitado: extraEnabled, extra, ajustes, resultado: {CHANCAY: chancay, CALLAO: callao}}
      });
      toast('Simulación guardada en trazabilidad');
      updateBoard();
    }catch(err){
      toast('No se pudo guardar: ' + (err.message||'error desconocido'));
    }
  });
}
