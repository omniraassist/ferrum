-- Ferrum: arreglo de la verificación (el parámetro chocaba con la columna "nombre").
-- Pegar entero en Supabase → SQL Editor → Run.
create or replace function public.puede_ver_video(nombre text) returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.intentos i where i.ruta = $1 and (
  i.usuario = (select auth.uid())
  or public.es_staff(i.gym)
  or (select p.gimnasio from public.perfiles p where p.id = (select auth.uid())) = i.gym)); $$;
