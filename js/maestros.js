/* maestros.js — Pestaña 'Maestros & Gobierno': edición de tarifas como
   borrador y publicación de nuevas versiones con vigencia. */

let DRAFT = null;
function startDraft(){ DRAFT = JSON.parse(JSON.stringify(getActiveVersion())); }

function renderMaestros(){
  if(!DRAFT) startDraft();
  const today = new Date().toISOString().slice(0,10);

  content.innerHTML = `
    <div class="section-head">
      <h1>Maestros &amp; Gobierno de Datos</h1>
      <p>Las tarifas cambian en el tiempo: aquí no se sobrescriben — cada actualización crea una <strong>nueva versión con fecha de vigencia</strong> y queda guardada en el historial, junto con las que ya usaste.</p>
    </div>

    <div class="card" style="border-color:var(--amber);background:#FDEEEC">
      <h3>Editando un borrador de tarifas</h3>
      <p class="hint">Modifica los valores abajo y luego publícalos como nueva versión vigente. Nada se aplica hasta que guardes.</p>
      <div class="form-grid">
        <div class="field"><label>Vigente desde</label><input id="mVigencia" type="date" value="${today}"></div>
        <div class="field"><label>Responsable</label><input id="mAutor" type="text" placeholder="Tu nombre" value="${localStorage.getItem('muelle_user')||''}"></div>
      </div>
      <div class="field"><label>Nota / motivo del cambio</label><input id="mNota" type="text" placeholder="Ej. Reajuste de flete por alza de combustible"></div>
      <div style="display:flex;gap:8px;margin-top:4px">
        <button class="btn amber" id="btnPublicar">Guardar como nueva versión vigente</button>
        <button class="btn ghost" id="btnDescartar">Descartar cambios del borrador</button>
      </div>
      <div class="audit-note" style="margin-top:12px"><span class="dot"></span>Editando sobre <strong>${getActiveVersion().id}</strong> (vigente actualmente). Se creará <strong>${nextVersionId()}</strong> al publicar.</div>
    </div>

    <div class="grid-2">
      <div>
        <div class="card">
          <h3>Tipo de cambio</h3>
          <div class="field inline"><label>S/. por US$</label><input id="mTC" type="number" step="0.01" value="${DRAFT.tipoCambio}"></div>
        </div>

        <div class="card">
          <h3>Tarifas de flete — Puerto Chancay → Planta (S//TN)</h3>
          <p class="hint">Distancia corta a plantas de Lima Norte; diferenciada por transportista.</p>
          <div class="scroll-x">${renderFleteTable('CHANCAY')}</div>
        </div>

        <div class="card">
          <h3>Tarifas de flete — Puerto Callao → Planta (S//TN)</h3>
          <p class="hint">Trayecto más largo; tarifa promedio (editable por transportista).</p>
          <div class="scroll-x">${renderFleteTable('CALLAO')}</div>
        </div>
      </div>

      <div>
        <div class="card">
          <h3>Costos de descarga por puerto (S//TN)</h3>
          <div id="descargaWrap">${renderDescargaTable()}</div>
        </div>
        <div class="card">
          <h3>Almacenamiento por producto (S//TN)</h3>
          ${renderAlmacenTable()}
        </div>
        <div class="card">
          <h3>Reglas de gobierno de datos</h3>
          <ul class="rules">
            <li><span class="idx">01</span>Las tarifas no se sobrescriben: cada cambio publica una nueva versión con fecha de vigencia, responsable y nota.</li>
            <li><span class="idx">02</span>No pueden guardarse valores negativos; el sistema rechaza el borrador antes de publicarlo.</li>
            <li><span class="idx">03</span>El Simulador y el Panel General siempre calculan a partir de estas versiones — nunca se edita un resultado a mano.</li>
            <li><span class="idx">04</span>Cada simulación guardada queda enlazada al ID de la versión de tarifas usada (ver pestaña Trazabilidad).</li>
          </ul>
        </div>
      </div>
    </div>

    <div class="card" style="margin-top:16px">
      <h3>Historial de versiones de tarifas</h3>
      <p class="hint">Todas las versiones publicadas quedan disponibles — para auditoría y para simular con tarifas que ya usaste antes.</p>
      <div class="scroll-x">${renderVersionHistory()}</div>
    </div>

    <div class="footer-note">
      Valores semilla extraídos de las hojas <em>tarifas</em>, <em>Gastos de Transporte</em>, <em>Gastos de descarga BI</em> y <em>Gastos APM</em> del Excel original.
      Las tarifas de flete desde Callao y de almacenamiento por producto son promedios estimados — verifícalas contra el contrato vigente
      antes de usarlas para decisiones reales.
    </div>
  `;

  document.getElementById('mTC').addEventListener('change', e=>{
    const v = parseFloat(e.target.value); if(v>0) DRAFT.tipoCambio = v;
  });
  content.querySelectorAll('input[data-flete]').forEach(inp=>{
    inp.addEventListener('change', e=>{
      const [puerto,planta,trans] = e.target.dataset.flete.split('|');
      const v = parseFloat(e.target.value);
      if(v>=0) DRAFT.flete[puerto][planta][trans] = v;
    });
  });
  content.querySelectorAll('input[data-desc]').forEach(inp=>{
    inp.addEventListener('change', e=>{
      const [puerto,campo] = e.target.dataset.desc.split('|');
      const v = parseFloat(e.target.value);
      if(v>=0){ DRAFT.descarga[puerto][campo] = v; document.getElementById('descargaWrap').innerHTML = renderDescargaTable(); rebindDescargaInputs(); }
    });
  });
  content.querySelectorAll('input[data-alm]').forEach(inp=>{
    inp.addEventListener('change', e=>{
      const prod = e.target.dataset.alm;
      const v = parseFloat(e.target.value);
      if(v>=0) DRAFT.almacenamiento[prod] = v;
    });
  });

  document.getElementById('btnPublicar').addEventListener('click', publicarVersion);
  document.getElementById('btnDescartar').addEventListener('click', ()=>{
    startDraft(); toast('Borrador descartado'); renderMaestros();
  });

  content.querySelectorAll('#historyTable button[data-usever]').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      DATA.versions.push(Object.assign(JSON.parse(JSON.stringify(getVersionById(btn.dataset.usever))), {
        id: nextVersionId(), vigenteDesde: today, creadoEn: new Date().toISOString(),
        autor: localStorage.getItem('muelle_user')||'Analista', nota: `Reactivada desde ${btn.dataset.usever}`
      }));
      persistDATA(); startDraft(); toast('Versión anterior reactivada como vigente'); renderMaestros();
    });
  });
}
function rebindDescargaInputs(){
  content.querySelectorAll('input[data-desc]').forEach(inp=>{
    inp.addEventListener('change', e=>{
      const [puerto,campo] = e.target.dataset.desc.split('|');
      const v = parseFloat(e.target.value);
      if(v>=0){ DRAFT.descarga[puerto][campo] = v; document.getElementById('descargaWrap').innerHTML = renderDescargaTable(); rebindDescargaInputs(); }
    });
  });
}

