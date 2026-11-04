-- Ferrum: seguir a gente, fuerza y comentarios.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-cuentas.sql.
-- Las tablas usan id propio a propósito: con clave compuesta, la API vería una relación
-- ambigua entre perfiles y publicaciones y dejaría de cargar las publicaciones.

create table public.seguimientos (
  id uuid primary key default gen_random_uuid(),
  seguidor uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  seguido uuid not null references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (seguidor, seguido),
  check (seguidor <> seguido)
);
create index seguimientos_seguido on public.seguimientos (seguido);

create table public.fuerzas (
  id uuid primary key default gen_random_uuid(),
  publicacion uuid not null references public.publicaciones (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (publicacion, usuario)
);

create table public.comentarios (
  id uuid primary key default gen_random_uuid(),
  publicacion uuid not null references public.publicaciones (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  texto text not null check (char_length(btrim(texto)) between 1 and 300),
  creado timestamptz not null default now()
);
create index comentarios_publicacion on public.comentarios (publicacion, creado);

alter table public.seguimientos enable row level security;
alter table public.fuerzas enable row level security;
alter table public.comentarios enable row level security;

create policy "leer seguimientos" on public.seguimientos for select to authenticated using (true);
create policy "seguir" on public.seguimientos for insert to authenticated with check (seguidor = (select auth.uid()));
create policy "dejar de seguir" on public.seguimientos for delete to authenticated using (seguidor = (select auth.uid()));

create policy "leer fuerzas" on public.fuerzas for select to authenticated using (true);
create policy "dar fuerza" on public.fuerzas for insert to authenticated with check (usuario = (select auth.uid()));
create policy "quitar fuerza" on public.fuerzas for delete to authenticated using (usuario = (select auth.uid()));

create policy "leer comentarios" on public.comentarios for select to authenticated using (true);
create policy "comentar" on public.comentarios for insert to authenticated with check (usuario = (select auth.uid()));
create policy "borrar comentario" on public.comentarios for delete to authenticated using (
  usuario = (select auth.uid())
  or exists (select 1 from public.publicaciones p where p.id = publicacion and p.usuario = (select auth.uid()))
);
