-- ============================================================================
-- Muelle · MODELO DIMENSIONAL (esquema estrella) del ciclo de importación de
-- macroinsumos: nave -> escala en puerto -> descarga -> laytime (despatch /
-- demurrage) -> distribución en camión -> almacén tercero (AT) -> planta (PAB)
-- -> mermas -> costos (real / plan / presupuesto).
--
-- Convenciones
--   dim_*   dimensiones (quién, qué, dónde, cuándo). Clave surrogate bigint.
--   fact_*  tablas de hechos, cada una con su GRANO declarado en el comentario.
--   v_*     vistas analíticas (security_invoker: respetan RLS del usuario).
--   Cantidades de carga en TM (numeric 14,3); pesos de balanza en KG.
--   Montos: se guarda moneda + monto original + tipo de cambio, y monto_pen
--   se calcula (columna generada). Nunca se guardan montos ya convertidos sin
--   su origen.
--   Fechas: timestamptz para hitos operativos (SOF, balanza), date para
--   devengo/contable, y fecha_id (yyyymmdd) -> dim_fecha para agregar.
--
-- No modifica las tablas existentes de la app (tarifa_*, naves_historico,
-- simulaciones). El tarifario nuevo reutiliza public.tarifa_versiones para
-- que el gobierno de versiones sea uno solo.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. DIMENSIÓN FECHA (calendario Perú, con feriados para laytime SHEX)
-- ---------------------------------------------------------------------------
create or replace function public.fn_pascua(p_anio int)
returns date
language plpgsql immutable
as $$
-- Algoritmo anónimo gregoriano (Meeus/Jones/Butcher).
declare a int; b int; c int; d int; e int; f int; g int; h int; i int; k int; l int; m int; mes int; dia int;
begin
  a := p_anio % 19; b := p_anio / 100; c := p_anio % 100;
  d := b / 4; e := b % 4; f := (b + 8) / 25; g := (b - f + 1) / 3;
  h := (19*a + b - d - g + 15) % 30; i := c / 4; k := c % 4;
  l := (32 + 2*e + 2*i - h - k) % 7; m := (a + 11*h + 22*l) / 451;
  mes := (h + l - 7*m + 114) / 31; dia := ((h + l - 7*m + 114) % 31) + 1;
  return make_date(p_anio, mes, dia);
end;
$$;

create table public.dim_fecha (
  fecha_id        int primary key,                 -- yyyymmdd
  fecha           date not null unique,
  anio            smallint not null,
  trimestre       smallint not null,
  mes             smallint not null,
  mes_nombre      text not null,
  anio_mes        text not null,                   -- 'YYYY-MM'
  periodo         date not null,                   -- primer día del mes
  semana_iso      smallint not null,
  dia_semana_iso  smallint not null,               -- 1=lunes ... 7=domingo
  dia_nombre      text not null,
  es_fin_semana   boolean not null,
  es_feriado      boolean not null default false,
  feriado_nombre  text
);
comment on table public.dim_fecha is 'Calendario 2019-2030. es_feriado = feriados nacionales del Perú (fijos + Jueves/Viernes Santo). Se usa para agregar hechos y para excluir domingos/feriados en el cálculo de laytime SHEX/SSHEX.';

insert into public.dim_fecha (fecha_id, fecha, anio, trimestre, mes, mes_nombre, anio_mes, periodo,
                              semana_iso, dia_semana_iso, dia_nombre, es_fin_semana)
select to_char(d,'YYYYMMDD')::int, d, extract(year from d), extract(quarter from d), extract(month from d),
       (array['ENERO','FEBRERO','MARZO','ABRIL','MAYO','JUNIO','JULIO','AGOSTO','SETIEMBRE','OCTUBRE','NOVIEMBRE','DICIEMBRE'])[extract(month from d)::int],
       to_char(d,'YYYY-MM'), date_trunc('month', d)::date,
       extract(week from d), extract(isodow from d),
       (array['LUNES','MARTES','MIÉRCOLES','JUEVES','VIERNES','SÁBADO','DOMINGO'])[extract(isodow from d)::int],
       extract(isodow from d) in (6,7)
from generate_series('2019-01-01'::date, '2030-12-31'::date, interval '1 day') g(d);

-- Feriados fijos (Ley peruana vigente) + móviles de Semana Santa.
update public.dim_fecha f set es_feriado = true, feriado_nombre = x.nombre
from (values ('01-01','Año Nuevo'),('05-01','Día del Trabajo'),('06-07','Batalla de Arica y Día de la Bandera'),
             ('06-29','San Pedro y San Pablo'),('07-23','Día de la Fuerza Aérea'),('07-28','Fiestas Patrias'),
             ('07-29','Fiestas Patrias'),('08-06','Batalla de Junín'),('08-30','Santa Rosa de Lima'),
             ('10-08','Combate de Angamos'),('11-01','Todos los Santos'),('12-08','Inmaculada Concepción'),
             ('12-09','Batalla de Ayacucho'),('12-25','Navidad')) x(mmdd, nombre)
where to_char(f.fecha,'MM-DD') = x.mmdd;

update public.dim_fecha f set es_feriado = true, feriado_nombre = s.nombre
from (select public.fn_pascua(y) - 3 as fecha, 'Jueves Santo' as nombre from generate_series(2019,2030) y
      union all
      select public.fn_pascua(y) - 2, 'Viernes Santo' from generate_series(2019,2030) y) s
where f.fecha = s.fecha;

-- ---------------------------------------------------------------------------
-- 1. DIMENSIONES GEOGRÁFICAS Y DE RED LOGÍSTICA
-- ---------------------------------------------------------------------------
create table public.dim_pais (
  id      bigint generated always as identity primary key,
  iso2    char(2) not null unique,
  nombre  text not null unique
);

create table public.dim_puerto (
  id       bigint generated always as identity primary key,
  locode   text not null unique,                  -- UN/LOCODE: PECLL, PECHY
  nombre   text not null unique,                  -- 'CALLAO', 'CHANCAY'
  pais_id  bigint not null references public.dim_pais(id)
);

-- Empresas con las que se opera: una misma empresa puede tener varios roles
-- (p.ej. RANSA = almacén tercero + transporte AT->PAB).
create table public.dim_proveedor (
  id            bigint generated always as identity primary key,
  razon_social  text not null unique,
  nombre_corto  text,
  ruc           text unique,
  roles         text[] not null default '{}',
  es_persona_natural boolean not null default false,
  activo        boolean not null default true,
  constraint dim_proveedor_roles_chk check (roles <@ array[
    'TERMINAL','AGENCIA_MARITIMA','ARMADOR','FLETADOR','SURVEYOR','TRANSPORTISTA',
    'ALMACEN','BALANZA','ASEGURADORA','PROVEEDOR_MERCADERIA','OTRO']::text[])
);
comment on table public.dim_proveedor is 'Terceros del proceso: terminal portuario, agencia marítima, armador/fletador (contraparte de laytime), surveyor, transportistas, almacenes terceros, etc.';

-- Los nombres llegan escritos de muchas formas ("TOSA", "TOSAE.I.R.L.", ...).
-- Toda carga resuelve proveedor_id a través de esta tabla.
create table public.dim_proveedor_alias (
  alias         text primary key,                 -- texto tal cual aparece en la fuente (upper/trim)
  proveedor_id  bigint not null references public.dim_proveedor(id) on delete cascade
);

create table public.dim_terminal (
  id                     bigint generated always as identity primary key,
  codigo                 text not null unique,    -- 'APM', 'COSCO'
  nombre                 text not null,
  puerto_id              bigint not null references public.dim_puerto(id),
  operador_proveedor_id  bigint references public.dim_proveedor(id)
);

