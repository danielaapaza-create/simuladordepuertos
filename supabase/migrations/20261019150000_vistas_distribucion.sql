-- Vistas de distribución por nave (usadas por la pestaña Naves de la app).
-- Requiere 20261019120000_modelo_dimensional.sql.

-- Flujo físico por lote: cada tramo origen -> destino con TM salida / llegada.
create or replace view public.v_lote_flujo with (security_invoker = true) as
select l.id as lote_id, e.codigo as escala, b.nombre as buque, pu.nombre as puerto, e.periodo_operacion,
       pr.codigo as producto, r.tramo,
       uo.codigo as origen_codigo, uo.nombre as origen, ud.codigo as destino_codigo, ud.nombre as destino, ud.tipo as tipo_destino,
       round(sum(vc.peso_salida_kg)  / 1000.0, 3) as tm_salida,
       round(sum(vc.peso_llegada_kg) / 1000.0, 3) as tm_llegada,
       round((sum(vc.peso_llegada_kg) - sum(vc.peso_salida_kg)) / 1000.0, 3) as diferencia_tm,
       sum(vc.n_viajes) as viajes,
       bool_or(vc.es_agregado) as es_agregado
from public.fact_viaje_camion vc
join public.dim_lote l on l.id = vc.lote_id
join public.dim_escala e on e.id = l.escala_id
join public.dim_buque b on b.id = e.buque_id
join public.dim_puerto pu on pu.id = e.puerto_id
join public.dim_material m on m.id = l.material_id
join public.dim_producto pr on pr.id = m.producto_id
join public.dim_ruta r on r.id = vc.ruta_id
join public.dim_ubicacion uo on uo.id = r.origen_ubicacion_id
join public.dim_ubicacion ud on ud.id = r.destino_ubicacion_id
group by l.id, e.codigo, b.nombre, pu.nombre, e.periodo_operacion, pr.codigo, r.tramo,
         uo.codigo, uo.nombre, ud.codigo, ud.nombre, ud.tipo;

-- Distribución por lote y destino: plan vs. real, cuánto llegó directo del
-- puerto, cuánto pasó por un almacén tercero y cuánto sigue en stock en AT.
create or replace view public.v_lote_distribucion with (security_invoker = true) as
with f as (
  select lote_id, destino_codigo as nodo, tipo_destino as tipo,
         sum(tm_llegada) filter (where tramo in ('PUERTO_PLANTA','PUERTO_ALMACEN')) as tm_desde_puerto,
         sum(tm_llegada) filter (where tramo = 'ALMACEN_PLANTA')                    as tm_desde_almacen,
         0::numeric as tm_salida_almacen
  from public.v_lote_flujo group by 1, 2, 3
  union all
  select lote_id, origen_codigo, 'ALMACEN_TERCERO', 0, 0, sum(tm_salida)
  from public.v_lote_flujo where tramo = 'ALMACEN_PLANTA' group by 1, 2
), n as (
  select lote_id, nodo, max(tipo) as tipo,
         coalesce(sum(tm_desde_puerto), 0) as tm_desde_puerto,
         coalesce(sum(tm_desde_almacen), 0) as tm_desde_almacen,
         coalesce(sum(tm_salida_almacen), 0) as tm_salida_almacen
  from f group by 1, 2
), p as (
  select pd.lote_id, u.codigo as nodo, u.tipo, sum(pd.tm_planificadas) as tm_plan
  from public.fact_plan_distribucion pd join public.dim_ubicacion u on u.id = pd.destino_ubicacion_id
  group by 1, 2, 3
), x as (
  select coalesce(n.lote_id, p.lote_id) as lote_id, coalesce(n.nodo, p.nodo) as nodo, coalesce(n.tipo, p.tipo) as tipo,
         coalesce(p.tm_plan, 0) as tm_plan,
         coalesce(n.tm_desde_puerto, 0) as tm_desde_puerto,
         coalesce(n.tm_desde_almacen, 0) as tm_desde_almacen,
         coalesce(n.tm_salida_almacen, 0) as tm_salida_almacen
  from n full join p on p.lote_id = n.lote_id and p.nodo = n.nodo
)
select x.lote_id, e.codigo as escala, b.nombre as buque, pu.nombre as puerto, e.periodo_operacion, pr.codigo as producto,
       u.codigo as destino_codigo, u.nombre as destino, x.tipo as tipo_destino,
       x.tm_plan,
       x.tm_desde_puerto                                       as tm_recibida_desde_puerto,
       x.tm_desde_almacen                                      as tm_recibida_desde_almacen,
       case when x.tipo = 'PLANTA' then x.tm_desde_puerto + x.tm_desde_almacen end as tm_total_planta,
       case when x.tipo = 'ALMACEN_TERCERO' then x.tm_salida_almacen end            as tm_despachada_a_planta,
       case when x.tipo = 'ALMACEN_TERCERO' then
            case when l.almacen_cerrado then 0 else x.tm_desde_puerto - x.tm_salida_almacen end end as tm_stock_almacen,
       round(case when x.tipo = 'PLANTA' then x.tm_desde_puerto + x.tm_desde_almacen else x.tm_desde_puerto end
             / l.tm_manifestadas, 4)                          as pct_del_lote,
       case when x.tipo = 'PLANTA' then x.tm_desde_puerto + x.tm_desde_almacen else x.tm_desde_puerto end
             - x.tm_plan                                      as desvio_vs_plan_tm
from x
join public.dim_lote l on l.id = x.lote_id
join public.dim_escala e on e.id = l.escala_id
join public.dim_buque b on b.id = e.buque_id
join public.dim_puerto pu on pu.id = e.puerto_id
join public.dim_material m on m.id = l.material_id
join public.dim_producto pr on pr.id = m.producto_id
join public.dim_ubicacion u on u.codigo = x.nodo;
