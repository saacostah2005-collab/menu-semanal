-- =====================================================================
--  WeekMenuIA — ajuste 7: cada producto de la lista semanal sabe a qué
--  semana pertenece. Así se puede ver la lista de cualquier semana con las
--  flechas y, al volver a abrir una semana cerrada, sus productos NO se
--  mezclan con los de otra semana.
--    • lista_items.semana: lunes de la semana del producto (lista semanal)
--    • Si una página antigua agrega un producto sin semana, se le pone la
--      semana de la lista del hogar (trigger).
--    • guardar_semana: al cerrar, solo quita los productos de ESA semana.
--    • reabrir_semana: los productos vuelven con su semana; ya no hace
--      falta vaciar la lista antes.
--  Requiere haber corrido 06-cerrar-semana.sql. Se puede ejecutar varias
--  veces sin problema.
-- =====================================================================

alter table public.lista_items add column if not exists semana date;

-- Los productos que ya están en la lista son de la semana de la lista
update public.lista_items li
   set semana = coalesce(h.lista_semana, public.lunes_de(current_date))
  from public.hogares h
 where h.id = li.hogar_id and li.tipo = 'semanal' and li.semana is null;

-- Producto nuevo sin semana: la de la lista del hogar
create or replace function public.lista_items_semana()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.tipo = 'semanal' then
    if new.semana is null then
      select coalesce(lista_semana, public.lunes_de(current_date)) into new.semana
      from public.hogares where id = new.hogar_id;
    else
      new.semana := public.lunes_de(new.semana);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists lista_items_semana on public.lista_items;
create trigger lista_items_semana before insert on public.lista_items
  for each row execute function public.lista_items_semana();

create index if not exists lista_items_semana_idx on public.lista_items (hogar_id, tipo, semana);

-- Guardar (y opcionalmente cerrar) una semana
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
    delete from public.lista_items where hogar_id = h and tipo = 'semanal' and semana = s;
    update public.hogares set lista_semana = s + 7 where id = h and (lista_semana is null or lista_semana <= s);
  end if;

  return c;
end $$;

-- Volver a abrir una semana: sus productos regresan a la lista CON SU SEMANA
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

  -- Si esa semana ya tiene productos en la lista, ya está abierta: no se duplica
  if not exists (select 1 from public.lista_items
                 where hogar_id = h and tipo = 'semanal' and semana = cp.semana_inicio) then
    insert into public.lista_items (hogar_id, nombre, precio, comprado, categoria, orden, tipo, semana)
    select h, ci.nombre, ci.precio, ci.comprado,
           coalesce(ci.categoria, ''),
           extract(epoch from now()) + (row_number() over (order by ci.ctid)) / 1000.0,
           'semanal', cp.semana_inicio
    from public.compra_items ci
    where ci.compra_id = cp.id and coalesce(ci.nombre, '') <> '';
  end if;

  update public.compras set cerrada = false where id = cp.id;
  return cp.semana_inicio;
end $$;

revoke all on function public.lista_items_semana()                  from public, anon;
revoke all on function public.guardar_semana(date, jsonb, boolean)  from public, anon;
revoke all on function public.reabrir_semana(uuid)                  from public, anon;
grant execute on function public.guardar_semana(date, jsonb, boolean) to authenticated;
grant execute on function public.reabrir_semana(uuid)                 to authenticated;