-- Nodo logístico donde la carga puede estar físicamente: terminal portuario,
-- almacén tercero (AT) o planta de alimento balanceado (PAB).
create table public.dim_ubicacion (
  id                     bigint generated always as identity primary key,
  codigo                 text not null unique,    -- centro/almacén SAP ('5003','2111') o 'TER-APM'
  nombre                 text not null,
  tipo                   text not null check (tipo in ('TERMINAL','ALMACEN_TERCERO','PLANTA')),
  centro_sap             text,
  almacen_sap            text,
  terminal_id            bigint references public.dim_terminal(id),
  operador_proveedor_id  bigint references public.dim_proveedor(id),
  ciudad                 text,
  capacidad_tm           numeric(14,3),
  bajo_techo             boolean,
  activo                 boolean not null default true,
  constraint dim_ubicacion_terminal_chk check ((tipo = 'TERMINAL') = (terminal_id is not null))
);
comment on table public.dim_ubicacion is 'Nodos de la red: TERMINAL (APM Callao, COSCO Chancay), ALMACEN_TERCERO (Ransa Argentina 2111, Ransa Oquendo 2130, DIEF 2129, Bulkbox/Ransa Primax 2110, DEPSA) y PLANTA (PAB Lurín 5001, Lurín 2 1028, Chancay 5003, GH Chancay 5029).';

create table public.dim_ubicacion_alias (
  alias         text primary key,                 -- 'AABB CHANCAY - 5003', '5003 - CHANCAY', 'R. ARGENTINA'
  ubicacion_id  bigint not null references public.dim_ubicacion(id) on delete cascade
);

-- Tramo origen -> destino. El tipo de tramo se deriva de los tipos de nodo.
create table public.dim_ruta (
  id                    bigint generated always as identity primary key,
  origen_ubicacion_id   bigint not null references public.dim_ubicacion(id),
  destino_ubicacion_id  bigint not null references public.dim_ubicacion(id),
  tramo                 text not null check (tramo in ('PUERTO_PLANTA','PUERTO_ALMACEN','ALMACEN_PLANTA',
                                                       'ALMACEN_ALMACEN','PLANTA_PLANTA','PLANTA_ALMACEN')),
  distancia_km          numeric(8,1),
  unique (origen_ubicacion_id, destino_ubicacion_id),
  check (origen_ubicacion_id <> destino_ubicacion_id)
);

create or replace function public.fn_dim_ruta_tramo()
returns trigger language plpgsql as $$
declare o text; d text;
begin
  select tipo into o from public.dim_ubicacion where id = new.origen_ubicacion_id;
  select tipo into d from public.dim_ubicacion where id = new.destino_ubicacion_id;
  new.tramo := case
    when o = 'TERMINAL'        and d = 'PLANTA'          then 'PUERTO_PLANTA'
    when o = 'TERMINAL'        and d = 'ALMACEN_TERCERO' then 'PUERTO_ALMACEN'
    when o = 'ALMACEN_TERCERO' and d = 'PLANTA'          then 'ALMACEN_PLANTA'
    when o = 'ALMACEN_TERCERO' and d = 'ALMACEN_TERCERO' then 'ALMACEN_ALMACEN'
    when o = 'PLANTA'          and d = 'PLANTA'          then 'PLANTA_PLANTA'
    when o = 'PLANTA'          and d = 'ALMACEN_TERCERO' then 'PLANTA_ALMACEN'
  end;
  if new.tramo is null then
    raise exception 'Ruta no válida: % -> %', o, d;
  end if;
  return new;
end;
$$;
create trigger dim_ruta_tramo before insert or update on public.dim_ruta
  for each row execute function public.fn_dim_ruta_tramo();

-- ---------------------------------------------------------------------------
-- 2. DIMENSIONES DE PRODUCTO
-- ---------------------------------------------------------------------------
create table public.dim_producto (
  id      bigint generated always as identity primary key,
  codigo  text not null unique,                   -- 'MAIZ','TORTA','FREJOL'
  nombre  text not null
);

create table public.dim_material (
  id              bigint generated always as identity primary key,
  descripcion     text not null unique,           -- 'MAIZ ARGENTINO' (texto material SAP)
  codigo_sap      text unique,
  producto_id     bigint not null references public.dim_producto(id),
  pais_origen_id  bigint references public.dim_pais(id)
);

-- Tolerancias de merma aceptada (Resumen: 0.5 %) por producto y etapa.
create table public.dim_tolerancia_merma (
  id              bigint generated always as identity primary key,
  producto_id     bigint references public.dim_producto(id),   -- null = todos
  etapa           text not null check (etapa in ('TRAVESIA','TRANSPORTE','ALMACENAMIENTO','TRASLADO_ALMACEN','TOTAL')),
  pct_tolerado    numeric(7,5) not null check (pct_tolerado >= 0),
  vigente_desde   date not null,
  unique nulls not distinct (producto_id, etapa, vigente_desde)
);

-- ---------------------------------------------------------------------------
-- 3. DIMENSIONES DEL BUQUE, LA ESCALA Y EL LOTE
-- ---------------------------------------------------------------------------
create table public.dim_buque (
  id                 bigint generated always as identity primary key,
  nombre             text not null,
  imo                text unique,
  tipo_buque         text check (tipo_buque in ('HANDYSIZE','HANDYMAX','SUPRAMAX','ULTRAMAX','PANAMAX','KAMSARMAX','OTRO')),
  dwt                numeric(10,0),
  eslora_m           numeric(6,2),
  bodegas            smallint,
  bandera_pais_id    bigint references public.dim_pais(id),
  anio_construccion  smallint,
  unique nulls not distinct (nombre, imo)
);
comment on table public.dim_buque is 'El buque físico. Un mismo buque puede venir varias veces (p.ej. DIAMOND SKY ene-26 y set-26): cada visita es una dim_escala distinta.';

-- Escala = una visita de un buque a un puerto/terminal. Es la unidad de
-- operación portuaria, de agencia y de laytime.
create table public.dim_escala (
  id                     bigint generated always as identity primary key,
  codigo                 text not null unique,    -- p.ej. 'DIAMOND SKY|2026-01'
  buque_id               bigint not null references public.dim_buque(id),
  puerto_id              bigint not null references public.dim_puerto(id),
  terminal_id            bigint references public.dim_terminal(id),
  agencia_proveedor_id   bigint references public.dim_proveedor(id),
  numero_viaje           text,
  muelle                 text,
  periodo_operacion      date not null,           -- mes de operación (primer día)
  puerto_carga           text,
  estado                 text not null default 'CONCLUIDA'
                           check (estado in ('PROGRAMADA','EN_RADA','EN_OPERACION','CONCLUIDA','ANULADA')),
  observacion            text
);

-- Lote = parcela de carga de una escala para un material (grano de la hoja
-- BASE). Una escala puede traer varios lotes (QUEST: maíz + torta).
create table public.dim_lote (
  id                      bigint generated always as identity primary key,
  escala_id               bigint not null references public.dim_escala(id) on delete cascade,
  material_id             bigint not null references public.dim_material(id),
  codigo_lote_sap         text,                    -- 'IONISL0125'
  clave_fuente            text not null,          -- ID de la hoja BASE = MN & MATERIAL
  bl_numero               text,
  pais_origen_id          bigint references public.dim_pais(id),
  proveedor_mercaderia_id bigint references public.dim_proveedor(id),
  incoterm                text,
  tm_manifestadas         numeric(14,3) not null check (tm_manifestadas > 0),
  precio_cif_usd_tm       numeric(12,4),
  almacen_cerrado         boolean not null default false,  -- true = el saldo en AT ya se trasladó; recién ahí se reconoce la merma de almacenamiento
  fecha_cierre_almacen    date,
  estado                  text not null default 'CONCLUIDO' check (estado in ('EN_PROCESO','CONCLUIDO')),
  unique (escala_id, material_id)
);
create index dim_lote_clave_fuente_idx on public.dim_lote (clave_fuente);

