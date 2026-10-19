-- ============================================================================
-- Paso 2 de la carga: staging.base (hoja BASE) -> modelo dimensional.
--
-- Requiere: migración 20261019120000_modelo_dimensional.sql aplicada y
-- staging.base cargada (etl/base_a_staging.py).
-- Usa tablas de trabajo en el esquema staging (no temporales): el SQL Editor
-- de Supabase no garantiza la misma sesión entre sentencias.
-- Idempotente: re-ejecutarlo actualiza dimensiones (upsert) y reemplaza los
-- hechos con fuente = 'BASE' de los lotes presentes en staging.
--
-- Qué se puede y qué no se puede granular desde BASE:
--   * BASE trae totales por lote y destino, no viajes individuales: cada fila
--     de fact_viaje_camion que sale de aquí es es_agregado = true (1 fila =
--     todos los viajes del lote a ese destino). Cuando se cargue la hoja de
--     balanza (PUERTO - PAB+AT / TERCEROS A PLANTA) se reemplazan por viajes.
--   * Almacén -> planta: BASE trae salidas por almacén y llegadas por planta,
--     pero no el cruce. Si hay más de un almacén o planta se reparte
--     proporcionalmente (preserva ambos totales).
--   * Costos: se abren al nivel más fino que permiten las fórmulas de BASE
--     (flete por ruta = TM x tarifa; descarga por componente en 2026). Todo
--     lo que no se puede abrir queda en una línea AJ_* de conciliación, para
--     que el total del modelo sea siempre igual al total de BASE.
-- ============================================================================
begin;

-- ---------------------------------------------------------------------------
-- 0. Tarifario usado por las fórmulas de BASE (hoja TARIFARIO DE GASTOS)
-- ---------------------------------------------------------------------------
insert into public.tarifa_versiones (id, vigente_desde, autor, nota, tipo_cambio)
values ('V-EXCEL-2025', '2025-01-01', 'Carga hoja BASE (MACROINSUMOS 2025-2026)',
        'Tarifas que usan las fórmulas de BASE y TARIFARIO DE GASTOS. TC 3.5 = el usado en las fórmulas de plan y presupuesto.', 3.5)
on conflict (id) do nothing;

with t(origen, destino, concepto, valor) as (values
  ('TER-APM','5001','FLETE_PTO_PAB',23.96), ('TER-APM','1028','FLETE_PTO_PAB',23.96),
  ('TER-APM','5003','FLETE_PTO_PAB',29.03), ('TER-APM','5029','FLETE_PTO_PAB',31.51),
  ('TER-APM','2111','FLETE_PTO_ALM',6.40),  ('TER-APM','2129','FLETE_PTO_ALM',6.40),
  ('TER-APM','2130','FLETE_PTO_ALM',9.50),
  ('TER-COSCO','5001','FLETE_PTO_PAB',48.00),('TER-COSCO','1028','FLETE_PTO_PAB',48.00),
  ('TER-COSCO','5003','FLETE_PTO_PAB',8.025),('TER-COSCO','5029','FLETE_PTO_PAB',8.735),
  ('1028','5001','FLETE_PAB_PAB',2.50), ('5003','5029','FLETE_PAB_PAB',10.50), ('5001','5003','FLETE_PAB_PAB',39.90),
  ('DEPSA','5029','FLETE_ALM_PAB',26.90), ('DEPSA','5003','FLETE_ALM_PAB',25.50), ('DEPSA','5001','FLETE_ALM_PAB',25.90),
  ('2129','5003','FLETE_ALM_PAB',24.00),  ('2129','5001','FLETE_ALM_PAB',24.00),
  ('2111','5003','FLETE_ALM_PAB',26.90),  ('2111','5029','FLETE_ALM_PAB',26.90), ('2111','5001','FLETE_ALM_PAB',24.00))
