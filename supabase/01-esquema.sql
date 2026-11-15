-- =====================================================================
--  WeekMenuIA — Base de datos en Supabase (paso 1: tablas y seguridad)
--
--  Cómo usarlo:
--    Supabase → menú izquierdo "SQL Editor" → "New query" →
--    pega TODO este archivo → botón "Run".
--  Se puede volver a ejecutar sin romper nada (no borra datos).
--
--  Idea general:
--    • Cada cliente pertenece a un HOGAR (la familia comparte menú y lista).
--    • Row Level Security: cada persona solo ve y cambia los datos de su hogar.
--    • Si el hogar no pagó ("activo_hasta" ya pasó) queda en SOLO LECTURA.
--    • Pagos por Yape/Plin: el cliente registra su número de operación y el
--      administrador lo aprueba, lo que alarga "activo_hasta".
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tablas base: hogares, miembros y administradores
-- ---------------------------------------------------------------------

create table if not exists public.hogares (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null check (char_length(nombre) between 1 and 60),
  creado_por         uuid not null references auth.users(id),
  activo_hasta       date not null default (current_date + 14),   -- 14 días de prueba gratis
  lista_bloqueada    boolean not null default false,               -- interruptor "Editar lista"
  codigo_invitacion  text not null unique
                     default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  creado_en          timestamptz not null default now()
);

create table if not exists public.miembros (
  hogar_id   uuid not null references public.hogares(id) on delete cascade,
  user_id    uuid not null unique references auth.users(id) on delete cascade,  -- una persona = un hogar
  rol        text not null default 'miembro' check (rol in ('dueño', 'miembro')),
  unido_en   timestamptz not null default now(),
  primary key (hogar_id, user_id)
);

create table if not exists public.admins (
  user_id  uuid primary key references auth.users(id) on delete cascade
);


-- ---------------------------------------------------------------------
-- 2. Funciones de ayuda (las usan las reglas de seguridad)
-- ---------------------------------------------------------------------

-- El hogar de la persona que está usando la app
create or replace function public.mi_hogar()
returns uuid
language sql stable security definer set search_path = public
as $$
  select hogar_id from public.miembros where user_id = auth.uid()
$$;

-- ¿Es administrador (dueño del negocio)?
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

-- ¿Puede este hogar hacer cambios? (es su hogar y está al día con el pago)
create or replace function public.puede_editar(h uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.hogares
    where id = h and id = public.mi_hogar() and activo_hasta >= current_date
  )
$$;

