-- ============================================================================
-- Muelle · Ecosistema de Datos de Costos Logísticos
-- Migración inicial: esquema + RLS
--
-- Traduce 1:1 el modelo de js/data.js + js/store.js:
--   - Catálogos (plantas, transportistas, productos): no cambian en el tiempo.
--   - Tarifas: SÍ cambian en el tiempo -> versionadas e INMUTABLES. Una vez
--     insertada una versión, no se permite UPDATE ni DELETE (ni para admin):
--     al no crear política alguna para esos comandos, RLS deniega por defecto.
--     Corregir una tarifa = crear una nueva versión, igual que hoy en la app.
--   - Simulaciones: quedan enlazadas al id de la versión de tarifas usada
--     (trazabilidad).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. PERFILES Y ROLES (Supabase Auth)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text not null,
  role       text not null default 'analista' check (role in ('admin','analista')),
  created_at timestamptz not null default now()
);

comment on table public.profiles is 'Perfil + rol de cada usuario de Supabase Auth. admin = edita maestros/tarifas (pestaña "Maestros & Gobierno"); analista = solo corre y guarda simulaciones.';

-- Crea automáticamente el perfil cuando alguien se registra en Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nombre, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'nombre', new.email), 'analista');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Helper para políticas: ¿el usuario autenticado es admin?
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. CATÁLOGOS — CATALOGOS.plantas / transportistas / productos
-- ---------------------------------------------------------------------------
create table public.plantas (
  id     text primary key,          -- código SAP: '5003', '5029', '5001'
  nombre text not null,
  codigo text not null
);

create table public.transportistas (
  id     bigint generated always as identity primary key,
  nombre text not null unique
);

create table public.productos (
  id     bigint generated always as identity primary key,
  nombre text not null unique
);

-- ---------------------------------------------------------------------------
-- 3. TARIFAS VERSIONADAS — seedVersion() en js/data.js
-- ---------------------------------------------------------------------------
create table public.tarifa_versiones (
  id             text primary key,        -- 'V-2026-01'
  vigente_desde  date not null,
  autor          text,
  nota           text,
  tipo_cambio    numeric(10,4) not null check (tipo_cambio > 0),
  created_by     uuid references auth.users(id),
  creado_en      timestamptz not null default now()
);

-- S/. por TN — flete puerto de origen -> planta, por transportista
create table public.tarifa_flete (
  id                bigint generated always as identity primary key,
  version_id        text not null references public.tarifa_versiones(id) on delete cascade,
  puerto            text not null check (puerto in ('CHANCAY','CALLAO')),
  planta_id         text not null references public.plantas(id),
  transportista_id  bigint not null references public.transportistas(id),
  valor             numeric(10,2) not null check (valor >= 0),
  unique (version_id, puerto, planta_id, transportista_id)
);

-- S/. por TN — componentes de descarga en puerto
create table public.tarifa_descarga (
  id          bigint generated always as identity primary key,
  version_id  text not null references public.tarifa_versiones(id) on delete cascade,
  puerto      text not null check (puerto in ('CHANCAY','CALLAO')),
  balanza     numeric(10,3) not null default 0,
  comision    numeric(10,3) not null default 0,
  operativa   numeric(10,3) not null default 0,
  ayg         numeric(10,3) not null default 0,
  unique (version_id, puerto)
);

-- S/. por TN — almacenamiento estimado por producto (0 = no aplica)
create table public.tarifa_almacenamiento (
  id           bigint generated always as identity primary key,
  version_id   text not null references public.tarifa_versiones(id) on delete cascade,
  producto_id  bigint not null references public.productos(id),
  valor        numeric(10,2) not null default 0,
  unique (version_id, producto_id)
);

-- ---------------------------------------------------------------------------
-- 4. HISTÓRICO DE NAVES — NAVES_HISTORICO en js/data.js (hoja "Comparativo")
-- producto queda como texto libre: el histórico real incluye combos
-- ("Maíz + torta de soya") que no calzan 1:1 con el catálogo de productos.
-- ---------------------------------------------------------------------------
create table public.naves_historico (
  id           bigint generated always as identity primary key,
  mes          text not null,
  puerto       text not null check (puerto in ('CHANCAY','CALLAO')),
  nave         text not null,
  tn           numeric(12,3) not null check (tn >= 0),
  producto     text not null,
  presupuesto  numeric(14,2),
  cosco        numeric(14,2),
  apm          numeric(14,2)
);

