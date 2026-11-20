-- =====================================================================
--  WeekMenuIA — ajuste 4: compras del mes
--  Además de la lista semanal, cada hogar tiene una "lista del mes"
--  (arroz, azúcar, aceite…). Al guardarla en el historial, su monto se
--  suma al mes en que se hizo la compra.
--    • lista_items.tipo: 'semanal' o 'mensual' (a qué lista pertenece)
--    • compras.tipo:     'semanal' o 'mensual' (qué se guardó)
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================

alter table public.lista_items add column if not exists tipo text not null default 'semanal'
  check (tipo in ('semanal', 'mensual'));
alter table public.compras add column if not exists tipo text not null default 'semanal'
  check (tipo in ('semanal', 'mensual'));

-- "Guardar en historial" ahora también recibe el tipo de compra
drop function if exists public.guardar_compra(date, date, jsonb);

create or replace function public.guardar_compra(p_semana_inicio date, p_semana_fin date, p_items jsonb,
                                                 p_tipo text default 'semanal')
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  h uuid := public.mi_hogar();
  c uuid;
begin
  if not public.puede_editar(h) then raise exception 'Tu suscripción venció: el historial es de solo lectura'; end if;
  if coalesce(p_tipo, '') not in ('semanal', 'mensual') then raise exception 'Tipo de compra no válido'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La lista está vacía';
  end if;

  insert into public.compras (hogar_id, semana_inicio, semana_fin, total, num_items, tipo)
  select h, p_semana_inicio, p_semana_fin,
         coalesce(sum(nullif(x->>'precio', '')::numeric), 0), count(*), p_tipo
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

revoke all on function public.guardar_compra(date, date, jsonb, text) from public, anon;
grant execute on function public.guardar_compra(date, date, jsonb, text) to authenticated;
