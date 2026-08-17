/* roadmap.js — Pestaña 'Hoja de Ruta'. */

function renderRoadmap(){
  content.innerHTML = `
    <div class="section-head">
      <h1>Hoja de Ruta del Ecosistema</h1>
      <p>Este prototipo cubre la Fase 1. Así se conecta con las capacidades analíticas, predictivas y prescriptivas que sigue.</p>
    </div>
    <div class="card">
      <div class="roadmap-phase now">
        <div class="ph">01</div>
        <div>
          <h4>Centralizar &amp; automatizar (este prototipo)</h4>
          <p>Maestros únicos de puertos, plantas, transportistas y tarifas. Cálculo automático de descarga + transporte + almacenamiento. Simulador Callao vs. Chancay. Registro de trazabilidad de cada simulación con autor y fecha.</p>
        </div>
      </div>
      <div class="roadmap-phase">
        <div class="ph">02</div>
        <div>
          <h4>Integrar fuentes operativas</h4>
          <p>Conectar directamente con el sistema de balanza/APM (hoja "BD" del Excel: ~990 registros de ingreso/salida de camiones) para que el costo de transporte se calcule desde el peso real por viaje, no por simulación manual. Definir API/ETL en vez de copiar y pegar Excel.</p>
        </div>
      </div>
      <div class="roadmap-phase">
        <div class="ph">03</div>
        <div>
          <h4>Gobierno de datos formal</h4>
          <p>Roles y permisos por perfil (analista, jefe de logística, finanzas), versionado completo de tarifas, aprobación de cambios de maestros, y catálogo de datos con definiciones estándar (diccionario de datos).</p>
        </div>
      </div>
      <div class="roadmap-phase">
        <div class="ph">04</div>
        <div>
          <h4>Analítica avanzada</h4>
          <p>Tableros de laytime/demurrage (hojas "Laytime2024/2025"), estacionalidad de costos por producto, y benchmarking histórico Callao vs. Chancay por transportista y planta.</p>
        </div>
      </div>
      <div class="roadmap-phase">
        <div class="ph">05</div>
        <div>
          <h4>Modelos predictivos y prescriptivos</h4>
          <p>Predecir el costo total esperado de una nave según producto, tonelaje y temporada; recomendar automáticamente puerto + transportista óptimo sujeto a restricciones de capacidad de almacenamiento y ventanas de atraque.</p>
        </div>
      </div>
    </div>
  `;
}
