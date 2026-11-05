-- Ferrum: desafíos entre usuarios.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-clubs.sql.

create table public.desafios (
  id uuid primary key default gen_random_uuid(),
  retador uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  rival uuid not null references public.perfiles (id) on delete cascade,
  publicacion uuid references public.publicaciones (id) on delete set null,
  titulo text not null check (char_length(titulo) <= 120),
  estado text not null default 'activo' check (estado in ('activo', 'ganado', 'perdido')),
  puntos_retador integer not null default 0 check (puntos_retador between 0 and 100),
  puntos_rival integer not null default 0 check (puntos_rival between 0 and 100),
  creado timestamptz not null default now(),
  resuelto timestamptz,
  check (retador <> rival)
);
create index desafios_creado on public.desafios (creado desc);
create index desafios_rival on public.desafios (rival);
create unique index desafios_uno_activo on public.desafios (retador, publicacion) where estado = 'activo';

alter table public.desafios enable row level security;

create policy "leer desafios" on public.desafios for select to authenticated using (true);
create policy "crear desafio" on public.desafios for insert to authenticated with check (retador = (select auth.uid()));
create policy "resolver mi desafio" on public.desafios for update to authenticated using (retador = (select auth.uid())) with check (retador = (select auth.uid()));
create policy "borrar mi desafio" on public.desafios for delete to authenticated using (retador = (select auth.uid()));