-- ---------------------------------------------------------------------------
-- 4. DIMENSIONES DE COSTO
-- ---------------------------------------------------------------------------
create table public.dim_concepto_costo (
  id            bigint generated always as identity primary key,
  codigo        text not null unique,
  nombre        text not null,
  categoria     text not null check (categoria in ('DESCARGA','TRANSPORTE','ALMACENAMIENTO','LAYTIME','PENALIDAD','MERMA','GLOBAL')),
  subcategoria  text,
  unidad_base   text not null check (unidad_base in ('TM','TM_MES','HORA','DIA','VIAJE','GLOBAL')),
  es_ingreso    boolean not null default false,   -- despatch, penalidad cobrada, recupero de merma
  orden         smallint not null default 100
);

create table public.dim_centro_costo (
  id                  bigint generated always as identity primary key,
  codigo              text not null unique,       -- '1401207'
  nombre              text not null,              -- 'C.C. PAB CHANCAY'
  planta_ubicacion_id bigint references public.dim_ubicacion(id)
);

-- Evento del Statement of Facts y si cuenta para laytime por defecto.
create table public.dim_evento_sof (
  codigo                  text primary key,
  nombre                  text not null,
  fase                    text not null check (fase in ('LLEGADA','ATRAQUE','DESCARGA','PARALIZACION','CIERRE')),
  cuenta_laytime_default  numeric(3,2) not null default 0 check (cuenta_laytime_default between 0 and 1),
  orden                   smallint not null
);

-- Tarifario versionado general (reemplaza la lógica dispersa en
-- 'TARIFARIO DE GASTOS'). Reutiliza tarifa_versiones: inmutable, solo INSERT.
create table public.tarifa (
  id             bigint generated always as identity primary key,
  version_id     text not null references public.tarifa_versiones(id),
  concepto_id    bigint not null references public.dim_concepto_costo(id),
  puerto_id      bigint references public.dim_puerto(id),
  terminal_id    bigint references public.dim_terminal(id),
  ruta_id        bigint references public.dim_ruta(id),
  ubicacion_id   bigint references public.dim_ubicacion(id),
  proveedor_id   bigint references public.dim_proveedor(id),
  producto_id    bigint references public.dim_producto(id),
  unidad         text not null check (unidad in ('TM','TM_MES','HORA','DIA','VIAJE','GLOBAL')),
  moneda         char(3) not null check (moneda in ('PEN','USD')),
  valor          numeric(14,4) not null check (valor >= 0),
  observacion    text,
  unique nulls not distinct (version_id, concepto_id, puerto_id, terminal_id, ruta_id, ubicacion_id, proveedor_id, producto_id)
);
comment on table public.tarifa is 'Una fila = un precio unitario vigente en una versión, para un concepto y su ámbito (puerto, ruta, almacén, proveedor y/o producto; null = aplica a todos).';

-- ---------------------------------------------------------------------------
-- 5. HECHOS PORTUARIOS: ESCALA, SOF, LAYTIME, DESCARGA
-- ---------------------------------------------------------------------------

-- GRANO: 1 fila por escala (snapshot acumulativo: se actualiza a medida que
-- la escala avanza por sus hitos).
create table public.fact_escala (
  escala_id              bigint primary key references public.dim_escala(id) on delete cascade,
  ts_llegada_rada        timestamptz,
  ts_nor_presentado      timestamptz,
  ts_nor_aceptado        timestamptz,
  ts_libre_platica       timestamptz,
  ts_atraque             timestamptz,
  ts_inicio_descarga     timestamptz,
  ts_fin_descarga        timestamptz,
  ts_desatraque          timestamptz,
  ts_zarpe               timestamptz,
  tm_draft_survey_inicial numeric(14,3),
  tm_draft_survey_final   numeric(14,3),
  horas_espera_rada      numeric(10,2) generated always as (round(extract(epoch from (ts_atraque - ts_llegada_rada)) / 3600.0, 2)) stored,
  horas_en_muelle        numeric(10,2) generated always as (round(extract(epoch from (ts_desatraque - ts_atraque)) / 3600.0, 2)) stored,
  horas_descarga_bruta   numeric(10,2) generated always as (round(extract(epoch from (ts_fin_descarga - ts_inicio_descarga)) / 3600.0, 2)) stored,
  fecha_atraque_id       int references public.dim_fecha(fecha_id),
  check (ts_fin_descarga is null or ts_inicio_descarga is null or ts_fin_descarga >= ts_inicio_descarga)
);

-- Condiciones de laytime pactadas en el contrato de fletamento (C/P) para la
-- escala. GRANO: 1 por escala.
create table public.laytime_condicion (
  escala_id                 bigint primary key references public.dim_escala(id) on delete cascade,
  contraparte_proveedor_id  bigint references public.dim_proveedor(id),   -- armador / fletador
  cp_fecha                  date,
  cp_formulario             text,                 -- GENCON, NORGRAIN, ...
  tasa_descarga_tm_dia      numeric(10,2) not null check (tasa_descarga_tm_dia > 0),
  base_calculo              text not null default 'SHINC' check (base_calculo in ('SHINC','SHEX','SSHEX')),
  turn_time_horas           numeric(5,2) not null default 0,
  demurrage_usd_dia         numeric(12,2) not null check (demurrage_usd_dia >= 0),
  despatch_usd_dia          numeric(12,2) not null check (despatch_usd_dia >= 0),  -- usual: 50 % del demurrage
  despatch_sobre_tiempo     text not null default 'LAYTIME_AHORRADO' check (despatch_sobre_tiempo in ('LAYTIME_AHORRADO','TODO_TIEMPO_AHORRADO')),
  reversible                boolean not null default false,
  observacion               text
);

-- GRANO: 1 fila por intervalo/evento del Statement of Facts de una escala
-- (y opcionalmente por bodega). factor_laytime: 1 cuenta todo, 0 no cuenta,
-- 0.5 cuenta la mitad (p.ej. lluvia con cláusula de reparto).
create table public.fact_sof_evento (
  id               bigint generated always as identity primary key,
  escala_id        bigint not null references public.dim_escala(id) on delete cascade,
  evento_codigo    text not null references public.dim_evento_sof(codigo),
  ts_inicio        timestamptz not null,
  ts_fin           timestamptz,
  bodega           smallint,
  factor_laytime   numeric(3,2) check (factor_laytime between 0 and 1),   -- null = usar default del evento
  duracion_horas   numeric(10,2) generated always as (round(extract(epoch from (ts_fin - ts_inicio)) / 3600.0, 2)) stored,
  fuente           text,
  observacion      text,
  check (ts_fin is null or ts_fin >= ts_inicio)
);
create index fact_sof_evento_escala_idx on public.fact_sof_evento (escala_id, ts_inicio);

-- GRANO: 1 fila por versión de liquidación de laytime de una escala (lo
-- calculado vs. lo que finalmente se acuerda/factura con el armador).
create table public.fact_laytime_liquidacion (
  id                      bigint generated always as identity primary key,
  escala_id               bigint not null references public.dim_escala(id) on delete cascade,
  version                 smallint not null default 1,
  fecha_liquidacion       date,
  laytime_permitido_horas numeric(10,2) not null,
  laytime_usado_horas     numeric(10,2) not null,
  horas_ahorradas         numeric(10,2) generated always as (greatest(laytime_permitido_horas - laytime_usado_horas, 0)) stored,
  horas_exceso            numeric(10,2) generated always as (greatest(laytime_usado_horas - laytime_permitido_horas, 0)) stored,
  demurrage_usd           numeric(14,2) not null default 0,
  despatch_usd            numeric(14,2) not null default 0,
  neto_usd                numeric(14,2) generated always as (demurrage_usd - despatch_usd) stored,   -- >0 pagamos, <0 cobramos
  estado                  text not null default 'BORRADOR' check (estado in ('BORRADOR','PRESENTADA','ACORDADA','FACTURADA','ANULADA')),
  documento               text,
  observacion             text,
  unique (escala_id, version)
);

