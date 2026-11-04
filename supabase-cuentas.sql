-- Ferrum: copia privada de los entrenos y borrado de cuenta.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase.sql.

create table public.sesiones (
  usuario uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null check (char_length(id) <= 60),
  ts bigint not null,
  doc jsonb check (pg_column_size(doc) < 200000),
  primary key (usuario, id)
);

alter table public.sesiones enable row level security;

create policy "leer mis sesiones" on public.sesiones for select to authenticated using (usuario = (select auth.uid()));
create policy "crear mis sesiones" on public.sesiones for insert to authenticated with check (usuario = (select auth.uid()));
create policy "cambiar mis sesiones" on public.sesiones for update to authenticated using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));
create policy "borrar mis sesiones" on public.sesiones for delete to authenticated using (usuario = (select auth.uid()));

create function public.borrar_mi_cuenta() returns void
language sql security definer set search_path = ''
as $$ delete from auth.users where id = (select auth.uid()); $$;

revoke execute on function public.borrar_mi_cuenta() from public, anon;
grant execute on function public.borrar_mi_cuenta() to authenticated;