function publicarVersion(){
  const vigenteDesde = document.getElementById('mVigencia').value;
  const autor = document.getElementById('mAutor').value || 'Analista';
  const nota = document.getElementById('mNota').value || '';
  if(!vigenteDesde){ toast('Indica la fecha de vigencia'); return; }
  localStorage.setItem('muelle_user', autor);

  const nueva = JSON.parse(JSON.stringify(DRAFT));
  nueva.id = nextVersionId();
  nueva.vigenteDesde = vigenteDesde;
  nueva.autor = autor;
  nueva.nota = nota;
  nueva.creadoEn = new Date().toISOString();

  DATA.versions.push(nueva);
  persistDATA();
  DRAFT = null;
  toast('Nueva versión de tarifas publicada: ' + nueva.id);
  renderMaestros();
}

function renderFleteTable(puerto){
  return `<table>
    <thead><tr><th>Planta</th>${CATALOGOS.transportistas.map(t=>`<th>${t}</th>`).join('')}</tr></thead>
    <tbody>${CATALOGOS.plantas.map(p=>`
      <tr><td class="txt">${p.nombre}</td>
      ${CATALOGOS.transportistas.map(t=>`<td><input data-flete="${puerto}|${p.id}|${t}" type="number" step="0.01" value="${DRAFT.flete[puerto][p.id][t]}" style="width:72px;font-family:var(--font-mono);border:1px solid var(--line);border-radius:5px;padding:4px 6px"></td>`).join('')}
      </tr>`).join('')}</tbody>
  </table>`;
}
function renderDescargaTable(){
  const labels = {balanza:'Control de balanza',comision:'Comisión de agente',operativa:'Área operativa',ayg:'Gastos A&G'};
  return `<table>
    <thead><tr><th>Componente</th><th>Chancay</th><th>Callao</th></tr></thead>
    <tbody>${Object.keys(labels).map(k=>`
      <tr><td class="txt">${labels[k]}</td>
        <td><input data-desc="CHANCAY|${k}" type="number" step="0.001" value="${DRAFT.descarga.CHANCAY[k]}" style="width:78px;font-family:var(--font-mono);border:1px solid var(--line);border-radius:5px;padding:4px 6px"></td>
        <td><input data-desc="CALLAO|${k}" type="number" step="0.001" value="${DRAFT.descarga.CALLAO[k]}" style="width:78px;font-family:var(--font-mono);border:1px solid var(--line);border-radius:5px;padding:4px 6px"></td>
      </tr>`).join('')}
      <tr><td class="txt"><strong>Total CU/TN</strong></td>
        <td><strong>${fmtN(Object.values(DRAFT.descarga.CHANCAY).reduce((a,b)=>a+b,0))}</strong></td>
        <td><strong>${fmtN(Object.values(DRAFT.descarga.CALLAO).reduce((a,b)=>a+b,0))}</strong></td>
      </tr>
    </tbody></table>`;
}
function renderAlmacenTable(){
  return `<table><thead><tr><th>Producto</th><th>S//TN</th></tr></thead>
    <tbody>${CATALOGOS.productos.map(p=>`<tr><td class="txt">${p}</td><td><input data-alm="${p}" type="number" step="0.01" value="${DRAFT.almacenamiento[p]}" style="width:78px;font-family:var(--font-mono);border:1px solid var(--line);border-radius:5px;padding:4px 6px"></td></tr>`).join('')}</tbody></table>`;
}
function renderVersionHistory(){
  const sv = sortedVersions();
  const activeId = getActiveVersion().id;
  return `<table id="historyTable">
    <thead><tr><th>Versión</th><th>Vigente desde</th><th>Estado</th><th>Responsable</th><th>Publicado</th><th>Nota</th><th>Tipo cambio</th><th></th></tr></thead>
    <tbody>${sv.map(v=>`
      <tr>
        <td>${v.id}</td>
        <td>${new Date(v.vigenteDesde+'T00:00:00').toLocaleDateString('es-PE')}</td>
        <td>${v.id===activeId?'<span class="tag chancay">VIGENTE</span>':'<span class="badge" style="margin:0">histórica</span>'}</td>
        <td class="txt">${v.autor}</td>
        <td>${new Date(v.creadoEn).toLocaleDateString('es-PE')}</td>
        <td class="txt">${v.nota||'—'}</td>
        <td>S/ ${fmtN(v.tipoCambio)}</td>
        <td>${v.id!==activeId?`<button class="btn ghost sm" data-usever="${v.id}">Usar de nuevo</button>`:''}</td>
      </tr>`).join('')}</tbody>
  </table>`;
}

/* =====================================================================
   11. HOJA DE RUTA
   ===================================================================== */
