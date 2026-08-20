-- ============================================================================
-- Seed: catálogos, versión de tarifas inicial e histórico de naves.
-- Traducción directa de CATALOGOS, seedVersion() y NAVES_HISTORICO en
-- js/data.js — mismos valores, ahora como filas.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Catálogos
-- ---------------------------------------------------------------------------
insert into public.plantas (id, nombre, codigo) values
  ('5003', 'Chancay',    '5003'),
  ('5029', 'GH Chancay', '5029'),
  ('5001', 'Lurín',      '5001');

insert into public.transportistas (nombre) values
  ('TOSA E.I.R.L.'),
  ('TRANSJIBAJA S.A.C.'),
  ('VILMA ROJAS');

insert into public.productos (nombre) values
  ('Maíz'),
  ('Torta de soya'),
  ('Grano de soya');

-- ---------------------------------------------------------------------------
-- Versión de tarifas inicial: V-2026-01
-- (created_by queda null: es carga de datos semilla, no un admin real)
-- ---------------------------------------------------------------------------
insert into public.tarifa_versiones (id, vigente_desde, autor, nota, tipo_cambio, creado_en) values
  ('V-2026-01', '2026-01-01', 'Carga inicial (Excel)',
   'Valores extraídos del consolidado original.', 3.35, '2026-01-01T00:00:00Z');

-- Flete: S/. por TN, por puerto de origen -> planta -> transportista
insert into public.tarifa_flete (version_id, puerto, planta_id, transportista_id, valor)
select 'V-2026-01', puerto, planta_id, t.id, valor
from (values
  ('CHANCAY', '5003', 'TOSA E.I.R.L.',       9.50),
  ('CHANCAY', '5003', 'TRANSJIBAJA S.A.C.',  8.00),
  ('CHANCAY', '5003', 'VILMA ROJAS',         7.90),
  ('CHANCAY', '5029', 'TOSA E.I.R.L.',       9.50),
  ('CHANCAY', '5029', 'TRANSJIBAJA S.A.C.',  9.50),
  ('CHANCAY', '5029', 'VILMA ROJAS',         8.90),
  ('CHANCAY', '5001', 'TOSA E.I.R.L.',      50.00),
  ('CHANCAY', '5001', 'TRANSJIBAJA S.A.C.', 45.00),
  ('CHANCAY', '5001', 'VILMA ROJAS',        45.00),
  ('CALLAO',  '5003', 'TOSA E.I.R.L.',      29.03),
  ('CALLAO',  '5003', 'TRANSJIBAJA S.A.C.', 29.03),
  ('CALLAO',  '5003', 'VILMA ROJAS',        29.03),
  ('CALLAO',  '5029', 'TOSA E.I.R.L.',      31.51),
  ('CALLAO',  '5029', 'TRANSJIBAJA S.A.C.', 31.51),
  ('CALLAO',  '5029', 'VILMA ROJAS',        31.51),
  ('CALLAO',  '5001', 'TOSA E.I.R.L.',      23.96),
  ('CALLAO',  '5001', 'TRANSJIBAJA S.A.C.', 23.96),
  ('CALLAO',  '5001', 'VILMA ROJAS',        23.96)
) as f(puerto, planta_id, transportista_nombre, valor)
join public.transportistas t on t.nombre = f.transportista_nombre;

-- Descarga: S/. por TN, componentes fijos por puerto
insert into public.tarifa_descarga (version_id, puerto, balanza, comision, operativa, ayg) values
  ('V-2026-01', 'CHANCAY', 0.20, 1.139, 33.50, 0.82),
  ('V-2026-01', 'CALLAO',  0.20, 1.139, 34.17, 0.82);

-- Almacenamiento: S/. por TN, por producto
insert into public.tarifa_almacenamiento (version_id, producto_id, valor)
select 'V-2026-01', p.id, a.valor
from (values
  ('Maíz', 0.00),
  ('Torta de soya', 6.00),
  ('Grano de soya', 5.50)
) as a(producto_nombre, valor)
join public.productos p on p.nombre = a.producto_nombre;