insert into public.tarifa (version_id, concepto_id, ruta_id, unidad, moneda, valor)
select 'V-EXCEL-2025', c.id, r.id, 'TM', 'PEN', t.valor
from t
join public.dim_ubicacion o on o.codigo = t.origen
join public.dim_ubicacion d on d.codigo = t.destino
join public.dim_ruta r on r.origen_ubicacion_id = o.id and r.destino_ubicacion_id = d.id
join public.dim_concepto_costo c on c.codigo = t.concepto
on conflict do nothing;

with t(concepto, ubicacion, puerto, unidad, valor) as (values
  ('DESC_INTEGRAL', null, 'CALLAO', 'TM', 37.41), ('DESC_INTEGRAL', null, 'CHANCAY', 'TM', 36.70),
  ('ALM_ALMACENAJE', '2111', null, 'TM_MES', 5.80), ('ALM_ALMACENAJE', '2129', null, 'TM_MES', 5.50),
  ('ALM_ALMACENAJE', '2130', null, 'TM_MES', 5.80), ('ALM_ALMACENAJE_TECHO', '2111', null, 'TM_MES', 6.80),
  ('ALM_CARGADOR', '2111', null, 'TM', 2.00), ('ALM_CARGADOR', '2129', null, 'TM', 2.00), ('ALM_CARGADOR', '2130', null, 'TM', 2.00),
  ('ALM_HE_SIMPLE', '2111', null, 'HORA', 90.00), ('ALM_HE_SIMPLE', '2129', null, 'HORA', 100.00), ('ALM_HE_SIMPLE', '2130', null, 'HORA', 90.00),
  ('ALM_HE_DOBLE', '2111', null, 'HORA', 120.00), ('ALM_HE_DOBLE', '2129', null, 'HORA', 150.00), ('ALM_HE_DOBLE', '2130', null, 'HORA', 120.00))
insert into public.tarifa (version_id, concepto_id, ubicacion_id, puerto_id, unidad, moneda, valor)
select 'V-EXCEL-2025', c.id, u.id, p.id, t.unidad, 'PEN', t.valor
from t
join public.dim_concepto_costo c on c.codigo = t.concepto
left join public.dim_ubicacion u on u.codigo = t.ubicacion
left join public.dim_puerto p on p.nombre = t.puerto
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 1. Staging normalizado
-- ---------------------------------------------------------------------------
drop table if exists staging.b;
create table staging.b as
select s.*,
       make_date(s.anio, left(s.mes_txt, 2)::int, 1)          as periodo,
       upper(s.puerto)                                        as puerto_nombre,
       case upper(s.puerto) when 'CALLAO' then 'TER-APM' when 'CHANCAY' then 'TER-COSCO' end as terminal_cod,
       upper(s.mn) || '|' || to_char(make_date(s.anio, left(s.mes_txt, 2)::int, 1), 'YYYY-MM') as escala_cod
from staging.base s;

do $$
begin
  if exists (select 1 from staging.b where terminal_cod is null) then
    raise exception 'Hay lotes con puerto no reconocido: %', (select string_agg(distinct puerto, ', ') from staging.b where terminal_cod is null);
  end if;
  if exists (select 1 from staging.b where upper(producto) not in (select codigo from public.dim_producto)) then
    raise exception 'Producto no reconocido: %', (select string_agg(distinct producto, ', ') from staging.b where upper(producto) not in (select codigo from public.dim_producto));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Dimensiones (upsert)
-- ---------------------------------------------------------------------------
insert into public.dim_material (descripcion, producto_id, pais_origen_id)
select distinct on (upper(b.material)) upper(b.material), p.id, pa.id
from staging.b
join public.dim_producto p on p.codigo = upper(b.producto)
left join public.dim_pais pa on pa.nombre = upper(b.origen)
on conflict (descripcion) do nothing;

insert into public.dim_buque (nombre)
select distinct upper(b.mn) from staging.b
where not exists (select 1 from public.dim_buque x where x.nombre = upper(b.mn));

