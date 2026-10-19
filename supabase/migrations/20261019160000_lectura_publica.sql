-- ============================================================================
-- Lectura pública (sin login) de la app.
-- Cualquiera con el link puede VER paneles, naves, costos, tarifas e
-- historial de simulaciones. Escribir sigue requiriendo sesión: no se crea
-- ninguna política de INSERT/UPDATE/DELETE para el rol anon.
-- profiles (nombres y roles de usuarios) NO se abre.
-- Para revertir: drop policy "<tabla>_select_anon" en cada tabla.
-- ============================================================================
do $$
declare t text;
begin
  foreach t in array array[
    -- app original
    'plantas','transportistas','productos','tarifa_versiones','tarifa_flete','tarifa_descarga',
    'tarifa_almacenamiento','naves_historico','simulaciones',
    -- modelo dimensional (las vistas v_* son security_invoker: leen estas tablas)
    'dim_fecha','dim_pais','dim_puerto','dim_proveedor','dim_proveedor_alias','dim_terminal',
    'dim_ubicacion','dim_ubicacion_alias','dim_ruta','dim_producto','dim_material','dim_tolerancia_merma',
    'dim_buque','dim_escala','dim_lote','dim_concepto_costo','dim_centro_costo','dim_evento_sof',
    'fact_escala','laytime_condicion','fact_sof_evento','fact_laytime_liquidacion','fact_descarga_diaria',
    'fact_plan_distribucion','fact_viaje_camion','fact_movimiento_almacen','fact_inventario_almacen',
    'fact_reclamo_merma','fact_costo','fact_presupuesto_mensual','tarifa']
  loop
    if to_regclass('public.' || t) is null then
      raise notice 'Tabla public.% no existe; se omite', t;
      continue;
    end if;
    execute format('grant select on public.%I to anon', t);
    execute format('drop policy if exists %I on public.%I', t || '_select_anon', t);
    execute format('create policy %I on public.%I for select to anon using (true)', t || '_select_anon', t);
  end loop;
end $$;

grant select on public.v_lote_balance_masa, public.v_lote_merma_etapa, public.v_lote_costo,
  public.v_penalidad_transportista, public.v_almacen_permanencia, public.v_laytime_escala,
  public.v_lote_flujo, public.v_lote_distribucion to anon;