-- ---------------------------------------------------------------------------
-- 5. SIMULACIONES — trazabilidad (pestaña "Trazabilidad")
-- ---------------------------------------------------------------------------
create table public.simulaciones (
  id                  text primary key,     -- 'SIM-<timestamp36>' generado en cliente
  fecha               timestamptz not null default now(),
  analista_id         uuid references auth.users(id),
  analista_nombre     text not null,         -- copia denormalizada (se conserva si se borra el usuario)
  nave                text not null default 'Escenario sin nombre',
  tn                  numeric(12,3) not null check (tn > 0),
  producto_id         bigint references public.productos(id),
  planta_id           text references public.plantas(id),
  transportista_id    bigint references public.transportistas(id),
  version_tarifas_id  text not null references public.tarifa_versiones(id),
  costo_chancay       numeric(14,2) not null,
  costo_callao        numeric(14,2) not null,
  puerto_recomendado  text not null check (puerto_recomendado in ('CHANCAY','CALLAO')),
  ahorro              numeric(14,2) not null
);

create index simulaciones_fecha_idx on public.simulaciones (fecha desc);
create index tarifa_flete_version_idx on public.tarifa_flete (version_id);
create index tarifa_descarga_version_idx on public.tarifa_descarga (version_id);
create index tarifa_almacenamiento_version_idx on public.tarifa_almacenamiento (version_id);

-- ============================================================================
-- 6. ROW LEVEL SECURITY
-- ============================================================================
alter table public.profiles              enable row level security;
alter table public.plantas               enable row level security;
alter table public.transportistas        enable row level security;
alter table public.productos             enable row level security;
alter table public.tarifa_versiones      enable row level security;
alter table public.tarifa_flete          enable row level security;
alter table public.tarifa_descarga       enable row level security;
alter table public.tarifa_almacenamiento enable row level security;
alter table public.naves_historico       enable row level security;
alter table public.simulaciones          enable row level security;

-- profiles: cada quien ve/edita su propio perfil (menos el rol); admin ve todo.
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid() and role = (select role from public.profiles where id = auth.uid()));
create policy "profiles_admin_manage" on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- Catálogos: lectura para cualquier usuario autenticado; escritura solo admin.
create policy "plantas_select" on public.plantas
  for select using (auth.role() = 'authenticated');
create policy "plantas_admin_write" on public.plantas
  for all using (public.is_admin()) with check (public.is_admin());

create policy "transportistas_select" on public.transportistas
  for select using (auth.role() = 'authenticated');
create policy "transportistas_admin_write" on public.transportistas
  for all using (public.is_admin()) with check (public.is_admin());

create policy "productos_select" on public.productos
  for select using (auth.role() = 'authenticated');
create policy "productos_admin_write" on public.productos
  for all using (public.is_admin()) with check (public.is_admin());

-- Tarifas: lectura para autenticados; SOLO INSERT para admin (no hay política
-- de update/delete -> queda bloqueado para todos, garantizando inmutabilidad).
create policy "tarifa_versiones_select" on public.tarifa_versiones
  for select using (auth.role() = 'authenticated');
create policy "tarifa_versiones_admin_insert" on public.tarifa_versiones
  for insert with check (public.is_admin());

create policy "tarifa_flete_select" on public.tarifa_flete
  for select using (auth.role() = 'authenticated');
create policy "tarifa_flete_admin_insert" on public.tarifa_flete
  for insert with check (public.is_admin());

create policy "tarifa_descarga_select" on public.tarifa_descarga
  for select using (auth.role() = 'authenticated');
create policy "tarifa_descarga_admin_insert" on public.tarifa_descarga
  for insert with check (public.is_admin());

create policy "tarifa_almacenamiento_select" on public.tarifa_almacenamiento
  for select using (auth.role() = 'authenticated');
create policy "tarifa_almacenamiento_admin_insert" on public.tarifa_almacenamiento
  for insert with check (public.is_admin());

-- Histórico de naves: lectura para autenticados; admin corrige datos históricos.
create policy "naves_historico_select" on public.naves_historico
  for select using (auth.role() = 'authenticated');
create policy "naves_historico_admin_write" on public.naves_historico
  for all using (public.is_admin()) with check (public.is_admin());

-- Simulaciones: cualquier autenticado ve todas (tablero compartido de
-- trazabilidad); solo puede insertar las suyas; nadie edita/borra salvo admin
-- (integridad del registro de auditoría).
create policy "simulaciones_select" on public.simulaciones
  for select using (auth.role() = 'authenticated');
create policy "simulaciones_insert_own" on public.simulaciones
  for insert with check (analista_id = auth.uid());
create policy "simulaciones_admin_delete" on public.simulaciones
  for delete using (public.is_admin());
