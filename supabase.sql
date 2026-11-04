-- Ferrum: base de datos compartida (clasificación y publicaciones).
-- Pegar entero en Supabase → SQL Editor → Run.
-- Cada usuario entra con una sesión anónima: lee todo, pero solo escribe lo suyo.

create table public.perfiles (
  id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  nombre text not null check (char_length(btrim(nombre)) between 2 and 24),
  creado timestamptz not null default now()
);
create unique index perfiles_nombre_unico on public.perfiles (lower(btrim(nombre)));

create table public.marcas (
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  clave text not null check (char_length(clave) <= 80),
  nombre text not null check (char_length(nombre) <= 80),
  peso numeric not null check (peso > 0 and peso <= 1000),
  reps numeric not null check (reps > 0 and reps <= 200),
  rm numeric not null check (rm > 0 and rm <= 10000),
  fecha date not null,
  primary key (usuario, clave)
);
create index marcas_clave_rm on public.marcas (clave, rm desc);

create table public.publicaciones (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  sesion text not null check (char_length(sesion) <= 40),
  fecha date not null,
  titulo text not null check (char_length(titulo) <= 120),
  datos jsonb not null check (pg_column_size(datos) < 30000),
  creado timestamptz not null default now(),
  unique (usuario, sesion)
);
create index publicaciones_creado on public.publicaciones (creado desc);

alter table public.perfiles enable row level security;
alter table public.marcas enable row level security;
alter table public.publicaciones enable row level security;

create policy "leer perfiles" on public.perfiles for select to authenticated using (true);
create policy "crear mi perfil" on public.perfiles for insert to authenticated with check (id = (select auth.uid()));
create policy "borrar mi perfil" on public.perfiles for delete to authenticated using (id = (select auth.uid()));

create policy "leer marcas" on public.marcas for select to authenticated using (true);
create policy "crear mis marcas" on public.marcas for insert to authenticated with check (usuario = (select auth.uid()));
create policy "cambiar mis marcas" on public.marcas for update to authenticated using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));
create policy "borrar mis marcas" on public.marcas for delete to authenticated using (usuario = (select auth.uid()));

create policy "leer publicaciones" on public.publicaciones for select to authenticated using (true);
create policy "crear mis publicaciones" on public.publicaciones for insert to authenticated with check (usuario = (select auth.uid()));
create policy "cambiar mis publicaciones" on public.publicaciones for update to authenticated using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));
create policy "borrar mis publicaciones" on public.publicaciones for delete to authenticated using (usuario = (select auth.uid()));
