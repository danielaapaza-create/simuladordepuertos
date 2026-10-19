/* naves.js — Pestaña 'Naves & Comparativo'.
   Dos vistas:
   - Distribución por nave (modelo dimensional): a dónde fue cada lote —
     directo a PAB, vía almacén tercero (AT), cuánto sigue en stock — con
     plan vs. real y merma. Lee v_lote_balance_masa / v_lote_distribucion /
     v_lote_flujo (store.js -> fetchModelo).
   - Comparativo 2026: histórico de la hoja "Comparativo" (naves_historico). */

let navesView = 'distribucion';
let navesFilter = 'TODOS';          // puerto (comparativo)
const distFiltro = { puerto: 'TODOS', anio: 'TODOS', producto: 'TODOS', q: '', soloAT: false };
let distSel = null;                 // lote_id seleccionado

/* Color fijo por entidad (nunca por rango): una planta tiene siempre el mismo
   color en la barra, el diagrama y la leyenda. Paleta validada (dataviz). */
const PAB_COLORES = { '5003': '#2a78d6', '5029': '#eb6834', '5001': '#1baf7a', '1028': '#eda100' };
const PAB_ORDEN = ['5003', '5029', '5001', '1028'];
const PAB_CORTO = { '5003': 'PAB Chancay', '5029': 'PAB GH Chancay', '5001': 'PAB Lurín', '1028': 'PAB Lurín 2' };
const MESES = ['ENE','FEB','MAR','ABR','MAY','JUN','JUL','AGO','SET','OCT','NOV','DIC'];

const fmtTm0 = n => Number(n||0).toLocaleString('es-PE', {maximumFractionDigits:0});
const fmtPct = (n, d=1) => (Number(n||0)*100).toLocaleString('es-PE', {minimumFractionDigits:d, maximumFractionDigits:d}) + '%';
const periodoTxt = p => { const [y,m] = String(p).split('-'); return `${MESES[Number(m)-1]} ${y}`; };
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