-- GRANO: escala x lote x día x turno x bodega (lo que tenga el reporte diario
-- de la agencia; columnas opcionales en null si no se reporta a ese detalle).
create table public.fact_descarga_diaria (
  id                 bigint generated always as identity primary key,
  escala_id          bigint not null references public.dim_escala(id) on delete cascade,
  lote_id            bigint references public.dim_lote(id) on delete cascade,
  fecha_id           int not null references public.dim_fecha(fecha_id),
  turno              text,
  bodega             smallint,
  tm_descargadas     numeric(14,3) not null check (tm_descargadas >= 0),
  horas_operativas   numeric(6,2),
  horas_paralizadas  numeric(6,2),
  ganchos            smallint,
  camiones_atendidos int,
  unique nulls not distinct (escala_id, lote_id, fecha_id, turno, bodega)
);

-- ---------------------------------------------------------------------------
-- 6. HECHOS DE DISTRIBUCIÓN, ALMACÉN Y MERMA
-- ---------------------------------------------------------------------------

-- GRANO: lote x destino x versión de plan. Lo que se planificó enviar a cada
-- planta / almacén antes de la descarga.
create table public.fact_plan_distribucion (
  id                    bigint generated always as identity primary key,
  lote_id               bigint not null references public.dim_lote(id) on delete cascade,
  destino_ubicacion_id  bigint not null references public.dim_ubicacion(id),
  version               text not null default 'PLAN',
  tm_planificadas       numeric(14,3) not null check (tm_planificadas >= 0),
  unique (lote_id, destino_ubicacion_id, version)
);

-- GRANO: 1 viaje de camión (1 guía de remisión / ticket de balanza) de un
-- lote por una ruta. Cubre los tres tramos: terminal->PAB, terminal->AT y
-- AT->PAB. Aquí nacen la merma de transporte y la penalidad al transportista.
create table public.fact_viaje_camion (
  id                         bigint generated always as identity primary key,
  lote_id                    bigint not null references public.dim_lote(id) on delete cascade,
  ruta_id                    bigint not null references public.dim_ruta(id),
  transportista_proveedor_id bigint references public.dim_proveedor(id),
  periodo                    date not null,        -- mes de la operación (la fuente actual no trae fecha por viaje)
  fecha_id                   int references public.dim_fecha(fecha_id),
  ts_salida                  timestamptz,
  ts_llegada                 timestamptz,
  guia_remision              text,
  ticket_balanza             text,
  placa                      text,
  documento_sap              text,                 -- EM / documento de material
  pedido_traslado            text,                 -- orden de traslado ZTRA
  peso_salida_kg             numeric(12,1),        -- balanza de origen (terminal / AT)
  peso_llegada_kg            numeric(12,1),        -- balanza de destino (EM en SAP)
  tolerancia_kg              numeric(8,1) not null default 40,
  diferencia_kg              numeric(12,1) generated always as (peso_llegada_kg - peso_salida_kg) stored,
  es_agregado                boolean not null default false,  -- true = fila resumen (la fuente no tenía el detalle por viaje)
  -- La tolerancia es por viaje: en filas agregadas no se puede calcular -> null.
  kg_en_contra               numeric(12,1) generated always as (
                               case when es_agregado then null
                                    when peso_llegada_kg - peso_salida_kg < -tolerancia_kg
                                    then peso_llegada_kg - peso_salida_kg + tolerancia_kg else 0 end) stored,
  kg_a_favor                 numeric(12,1) generated always as (
                               case when es_agregado then null
                                    when peso_llegada_kg - peso_salida_kg > tolerancia_kg
                                    then peso_llegada_kg - peso_salida_kg - tolerancia_kg else 0 end) stored,
  n_viajes                   int default 1 check (n_viajes >= 1),  -- null = desconocido (fila agregada)
  fuente                     text,
  fuente_fila                int
);
comment on table public.fact_viaje_camion is 'Un viaje de camión. diferencia_kg = llegada - salida; fuera de la tolerancia (40 kg por defecto) genera kg_en_contra (penalidad al transportista) o kg_a_favor. es_agregado marca filas que resumen varios viajes cuando la fuente solo traía totales por lote y destino.';
create index fact_viaje_camion_lote_idx on public.fact_viaje_camion (lote_id, ruta_id);
create index fact_viaje_camion_transp_idx on public.fact_viaje_camion (transportista_proveedor_id);

-- GRANO: 1 movimiento físico (ingreso / salida / ajuste) de un lote en un
-- almacén tercero. Permite TM-día de almacenaje y días de permanencia.
create table public.fact_movimiento_almacen (
  id                    bigint generated always as identity primary key,
  lote_id               bigint not null references public.dim_lote(id) on delete cascade,
  almacen_ubicacion_id  bigint not null references public.dim_ubicacion(id),
  fecha_id              int not null references public.dim_fecha(fecha_id),
  tipo                  text not null check (tipo in ('INGRESO','SALIDA','AJUSTE')),
  tm                    numeric(14,3) not null,     -- siempre positivo para INGRESO/SALIDA; con signo en AJUSTE
  tm_con_signo          numeric(14,3) generated always as (case tipo when 'SALIDA' then -tm else tm end) stored,
  destino_ubicacion_id  bigint references public.dim_ubicacion(id),
  tm_llegada_destino    numeric(14,3),
  pedido_sap            text,
  observacion           text,
  check (tipo = 'AJUSTE' or tm >= 0)
);
create index fact_mov_almacen_lote_idx on public.fact_movimiento_almacen (lote_id, almacen_ubicacion_id, fecha_id);

-- GRANO: fecha de corte x almacén x lote/material. Saldo físico vs. SAP
-- (exactitud de inventario, hoja ERI).
create table public.fact_inventario_almacen (
  id                    bigint generated always as identity primary key,
  fecha_corte_id        int not null references public.dim_fecha(fecha_id),
  almacen_ubicacion_id  bigint not null references public.dim_ubicacion(id),
  lote_id               bigint references public.dim_lote(id),
  lote_referencia       text,                       -- texto original si el lote no está en el modelo
  material_id           bigint references public.dim_material(id),
  saldo_fisico_tm       numeric(14,3) not null,
  saldo_sap_tm          numeric(14,3) not null,
  diferencia_tm         numeric(14,3) generated always as (saldo_fisico_tm - saldo_sap_tm) stored,
  es_exacto             boolean generated always as (abs(saldo_fisico_tm - saldo_sap_tm) < 0.001) stored
);

-- GRANO: 1 reclamo por lote y etapa de merma (al armador, aseguradora o
-- transportista) y su recupero.
create table public.fact_reclamo_merma (
  id                        bigint generated always as identity primary key,
  lote_id                   bigint not null references public.dim_lote(id) on delete cascade,
  etapa                     text not null check (etapa in ('TRAVESIA','TRANSPORTE','ALMACENAMIENTO','TRASLADO_ALMACEN')),
  contraparte_proveedor_id  bigint references public.dim_proveedor(id),
  fecha_id                  int references public.dim_fecha(fecha_id),
  tm_reclamadas             numeric(14,3) not null,
  moneda                    char(3) not null default 'USD' check (moneda in ('PEN','USD')),
  monto_reclamado           numeric(14,2),
  monto_recuperado          numeric(14,2),
  estado                    text not null default 'ABIERTO' check (estado in ('ABIERTO','RECUPERADO','DESCONTADO','RECHAZADO')),
  documento                 text
);

-- ---------------------------------------------------------------------------
-- 7. HECHOS DE COSTO Y PRESUPUESTO
-- ---------------------------------------------------------------------------