insert into public.dim_escala (codigo, buque_id, puerto_id, terminal_id, periodo_operacion, estado)
select b.escala_cod, bu.id, pu.id, t.id, b.periodo,
       case when bool_or(b.estado ilike 'en proceso') then 'EN_OPERACION' else 'CONCLUIDA' end
from staging.b
join public.dim_buque bu on bu.nombre = upper(b.mn) and bu.imo is null
join public.dim_puerto pu on pu.nombre = b.puerto_nombre
join public.dim_ubicacion ut on ut.codigo = b.terminal_cod
join public.dim_terminal t on t.id = ut.terminal_id
group by b.escala_cod, bu.id, pu.id, t.id, b.periodo
on conflict (codigo) do update
  set puerto_id = excluded.puerto_id, terminal_id = excluded.terminal_id,
      periodo_operacion = excluded.periodo_operacion, estado = excluded.estado;

insert into public.dim_lote (escala_id, material_id, codigo_lote_sap, clave_fuente, pais_origen_id,
                             tm_manifestadas, precio_cif_usd_tm, almacen_cerrado, estado)
select e.id, m.id, b.lote_sap, b.clave, pa.id, b.tm_manifestadas, b.cif_usd_tm,
       -- BASE solo calcula merma de almacenamiento cuando el AT ya se vació
       coalesce(b.i_2111,0)+coalesce(b.i_2110,0)+coalesce(b.i_2129,0)+coalesce(b.i_2130,0) > 0
         and coalesce(b.s_2111,0)+coalesce(b.s_2110,0)+coalesce(b.s_2129,0)+coalesce(b.s_2130,0) > 0
         and b.merma_almacenamiento is not null,
       case when b.estado ilike 'en proceso' then 'EN_PROCESO' else 'CONCLUIDO' end
from staging.b
join public.dim_escala e on e.codigo = b.escala_cod
join public.dim_material m on m.descripcion = upper(b.material)
left join public.dim_pais pa on pa.nombre = upper(b.origen)
on conflict (escala_id, material_id) do update
  set codigo_lote_sap = excluded.codigo_lote_sap, clave_fuente = excluded.clave_fuente,
      pais_origen_id = excluded.pais_origen_id, tm_manifestadas = excluded.tm_manifestadas,
      precio_cif_usd_tm = excluded.precio_cif_usd_tm, almacen_cerrado = excluded.almacen_cerrado,
      estado = excluded.estado;

-- b + ids del modelo
drop table if exists staging.bl;
create table staging.bl as
select b.*, l.id as lote_id, l.escala_id,
       (select id from public.dim_ubicacion where codigo = b.terminal_cod) as terminal_ubic_id
from staging.b
join public.dim_escala e on e.codigo = b.escala_cod
join public.dim_material m on m.descripcion = upper(b.material)
join public.dim_lote l on l.escala_id = e.id and l.material_id = m.id;

-- ---------------------------------------------------------------------------
-- 3. Limpiar hechos previos de BASE para estos lotes
-- ---------------------------------------------------------------------------
delete from public.fact_viaje_camion      where fuente = 'BASE' and lote_id in (select lote_id from staging.bl);
delete from public.fact_plan_distribucion where version = 'PLAN BASE' and lote_id in (select lote_id from staging.bl);
delete from public.fact_costo             where fuente = 'BASE' and lote_id in (select lote_id from staging.bl);
delete from public.fact_reclamo_merma     where documento like 'BASE:%' and lote_id in (select lote_id from staging.bl);

-- ---------------------------------------------------------------------------
-- 4. Distribución física (viajes agregados por lote x ruta)
-- ---------------------------------------------------------------------------
-- 4a. Terminal -> planta / almacén tercero
insert into public.fact_viaje_camion (lote_id, ruta_id, periodo, peso_salida_kg, peso_llegada_kg,
                                      es_agregado, n_viajes, fuente, fuente_fila)
select bl.lote_id, r.id, bl.periodo,
       round(coalesce(x.salida, 0) * 1000, 1), round(coalesce(x.llegada, 0) * 1000, 1),
       true, null, 'BASE', bl.fila
