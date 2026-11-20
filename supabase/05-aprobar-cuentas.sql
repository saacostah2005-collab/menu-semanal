-- =====================================================================
--  WeekMenuIA — ajuste 5: el administrador aprueba cada cuenta
--
--  • Cada persona que se registra queda "pendiente" hasta que el
--    administrador la aprueba en admin.html.
--  • Estados: 'pendiente' (recién registrada), 'activa', 'bloqueada'.
--  • Mientras no esté activa no ve ni cambia nada (ni crea hogar), así
--    que los 14 días gratis empiezan cuando se aprueba y crea su hogar.
--  • Todas las personas que ya existían quedan ACTIVAS.
--  • El administrador siempre cuenta como activo y no se puede bloquear.
--
--  Cómo usarlo: Supabase → SQL Editor → New query → pegar todo → Run.
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================


-- 1. Tabla de cuentas -------------------------------------------------

create table if not exists public.cuentas (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  email        text not null default '',
  estado       text not null default 'pendiente'
               check (estado in ('pendiente', 'activa', 'bloqueada')),
  creado_en    timestamptz not null default now(),
  revisado_en  timestamptz
);

alter table public.cuentas enable row level security;

drop policy if exists cuentas_ver on public.cuentas;
create policy cuentas_ver on public.cuentas for select to authenticated
  using (user_id = auth.uid() or public.es_admin());

grant select on public.cuentas to authenticated;

-- Las personas que ya existían quedan activas
insert into public.cuentas (user_id, email, estado, creado_en, revisado_en)
select u.id, coalesce(u.email, ''), 'activa', u.created_at, now()
from auth.users u
on conflict (user_id) do nothing;


-- 2. Cada registro nuevo crea su cuenta "pendiente" -------------------

create or replace function public.nueva_cuenta()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.cuentas (user_id, email) values (new.id, coalesce(new.email, ''))
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function public.nueva_cuenta();


-- 3. ¿En qué estado está mi cuenta? -----------------------------------

create or replace function public.mi_cuenta()
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when exists (select 1 from public.admins where user_id = auth.uid()) then 'activa'
    else coalesce((select estado from public.cuentas where user_id = auth.uid()), 'pendiente')
  end
$$;

-- El hogar de la persona: solo si su cuenta está activa.
-- Como todas las reglas de seguridad usan mi_hogar(), una cuenta pendiente
-- o bloqueada no ve ni cambia nada.
create or replace function public.mi_hogar()
returns uuid
language sql stable security definer set search_path = public
as $$
  select hogar_id from public.miembros
  where user_id = auth.uid() and public.mi_cuenta() = 'activa'
$$;


-- 4. Crear hogar / unirse: solo con la cuenta activa ------------------

create or replace function public.crear_hogar(p_nombre text)
returns public.hogares
language plpgsql security definer set search_path = public
as $$
declare h public.hogares;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if public.mi_cuenta() <> 'activa' then raise exception 'Tu cuenta todavía no fue aprobada'; end if;
  if public.mi_hogar() is not null then raise exception 'Ya perteneces a un hogar'; end if;
  insert into public.hogares (nombre, creado_por)
    values (trim(p_nombre), auth.uid()) returning * into h;
  insert into public.miembros (hogar_id, user_id, rol) values (h.id, auth.uid(), 'dueño');
  return h;
end $$;

create or replace function public.unirse_hogar(p_codigo text)
returns public.hogares
language plpgsql security definer set search_path = public
as $$
declare h public.hogares;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if public.mi_cuenta() <> 'activa' then raise exception 'Tu cuenta todavía no fue aprobada'; end if;
  if public.mi_hogar() is not null then raise exception 'Ya perteneces a un hogar'; end if;
  select * into h from public.hogares where codigo_invitacion = upper(trim(p_codigo));
  if h.id is null then raise exception 'Código de invitación no válido'; end if;
  if (select count(*) from public.miembros where hogar_id = h.id) >= 6 then
    raise exception 'Este hogar ya tiene el máximo de 6 personas';
  end if;
  insert into public.miembros (hogar_id, user_id, rol) values (h.id, auth.uid(), 'miembro');
  return h;
end $$;


-- 5. ADMIN: lista de cuentas y cambiar su estado ----------------------

create or replace function public.admin_cuentas()
returns table (user_id uuid, email text, estado text, creado_en timestamptz, revisado_en timestamptz,
               ultimo_ingreso timestamptz, correo_confirmado boolean, hogar text, rol text, es_admin boolean)
language sql stable security definer set search_path = public
as $$
  select c.user_id, coalesce(u.email, c.email), c.estado, c.creado_en, c.revisado_en,
         u.last_sign_in_at, u.email_confirmed_at is not null,
         h.nombre, m.rol, a.user_id is not null
  from public.cuentas c
  left join auth.users u      on u.id = c.user_id
  left join public.miembros m on m.user_id = c.user_id
  left join public.hogares h  on h.id = m.hogar_id
  left join public.admins a   on a.user_id = c.user_id
  where public.es_admin()
  order by c.creado_en desc
$$;

create or replace function public.admin_cambiar_cuenta(p_user uuid, p_estado text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then raise exception 'Solo el administrador puede cambiar cuentas'; end if;
  if p_estado not in ('activa', 'bloqueada') then raise exception 'Estado no válido'; end if;
  if p_estado = 'bloqueada' and exists (select 1 from public.admins where user_id = p_user) then
    raise exception 'No se puede bloquear al administrador';
  end if;
  update public.cuentas set estado = p_estado, revisado_en = now() where user_id = p_user;
  if not found then raise exception 'Cuenta no encontrada'; end if;
end $$;


-- 6. Permisos ---------------------------------------------------------

revoke all on function public.nueva_cuenta()                     from public, anon, authenticated;
revoke all on function public.mi_cuenta()                        from public, anon;
revoke all on function public.mi_hogar()                         from public, anon;
revoke all on function public.crear_hogar(text)                  from public, anon;
revoke all on function public.unirse_hogar(text)                 from public, anon;
revoke all on function public.admin_cuentas()                    from public, anon;
revoke all on function public.admin_cambiar_cuenta(uuid, text)   from public, anon;

grant execute on function public.mi_cuenta()                      to authenticated;
grant execute on function public.mi_hogar()                       to authenticated;
grant execute on function public.crear_hogar(text)                to authenticated;
grant execute on function public.unirse_hogar(text)               to authenticated;
grant execute on function public.admin_cuentas()                  to authenticated;
grant execute on function public.admin_cambiar_cuenta(uuid, text) to authenticated;