-- GRANO: 1 línea de costo = escenario x lote (o escala, si el gasto es de la
-- nave completa: agencia, demurrage) x concepto x proveedor x ubicación/ruta
-- x documento. REAL viene de facturas o de TM x tarifa; PLAN y PRESUPUESTO
-- del planeamiento. Mismo grano para los tres -> comparables directamente.
create table public.fact_costo (
  id                 bigint generated always as identity primary key,
  escenario          text not null check (escenario in ('REAL','PLAN','PRESUPUESTO','SIMULACION')),
  escala_id          bigint not null references public.dim_escala(id) on delete cascade,
  lote_id            bigint references public.dim_lote(id) on delete cascade,
  concepto_id        bigint not null references public.dim_concepto_costo(id),
  proveedor_id       bigint references public.dim_proveedor(id),
  ubicacion_id       bigint references public.dim_ubicacion(id),
  ruta_id            bigint references public.dim_ruta(id),
  centro_costo_id    bigint references public.dim_centro_costo(id),
  periodo            date not null,
  fecha_id           int references public.dim_fecha(fecha_id),
  cantidad           numeric(14,3),
  unidad             text check (unidad in ('TM','TM_MES','HORA','DIA','VIAJE','GLOBAL')),
  tarifa_unitaria    numeric(14,4),
  moneda             char(3) not null default 'PEN' check (moneda in ('PEN','USD')),
  monto              numeric(16,2) not null,
  tipo_cambio        numeric(10,4) not null default 1 check (tipo_cambio > 0),
  monto_pen          numeric(16,2) generated always as (round(monto * tipo_cambio, 2)) stored,
  tarifa_version_id  text references public.tarifa_versiones(id),
  origen_dato        text not null check (origen_dato in ('FACTURA','TARIFA_X_CANTIDAD','FORMULA_PLAN','ESTIMADO','LIQUIDACION')),
  factura            text,
  orden_compra       text,
  hes                text,
  descripcion        text,
  fuente             text,
  check (moneda <> 'PEN' or tipo_cambio = 1)
);
create index fact_costo_lote_idx on public.fact_costo (lote_id, escenario);
create index fact_costo_escala_idx on public.fact_costo (escala_id, escenario);

-- GRANO: mes x producto (hoja PRESUPUESTOS).
create table public.fact_presupuesto_mensual (
  id           bigint generated always as identity primary key,
  periodo      date not null,
  producto_id  bigint not null references public.dim_producto(id),
  tm           numeric(14,3) not null,
  monto_pen    numeric(16,2) not null,
  cu_pen_tm    numeric(12,4) generated always as (case when tm > 0 then round(monto_pen / tm, 4) end) stored,
  unique (periodo, producto_id)
);

-- ============================================================================
-- 8. FUNCIONES Y VISTAS ANALÍTICAS
-- ============================================================================

-- Horas que cuentan para laytime en una escala: suma los intervalos del SOF
-- ponderados por su factor, partidos por día, y excluye domingos y feriados
-- (SHEX) o sábados, domingos y feriados (SSHEX) según el C/P.
create or replace function public.fn_laytime_horas_usadas(p_escala_id bigint)
returns numeric
language sql stable
set search_path = public
as $$
  with cond as (
    select base_calculo from laytime_condicion where escala_id = p_escala_id
  ), ev as (
    select e.ts_inicio, e.ts_fin, coalesce(e.factor_laytime, d.cuenta_laytime_default) as factor
    from fact_sof_evento e
    join dim_evento_sof d on d.codigo = e.evento_codigo
    where e.escala_id = p_escala_id and e.ts_fin is not null
  ), trozos as (
    -- Los días se cortan en hora local de Lima (domingo/feriado = día calendario peruano).
    select ev.factor,
           greatest(ev.ts_inicio, (g.dia::date)::timestamp at time zone 'America/Lima')       as ini,
           least(ev.ts_fin, (g.dia::date + 1)::timestamp at time zone 'America/Lima')         as fin,
           g.dia::date as dia
    from ev,
         generate_series((ev.ts_inicio at time zone 'America/Lima')::date,
                         (ev.ts_fin    at time zone 'America/Lima')::date, interval '1 day') g(dia)
    where ev.factor > 0
  )
  select coalesce(round(sum(extract(epoch from (t.fin - t.ini)) / 3600.0 * t.factor), 2), 0)
  from trozos t
  join dim_fecha f on f.fecha = t.dia
  cross join cond c
  where t.fin > t.ini
    and not (c.base_calculo in ('SHEX','SSHEX') and (f.dia_semana_iso = 7 or f.es_feriado))
    and not (c.base_calculo = 'SSHEX' and f.dia_semana_iso = 6);
$$;

-- Laytime calculado por escala (permitido vs. usado -> demurrage / despatch).
create or replace view public.v_laytime_escala with (security_invoker = true) as
with tm as (
  select escala_id, sum(tm_manifestadas) as tm_manifestadas from public.dim_lote group by escala_id
)
select e.id as escala_id, e.codigo, b.nombre as buque, p.nombre as puerto,
       c.tasa_descarga_tm_dia, c.base_calculo, c.turn_time_horas,
       tm.tm_manifestadas,
       round(tm.tm_manifestadas / c.tasa_descarga_tm_dia * 24, 2)            as laytime_permitido_horas,
       public.fn_laytime_horas_usadas(e.id)                                   as laytime_usado_horas,
       round(greatest(public.fn_laytime_horas_usadas(e.id) - tm.tm_manifestadas / c.tasa_descarga_tm_dia * 24, 0) / 24 * c.demurrage_usd_dia, 2) as demurrage_usd,
       round(greatest(tm.tm_manifestadas / c.tasa_descarga_tm_dia * 24 - public.fn_laytime_horas_usadas(e.id), 0) / 24 * c.despatch_usd_dia, 2) as despatch_usd,
       l.neto_usd as neto_liquidado_usd, l.estado as estado_liquidacion
from public.dim_escala e
join public.dim_buque b on b.id = e.buque_id
join public.dim_puerto p on p.id = e.puerto_id
join public.laytime_condicion c on c.escala_id = e.id
join tm on tm.escala_id = e.id
left join lateral (
  select neto_usd, estado from public.fact_laytime_liquidacion x
  where x.escala_id = e.id and x.estado <> 'ANULADA' order by version desc limit 1
) l on true;