from staging.bl
cross join lateral (values
  ('5001', bl.d_5001, bl.i_5001), ('1028', bl.d_1028, bl.i_1028),
  ('5003', bl.d_5003, bl.i_5003), ('5029', bl.d_5029, bl.i_5029),
  ('2111', bl.d_2111, bl.i_2111), ('2110', bl.d_2110, bl.i_2110),
  ('2129', bl.d_2129, bl.i_2129), ('2130', bl.d_2130, bl.i_2130)) x(destino, salida, llegada)
join public.dim_ubicacion ud on ud.codigo = x.destino
join public.dim_ruta r on r.origen_ubicacion_id = bl.terminal_ubic_id and r.destino_ubicacion_id = ud.id
where coalesce(x.salida, 0) <> 0 or coalesce(x.llegada, 0) <> 0;

-- 4b. Almacén tercero -> planta (reparto proporcional salida x llegada)
with s as (
  select bl.lote_id, bl.periodo, bl.fila, k.almacen, k.tm
  from staging.bl cross join lateral (values ('2111', bl.s_2111), ('2110', bl.s_2110), ('2129', bl.s_2129), ('2130', bl.s_2130)) k(almacen, tm)
  where coalesce(k.tm, 0) > 0
), a as (
  select bl.lote_id, j.planta, j.tm
  from staging.bl cross join lateral (values ('5001', bl.a_5001), ('1028', bl.a_1028), ('5003', bl.a_5003), ('5029', bl.a_5029)) j(planta, tm)
  where coalesce(j.tm, 0) > 0
), st as (select lote_id, sum(tm) as total from s group by lote_id),
   at as (select lote_id, sum(tm) as total from a group by lote_id)
insert into public.fact_viaje_camion (lote_id, ruta_id, periodo, peso_salida_kg, peso_llegada_kg,
                                      es_agregado, n_viajes, fuente, fuente_fila)
select s.lote_id, r.id, s.periodo,
       round(s.tm * a.tm / at.total * 1000, 1),
       round(a.tm * s.tm / st.total * 1000, 1),
       true, null, 'BASE', s.fila
from s
join st on st.lote_id = s.lote_id
join a  on a.lote_id = s.lote_id
join at on at.lote_id = s.lote_id
join public.dim_ubicacion uo on uo.codigo = s.almacen
join public.dim_ubicacion ud on ud.codigo = a.planta
join public.dim_ruta r on r.origen_ubicacion_id = uo.id and r.destino_ubicacion_id = ud.id;

-- 4c. Plan de distribución
insert into public.fact_plan_distribucion (lote_id, destino_ubicacion_id, version, tm_planificadas)
select bl.lote_id, u.id, 'PLAN BASE', x.tm
from staging.bl
cross join lateral (values ('5001', bl.plan_5001), ('1028', bl.plan_1028), ('5003', bl.plan_5003), ('5029', bl.plan_5029),
                           ('2111', bl.plan_2111), ('2130', bl.plan_2130), ('2129', bl.plan_2129)) x(destino, tm)
join public.dim_ubicacion u on u.codigo = x.destino
where coalesce(x.tm, 0) > 0;

-- ---------------------------------------------------------------------------
-- 5. Costos
-- ---------------------------------------------------------------------------
drop table if exists staging.lc;
create table staging.lc (
  escenario text, lote_id bigint, escala_id bigint, periodo date, concepto text,
  ubicacion_id bigint, ruta_id bigint, proveedor_id bigint,
  cantidad numeric, unidad text, tarifa numeric, monto numeric, origen text, version text, descripcion text
);