-- ---------------------------------------------------------------------------
-- Histórico de naves 2026 (hoja "Comparativo" del consolidado)
-- ---------------------------------------------------------------------------
insert into public.naves_historico (mes, puerto, nave, tn, producto, presupuesto, cosco, apm) values
  ('ENERO',    'CALLAO',  'MN CAPRICORN CONFIDENCE', 19500,     'Torta de soya',          1262625,      1505005.235064, 1103787.630484),
  ('ENERO',    'CHANCAY', 'MN DIAMOND SKY',          53538.89,  'Maíz',                   3466643.1275, 2807568.766856, 3940830.053936),
  ('ENERO',    'CHANCAY', 'MN LEO OCEAN',            8100,      'Grano de soya',          524475,       475307.336942,  485171.43629),
  ('FEBRERO',  'CALLAO',  'MN QUEST',                32348,     'Maíz + torta de soya',   2094533,      2220157.879952, 2013020.939912),
  ('FEBRERO',  'CALLAO',  'MN GRANDE ISLAND',        8000,      'Torta de soya',          518000,       696431.00304,   446427.41724),
  ('MARZO',    'CALLAO',  'MN STELLAR RIONI',        34097.59,  'Maíz',                   2207818.9525, 2222460.89766,  2141156.09756),
  ('MARZO',    'CALLAO',  'MN BUNUN FORTUNE',        12552.418, 'Grano de soya',          812769.0655,  1106531.05648,  727938.74408),
  ('MARZO',    'CHANCAY', 'MN LILA NOLA',            9546,      'Torta de soya',          618103.5,     443266.711008,  620059.043248),
  ('ABRIL',    'CHANCAY', 'MN TAC SUZUKA',           34099.07,  'Maíz',                   2207914.7825, 1621839.27051,  2273825.53591),
  ('ABRIL',    'CALLAO',  'MN EPTALOFOS',            34100,     'Maíz',                   2207975,      2785731.3,      2091796.3),
  ('ABRIL',    'CALLAO',  'MN SUNSET',               10800,     'Grano de soya',          699300,       804595.28,      670347.68),
  ('ABRIL',    'CALLAO',  'MN ROSSANA',              13877.245, 'Torta de soya',          898551.61375, 979058.492417,  860634.153427),
  ('MAYO',     'CALLAO',  'MN LUCKY LUKE',           18700,     'Torta de soya',          1210825,      1289934,        1096077),
  ('MAYO',     'CHANCAY', 'MN KING ISLAND',          30600,     'Maíz',                   1981350,      1449726,        2063244),
  ('MAYO',     'CALLAO',  'MN ARCADIA',              38757.82,  'Maíz',                   2509568.845,  2609399,        2469357),
  ('JUNIO',    'CHANCAY', 'MN GEORGIA',              34820.955, 'Maíz + torta de soya',   2254656.83625,2096630,        2222686),
  ('JUNIO',    'CALLAO',  'MN SHARP ISLAND',         7022,      'Grano de soya',          454674.5,     449121,         440558),
  ('JULIO',    'CALLAO',  'MN AGHIA DYNAMI',         34140.74,  'Maíz',                   2210612.915,  2348588,        2220953),
  ('JULIO',    'CALLAO',  'MN PACIFIC ETERNITY',     7499.655,  'Grano de soya',          485602.66125, 645042,         507607),
  ('JULIO',    'CALLAO',  'SEA GOAT',                7000,      'Grano de soya',          453250,       618982,         502740),
  ('JULIO',    'CALLAO',  'ICY BAY',                 8000,      'Torta de soya',          518000,       528908,         566767),
  ('JULIO',    'CHANCAY', 'UNITED HARMONY',          34089.99,  'Maíz + torta',           2207326.8525, 1719472.34,     2500876.21),
  ('JULIO',    'CALLAO',  'MUROVDAG',                13200,     'Torta de soya',          854700,       1133020,        948024);