function renderNaves(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Naves &amp; Comparativo</h1>
      <p>Qué pasó con cada nave después de la descarga: cuánto fue directo a cada planta (PAB), cuánto pasó por un almacén tercero y cuánto sigue ahí, contra lo planificado. El comparativo 2026 conserva la vista del archivo original.</p>
    </div>
    <div class="tabs-filter" id="navesViewChips">
      <div class="chip ${navesView==='distribucion'?'active':''}" data-v="distribucion">Distribución por nave</div>
      <div class="chip ${navesView==='comparativo'?'active':''}" data-v="comparativo">Comparativo 2026 (presupuesto vs. real)</div>
    </div>
    <div id="navesBody"></div>
  `;
  document.getElementById('navesViewChips').addEventListener('click', e=>{
    const chip = e.target.closest('.chip'); if(!chip) return;
    navesView = chip.dataset.v; renderNaves();
  });
  if(navesView === 'comparativo') renderComparativo();
  else renderDistribucion();
}

/* =====================================================================
   DISTRIBUCIÓN POR NAVE
   ===================================================================== */
async function renderDistribucion(){
  const body = document.getElementById('navesBody');
  if(!MODELO.cargado){
    body.innerHTML = `<div class="card"><div class="empty">Cargando detalle de naves…</div></div>`;
    try{ await fetchModelo(); }catch(err){ MODELO.cargado = true; MODELO.error = err; }
    if(navesView !== 'distribucion' || !document.getElementById('navesBody')) return; // el usuario cambió de pestaña
  }
  if(MODELO.error){
    body.innerHTML = `
      <div class="alert alert-warning">
        <h3>El modelo de datos todavía no está aplicado en Supabase</h3>
        <p class="hint" style="margin:6px 0 0;">Esta vista lee <code>v_lote_distribucion</code>. En el SQL Editor del proyecto ejecuta, en orden:
        <code>supabase/migrations/20261019120000_modelo_dimensional.sql</code>, <code>20261019150000_vistas_distribucion.sql</code>, <code>etl/out/staging_base.sql</code> y <code>etl/transformar_base.sql</code> (omite los que ya hayas corrido).
        Detalle: ${esc(MODELO.error.message || MODELO.error.code || 'error desconocido')}</p>
      </div>`;
    return;
  }
  if(!MODELO.lotes.length){
    body.innerHTML = `<div class="card"><div class="empty">El modelo está aplicado pero no tiene naves cargadas. Ejecuta <code>etl/transformar_base.sql</code>.</div></div>`;
    return;
  }

  const anios = [...new Set(MODELO.lotes.map(l=>String(l.periodo_operacion).slice(0,4)))].sort().reverse();
  const productos = [...new Set(MODELO.lotes.map(l=>l.producto))].sort();
  const chips = (key, opts) => opts.map(([v,t])=>`<div class="chip ${distFiltro[key]===v?'active':''}" data-k="${key}" data-v="${v}">${t}</div>`).join('');

  body.innerHTML = `
    <div class="card">
      <div class="dist-filters" id="distFilters">
        <div class="tabs-filter">${chips('puerto', [['TODOS','Todos los puertos'],['CALLAO','Callao'],['CHANCAY','Chancay']])}</div>
        <div class="tabs-filter">${chips('anio', [['TODOS','Todos los años'], ...anios.map(a=>[a,a])])}</div>
        <div class="tabs-filter">${chips('producto', [['TODOS','Todos'], ...productos.map(p=>[p, p.charAt(0)+p.slice(1).toLowerCase()])])}</div>
        <label class="dist-check"><input type="checkbox" id="distSoloAT" ${distFiltro.soloAT?'checked':''}> Solo naves que pasaron por almacén</label>
        <input class="dist-search" id="distSearch" type="search" placeholder="Buscar nave…" value="${esc(distFiltro.q)}">
      </div>
      <div id="distKpis" class="dist-kpis"></div>
      <div class="dist-legend" id="distLegend"></div>
      <div class="scroll-x"><table id="tblDist" class="dist-table"></table></div>
    </div>
    <div id="distDetalle"></div>
    <div class="viz-tip" id="vizTip" hidden></div>
  `;

  document.getElementById('distFilters').addEventListener('click', e=>{
    const chip = e.target.closest('.chip'); if(!chip) return;
    distFiltro[chip.dataset.k] = chip.dataset.v; renderDistribucion();
  });
  document.getElementById('distSoloAT').addEventListener('change', e=>{ distFiltro.soloAT = e.target.checked; drawDist(); });
  document.getElementById('distSearch').addEventListener('input', e=>{ distFiltro.q = e.target.value; drawDist(); });
  drawDist();
}

/* Agrega la distribución de un lote en una estructura cómoda para dibujar. */
function resumenLote(loteId){
  const filas = MODELO.distribucion.filter(d=>d.lote_id===loteId);
  const plantas = filas.filter(d=>d.tipo_destino==='PLANTA');
  const ats = filas.filter(d=>d.tipo_destino==='ALMACEN_TERCERO');
  const porPlanta = Object.fromEntries(plantas.map(p=>[p.destino_codigo, p]));
  return {
    plantas, ats, porPlanta,
    tmAT: ats.reduce((s,a)=>s+(a.tm_recibida_desde_puerto||0),0),
    stockAT: ats.reduce((s,a)=>s+(a.tm_stock_almacen||0),0),
    planTotal: filas.reduce((s,f)=>s+(f.tm_plan||0),0),
  };
}

function lotesFiltrados(){
  const q = distFiltro.q.trim().toUpperCase();
  return MODELO.lotes.filter(l=>{
    if(distFiltro.puerto!=='TODOS' && l.puerto!==distFiltro.puerto) return false;
    if(distFiltro.anio!=='TODOS' && !String(l.periodo_operacion).startsWith(distFiltro.anio)) return false;
    if(distFiltro.producto!=='TODOS' && l.producto!==distFiltro.producto) return false;
    if(q && !l.buque.toUpperCase().includes(q)) return false;
    if(distFiltro.soloAT && !(l.tm_ingreso_almacen > 0)) return false;
    return true;
  }).sort((a,b)=> String(b.periodo_operacion).localeCompare(String(a.periodo_operacion)) || a.buque.localeCompare(b.buque));
}

function drawDist(){
  const lotes = lotesFiltrados();
  const tot = k => lotes.reduce((s,l)=>s+(Number(l[k])||0),0);
  const tmManif = tot('tm_manifestadas'), tmAT = tot('tm_ingreso_almacen'), stock = tot('tm_stock_almacen'), merma = tot('merma_total_tm');
  const conAT = lotes.filter(l=>l.tm_ingreso_almacen>0).length;

  document.getElementById('distKpis').innerHTML = `
    <div class="dist-kpi"><span class="k">Naves (lotes)</span><span class="v">${lotes.length}</span><span class="s">${fmtTm0(tmManif)} TM manifestadas</span></div>
    <div class="dist-kpi"><span class="k">Directo a PAB</span><span class="v">${fmtPct(tmManif ? tot('tm_ingreso_planta_directo')/tmManif : 0)}</span><span class="s">${fmtTm0(tot('tm_ingreso_planta_directo'))} TM</span></div>
    <div class="dist-kpi"><span class="k">Pasó por almacén tercero</span><span class="v">${fmtPct(tmManif ? tmAT/tmManif : 0)}</span><span class="s">${fmtTm0(tmAT)} TM · ${conAT} naves</span></div>
    <div class="dist-kpi ${stock>0?'is-warn':''}"><span class="k">Sigue en almacén</span><span class="v">${fmtTm0(stock)} <small>TM</small></span><span class="s">sin salida registrada a planta</span></div>
    <div class="dist-kpi"><span class="k">Merma total</span><span class="v">${fmtPct(tmManif ? merma/tmManif : 0, 2)}</span><span class="s">${fmtTm0(merma)} TM</span></div>
  `;
  document.getElementById('distLegend').innerHTML =
    PAB_ORDEN.map(c=>`<span class="legend-item"><span class="legend-sw" style="background:${PAB_COLORES[c]}"></span>${PAB_CORTO[c]}</span>`).join('') +
    `<span class="legend-item"><span class="legend-sw sw-stock"></span>Stock en almacén</span>`;

  const tbl = document.getElementById('tblDist');
  if(!lotes.length){ tbl.innerHTML = `<tbody><tr><td class="empty">Ninguna nave coincide con los filtros.</td></tr></tbody>`; return; }
  if(!lotes.some(l=>l.lote_id===distSel)) distSel = lotes[0].lote_id;

  tbl.innerHTML = `
    <thead><tr><th>Mes</th><th>Nave</th><th>Producto</th><th>Puerto</th><th>TM manif.</th><th style="min-width:220px">Reparto final del lote</th><th>Vía almacén</th><th>Stock AT</th><th>Merma</th></tr></thead>
    <tbody>${lotes.map(l=>{
      const r = resumenLote(l.lote_id);
      const segs = PAB_ORDEN.filter(c=>r.porPlanta[c]?.tm_total_planta>0).map(c=>{
        const p = r.porPlanta[c];
        return `<span class="seg" style="width:${(p.tm_total_planta/l.tm_manifestadas*100).toFixed(2)}%;background:${PAB_COLORES[c]}"
                 data-tip="${esc(PAB_CORTO[c])}|${fmtTm0(p.tm_total_planta)} TM · ${fmtPct(p.pct_del_lote)}${p.tm_recibida_desde_almacen>0?` (${fmtTm0(p.tm_recibida_desde_almacen)} vía AT)`:''}"></span>`;
      }).join('') + (r.stockAT>0 ? `<span class="seg sw-stock" style="width:${(r.stockAT/l.tm_manifestadas*100).toFixed(2)}%"
                 data-tip="Stock en almacén|${fmtTm0(r.stockAT)} TM · ${fmtPct(r.stockAT/l.tm_manifestadas)}"></span>` : '');
      const ats = r.ats.filter(a=>a.tm_recibida_desde_puerto>0).map(a=>a.destino).join(', ');
      return `<tr class="${l.lote_id===distSel?'is-sel':''}" data-lote="${l.lote_id}">
        <td>${periodoTxt(l.periodo_operacion)}</td>
        <td class="txt"><strong>${esc(l.buque)}</strong>${l.estado==='EN_PROCESO'?' <span class="tag pill-proc">en proceso</span>':''}</td>
        <td class="txt">${esc(l.material)}</td>
        <td><span class="tag ${l.puerto.toLowerCase()}">${l.puerto}</span></td>
        <td>${fmtTm0(l.tm_manifestadas)}</td>
        <td><div class="stackbar">${segs}</div></td>
        <td class="txt">${l.tm_ingreso_almacen>0 ? `${fmtPct(l.tm_ingreso_almacen/l.tm_manifestadas,0)} <span class="muted">· ${esc(ats)}</span>` : '<span class="muted">—</span>'}</td>
        <td class="${r.stockAT>0?'pos':''}">${r.stockAT>0 ? fmtTm0(r.stockAT) : '<span class="muted">—</span>'}</td>
        <td>${fmtPct(l.merma_total_pct, 2)}</td>
      </tr>`;
    }).join('')}</tbody>`;

  tbl.querySelector('tbody').addEventListener('click', e=>{
    const tr = e.target.closest('tr[data-lote]'); if(!tr) return;
    distSel = Number(tr.dataset.lote);
    tbl.querySelectorAll('tr.is-sel').forEach(x=>x.classList.remove('is-sel'));
    tr.classList.add('is-sel');
    drawDetalle();
    document.getElementById('distDetalle').scrollIntoView({behavior:'smooth', block:'start'});
  });
  bindTips(tbl);
  drawDetalle();
}

function drawDetalle(){
  const el = document.getElementById('distDetalle');
  const l = MODELO.lotes.find(x=>x.lote_id===distSel);
  if(!l){ el.innerHTML = ''; return; }
  const r = resumenLote(l.lote_id);
  const flujo = MODELO.flujo.filter(f=>f.lote_id===l.lote_id);
  const sinPlan = r.planTotal === 0;

  const filas = [...r.plantas].sort((a,b)=>PAB_ORDEN.indexOf(a.destino_codigo)-PAB_ORDEN.indexOf(b.destino_codigo));
  const mermas = [
    ['Travesía', l.merma_travesia_tm, 'manifestado − salida de terminal'],
    ['Transporte puerto → destino', l.merma_transporte_tm, 'salida de terminal − ingreso en PAB/AT'],
    ['Almacenamiento', l.merma_almacenamiento_tm, l.merma_almacenamiento_tm==null && l.tm_ingreso_almacen>0 ? 'se reconoce al vaciarse el almacén' : 'ingreso AT − salida AT'],
    ['Traslado almacén → PAB', l.merma_traslado_almacen_tm, 'salida AT − llegada a PAB'],
  ];

  el.innerHTML = `
    <div class="card">
      <div class="card-head"><span class="eyebrow">DETALLE</span><h3>${esc(l.buque)} · ${esc(l.material)}</h3>
        <span class="tag ${l.puerto.toLowerCase()}">${l.puerto}</span><span class="badge">${periodoTxt(l.periodo_operacion)}</span></div>
      <p class="hint">Recorrido físico del lote desde la terminal. El ancho de cada flujo es proporcional a las TM; pasa el cursor para ver cifras.</p>
      <div class="dist-steps">
        <div><span class="k">Manifestado</span><span class="v">${fmtTm0(l.tm_manifestadas)}</span></div>
        <div><span class="k">Salió de terminal</span><span class="v">${fmtTm0(l.tm_descargada)}</span></div>
        <div><span class="k">Llegó a PAB</span><span class="v">${fmtTm0(l.tm_total_en_planta)}</span></div>
        <div class="${l.tm_stock_almacen>0?'is-warn':''}"><span class="k">En almacén</span><span class="v">${fmtTm0(l.tm_stock_almacen)}</span></div>
        <div><span class="k">Merma</span><span class="v">${fmtTm0(l.merma_total_tm)} <small>(${fmtPct(l.merma_total_pct,2)})</small></span></div>
      </div>
      <div class="sankey-wrap" id="sankey">${sankeySVG(l, r, flujo)}</div>
    </div>

    <div class="grid-2 mt-16">
      <div class="card">
        <h3>Distribución por planta: plan vs. real</h3>
        <p class="hint">${sinPlan ? 'Esta nave no tiene plan de distribución cargado en la fuente (BASE).' : 'Desvío = total recibido en la planta − TM planificadas.'}</p>
        <div class="scroll-x"><table>
          <thead><tr><th>Destino</th><th>Plan</th><th>Directo puerto</th><th>Desde almacén</th><th>Total</th><th>% lote</th><th>Desvío</th></tr></thead>
          <tbody>${filas.map(p=>`<tr>
            <td class="txt"><span class="legend-sw" style="background:${PAB_COLORES[p.destino_codigo]||'#98A2B3'}"></span>${esc(p.destino)}</td>
            <td>${p.tm_plan ? fmtTm0(p.tm_plan) : '<span class="muted">—</span>'}</td>
            <td>${fmtTm0(p.tm_recibida_desde_puerto)}</td>
            <td>${p.tm_recibida_desde_almacen ? fmtTm0(p.tm_recibida_desde_almacen) : '<span class="muted">—</span>'}</td>
            <td><strong>${fmtTm0(p.tm_total_planta)}</strong></td>
            <td>${fmtPct(p.pct_del_lote)}</td>
            <td>${sinPlan ? '<span class="muted">—</span>' : `<span class="${p.desvio_vs_plan_tm<0?'pos':'neg'}">${p.desvio_vs_plan_tm>0?'+':''}${fmtTm0(p.desvio_vs_plan_tm)}</span>`}</td>
          </tr>`).join('')}
          ${r.ats.map(a=>`<tr class="row-at">
            <td class="txt"><span class="legend-sw sw-stock"></span>${esc(a.destino)} <span class="muted">(almacén)</span></td>
            <td>${a.tm_plan ? fmtTm0(a.tm_plan) : '<span class="muted">—</span>'}</td>
            <td>${fmtTm0(a.tm_recibida_desde_puerto)}</td>
            <td class="txt muted" colspan="2">despachó ${fmtTm0(a.tm_despachada_a_planta)} a PAB · stock ${fmtTm0(a.tm_stock_almacen)}</td>
            <td>${fmtPct(a.pct_del_lote)}</td>
            <td><span class="muted">—</span></td>
          </tr>`).join('')}
          </tbody>
        </table></div>
      </div>
      <div class="card">
        <h3>Merma por etapa</h3>
        <p class="hint">Negativo = llegó más de lo que salió (diferencias de balanza).</p>
        ${mermas.map(([t,v,nota])=>`<div class="line-item"><span>${t}<br><small class="muted">${nota}</small></span><span>${v==null ? '<span class="muted">pendiente</span>' : fmtN(v)+' TM'}</span></div>`).join('')}
        <div class="line-item total"><span>Merma total del proceso</span><span>${fmtN(l.merma_total_tm)} TM · ${fmtPct(l.merma_total_pct,2)}</span></div>
        ${flujo.some(f=>f.es_agregado) ? `<p class="audit-note"><span class="dot" style="background:var(--amber)"></span>Cifras por lote y destino (hoja BASE). El detalle viaje por viaje llega al cargar las hojas de balanza.</p>` : ''}
      </div>
    </div>`;
  bindTips(el);
}

/* Diagrama de flujo (sankey simple): Terminal → [Almacén] → PAB / Stock.
   Altura de nodos y ancho de cintas ∝ TM. Sin librerías. */
function sankeySVG(l, r, flujo){
  const W = 860, H = 300, NW = 12, TOP = 34, PAD = 10, GAP = 14;  // TOP: espacio para títulos de columna y etiquetas
  const tieneAT = r.ats.some(a=>a.tm_recibida_desde_puerto>0);
  const xT = 210, xA = tieneAT ? 455 : null, xP = 690;

  const terminalOut = flujo.filter(f=>f.tramo==='PUERTO_PLANTA' || f.tramo==='PUERTO_ALMACEN');
  const atOut = flujo.filter(f=>f.tramo==='ALMACEN_PLANTA');
  const ats = r.ats.filter(a=>a.tm_recibida_desde_puerto>0).map(a=>({codigo:a.destino_codigo, nombre:a.destino, tm:a.tm_recibida_desde_puerto, stock:a.tm_stock_almacen||0}));
  const plantas = PAB_ORDEN.filter(c=>r.porPlanta[c]?.tm_total_planta>0).map(c=>({codigo:c, nombre:PAB_CORTO[c], tm:r.porPlanta[c].tm_total_planta}));
  const derecha = [...plantas];
  if(r.stockAT>0) derecha.push({codigo:'STOCK', nombre:'Stock en almacén', tm:r.stockAT});

  const totalT = terminalOut.reduce((s,f)=>s+f.tm_salida,0) || 1;
  const maxCol = Math.max(totalT, derecha.reduce((s,n)=>s+n.tm,0), ats.reduce((s,a)=>s+a.tm,0));
  const nMax = Math.max(1, derecha.length, ats.length);
  const k = (H - TOP - PAD - GAP*(nMax-1)) / maxCol;

  // posiciones verticales de nodos (columna centrada)
  const colocar = (nodos) => { const alto = nodos.reduce((s,n)=>s+n.tm*k,0) + GAP*(nodos.length-1); let y = TOP + (H-TOP-PAD-alto)/2;
    nodos.forEach(n=>{ n.y = y; n.h = Math.max(2, n.tm*k); n.inY = y; n.outY = y; y += n.h + GAP; }); };
  const T = {codigo:'T', nombre: l.puerto==='CALLAO' ? 'APM Callao' : 'COSCO Chancay', tm: totalT};
  colocar([T]); colocar(ats); colocar(derecha);
  const byCod = Object.fromEntries([...ats.map(a=>['A'+a.codigo,a]), ...derecha.map(p=>['P'+p.codigo,p])]);

  const cinta = (x0, y0, x1, y1, h, color, tip) => {
    const c = (x0+x1)/2;
    return `<path class="link" d="M${x0},${y0} C${c},${y0} ${c},${y1} ${x1},${y1} L${x1},${y1+h} C${c},${y1+h} ${c},${y0+h} ${x0},${y0+h} Z"
             fill="${color}" data-tip="${esc(tip)}"/>`;
  };
  let links = '';
  // terminal -> planta directo, luego terminal -> almacén
  // Cada cinta sale de la terminal en el orden vertical de su destino -> menos cruces
  const yDestino = f => (f.tramo==='PUERTO_PLANTA' ? byCod['P'+f.destino_codigo] : byCod['A'+f.destino_codigo])?.y ?? 0;
  const ordT = [...terminalOut].sort((a,b)=> yDestino(a) - yDestino(b));
  ordT.forEach(f=>{
    const dest = f.tramo==='PUERTO_PLANTA' ? byCod['P'+f.destino_codigo] : byCod['A'+f.destino_codigo];
    if(!dest) return;
    const h = f.tm_salida*k, x1 = f.tramo==='PUERTO_PLANTA' ? xP : xA;
    const color = f.tramo==='PUERTO_PLANTA' ? PAB_COLORES[f.destino_codigo] : '#98A2B3';
    links += cinta(xT+NW, T.outY, x1, dest.inY, h, color, `${T.nombre} → ${dest.nombre}|${fmtTm0(f.tm_salida)} TM salieron · ${fmtTm0(f.tm_llegada)} TM llegaron`);
    T.outY += h; dest.inY += f.tm_llegada*k;
  });
  // almacén -> planta, luego almacén -> stock
  [...atOut].sort((a,b)=>PAB_ORDEN.indexOf(a.destino_codigo)-PAB_ORDEN.indexOf(b.destino_codigo)).forEach(f=>{
    const src = byCod['A'+f.origen_codigo], dest = byCod['P'+f.destino_codigo];
    if(!src || !dest) return;
    const h = f.tm_salida*k;
    links += cinta(xA+NW, src.outY, xP, dest.inY, h, PAB_COLORES[f.destino_codigo], `${src.nombre} → ${dest.nombre}|${fmtTm0(f.tm_salida)} TM salieron · ${fmtTm0(f.tm_llegada)} TM llegaron`);
    src.outY += h; dest.inY += f.tm_llegada*k;
  });
  const st = byCod['PSTOCK'];
  ats.filter(a=>a.stock>0).forEach(a=>{
    const h = a.stock*k;
    links += cinta(xA+NW, a.outY, xP, st.inY, h, 'url(#hatch)', `${a.nombre}: en stock|${fmtTm0(a.stock)} TM sin salida registrada`);
    a.outY += h; st.inY += h;
  });

  // alinear: 'end' = etiqueta a la izquierda, 'start' = a la derecha, 'above' = centrada encima
  const nodo = (x, n, color, alinear) => {
    const lx = alinear==='end' ? x-8 : alinear==='start' ? x+NW+8 : x+NW/2;
    const ly = alinear==='above' ? n.y-6 : n.y+n.h/2;
    const anchor = alinear==='above' ? 'middle' : alinear;
    const base = alinear==='above' ? 'auto' : 'middle';
    return `<rect x="${x}" y="${n.y}" width="${NW}" height="${n.h}" rx="2" fill="${color}" data-tip="${esc(n.nombre)}|${fmtTm0(n.tm)} TM"/>
      <text x="${lx}" y="${ly}" text-anchor="${anchor}" dominant-baseline="${base}" class="sk-lbl">
        <tspan font-weight="600">${esc(n.nombre)}</tspan><tspan class="sk-val" dx="6">${fmtTm0(n.tm)}</tspan></text>`;
  };

  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Flujo de ${esc(l.buque)}: terminal, almacenes y plantas">
    <defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="6" height="6" fill="#E3E7EE"/><line x1="0" y1="0" x2="0" y2="6" stroke="#98A2B3" stroke-width="2"/></pattern></defs>
    <g class="links">${links}</g>
    ${nodo(xT, T, '#1B2433', 'end')}
    ${ats.map(a=>nodo(xA, a, '#5B6572', 'above')).join('')}
    ${derecha.map(p=>nodo(xP, p, p.codigo==='STOCK' ? 'url(#hatch)' : PAB_COLORES[p.codigo], 'start')).join('')}
    <text x="${xT+NW/2}" y="10" text-anchor="middle" class="sk-col">TERMINAL</text>
    ${tieneAT ? `<text x="${xA+NW/2}" y="10" text-anchor="middle" class="sk-col">ALMACÉN TERCERO</text>` : ''}
    <text x="${xP+NW/2}" y="10" text-anchor="middle" class="sk-col">DESTINO FINAL</text>
  </svg>`;
}