-- 5a. REAL · descarga: por componente si la suma cuadra con BASE (2026), si no tarifa integral x TM (2025)
insert into staging.lc
select 'REAL', bl.lote_id, bl.escala_id, bl.periodo, x.concepto, null, null,
       case when x.concepto = 'DESC_TERMINAL' then (select t.operador_proveedor_id from public.dim_terminal t join public.dim_ubicacion u on u.terminal_id = t.id where u.id = bl.terminal_ubic_id) end,
       bl.x_tm_descargada, 'TM', round(x.monto / nullif(bl.x_tm_descargada, 0), 4), x.monto, 'FACTURA', null, x.nombre
from staging.bl
cross join lateral (values ('DESC_TERMINAL', bl.r_terminal, 'Puerto / terminal'), ('DESC_SURVEYOR', bl.r_surveyor, 'Surveyor'),
                           ('DESC_AGENCIA', bl.r_agencia, 'Agencia marítima'), ('DESC_BALANZA', bl.r_balanza, 'Balanza')) x(concepto, monto, nombre)
where abs(coalesce(bl.r_terminal,0)+coalesce(bl.r_surveyor,0)+coalesce(bl.r_agencia,0)+coalesce(bl.r_balanza,0) - coalesce(bl.r_descarga,0)) < 1
  and coalesce(bl.r_descarga, 0) > 0;

insert into staging.lc
select 'REAL', bl.lote_id, bl.escala_id, bl.periodo, 'DESC_INTEGRAL', null, null, null,
       bl.x_tm_descargada, 'TM', bl.tarifa_descarga, bl.r_descarga, 'TARIFA_X_CANTIDAD', 'V-EXCEL-2025',
       'Tarifa integral de descarga x TM descargada'
from staging.bl
where coalesce(bl.r_descarga, 0) > 0
  and abs(coalesce(bl.r_terminal,0)+coalesce(bl.r_surveyor,0)+coalesce(bl.r_agencia,0)+coalesce(bl.r_balanza,0) - bl.r_descarga) >= 1;

-- 5b. REAL y PLAN · flete terminal -> destino por ruta = TM x tarifa vigente de la ruta
insert into staging.lc
select e.escenario, bl.lote_id, bl.escala_id, bl.periodo, c.codigo, ud.id, r.id, null,
       e.tm, 'TM', t.valor, round(e.tm * t.valor, 2),
       case e.escenario when 'REAL' then 'TARIFA_X_CANTIDAD' else 'FORMULA_PLAN' end, 'V-EXCEL-2025',
       case e.escenario when 'REAL' then 'TM ingresadas x tarifa de ruta' else 'TM planificadas x tarifa de ruta' end
from staging.bl
cross join lateral (values
  ('REAL','5001',bl.i_5001), ('REAL','1028',bl.i_1028), ('REAL','5003',bl.i_5003), ('REAL','5029',bl.i_5029),
  ('REAL','2111',bl.i_2111), ('REAL','2129',bl.i_2129), ('REAL','2130',bl.i_2130),
  ('PLAN','5001',bl.plan_5001), ('PLAN','1028',bl.plan_1028), ('PLAN','5003',bl.plan_5003), ('PLAN','5029',bl.plan_5029),
  ('PLAN','2111',bl.plan_2111), ('PLAN','2129',bl.plan_2129), ('PLAN','2130',bl.plan_2130)) e(escenario, destino, tm)
join public.dim_ubicacion ud on ud.codigo = e.destino
join public.dim_ruta r on r.origen_ubicacion_id = bl.terminal_ubic_id and r.destino_ubicacion_id = ud.id
join public.tarifa t on t.ruta_id = r.id and t.version_id = 'V-EXCEL-2025'
join public.dim_concepto_costo c on c.id = t.concepto_id
where coalesce(e.tm, 0) > 0;

