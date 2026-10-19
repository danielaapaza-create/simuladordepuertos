-- ============================================================================
-- Deshace el modelo dimensional (migraciones 20261019120000 y 20261019150000)
-- y la carga de BASE. Útil si una ejecución quedó a medias.
-- NO toca las tablas originales de la app (plantas, transportistas, productos,
-- tarifa_flete/descarga/almacenamiento, naves_historico, simulaciones, profiles).
-- ============================================================================
drop view if exists public.v_lote_distribucion, public.v_lote_flujo, public.v_almacen_permanencia,
  public.v_penalidad_transportista, public.v_lote_costo, public.v_lote_merma_etapa,
  public.v_lote_balance_masa, public.v_laytime_escala cascade;
drop function if exists public.fn_laytime_horas_usadas(bigint);
drop table if exists
  public.fact_presupuesto_mensual, public.fact_costo, public.fact_reclamo_merma, public.fact_inventario_almacen,
  public.fact_movimiento_almacen, public.fact_viaje_camion, public.fact_plan_distribucion,
  public.fact_descarga_diaria, public.fact_laytime_liquidacion, public.fact_sof_evento,
  public.laytime_condicion, public.fact_escala, public.tarifa,
  public.dim_evento_sof, public.dim_centro_costo, public.dim_concepto_costo,
  public.dim_lote, public.dim_escala, public.dim_buque, public.dim_tolerancia_merma,
  public.dim_material, public.dim_producto, public.dim_ruta, public.dim_ubicacion_alias,
  public.dim_ubicacion, public.dim_terminal, public.dim_proveedor_alias, public.dim_proveedor,
  public.dim_puerto, public.dim_pais, public.dim_fecha cascade;
drop function if exists public.fn_dim_ruta_tramo();
drop function if exists public.fn_pascua(int);
delete from public.tarifa_versiones where id = 'V-EXCEL-2025';
drop schema if exists staging cascade;