-- Balance de masa por lote: reproduce y reemplaza la lógica de la hoja BASE,
-- pero calculada desde los viajes de camión.
create or replace view public.v_lote_balance_masa with (security_invoker = true) as
with v as (
  select vc.lote_id, r.tramo, uo.tipo as tipo_origen, ud.tipo as tipo_destino,
         sum(vc.peso_salida_kg)  / 1000.0 as tm_salida,
         sum(vc.peso_llegada_kg) / 1000.0 as tm_llegada,
         sum(vc.n_viajes) as viajes
  from public.fact_viaje_camion vc
  join public.dim_ruta r on r.id = vc.ruta_id
  join public.dim_ubicacion uo on uo.id = r.origen_ubicacion_id
  join public.dim_ubicacion ud on ud.id = r.destino_ubicacion_id
  group by vc.lote_id, r.tramo, uo.tipo, ud.tipo
), agg as (
  select lote_id,
    coalesce(sum(tm_salida)  filter (where tipo_origen = 'TERMINAL'), 0)                     as tm_descargada,
    coalesce(sum(tm_llegada) filter (where tramo = 'PUERTO_PLANTA'), 0)                      as tm_ingreso_planta_directo,
    coalesce(sum(tm_llegada) filter (where tramo = 'PUERTO_ALMACEN'), 0)                     as tm_ingreso_almacen,
    coalesce(sum(tm_salida)  filter (where tramo = 'ALMACEN_PLANTA'), 0)                     as tm_salida_almacen,
    coalesce(sum(tm_llegada) filter (where tramo = 'ALMACEN_PLANTA'), 0)                     as tm_ingreso_planta_desde_almacen,
    coalesce(sum(viajes), 0)                                                                 as viajes
  from v group by lote_id
)
select l.id as lote_id, l.clave_fuente, e.codigo as escala, b.nombre as buque, pu.nombre as puerto,
       e.periodo_operacion, pr.codigo as producto, m.descripcion as material,
       l.tm_manifestadas,
       a.tm_descargada,
       a.tm_ingreso_planta_directo,
       a.tm_ingreso_almacen,
       a.tm_salida_almacen,
       a.tm_ingreso_planta_desde_almacen,
       a.tm_ingreso_planta_directo + a.tm_ingreso_planta_desde_almacen                      as tm_total_en_planta,
       case when not l.almacen_cerrado then a.tm_ingreso_almacen - a.tm_salida_almacen else 0 end as tm_stock_almacen,
       l.tm_manifestadas - a.tm_descargada                                                    as merma_travesia_tm,
       a.tm_descargada - (a.tm_ingreso_planta_directo + a.tm_ingreso_almacen)                as merma_transporte_tm,
       case when l.almacen_cerrado then a.tm_ingreso_almacen - a.tm_salida_almacen end as merma_almacenamiento_tm,
       a.tm_salida_almacen - a.tm_ingreso_planta_desde_almacen                               as merma_traslado_almacen_tm,
       (l.tm_manifestadas - a.tm_descargada)
         + (a.tm_descargada - (a.tm_ingreso_planta_directo + a.tm_ingreso_almacen))
         + coalesce(case when l.almacen_cerrado then a.tm_ingreso_almacen - a.tm_salida_almacen end, 0)
         + (a.tm_salida_almacen - a.tm_ingreso_planta_desde_almacen)                         as merma_total_tm,
       round(((l.tm_manifestadas - a.tm_descargada)
         + (a.tm_descargada - (a.tm_ingreso_planta_directo + a.tm_ingreso_almacen))
         + coalesce(case when l.almacen_cerrado then a.tm_ingreso_almacen - a.tm_salida_almacen end, 0)
         + (a.tm_salida_almacen - a.tm_ingreso_planta_desde_almacen)) / l.tm_manifestadas, 6) as merma_total_pct,
       a.viajes,
       l.estado
from public.dim_lote l
join public.dim_escala e on e.id = l.escala_id
join public.dim_buque b on b.id = e.buque_id
join public.dim_puerto pu on pu.id = e.puerto_id
join public.dim_material m on m.id = l.material_id
join public.dim_producto pr on pr.id = m.producto_id
left join agg a on a.lote_id = l.id;

-- Merma por lote y etapa en formato largo (para gráficos y control vs. tolerancia).
create or replace view public.v_lote_merma_etapa with (security_invoker = true) as
select b.lote_id, b.escala, b.producto, b.periodo_operacion, x.etapa, x.base_tm, x.merma_tm,
       case when x.base_tm > 0 then round(x.merma_tm / x.base_tm, 6) end as merma_pct
from public.v_lote_balance_masa b
cross join lateral (values
  ('TRAVESIA',         b.tm_manifestadas,     b.merma_travesia_tm),
  ('TRANSPORTE',       b.tm_descargada,       b.merma_transporte_tm),
  ('ALMACENAMIENTO',   b.tm_ingreso_almacen,  b.merma_almacenamiento_tm),
  ('TRASLADO_ALMACEN', b.tm_salida_almacen,   b.merma_traslado_almacen_tm),
  ('TOTAL',            b.tm_manifestadas,     b.merma_total_tm)
) x(etapa, base_tm, merma_tm)
where x.merma_tm is not null;

-- Costo por lote, escenario y categoría + costo unitario por TM descargada.
create or replace view public.v_lote_costo with (security_invoker = true) as
select c.escenario, l.id as lote_id, e.codigo as escala, pu.nombre as puerto, pr.codigo as producto,
       e.periodo_operacion, cc.categoria,
       sum(case when cc.es_ingreso then -c.monto_pen else c.monto_pen end) as monto_pen,
       bm.tm_descargada,
       round(sum(case when cc.es_ingreso then -c.monto_pen else c.monto_pen end) / nullif(bm.tm_descargada, 0), 4) as cu_pen_tm_descargada,
       round(sum(case when cc.es_ingreso then -c.monto_pen else c.monto_pen end) / l.tm_manifestadas, 4) as cu_pen_tm_manifestada
from public.fact_costo c
join public.dim_lote l on l.id = c.lote_id
join public.dim_escala e on e.id = l.escala_id
join public.dim_puerto pu on pu.id = e.puerto_id
join public.dim_material m on m.id = l.material_id
join public.dim_producto pr on pr.id = m.producto_id
join public.dim_concepto_costo cc on cc.id = c.concepto_id
left join public.v_lote_balance_masa bm on bm.lote_id = l.id
group by c.escenario, l.id, e.codigo, pu.nombre, pr.codigo, e.periodo_operacion, cc.categoria, bm.tm_descargada, l.tm_manifestadas;

-- Penalidad por transportista (kg fuera de tolerancia) por lote y ruta.
create or replace view public.v_penalidad_transportista with (security_invoker = true) as
select vc.lote_id, e.codigo as escala, r.tramo, ud.nombre as destino,
       p.razon_social as transportista,
       sum(vc.n_viajes)                       as viajes,
       count(*) filter (where vc.kg_en_contra < 0) as viajes_fuera_tolerancia,
       sum(vc.peso_llegada_kg) / 1000.0       as tm_entregadas,
       sum(vc.diferencia_kg)                  as diferencia_kg,
       sum(vc.kg_en_contra)                   as kg_en_contra,
       sum(vc.kg_a_favor)                     as kg_a_favor,
       round(sum(vc.kg_en_contra) / 1000.0 * l.precio_cif_usd_tm, 2) as valor_penalidad_usd
from public.fact_viaje_camion vc
join public.dim_lote l on l.id = vc.lote_id
join public.dim_escala e on e.id = l.escala_id
join public.dim_ruta r on r.id = vc.ruta_id
join public.dim_ubicacion ud on ud.id = r.destino_ubicacion_id
left join public.dim_proveedor p on p.id = vc.transportista_proveedor_id
where not vc.es_agregado
group by vc.lote_id, e.codigo, r.tramo, ud.nombre, p.razon_social, l.precio_cif_usd_tm;

-- Permanencia en almacén tercero por lote: TM ingresadas, salidas, saldo,
-- días promedio ponderados (TM-día) -> base para almacenaje por mes.
create or replace view public.v_almacen_permanencia with (security_invoker = true) as
with m as (
  select mv.lote_id, mv.almacen_ubicacion_id, f.fecha, mv.tipo, mv.tm
  from public.fact_movimiento_almacen mv join public.dim_fecha f on f.fecha_id = mv.fecha_id
), ing as (
  select lote_id, almacen_ubicacion_id, min(fecha) as fecha_ingreso, sum(tm) as tm_ingreso
  from m where tipo = 'INGRESO' group by 1,2
), sal as (
  select lote_id, almacen_ubicacion_id, max(fecha) as fecha_ultima_salida, sum(tm) as tm_salida
  from m where tipo = 'SALIDA'
  group by 1,2
)
select i.lote_id, e.codigo as escala, u.nombre as almacen,
       i.fecha_ingreso, s.fecha_ultima_salida,
       i.tm_ingreso, coalesce(s.tm_salida, 0) as tm_salida,
       i.tm_ingreso - coalesce(s.tm_salida, 0) as saldo_tm,
       (coalesce(s.fecha_ultima_salida, current_date) - i.fecha_ingreso) as dias_permanencia_max,
       (select round(sum(x.tm * (x.fecha - i.fecha_ingreso)) / nullif(sum(x.tm), 0), 1)
          from m x where x.lote_id = i.lote_id and x.almacen_ubicacion_id = i.almacen_ubicacion_id and x.tipo = 'SALIDA') as dias_promedio_ponderado
