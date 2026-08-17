/* dashboard.js — Pestaña 'Panel General': KPIs, gráficos Chart.js y tabla
   de desviación presupuestaria. */

let chartRefs = {};
function renderDashboard(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Panel General</h1>
      <p>Vista consolidada de gastos de descarga y transporte de macroinsumos, comparando Puerto Callao y Puerto Chancay, calculada automáticamente a partir de los maestros de tarifas.</p>
    </div>
    <div class="grid-2">
      <div class="card">
        <h3>Gasto real por puerto (2026)</h3>
        <p class="hint">Suma de gasto real (APM/COSCO) por nave, agrupado por puerto de descarga.</p>
        <canvas id="chPuerto" height="200"></canvas>
      </div>
      <div class="card">
        <h3>Distribución de flete por transportista</h3>
        <p class="hint">TN transportadas históricas — origen Puerto Chancay.</p>
        <canvas id="chTransportista" height="200"></canvas>
      </div>
    </div>
    <div class="card" style="margin-top:16px">
      <h3>Naves con mayor desviación presupuestaria</h3>
      <p class="hint">Diferencia entre gasto presupuestado y gasto real. Rojo = sobrecosto, verde = ahorro.</p>
      <div class="scroll-x"><table id="tblDesv"></table></div>
    </div>
  `;

  // Chart 1: gasto real por puerto
  const byPort = {CHANCAY:0, CALLAO:0};
  NAVES_HISTORICO.forEach(n=>byPort[n.puerto]+=n.apm);
  const ctx1 = document.getElementById('chPuerto');
  chartRefs.p1 = new Chart(ctx1,{
    type:'bar',
    data:{labels:['Chancay','Callao'],datasets:[{data:[byPort.CHANCAY,byPort.CALLAO],backgroundColor:['#F5B324','#2C6E8E'],borderRadius:6,maxBarThickness:70}]},
    options:{plugins:{legend:{display:false},tooltip:{callbacks:{label:c=>fmtS(c.raw)}}},scales:{y:{ticks:{callback:v=>(v/1e6).toFixed(1)+'M'},grid:{color:'#EEF1F0'}},x:{grid:{display:false}}}}
  });

  // Chart 2: transportista TN (Gastos transporte BI)
  const ctx2 = document.getElementById('chTransportista');
  chartRefs.p2 = new Chart(ctx2,{
    type:'doughnut',
    data:{labels:['TOSA E.I.R.L.','TRANSJIBAJA S.A.C.','VILMA ROJAS'],
      datasets:[{data:[19039.32,8032.58,5924.98],backgroundColor:['#0D1E2E','#2C6E8E','#F5B324']}]},
    options:{plugins:{legend:{position:'bottom',labels:{boxWidth:10,font:{size:11}}}}}
  });

  // tabla desviación
  const rows = NAVES_HISTORICO.map(n=>({...n, desv:n.presupuesto-n.apm})).sort((a,b)=>a.desv-b.desv).slice(0,10);
  document.getElementById('tblDesv').innerHTML = `
    <thead><tr><th>Nave</th><th>Puerto</th><th>Producto</th><th>TN</th><th>Presupuesto</th><th>Gasto real</th><th>Desviación</th></tr></thead>
    <tbody>${rows.map(r=>`
      <tr>
        <td class="txt">${r.nave}</td>
        <td><span class="tag ${r.puerto.toLowerCase()}">${r.puerto}</span></td>
        <td class="txt">${r.producto}</td>
        <td>${fmtTn(r.tn)}</td>
        <td>${fmtS(r.presupuesto)}</td>
        <td>${fmtS(r.apm)}</td>
        <td class="${r.desv<0?'pos':'neg'}">${r.desv<0?'▲':'▼'} ${fmtS(Math.abs(r.desv))}</td>
      </tr>`).join('')}</tbody>`;

  updateBoard();
}

/* =====================================================================
   7. NAVES / COMPARATIVO
   ===================================================================== */
