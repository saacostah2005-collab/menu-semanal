-- =====================================================================
--  WeekMenuIA — ajuste 6: la lista semanal tiene su propia semana
--    • hogares.lista_semana: lunes de la semana a la que pertenece la
--      lista semanal (la misma para toda la familia).
--    • compras.cerrada: la semana se cerró con «Guardar y cerrar».
--    • guardar_semana: guarda la lista en el historial de ESA semana
--      reemplazando lo que había (ya no se duplica). Si se pide cerrar,
--      además vacía la lista y la pasa a la semana siguiente.
--    • reabrir_semana: devuelve los productos de una semana cerrada a la
--      lista para seguir editándolos.
--    • fijar_semana_lista: cambiar a qué semana pertenece la lista.
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================

alter table public.hogares add column if not exists lista_semana date;
alter table public.compras add column if not exists cerrada boolean not null default false;

-- Lunes de la semana de una fecha
create or replace function public.lunes_de(d date)
returns date language sql immutable
as $$ select (d - ((extract(isodow from d)::int - 1)))::date $$;

-- Cambiar la semana de la lista
create or replace function public.fijar_semana_lista(p_semana date)
returns date
language plpgsql security definer set search_path = public
as $$
declare h uuid := public.mi_hogar(); s date := public.lunes_de(p_semana);
begin
  if not public.puede_editar(h) then raise exception 'No puedes cambiar este hogar'; end if;
  update public.hogares set lista_semana = s where id = h;
  return s;
end $$;

-- Guardar la lista semanal en el historial (y opcionalmente cerrar la semana)
create or replace function public.guardar_semana(p_semana date, p_items jsonb, p_cerrar boolean default false)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  h uuid := public.mi_hogar();
  s date := public.lunes_de(p_semana);
  c uuid;
begin
  if not public.puede_editar(h) then raise exception 'Tu suscripción venció: el historial es de solo lectura'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La lista está vacía';
  end if;

  -- Una sola compra por semana: se reemplaza la anterior
  delete from public.compras where hogar_id = h and tipo = 'semanal' and semana_inicio = s;

  insert into public.compras (hogar_id, semana_inicio, semana_fin, total, num_items, tipo, cerrada)
  select h, s, s + 6, coalesce(sum(nullif(x->>'precio', '')::numeric), 0), count(*), 'semanal', coalesce(p_cerrar, false)
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

  if coalesce(p_cerrar, false) then
    delete from public.lista_items where hogar_id = h and tipo = 'semanal';
    update public.hogares set lista_semana = s + 7 where id = h;
  else
    update public.hogares set lista_semana = s where id = h;
  end if;

  return c;
end $$;

-- Volver a abrir una semana cerrada: sus productos regresan a la lista
create or replace function public.reabrir_semana(p_compra uuid)
returns date
language plpgsql security definer set search_path = public
as $$
declare
  h uuid := public.mi_hogar();
  cp public.compras;
begin
  if not public.puede_editar(h) then raise exception 'No puedes cambiar este hogar'; end if;
  select * into cp from public.compras where id = p_compra and hogar_id = h and tipo = 'semanal';
  if cp.id is null then raise exception 'No encontramos esa semana'; end if;
  if exists (select 1 from public.lista_items where hogar_id = h and tipo = 'semanal') then
    raise exception 'LISTA_CON_PRODUCTOS';
  end if;

  insert into public.lista_items (hogar_id, nombre, precio, comprado, categoria, orden, tipo)
  select h, ci.nombre, ci.precio, ci.comprado,
         coalesce(ci.categoria, ''),
         extract(epoch from now()) + (row_number() over (order by ci.ctid)) / 1000.0,
         'semanal'
  from public.compra_items ci
  where ci.compra_id = cp.id and coalesce(ci.nombre, '') <> '';

  update public.compras set cerrada = false where id = cp.id;
  update public.hogares set lista_semana = cp.semana_inicio where id = h;
  return cp.semana_inicio;
end $$;

revoke all on function public.lunes_de(date)                        from public, anon;
revoke all on function public.fijar_semana_lista(date)              from public, anon;
revoke all on function public.guardar_semana(date, jsonb, boolean)  from public, anon;
revoke all on function public.reabrir_semana(uuid)                  from public, anon;
grant execute on function public.lunes_de(date)                       to authenticated;
grant execute on function public.fijar_semana_lista(date)             to authenticated;
grant execute on function public.guardar_semana(date, jsonb, boolean) to authenticated;
grant execute on function public.reabrir_semana(uuid)                 to authenticated;