from ing i
left join sal s
  on s.lote_id = i.lote_id and s.almacen_ubicacion_id = i.almacen_ubicacion_id
join public.dim_lote l on l.id = i.lote_id
join public.dim_escala e on e.id = l.escala_id
join public.dim_ubicacion u on u.id = i.almacen_ubicacion_id;

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

-- ============================================================================
-- 9. ROW LEVEL SECURITY (mismo patrón que la migración inicial)
-- lectura: cualquier autenticado · escritura: admin · tarifa: solo INSERT admin
-- ============================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'dim_fecha','dim_pais','dim_puerto','dim_proveedor','dim_proveedor_alias','dim_terminal',
    'dim_ubicacion','dim_ubicacion_alias','dim_ruta','dim_producto','dim_material','dim_tolerancia_merma',
    'dim_buque','dim_escala','dim_lote','dim_concepto_costo','dim_centro_costo','dim_evento_sof',
    'fact_escala','laytime_condicion','fact_sof_evento','fact_laytime_liquidacion','fact_descarga_diaria',
    'fact_plan_distribucion','fact_viaje_camion','fact_movimiento_almacen','fact_inventario_almacen',
    'fact_reclamo_merma','fact_costo','fact_presupuesto_mensual']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (auth.role() = ''authenticated'')', t || '_select', t);
    execute format('create policy %I on public.%I for all using (public.is_admin()) with check (public.is_admin())', t || '_admin_write', t);
  end loop;
end $$;

alter table public.tarifa enable row level security;
create policy "tarifa_select" on public.tarifa for select using (auth.role() = 'authenticated');
create policy "tarifa_admin_insert" on public.tarifa for insert with check (public.is_admin());

-- ============================================================================
-- 10. CATÁLOGOS BASE (no son datos de naves: son la estructura del negocio)
-- ============================================================================
insert into public.dim_pais (iso2, nombre) values
  ('PE','PERÚ'),('AR','ARGENTINA'),('BR','BRASIL'),('PY','PARAGUAY'),('US','EEUU'),('BO','BOLIVIA');

insert into public.dim_puerto (locode, nombre, pais_id)
select x.locode, x.nombre, p.id from (values ('PECLL','CALLAO'),('PECHY','CHANCAY')) x(locode, nombre)
join public.dim_pais p on p.iso2 = 'PE';

insert into public.dim_producto (codigo, nombre) values
  ('MAIZ','Maíz amarillo duro'),('TORTA','Torta de soya'),('FREJOL','Grano / fréjol de soya');

insert into public.dim_tolerancia_merma (producto_id, etapa, pct_tolerado, vigente_desde) values
  (null, 'TOTAL', 0.005, '2025-01-01');

insert into public.dim_proveedor (razon_social, nombre_corto, roles) values
  ('APM TERMINALS CALLAO S.A.',               'APM',          array['TERMINAL','BALANZA']),
  ('COSCO SHIPPING PORTS CHANCAY PERU S.A.',  'COSCO',        array['TERMINAL','BALANZA']),
  ('RANSA COMERCIAL S.A.',                    'RANSA',        array['ALMACEN','TRANSPORTISTA']),
  ('DIEF ALMACENES',                          'DIEF',         array['ALMACEN','TRANSPORTISTA']),
  ('DEPSA',                                   'DEPSA',        array['ALMACEN','TRANSPORTISTA']),
  ('GH CORP',                                 'GH',           array['OTRO']);

insert into public.dim_terminal (codigo, nombre, puerto_id, operador_proveedor_id)
select x.codigo, x.nombre, pu.id, pr.id
from (values ('APM','APM Terminals Callao - Muelle Norte','CALLAO','APM'),
             ('COSCO','Terminal Portuario Multipropósito de Chancay','CHANCAY','COSCO')) x(codigo, nombre, puerto, op)
join public.dim_puerto pu on pu.nombre = x.puerto
join public.dim_proveedor pr on pr.nombre_corto = x.op;

insert into public.dim_ubicacion (codigo, nombre, tipo, centro_sap, almacen_sap, terminal_id, operador_proveedor_id, ciudad, bajo_techo)
select x.codigo, x.nombre, x.tipo, x.centro, x.almacen,
       (select id from public.dim_terminal t where t.codigo = x.terminal),
       (select id from public.dim_proveedor p where p.nombre_corto = x.op),
       x.ciudad, x.techo
from (values
  ('TER-APM',   'Terminal APM Callao',        'TERMINAL',        null,   null,   'APM',   'APM',   'CALLAO',  null),
  ('TER-COSCO', 'Terminal COSCO Chancay',     'TERMINAL',        null,   null,   'COSCO', 'COSCO', 'CHANCAY', null),
  ('5001',      'PAB Lurín',                  'PLANTA',          '5001', null,   null,    null,    'LURÍN',   true),
  ('1028',      'PAB Lurín 2 (depósito)',     'PLANTA',          '1028', null,   null,    null,    'LURÍN',   true),
  ('5003',      'PAB Chancay',                'PLANTA',          '5003', null,   null,    null,    'CHANCAY', true),
  ('5029',      'PAB GH Chancay (GHCORP)',    'PLANTA',          '5029', null,   null,    'GH',    'CHANCAY', true),
  ('2111',      'Ransa Argentina',            'ALMACEN_TERCERO', null,   '2111', null,    'RANSA', 'CALLAO',  null),
  ('2110',      'Ransa Primax / Bulkbox',     'ALMACEN_TERCERO', null,   '2110', null,    'RANSA', 'CALLAO',  null),
  ('2129',      'DIEF Almacenes',             'ALMACEN_TERCERO', null,   '2129', null,    'DIEF',  'CALLAO',  null),
  ('2130',      'Ransa Oquendo',              'ALMACEN_TERCERO', null,   '2130', null,    'RANSA', 'CALLAO',  null),
  ('DEPSA',     'DEPSA',                      'ALMACEN_TERCERO', null,   null,   null,    'DEPSA', 'CALLAO',  null),
  ('RANSA-NE',  'Ransa (almacén no especificado)', 'ALMACEN_TERCERO', null, null, null,   'RANSA', 'CALLAO',  null)
) x(codigo, nombre, tipo, centro, almacen, terminal, op, ciudad, techo);

insert into public.dim_ubicacion_alias (alias, ubicacion_id)
select x.alias, u.id from (values
  ('AABB LURIN - 5001','5001'),('5001 - LURIN','5001'),('LURIN','5001'),
  ('AABB LURIN - 1028','1028'),
  ('AABB CHANCAY - 5003','5003'),('5003 - CHANCAY','5003'),('CHANCAY','5003'),
  ('GHCORP - 5029','5029'),('5029 - GHCORP','5029'),('5029 - GH','5029'),('GH','5029'),
  ('RANSA ARGENTINA - 2111','2111'),('RANSA ARGENTINA','2111'),('R. ARGENTINA','2111'),
  ('RANSA PRIMAX - 2110','2110'),('BULKBOX','2110'),
  ('DIEF - 2129','2129'),('DIEF','2129'),('DIEF ALMACENES','2129'),
  ('RANSA OQUENDO - 2130','2130'),('RANSA OQUENDO','2130'),('R. OQUENDO','2130'),
  ('DEPSA','DEPSA'),('RANSA','RANSA-NE')
) x(alias, codigo) join public.dim_ubicacion u on u.codigo = x.codigo;

