-- Soporta simulaciones que reparten la carga de una nave entre varias plantas
-- (+ opcionalmente gastos de puerto/almacén fuera de planta), en vez de una
-- sola planta_id por simulación. planta_id se conserva para el caso de una
-- sola planta; planta_nombre y distribucion cubren el reparto multi-destino.

alter table public.simulaciones
  add column if not exists planta_nombre text,
  add column if not exists distribucion jsonb;

comment on column public.simulaciones.planta_nombre is
  'Resumen en texto de las plantas y toneladas repartidas (ej. "Chancay (12,000 TN), Lurín (16,000 TN)"). Reemplaza a plantas.nombre cuando la simulación reparte carga entre más de una planta.';
comment on column public.simulaciones.distribucion is
  'Detalle completo del reparto multi-destino del Simulador: TN por planta, gastos adicionales opcionales de puerto/almacén (Transporte Puerto/Ransa, Almacenamiento AT/PT) y el resultado calculado para Chancay y Callao. Null en simulaciones antiguas de una sola planta.';
