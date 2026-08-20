/* data.js — Datos semilla y catálogos extraídos del consolidado Excel
   'Resumen de gastos Puerto Chancay'. No depende de otros módulos. */

/* =====================================================================
   1. DATOS SEMILLA — extraídos del consolidado Excel del Puerto Chancay
   ===================================================================== */
// Catálogos — no varían en el tiempo (a diferencia de las tarifas)
const CATALOGOS = {
  plantas: [
    {id:'5003', nombre:'Chancay', codigo:'5003'},
    {id:'5029', nombre:'GH Chancay', codigo:'5029'},
    {id:'5001', nombre:'Lurín', codigo:'5001'},
  ],
  transportistas: ['TOSA E.I.R.L.', 'TRANSJIBAJA S.A.C.', 'VILMA ROJAS'],
  productos: ['Maíz', 'Torta de soya', 'Grano de soya'],
};

// Tarifas SÍ varían en el tiempo -> se guardan como versiones con vigencia,
// nunca se sobrescriben. Cada simulación queda enlazada al id de la versión usada.
function seedVersion(){
  return {
    id: 'V-2026-01',
    vigenteDesde: '2026-01-01',
    autor: 'Carga inicial (Excel)',
    creadoEn: new Date('2026-01-01').toISOString(),
    nota: 'Valores extraídos del consolidado original.',
    tipoCambio: 3.35,
    // S/. por TN — flete puerto de origen -> planta, por transportista
    flete: {
      CHANCAY: { '5003': {'TOSA E.I.R.L.':9.50,'TRANSJIBAJA S.A.C.':8.00,'VILMA ROJAS':7.90},
                 '5029': {'TOSA E.I.R.L.':9.50,'TRANSJIBAJA S.A.C.':9.50,'VILMA ROJAS':8.90},
                 '5001': {'TOSA E.I.R.L.':50.00,'TRANSJIBAJA S.A.C.':45.00,'VILMA ROJAS':45.00} },
      CALLAO:  { '5003': {'TOSA E.I.R.L.':29.03,'TRANSJIBAJA S.A.C.':29.03,'VILMA ROJAS':29.03},
                 '5029': {'TOSA E.I.R.L.':31.51,'TRANSJIBAJA S.A.C.':31.51,'VILMA ROJAS':31.51},
                 '5001': {'TOSA E.I.R.L.':23.96,'TRANSJIBAJA S.A.C.':23.96,'VILMA ROJAS':23.96} },
    },
    // S/. por TN — componentes de descarga en puerto
    descarga: {
      CHANCAY: {balanza:0.20, comision:1.139, operativa:33.50, ayg:0.82},
      CALLAO:  {balanza:0.20, comision:1.139, operativa:34.17, ayg:0.82},
    },
    // S/. por TN — almacenamiento estimado por producto (0 = no aplica / directo a planta)
    almacenamiento: {'Maíz':0, 'Torta de soya':6.00, 'Grano de soya':5.50},
  };
}

