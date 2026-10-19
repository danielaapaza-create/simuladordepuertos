-- ============================================================================
-- Paso 3: conciliación modelo vs. hoja BASE (staging.base).
-- Cada control debe devolver 0 lotes con diferencia. Tolerancia: 0.01 TM en
-- cantidades y S/ 1 en montos (redondeos de Excel).
-- ============================================================================
with m as (
  select bm.*, s.fila, s.x_tm_descargada, s.x_tm_ingresada, s.x_merma_total, s.x_costo_real, s.x_costo_plan, s.pp_total,
         s.merma_almacenamiento as x_merma_alm
  from public.v_lote_balance_masa bm
  join public.dim_lote l on l.id = bm.lote_id
  join staging.base s on s.clave = l.clave_fuente
                     and make_date(s.anio, left(s.mes_txt, 2)::int, 1) = bm.periodo_operacion
), c as (
  select lote_id,
         sum(monto_pen) filter (where escenario = 'REAL')        as real,
         sum(monto_pen) filter (where escenario = 'PLAN')        as plan,
         sum(monto_pen) filter (where escenario = 'PRESUPUESTO') as ppto
  from public.v_lote_costo group by lote_id
), controles as (
  select 'TM descargadas'          as control, count(*) filter (where abs(m.tm_descargada - m.x_tm_descargada) > 0.01) as con_diferencia, count(*) as lotes from m
  union all select 'TM ingresadas (planta directo + AT)', count(*) filter (where abs(m.tm_ingreso_planta_directo + m.tm_ingreso_almacen - m.x_tm_ingresada) > 0.01), count(*) from m
  union all select 'Merma total del proceso', count(*) filter (where abs(m.merma_total_tm - m.x_merma_total) > 0.01), count(*) from m
  union all select 'Costo total REAL',        count(*) filter (where abs(coalesce(c.real,0) - coalesce(m.x_costo_real,0)) > 1), count(*) from m left join c using (lote_id)
  union all select 'Costo total PLAN',        count(*) filter (where abs(coalesce(c.plan,0) - coalesce(m.x_costo_plan,0)) > 1), count(*) from m left join c using (lote_id)
  union all select 'Costo total PRESUPUESTO', count(*) filter (where abs(coalesce(c.ppto,0) - coalesce(m.pp_total,0)) > 1), count(*) from m left join c using (lote_id)
)
select * from controles;

-- Detalle de los lotes que no cuadran (vacío = todo concilia)
select bm.escala, bm.material, s.fila as fila_excel,
       round(bm.tm_descargada - s.x_tm_descargada, 3)                                  as dif_tm_descargada,
       round(bm.tm_ingreso_planta_directo + bm.tm_ingreso_almacen - s.x_tm_ingresada, 3) as dif_tm_ingresada,
       round(bm.merma_total_tm - s.x_merma_total, 3)                                    as dif_merma_total
from public.v_lote_balance_masa bm
join public.dim_lote l on l.id = bm.lote_id
join staging.base s on s.clave = l.clave_fuente and make_date(s.anio, left(s.mes_txt, 2)::int, 1) = bm.periodo_operacion
where abs(bm.tm_descargada - s.x_tm_descargada) > 0.01
   or abs(bm.tm_ingreso_planta_directo + bm.tm_ingreso_almacen - s.x_tm_ingresada) > 0.01
   or abs(bm.merma_total_tm - s.x_merma_total) > 0.01;

-- Líneas de ajuste de conciliación (lo que el modelo no pudo abrir a detalle)
select e.codigo as escala, f.escenario, cc.codigo as concepto, f.monto_pen
from public.fact_costo f
join public.dim_concepto_costo cc on cc.id = f.concepto_id and cc.subcategoria = 'AJUSTE'
join public.dim_escala e on e.id = f.escala_id
order by abs(f.monto_pen) desc;