/* Tooltip compartido: cualquier elemento con data-tip="Título|detalle". */
function bindTips(root){
  const tip = document.getElementById('vizTip'); if(!tip) return;
  root.addEventListener('mousemove', e=>{
    const t = e.target.closest('[data-tip]');
    if(!t){ tip.hidden = true; return; }
    const [a, b] = t.dataset.tip.split('|');
    tip.innerHTML = `<strong>${esc(a)}</strong>${b?`<br>${esc(b)}`:''}`;
    tip.hidden = false;
    const x = Math.min(e.clientX + 14, window.innerWidth - tip.offsetWidth - 8);
    tip.style.left = x + 'px'; tip.style.top = (e.clientY + 14) + 'px';
  });
  root.addEventListener('mouseleave', ()=>{ tip.hidden = true; });
}

/* =====================================================================
   COMPARATIVO 2026 (hoja "Comparativo")
   ===================================================================== */
function renderComparativo(){
  document.getElementById('navesBody').innerHTML = `
    <div class="card">
      <p class="hint">Histórico de naves descargadas en 2026, con el mismo modelo del comparativo Callao–Chancay del archivo original: gasto presupuestado vs. gasto real (COSCO / APM).</p>
      <div class="tabs-filter" id="filterChips">
        ${['TODOS','CHANCAY','CALLAO'].map(p=>`<div class="chip ${navesFilter===p?'active':''}" data-p="${p}">${p==='TODOS'?'Todos los puertos':p.charAt(0)+p.slice(1).toLowerCase()}</div>`).join('')}
      </div>
      <div class="scroll-x"><table id="tblNaves"></table></div>
    </div>
  `;
  document.getElementById('filterChips').addEventListener('click', e=>{
    const chip = e.target.closest('.chip'); if(!chip) return;
    navesFilter = chip.dataset.p; renderComparativo();
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
