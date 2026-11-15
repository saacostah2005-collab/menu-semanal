-- =====================================================================
--  WeekMenuIA — ajuste 3: presupuesto mensual del hogar
--  Toda la familia ve el mismo presupuesto; cualquiera del hogar lo
--  puede cambiar (si la suscripción está al día).
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================

alter table public.hogares add column if not exists presupuesto_mensual numeric(10,2)
  check (presupuesto_mensual is null or presupuesto_mensual > 0);

create or replace function public.fijar_presupuesto(p_monto numeric)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare h uuid := public.mi_hogar();
begin
  if not public.puede_editar(h) then raise exception 'No puedes cambiar este hogar'; end if;
  update public.hogares set presupuesto_mensual = nullif(round(p_monto, 2), 0) where id = h;
  return p_monto;
end $$;

revoke all on function public.fijar_presupuesto(numeric) from public, anon;
grant execute on function public.fijar_presupuesto(numeric) to authenticated;