-- ¿Puede cambiar la lista de compras? (además, que no esté bloqueada)
create or replace function public.puede_editar_lista(h uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.puede_editar(h)
     and not coalesce((select lista_bloqueada from public.hogares where id = h), true)
$$;


-- ---------------------------------------------------------------------
-- 3. Datos de cada hogar: menú, lista de compras, historial y pagos
-- ---------------------------------------------------------------------

create table if not exists public.menu_dias (
  id            uuid primary key default gen_random_uuid(),
  hogar_id      uuid not null default public.mi_hogar() references public.hogares(id) on delete cascade,
  fecha         date not null,
  desayuno      text not null default '',
  media_manana  text not null default '',
  almuerzo      text not null default '',
  cena          text not null default '',
  unique (hogar_id, fecha)
);

create table if not exists public.lista_items (
  id         uuid primary key default gen_random_uuid(),
  hogar_id   uuid not null default public.mi_hogar() references public.hogares(id) on delete cascade,
  nombre     text not null check (char_length(nombre) between 1 and 80),
  precio     numeric(10,2) check (precio is null or precio >= 0),
  comprado   boolean not null default false,
  categoria  text not null default '',
  orden      double precision not null default extract(epoch from now()),
  creado_en  timestamptz not null default now()
);
create index if not exists lista_items_hogar on public.lista_items (hogar_id, orden);

-- Historial: un registro por cada "Guardar en historial"
create table if not exists public.compras (
  id             uuid primary key default gen_random_uuid(),
  hogar_id       uuid not null default public.mi_hogar() references public.hogares(id) on delete cascade,
  fecha          timestamptz not null default now(),
  semana_inicio  date,
  semana_fin     date,
  total          numeric(10,2) not null default 0,
  num_items      integer not null default 0
);
create index if not exists compras_hogar on public.compras (hogar_id, fecha desc);

-- Detalle del historial: un ingrediente por fila
create table if not exists public.compra_items (
  id         uuid primary key default gen_random_uuid(),
  compra_id  uuid not null references public.compras(id) on delete cascade,
  hogar_id   uuid not null references public.hogares(id) on delete cascade,
  nombre     text not null,
  precio     numeric(10,2),
  comprado   boolean not null default false,
  categoria  text not null default ''
);
create index if not exists compra_items_compra on public.compra_items (compra_id);

-- Pagos por Yape / Plin (los revisa el administrador)
create table if not exists public.pagos (
  id                uuid primary key default gen_random_uuid(),
  hogar_id          uuid not null default public.mi_hogar() references public.hogares(id) on delete cascade,
  user_id           uuid not null default auth.uid() references auth.users(id),
  metodo            text not null check (metodo in ('yape', 'plin')),
  monto             numeric(10,2) not null check (monto > 0),
  numero_operacion  text not null check (char_length(numero_operacion) between 4 and 30),
  estado            text not null default 'pendiente' check (estado in ('pendiente', 'aprobado', 'rechazado')),
  meses             integer,
  creado_en         timestamptz not null default now(),
  revisado_en       timestamptz,
  unique (metodo, numero_operacion)   -- el mismo número de operación no se puede usar dos veces
);


-- ---------------------------------------------------------------------
-- 4. Row Level Security (cada hogar solo ve lo suyo)
-- ---------------------------------------------------------------------

alter table public.hogares      enable row level security;
alter table public.miembros     enable row level security;
alter table public.admins       enable row level security;
alter table public.menu_dias    enable row level security;
alter table public.lista_items  enable row level security;
alter table public.compras      enable row level security;
alter table public.compra_items enable row level security;
alter table public.pagos        enable row level security;

-- hogares: ver el propio (el admin ve todos). Los cambios van por funciones.
drop policy if exists hogares_ver on public.hogares;
create policy hogares_ver on public.hogares for select to authenticated
  using (id = public.mi_hogar() or public.es_admin());

-- miembros: ver a la gente de tu hogar
drop policy if exists miembros_ver on public.miembros;
create policy miembros_ver on public.miembros for select to authenticated
  using (hogar_id = public.mi_hogar() or public.es_admin());

-- admins: cada uno puede saber si él mismo es admin
drop policy if exists admins_ver on public.admins;
create policy admins_ver on public.admins for select to authenticated
  using (user_id = auth.uid());

-- menú: ver el de tu hogar; cambiarlo solo si el hogar está activo
drop policy if exists menu_ver on public.menu_dias;
create policy menu_ver on public.menu_dias for select to authenticated
  using (hogar_id = public.mi_hogar());
drop policy if exists menu_agregar on public.menu_dias;
create policy menu_agregar on public.menu_dias for insert to authenticated
  with check (public.puede_editar(hogar_id));
drop policy if exists menu_cambiar on public.menu_dias;
create policy menu_cambiar on public.menu_dias for update to authenticated
  using (public.puede_editar(hogar_id)) with check (public.puede_editar(hogar_id));
drop policy if exists menu_borrar on public.menu_dias;
create policy menu_borrar on public.menu_dias for delete to authenticated
  using (public.puede_editar(hogar_id));

-- lista de compras: ver la de tu hogar; cambiarla si está activo y sin bloqueo
drop policy if exists lista_ver on public.lista_items;
create policy lista_ver on public.lista_items for select to authenticated
  using (hogar_id = public.mi_hogar());
drop policy if exists lista_agregar on public.lista_items;
create policy lista_agregar on public.lista_items for insert to authenticated
  with check (public.puede_editar_lista(hogar_id));
drop policy if exists lista_cambiar on public.lista_items;
create policy lista_cambiar on public.lista_items for update to authenticated
  using (public.puede_editar_lista(hogar_id)) with check (public.puede_editar_lista(hogar_id));
drop policy if exists lista_borrar on public.lista_items;
create policy lista_borrar on public.lista_items for delete to authenticated
  using (public.puede_editar_lista(hogar_id));

-- historial: ver el de tu hogar; guardar va por la función guardar_compra; borrar si está activo
drop policy if exists compras_ver on public.compras;
create policy compras_ver on public.compras for select to authenticated
  using (hogar_id = public.mi_hogar());
drop policy if exists compras_borrar on public.compras;
create policy compras_borrar on public.compras for delete to authenticated
  using (public.puede_editar(hogar_id));
drop policy if exists compra_items_ver on public.compra_items;
create policy compra_items_ver on public.compra_items for select to authenticated
  using (hogar_id = public.mi_hogar());

-- pagos: ver los de tu hogar (admin ve todos); registrar uno nuevo como "pendiente"
drop policy if exists pagos_ver on public.pagos;
create policy pagos_ver on public.pagos for select to authenticated
  using (hogar_id = public.mi_hogar() or public.es_admin());
drop policy if exists pagos_registrar on public.pagos;
create policy pagos_registrar on public.pagos for insert to authenticated
  with check (hogar_id = public.mi_hogar() and user_id = auth.uid()
              and estado = 'pendiente' and meses is null and revisado_en is null);


-- ---------------------------------------------------------------------
-- 5. Acciones especiales (funciones que la página llama)
-- ---------------------------------------------------------------------

-- Crear mi hogar (la primera vez que alguien entra). Queda como dueño.
create or replace function public.crear_hogar(p_nombre text)
returns public.hogares
language plpgsql security definer set search_path = public
as $$
declare h public.hogares;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if public.mi_hogar() is not null then raise exception 'Ya perteneces a un hogar'; end if;
  insert into public.hogares (nombre, creado_por)
    values (trim(p_nombre), auth.uid()) returning * into h;
  insert into public.miembros (hogar_id, user_id, rol) values (h.id, auth.uid(), 'dueño');
  return h;
end $$;

-- Unirme al hogar de mi familia con el código de invitación
create or replace function public.unirse_hogar(p_codigo text)
returns public.hogares
language plpgsql security definer set search_path = public
as $$
declare h public.hogares;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if public.mi_hogar() is not null then raise exception 'Ya perteneces a un hogar'; end if;
  select * into h from public.hogares where codigo_invitacion = upper(trim(p_codigo));
  if h.id is null then raise exception 'Código de invitación no válido'; end if;
  if (select count(*) from public.miembros where hogar_id = h.id) >= 6 then
    raise exception 'Este hogar ya tiene el máximo de 6 personas';
  end if;
  insert into public.miembros (hogar_id, user_id, rol) values (h.id, auth.uid(), 'miembro');
  return h;
end $$;

-- Interruptor "Editar lista": bloquear o desbloquear la lista para toda la familia
create or replace function public.bloquear_lista(p_bloqueada boolean)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare h uuid := public.mi_hogar();
begin
  if not public.puede_editar(h) then raise exception 'No puedes cambiar este hogar'; end if;
  update public.hogares set lista_bloqueada = p_bloqueada where id = h;
  return p_bloqueada;
end $$;

-- Cambiar el nombre del hogar
create or replace function public.renombrar_hogar(p_nombre text)
returns void
language plpgsql security definer set search_path = public
as $$
declare h uuid := public.mi_hogar();
begin
  if h is null then raise exception 'No perteneces a un hogar'; end if;
  update public.hogares set nombre = trim(p_nombre) where id = h;
end $$;

-- "Guardar en historial": guarda el resumen y el detalle de una sola vez.
-- p_items = [{"nombre":"Pollo","precio":12.5,"comprado":true,"categoria":"Pollo"}, ...]
create or replace function public.guardar_compra(p_semana_inicio date, p_semana_fin date, p_items jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  h uuid := public.mi_hogar();
  c uuid;
begin
  if not public.puede_editar(h) then raise exception 'Tu suscripción venció: el historial es de solo lectura'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La lista está vacía';
  end if;

  insert into public.compras (hogar_id, semana_inicio, semana_fin, total, num_items)
  select h, p_semana_inicio, p_semana_fin,
         coalesce(sum(nullif(x->>'precio', '')::numeric), 0), count(*)
  from jsonb_array_elements(p_items) x
  returning id into c;

  insert into public.compra_items (compra_id, hogar_id, nombre, precio, comprado, categoria)
  select c, h,
         left(coalesce(x->>'nombre', ''), 80),
         nullif(x->>'precio', '')::numeric,
         coalesce((x->>'comprado')::boolean, false),
         coalesce(x->>'categoria', '')
  from jsonb_array_elements(p_items) x
  where coalesce(x->>'nombre', '') <> '';

  return c;
end $$;

-- ADMIN: aprobar un pago y alargar la suscripción del hogar
create or replace function public.aprobar_pago(p_pago uuid, p_meses integer default 1)
returns date
language plpgsql security definer set search_path = public
as $$
declare
  p public.pagos;
  nueva date;
begin
  if not public.es_admin() then raise exception 'Solo el administrador puede aprobar pagos'; end if;
  select * into p from public.pagos where id = p_pago for update;
  if p.id is null then raise exception 'Pago no encontrado'; end if;
  if p.estado <> 'pendiente' then raise exception 'Este pago ya fue revisado'; end if;

  update public.hogares
     set activo_hasta = (greatest(activo_hasta, current_date) + make_interval(months => p_meses))::date
   where id = p.hogar_id
  returning activo_hasta into nueva;

  update public.pagos set estado = 'aprobado', meses = p_meses, revisado_en = now() where id = p.id;
  return nueva;
end $$;

-- ADMIN: rechazar un pago (por ejemplo, si el número de operación no existe)
create or replace function public.rechazar_pago(p_pago uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then raise exception 'Solo el administrador puede rechazar pagos'; end if;
  update public.pagos set estado = 'rechazado', revisado_en = now()
   where id = p_pago and estado = 'pendiente';
end $$;


-- ---------------------------------------------------------------------
-- 6. Permisos (el proyecto se creó con "exponer tablas automáticamente"
--    apagado, así que se dan aquí uno por uno). Nadie sin iniciar sesión
--    ("anon") puede leer ni escribir nada.
-- ---------------------------------------------------------------------

grant usage on schema public to authenticated;

grant select                         on public.hogares      to authenticated;
grant select                         on public.miembros     to authenticated;
grant select                         on public.admins       to authenticated;
grant select, insert, update, delete on public.menu_dias    to authenticated;
grant select, insert, update, delete on public.lista_items  to authenticated;
grant select, delete                 on public.compras      to authenticated;
grant select                         on public.compra_items to authenticated;
grant select, insert                 on public.pagos        to authenticated;

revoke all on function public.mi_hogar()                         from public, anon;
revoke all on function public.es_admin()                         from public, anon;
revoke all on function public.puede_editar(uuid)                 from public, anon;
revoke all on function public.puede_editar_lista(uuid)           from public, anon;
revoke all on function public.crear_hogar(text)                  from public, anon;
revoke all on function public.unirse_hogar(text)                 from public, anon;
revoke all on function public.bloquear_lista(boolean)            from public, anon;
revoke all on function public.renombrar_hogar(text)              from public, anon;
revoke all on function public.guardar_compra(date, date, jsonb)  from public, anon;
revoke all on function public.aprobar_pago(uuid, integer)        from public, anon;
revoke all on function public.rechazar_pago(uuid)                from public, anon;

grant execute on function public.mi_hogar()                        to authenticated;
grant execute on function public.es_admin()                        to authenticated;
grant execute on function public.puede_editar(uuid)                to authenticated;
grant execute on function public.puede_editar_lista(uuid)          to authenticated;
grant execute on function public.crear_hogar(text)                 to authenticated;
grant execute on function public.unirse_hogar(text)                to authenticated;
grant execute on function public.bloquear_lista(boolean)           to authenticated;
grant execute on function public.renombrar_hogar(text)             to authenticated;
grant execute on function public.guardar_compra(date, date, jsonb) to authenticated;
grant execute on function public.aprobar_pago(uuid, integer)       to authenticated;
grant execute on function public.rechazar_pago(uuid)               to authenticated;


-- ---------------------------------------------------------------------
-- 7. Tiempo real: la lista y el bloqueo se actualizan solos en todos los
--    celulares del hogar (respeta las mismas reglas de seguridad).
-- ---------------------------------------------------------------------

do $$
begin
  begin alter publication supabase_realtime add table public.lista_items; exception when duplicate_object or undefined_object then null; end;
  begin alter publication supabase_realtime add table public.hogares;     exception when duplicate_object or undefined_object then null; end;
  begin alter publication supabase_realtime add table public.menu_dias;   exception when duplicate_object or undefined_object then null; end;
end $$;