// Histórico real de naves 2026 (hoja "Comparativo" del consolidado)
const NAVES_HISTORICO = [
 {mes:'ENERO',puerto:'CALLAO',nave:'MN CAPRICORN CONFIDENCE',tn:19500,producto:'Torta de soya',presupuesto:1262625,cosco:1505005.235064,apm:1103787.630484},
 {mes:'ENERO',puerto:'CHANCAY',nave:'MN DIAMOND SKY',tn:53538.89,producto:'Maíz',presupuesto:3466643.1275,cosco:2807568.766856,apm:3940830.053936},
 {mes:'ENERO',puerto:'CHANCAY',nave:'MN LEO OCEAN',tn:8100,producto:'Grano de soya',presupuesto:524475,cosco:475307.336942,apm:485171.43629},
 {mes:'FEBRERO',puerto:'CALLAO',nave:'MN QUEST',tn:32348,producto:'Maíz + torta de soya',presupuesto:2094533,cosco:2220157.879952,apm:2013020.939912},
 {mes:'FEBRERO',puerto:'CALLAO',nave:'MN GRANDE ISLAND',tn:8000,producto:'Torta de soya',presupuesto:518000,cosco:696431.00304,apm:446427.41724},
 {mes:'MARZO',puerto:'CALLAO',nave:'MN STELLAR RIONI',tn:34097.59,producto:'Maíz',presupuesto:2207818.9525,cosco:2222460.89766,apm:2141156.09756},
 {mes:'MARZO',puerto:'CALLAO',nave:'MN BUNUN FORTUNE',tn:12552.418,producto:'Grano de soya',presupuesto:812769.0655,cosco:1106531.05648,apm:727938.74408},
 {mes:'MARZO',puerto:'CHANCAY',nave:'MN LILA NOLA',tn:9546,producto:'Torta de soya',presupuesto:618103.5,cosco:443266.711008,apm:620059.043248},
 {mes:'ABRIL',puerto:'CHANCAY',nave:'MN TAC SUZUKA',tn:34099.07,producto:'Maíz',presupuesto:2207914.7825,cosco:1621839.27051,apm:2273825.53591},
 {mes:'ABRIL',puerto:'CALLAO',nave:'MN EPTALOFOS',tn:34100,producto:'Maíz',presupuesto:2207975,cosco:2785731.3,apm:2091796.3},
 {mes:'ABRIL',puerto:'CALLAO',nave:'MN SUNSET',tn:10800,producto:'Grano de soya',presupuesto:699300,cosco:804595.28,apm:670347.68},
 {mes:'ABRIL',puerto:'CALLAO',nave:'MN ROSSANA',tn:13877.245,producto:'Torta de soya',presupuesto:898551.61375,cosco:979058.492417,apm:860634.153427},
 {mes:'MAYO',puerto:'CALLAO',nave:'MN LUCKY LUKE',tn:18700,producto:'Torta de soya',presupuesto:1210825,cosco:1289934,apm:1096077},
 {mes:'MAYO',puerto:'CHANCAY',nave:'MN KING ISLAND',tn:30600,producto:'Maíz',presupuesto:1981350,cosco:1449726,apm:2063244},
 {mes:'MAYO',puerto:'CALLAO',nave:'MN ARCADIA',tn:38757.82,producto:'Maíz',presupuesto:2509568.845,cosco:2609399,apm:2469357},
 {mes:'JUNIO',puerto:'CHANCAY',nave:'MN GEORGIA',tn:34820.955,producto:'Maíz + torta de soya',presupuesto:2254656.83625,cosco:2096630,apm:2222686},
 {mes:'JUNIO',puerto:'CALLAO',nave:'MN SHARP ISLAND',tn:7022,producto:'Grano de soya',presupuesto:454674.5,cosco:449121,apm:440558},
 {mes:'JULIO',puerto:'CALLAO',nave:'MN AGHIA DYNAMI',tn:34140.74,producto:'Maíz',presupuesto:2210612.915,cosco:2348588,apm:2220953},
 {mes:'JULIO',puerto:'CALLAO',nave:'MN PACIFIC ETERNITY',tn:7499.655,producto:'Grano de soya',presupuesto:485602.66125,cosco:645042,apm:507607},
 {mes:'JULIO',puerto:'CALLAO',nave:'SEA GOAT',tn:7000,producto:'Grano de soya',presupuesto:453250,cosco:618982,apm:502740},
 {mes:'JULIO',puerto:'CALLAO',nave:'ICY BAY',tn:8000,producto:'Torta de soya',presupuesto:518000,cosco:528908,apm:566767},
 {mes:'JULIO',puerto:'CHANCAY',nave:'UNITED HARMONY',tn:34089.99,producto:'Maíz + torta',presupuesto:2207326.8525,cosco:1719472.34,apm:2500876.21},
 {mes:'JULIO',puerto:'CALLAO',nave:'MUROVDAG',tn:13200,producto:'Torta de soya',presupuesto:854700,cosco:1133020,apm:948024},
];