-- Rutas habilitadas (todas las combinaciones con tarifa en el tarifario).
insert into public.dim_ruta (origen_ubicacion_id, destino_ubicacion_id, tramo)
select o.id, d.id, 'PUERTO_PLANTA'   -- el trigger recalcula el tramo
from public.dim_ubicacion o, public.dim_ubicacion d
where o.tipo = 'TERMINAL' and d.tipo in ('PLANTA','ALMACEN_TERCERO')
   or o.tipo = 'ALMACEN_TERCERO' and d.tipo = 'PLANTA'
   or o.codigo = '1028' and d.codigo = '5001'
   or o.codigo = '5001' and d.codigo = '5003'
   or o.codigo = '5003' and d.codigo = '5029';

insert into public.dim_concepto_costo (codigo, nombre, categoria, subcategoria, unidad_base, es_ingreso, orden) values
  ('DESC_INTEGRAL',     'Descarga (tarifa integral por TM)',       'DESCARGA',       'INTEGRAL',     'TM',     false, 10),
  ('DESC_TERMINAL',     'Servicio de terminal / estiba-desestiba',  'DESCARGA',       'TERMINAL',     'TM',     false, 11),
  ('DESC_SURVEYOR',     'Surveyor / draft survey',                  'DESCARGA',       'SURVEYOR',     'TM',     false, 12),
  ('DESC_AGENCIA',      'Agencia marítima (comisión)',              'DESCARGA',       'AGENCIA',      'TM',     false, 13),
  ('DESC_BALANZA',      'Control de balanza',                       'DESCARGA',       'BALANZA',      'TM',     false, 14),
  ('DESC_OPERATIVA',    'Gastos de área operativa',                 'DESCARGA',       'OPERATIVA',    'TM',     false, 15),
  ('DESC_TRASLADO_INT', 'Traslado interno en puerto',               'DESCARGA',       'TRASLADO',     'TM',     false, 16),
  ('FLETE_PTO_PAB',     'Flete terminal -> PAB',                    'TRANSPORTE',     'PUERTO_PLANTA','TM',     false, 20),
  ('FLETE_PTO_ALM',     'Flete terminal -> almacén tercero',        'TRANSPORTE',     'PUERTO_ALMACEN','TM',    false, 21),
  ('FLETE_ALM_PAB',     'Flete almacén tercero -> PAB',             'TRANSPORTE',     'ALMACEN_PLANTA','TM',    false, 22),
  ('FLETE_PAB_PAB',     'Flete entre plantas',                      'TRANSPORTE',     'PLANTA_PLANTA','TM',     false, 23),
  ('ALM_ALMACENAJE',    'Almacenaje (por TM y mes)',                'ALMACENAMIENTO', 'ALMACENAJE',   'TM_MES', false, 30),
  ('ALM_ALMACENAJE_TECHO','Almacenaje bajo techo (por TM y mes)',  'ALMACENAMIENTO', 'ALMACENAJE',   'TM_MES', false, 30),
  ('ALM_CARGADOR',     'Cargador frontal (ingreso / salida)',      'ALMACENAMIENTO', 'CARGADOR',     'TM',     false, 31),
  ('ALM_HE_SIMPLE',     'Horas extras simples',                     'ALMACENAMIENTO', 'HORAS_EXTRAS', 'HORA',   false, 32),
  ('ALM_HE_DOBLE',      'Horas extras dobles',                      'ALMACENAMIENTO', 'HORAS_EXTRAS', 'HORA',   false, 33),
  ('LT_DEMURRAGE',      'Demurrage (sobrestadía)',                  'LAYTIME',        'DEMURRAGE',    'DIA',    false, 40),
  ('LT_DESPATCH',       'Despatch (pronto despacho)',               'LAYTIME',        'DESPATCH',     'DIA',    true,  41),
  ('PEN_TRANSPORTE',    'Penalidad cobrada a transportista',        'PENALIDAD',      'TRANSPORTE',   'TM',     true,  50),
  ('MERMA_VALOR',       'Valor de merma',                           'MERMA',          'MERMA',        'TM',     false, 60),
  ('MERMA_RECUPERO',    'Recupero / descuento de merma',            'MERMA',          'RECUPERO',     'TM',     true,  61),
  ('AJ_DESCARGA',       'Ajuste de conciliación con fuente (descarga)',       'DESCARGA',       'AJUSTE', 'GLOBAL', false, 95),
  ('AJ_TRANSPORTE',     'Ajuste de conciliación con fuente (transporte)',     'TRANSPORTE',     'AJUSTE', 'GLOBAL', false, 96),
  ('AJ_ALMACEN',        'Ajuste de conciliación con fuente (almacenamiento)', 'ALMACENAMIENTO', 'AJUSTE', 'GLOBAL', false, 97),
  ('PPTO_DESCARGA',    'Presupuesto de descarga',                  'DESCARGA',       'PRESUPUESTO',  'TM',     false, 90),
  ('PPTO_TRANSPORTE',   'Presupuesto de transporte',                'TRANSPORTE',     'PRESUPUESTO',  'TM',     false, 91),
  ('PPTO_ALMACEN',      'Presupuesto de almacenamiento',            'ALMACENAMIENTO', 'PRESUPUESTO',  'TM',     false, 92),
  ('PPTO_GLOBAL',       'Presupuesto logístico global (sin apertura)', 'GLOBAL',      'PRESUPUESTO',  'TM',     false, 93);

insert into public.dim_centro_costo (codigo, nombre, planta_ubicacion_id)
select x.codigo, x.nombre, u.id from (values ('1401207','C.C. PAB CHANCAY','5003'),('1401107','C.C. PAB LURIN','5001')) x(codigo, nombre, planta)
join public.dim_ubicacion u on u.codigo = x.planta;

insert into public.dim_evento_sof (codigo, nombre, fase, cuenta_laytime_default, orden) values
  ('LLEGADA_RADA',     'Llegada a rada / fondeo',                 'LLEGADA',      0,   10),
  ('NOR_PRESENTADO',   'NOR presentado',                          'LLEGADA',      0,   20),
  ('TURN_TIME',        'Turn time (tiempo libre tras NOR)',       'LLEGADA',      0,   25),
  ('ESPERA_MUELLE',    'Espera de muelle (laytime corriendo)',    'LLEGADA',      1,   30),
  ('LIBRE_PLATICA',    'Libre plática / autoridades',             'ATRAQUE',      0,   35),
  ('ATRAQUE',          'Maniobra de atraque',                     'ATRAQUE',      0,   40),
  ('DRAFT_INICIAL',    'Draft survey inicial',                    'ATRAQUE',      1,   45),
  ('DESCARGA',         'Descarga en curso',                       'DESCARGA',     1,   50),
  ('PARA_LLUVIA',      'Paralización por lluvia / garúa',         'PARALIZACION', 0,   60),
  ('PARA_FALLA_BUQUE', 'Paralización por falla del buque/grúas',  'PARALIZACION', 0,   61),
  ('PARA_FALLA_TERM',  'Paralización por falla del terminal',     'PARALIZACION', 1,   62),
  ('PARA_CAMIONES',    'Paralización por falta de camiones',      'PARALIZACION', 1,   63),
  ('PARA_CAMBIO_BOD',  'Cambio de bodega / shifting',             'PARALIZACION', 0,   64),
  ('PARA_OLEAJE',      'Puerto cerrado por oleaje (capitanía)',   'PARALIZACION', 0,   65),
  ('PARA_FERIADO',     'Feriado / domingo excluido',              'PARALIZACION', 0,   66),
  ('FIN_DESCARGA',     'Fin de descarga',                         'CIERRE',       0,   80),
  ('DRAFT_FINAL',      'Draft survey final',                      'CIERRE',       0,   85),
  ('DESATRAQUE',       'Desatraque',                              'CIERRE',       0,   90);
