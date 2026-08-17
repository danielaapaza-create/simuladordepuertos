/* naves.js — Pestaña 'Naves & Comparativo': histórico 2026 filtrable. */

let navesFilter = 'TODOS';
function renderNaves(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Naves &amp; Comparativo</h1>
      <p>Histórico de naves descargadas en 2026, con el mismo modelo del comparativo Callao–Chancay del archivo original: gasto presupuestado vs. gasto real (COSCO / APM).</p>
    </div>
    <div class="card">
      <div class="tabs-filter" id="filterChips">
        ${['TODOS','CHANCAY','CALLAO'].map(p=>`<div class="chip ${navesFilter===p?'active':''}" data-p="${p}">${p==='TODOS'?'Todos los puertos':p.charAt(0)+p.slice(1).toLowerCase()}</div>`).join('')}
      </div>
      <div class="scroll-x"><table id="tblNaves"></table></div>
    </div>
  `;
  document.getElementById('filterChips').addEventListener('click', e=>{
    const chip = e.target.closest('.chip'); if(!chip) return;
    navesFilter = chip.dataset.p; renderNaves();
  });
  drawNavesTable();
}
function drawNavesTable(){
  const rows = NAVES_HISTORICO.filter(n=>navesFilter==='TODOS'||n.puerto===navesFilter);
  const totTn = rows.reduce((s,r)=>s+r.tn,0);
  const totPre = rows.reduce((s,r)=>s+r.presupuesto,0);
  const totReal = rows.reduce((s,r)=>s+r.apm,0);
  document.getElementById('tblNaves').innerHTML = `
    <thead><tr><th>Mes</th><th>Puerto</th><th>Nave</th><th>Producto</th><th>TN</th><th>Presupuesto</th><th>Gasto COSCO</th><th>Gasto APM (real)</th><th>Ahorro / Sobrecosto</th></tr></thead>
    <tbody>${rows.map(r=>{
      const ahorro = r.presupuesto - r.apm;
      return `<tr>
        <td class="txt">${r.mes}</td>
        <td><span class="tag ${r.puerto.toLowerCase()}">${r.puerto}</span></td>
        <td class="txt">${r.nave}</td>
        <td class="txt">${r.producto}</td>
        <td>${fmtTn(r.tn)}</td>
        <td>${fmtS(r.presupuesto)}</td>
        <td>${fmtS(r.cosco)}</td>
        <td>${fmtS(r.apm)}</td>
        <td class="${ahorro<0?'pos':'neg'}">${ahorro<0?'▲':'▼'} ${fmtS(Math.abs(ahorro))}</td>
      </tr>`;
    }).join('')}</tbody>
    <tfoot><tr><td colspan="4">Total (${rows.length} naves)</td><td>${fmtTn(totTn)}</td><td>${fmtS(totPre)}</td><td></td><td>${fmtS(totReal)}</td><td class="${(totPre-totReal)<0?'pos':'neg'}">${fmtS(Math.abs(totPre-totReal))}</td></tr></tfoot>
  `;
}

/* =====================================================================
   8. SIMULADOR
   ===================================================================== */