-- 5c. Líneas que BASE solo trae como total (sin apertura por ruta/almacén)
--     El almacén se asigna si el lote pasó por un único AT.
insert into staging.lc
select x.escenario, bl.lote_id, bl.escala_id, bl.periodo, x.concepto,
       (select u.id from public.dim_ubicacion u
         where u.codigo = (select max(k.cod) from (values ('2111', bl.i_2111), ('2110', bl.i_2110), ('2129', bl.i_2129), ('2130', bl.i_2130)) k(cod, tm) where coalesce(k.tm,0) > 0)
           and (select count(*) from (values (bl.i_2111), (bl.i_2110), (bl.i_2129), (bl.i_2130)) k(tm) where coalesce(k.tm,0) > 0) = 1
           and x.concepto like any (array['ALM_%','FLETE_ALM_PAB'])),
       null, null, null, null, null, x.monto, x.origen, null, x.descripcion
from staging.bl
cross join lateral (values
  ('REAL','FLETE_ALM_PAB', bl.r_alm_pab,     'FACTURA', 'Facturas de transporte AT -> PAB (total según BASE)'),
  ('REAL','ALM_ALMACENAJE', bl.r_almacenaje, 'FACTURA', 'Facturas de almacenaje (total según BASE)'),
  ('REAL','ALM_CARGADOR',   bl.r_cargador,   'FACTURA', 'Facturas de cargador frontal (total según BASE)'),
  ('REAL','ALM_HE_SIMPLE',  bl.r_he,         'FACTURA', 'Facturas de horas extras (BASE no separa simples/dobles)'),
  ('PLAN','DESC_TERMINAL',  bl.pl_terminal,  'FORMULA_PLAN', 'Plan: puerto / terminal'),
  ('PLAN','DESC_SURVEYOR',  bl.pl_surveyor,  'FORMULA_PLAN', 'Plan: surveyor'),
  ('PLAN','DESC_AGENCIA',   bl.pl_agencia,   'FORMULA_PLAN', 'Plan: agencia marítima'),
  ('PLAN','DESC_BALANZA',   bl.pl_balanza,   'FORMULA_PLAN', 'Plan: balanza'),
  ('PLAN','FLETE_ALM_PAB',  bl.pl_alm_pab,   'FORMULA_PLAN', 'Plan: flete AT -> PAB'),
  ('PLAN','ALM_ALMACENAJE', bl.pl_almacenaje,'FORMULA_PLAN', 'Plan: almacenaje'),
  ('PLAN','ALM_CARGADOR',   bl.pl_cargador,  'FORMULA_PLAN', 'Plan: cargador frontal'),
  ('PLAN','ALM_HE_SIMPLE',  bl.pl_he,        'FORMULA_PLAN', 'Plan: horas extras')) x(escenario, concepto, monto, origen, descripcion)
where coalesce(x.monto, 0) <> 0;

-- 5d. PRESUPUESTO: abierto 53/28/19 cuando BASE lo trae así; si no, global
insert into staging.lc
select 'PRESUPUESTO', bl.lote_id, bl.escala_id, bl.periodo, x.concepto, null, null, null,
       bl.tm_manifestadas, 'TM', round(x.monto / bl.tm_manifestadas, 4), x.monto, 'FORMULA_PLAN', null, x.descripcion
from staging.bl
cross join lateral (
  select * from (values ('PPTO_DESCARGA', bl.pp_descarga, 'Presupuesto descarga'),
                        ('PPTO_TRANSPORTE', bl.pp_transporte, 'Presupuesto transporte'),
                        ('PPTO_ALMACEN', bl.pp_almacen, 'Presupuesto almacenamiento')) v(concepto, monto, descripcion)
  where bl.pp_transporte is not null
  union all
  select 'PPTO_GLOBAL', bl.pp_total, 'Presupuesto global (BASE no lo abre por categoría)'
  where bl.pp_transporte is null
) x
where coalesce(x.monto, 0) <> 0;

