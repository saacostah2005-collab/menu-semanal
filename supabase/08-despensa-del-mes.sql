-- =====================================================================
--  WeekMenuIA — ajuste 8: despensa del mes
--  Cada producto de la lista «Del mes» guarda:
--    • comprado_en:  el día que lo compraron
--    • terminado_en: el día que se acabó (vacío = aún hay en stock)
--  Los productos comprados se quedan en la lista como registro, así el
--  historial suma solo lo que compraron cada mes y se sabe cuánto duró.
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================

alter table public.lista_items add column if not exists comprado_en  date;
alter table public.lista_items add column if not exists terminado_en date;

alter table public.lista_items drop constraint if exists lista_items_fechas_ok;
alter table public.lista_items add constraint lista_items_fechas_ok
  check (terminado_en is null or comprado_en is null or terminado_en >= comprado_en);

-- Lo que ya estaba marcado como comprado en la lista del mes: comprado hoy
update public.lista_items
   set comprado_en = current_date
 where tipo = 'mensual' and comprado and comprado_en is null;
