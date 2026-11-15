-- =====================================================================
--  WeekMenuIA — ajuste 2 (historial antiguo de Google Sheets)
--  Los primeros guardados del historial solo tenían una lista de
--  ingredientes en texto y sin total. Para conservarlos:
--    • compras.ingredientes_texto: ese texto
--    • compras.total puede quedar vacío ("sin monto")
--  Se puede ejecutar varias veces sin problema.
-- =====================================================================

alter table public.compras add column if not exists ingredientes_texto text not null default '';
alter table public.compras alter column total drop not null;
alter table public.compras alter column total drop default;