-- 5e. Conciliación: por lote, escenario y categoría, el modelo debe sumar lo mismo que BASE
with objetivo as (
  select bl.lote_id, bl.escala_id, bl.periodo, o.escenario, o.categoria, coalesce(o.monto, 0) as monto
  from staging.bl cross join lateral (values
    ('REAL','DESCARGA',       bl.r_descarga),
    ('REAL','TRANSPORTE',     coalesce(bl.r_pto_pab,0) + coalesce(bl.r_pto_alm,0) + coalesce(bl.r_alm_pab,0)),
    ('REAL','ALMACENAMIENTO', bl.r_almacen_total),
    ('PLAN','DESCARGA',       coalesce(bl.pl_terminal,0) + coalesce(bl.pl_surveyor,0) + coalesce(bl.pl_agencia,0) + coalesce(bl.pl_balanza,0)),
    ('PLAN','TRANSPORTE',     coalesce(bl.pl_pto_pab,0) + coalesce(bl.pl_pto_alm,0) + coalesce(bl.pl_alm_pab,0)),
    ('PLAN','ALMACENAMIENTO', coalesce(bl.pl_almacenaje,0) + coalesce(bl.pl_cargador,0) + coalesce(bl.pl_he,0))) o(escenario, categoria, monto)
), cargado as (
  select lc.lote_id, lc.escenario, c.categoria, sum(lc.monto) as monto
  from staging.lc join public.dim_concepto_costo c on c.codigo = lc.concepto
  group by 1, 2, 3
)
insert into staging.lc
select o.escenario, o.lote_id, o.escala_id, o.periodo,
       case o.categoria when 'DESCARGA' then 'AJ_DESCARGA' when 'TRANSPORTE' then 'AJ_TRANSPORTE' else 'AJ_ALMACEN' end,
       null, null, null, null, null, null, round(o.monto - coalesce(k.monto, 0), 2), 'ESTIMADO', null,
       'Diferencia entre el total de BASE y el detalle reconstruido'
from objetivo o
left join cargado k on k.lote_id = o.lote_id and k.escenario = o.escenario and k.categoria = o.categoria
where abs(o.monto - coalesce(k.monto, 0)) >= 0.5;

insert into public.fact_costo (escenario, escala_id, lote_id, concepto_id, proveedor_id, ubicacion_id, ruta_id, periodo,
                               cantidad, unidad, tarifa_unitaria, moneda, monto, tipo_cambio, tarifa_version_id,
                               origen_dato, descripcion, fuente)
select lc.escenario, lc.escala_id, lc.lote_id, c.id, lc.proveedor_id, lc.ubicacion_id, lc.ruta_id, lc.periodo,
       lc.cantidad, lc.unidad, lc.tarifa, 'PEN', round(lc.monto, 2), 1, lc.version, lc.origen, lc.descripcion, 'BASE'
from staging.lc join public.dim_concepto_costo c on c.codigo = lc.concepto
where round(lc.monto, 2) <> 0;

-- ---------------------------------------------------------------------------
-- 6. Penalidades y recuperos registrados en BASE
-- ---------------------------------------------------------------------------
insert into public.fact_reclamo_merma (lote_id, etapa, tm_reclamadas, estado, documento)
select bl.lote_id, x.etapa, round(x.kg / 1000.0, 3), 'ABIERTO', x.doc
from staging.bl cross join lateral (values
  ('TRANSPORTE',       bl.pen_pto_pab_kg, 'BASE: penalidad transporte puerto -> PAB/AT (kg en contra fuera de tolerancia)'),
  ('TRASLADO_ALMACEN', bl.pen_at_pab_kg,  'BASE: penalidad traslado AT -> PAB (kg en contra fuera de tolerancia)')) x(etapa, kg, doc)
where coalesce(x.kg, 0) <> 0;

insert into public.fact_reclamo_merma (lote_id, etapa, tm_reclamadas, moneda, monto_recuperado, estado, documento)
select bl.lote_id, 'TRAVESIA', 0, 'USD', bl.recupero_merma, 'RECUPERADO', 'BASE: recuperado/descontado merma de travesía'
from staging.bl where coalesce(bl.recupero_merma, 0) <> 0;

-- tablas de trabajo: se borran al final (staging.base se conserva para validar_base.sql)
drop table staging.lc;
drop table staging.bl;
drop table staging.b;

commit;
