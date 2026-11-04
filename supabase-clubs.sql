-- Ferrum: clubs y rutinas compartidas.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-media.sql.
-- Tablas con id propio: una clave compuesta haría ambiguas las relaciones de la API.

create table public.clubes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (char_length(btrim(nombre)) between 3 and 40),
  creador uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now()
);
create unique index clubes_nombre_unico on public.clubes (lower(btrim(nombre)));

create table public.club_miembros (
  id uuid primary key default gen_random_uuid(),
  club uuid not null references public.clubes (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (club, usuario)
);

create table public.rutinas (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  nombre text not null check (char_length(btrim(nombre)) between 3 and 60),
  datos jsonb not null check (pg_column_size(datos) < 30000),
  creado timestamptz not null default now()
);
create index rutinas_creado on public.rutinas (creado desc);

alter table public.clubes enable row level security;
alter table public.club_miembros enable row level security;
alter table public.rutinas enable row level security;

create policy "leer clubes" on public.clubes for select to authenticated using (true);
create policy "crear club" on public.clubes for insert to authenticated with check (creador = (select auth.uid()));
create policy "borrar mi club" on public.clubes for delete to authenticated using (creador = (select auth.uid()));

create policy "leer miembros" on public.club_miembros for select to authenticated using (true);
create policy "unirme" on public.club_miembros for insert to authenticated with check (usuario = (select auth.uid()));
create policy "salir" on public.club_miembros for delete to authenticated using (usuario = (select auth.uid()));

create policy "leer rutinas" on public.rutinas for select to authenticated using (true);
create policy "crear rutina" on public.rutinas for insert to authenticated with check (usuario = (select auth.uid()));
create policy "borrar mi rutina" on public.rutinas for delete to authenticated using (usuario = (select auth.uid()));
