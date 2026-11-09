-- Ferrum: la app guarda sus propios errores para arreglarlos sin esperar a que alguien los cuente.
-- Pegar entero en Supabase → SQL Editor → Run. Solo Xavitus puede leerlos.

create table public.errores (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references auth.users (id) on delete cascade,
  version integer,
  vista text check (char_length(vista) <= 40),
  mensaje text not null check (char_length(mensaje) <= 500),
  pila text check (char_length(pila) <= 2000),
  creado timestamptz not null default now()
);
create index errores_creado on public.errores (creado desc);
alter table public.errores enable row level security;
create policy "avisar de un error" on public.errores for insert to authenticated with check (usuario = (select auth.uid()));
create policy "admin lee errores" on public.errores for select to authenticated using ((select auth.uid()) = 'c61a90cb-1fe2-4a4a-bd92-005937218ed9'::uuid);
create policy "admin borra errores" on public.errores for delete to authenticated using ((select auth.uid()) = 'c61a90cb-1fe2-4a4a-bd92-005937218ed9'::uuid);
