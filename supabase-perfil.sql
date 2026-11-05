-- Ferrum: perfil completo, "En el gym ahora", bloqueos y denuncias de usuarios.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-ligas.sql.

alter table public.perfiles
  add column avatar text check (avatar ~ '^[0-9a-f-]{36}/[a-z0-9]+\.jpg$'),
  add column bio text check (char_length(bio) <= 160),
  add column gimnasio text check (char_length(gimnasio) <= 60),
  add column objetivo text check (char_length(objetivo) <= 60),
  add column arroba text check (arroba ~ '^[a-z0-9_]{3,20}$');
create unique index perfiles_arroba_unica on public.perfiles (arroba) where arroba is not null;

create table public.entrenando (
  usuario uuid primary key default auth.uid() references public.perfiles (id) on delete cascade,
  titulo text not null check (char_length(titulo) <= 120),
  inicio timestamptz not null default now(),
  visto timestamptz not null default now()
);
alter table public.entrenando enable row level security;
create policy "ver quien entrena" on public.entrenando for select to authenticated using (true);
create policy "avisar que entreno" on public.entrenando for insert to authenticated with check (usuario = (select auth.uid()));
create policy "seguir entrenando" on public.entrenando for update to authenticated using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));
create policy "dejar de entrenar" on public.entrenando for delete to authenticated using (usuario = (select auth.uid()));

create table public.bloqueos (
  id uuid primary key default gen_random_uuid(),
  bloqueador uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  bloqueado uuid not null references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (bloqueador, bloqueado),
  check (bloqueador <> bloqueado)
);
alter table public.bloqueos enable row level security;
create policy "ver mis bloqueos" on public.bloqueos for select to authenticated using (bloqueador = (select auth.uid()) or bloqueado = (select auth.uid()));
create policy "bloquear" on public.bloqueos for insert to authenticated with check (bloqueador = (select auth.uid()));
create policy "desbloquear" on public.bloqueos for delete to authenticated using (bloqueador = (select auth.uid()));

create table public.denuncias_usuario (
  id uuid primary key default gen_random_uuid(),
  denunciado uuid not null references public.perfiles (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  motivo text check (char_length(motivo) <= 200),
  creado timestamptz not null default now(),
  unique (denunciado, usuario)
);
alter table public.denuncias_usuario enable row level security;
create policy "denunciar usuario" on public.denuncias_usuario for insert to authenticated with check (usuario = (select auth.uid()));

-- el bloqueo se aplica en el servidor: quien está bloqueado no puede interactuar
create function public.hay_bloqueo(otro uuid) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.bloqueos b where (b.bloqueador = (select auth.uid()) and b.bloqueado = otro) or (b.bloqueado = (select auth.uid()) and b.bloqueador = otro)); $$;
revoke execute on function public.hay_bloqueo(uuid) from public, anon;
grant execute on function public.hay_bloqueo(uuid) to authenticated;

drop policy "comentar" on public.comentarios;
create policy "comentar" on public.comentarios for insert to authenticated with check (
  usuario = (select auth.uid()) and not public.hay_bloqueo((select p.usuario from public.publicaciones p where p.id = publicacion)));
drop policy "dar fuerza" on public.fuerzas;
create policy "dar fuerza" on public.fuerzas for insert to authenticated with check (
  usuario = (select auth.uid()) and not public.hay_bloqueo((select p.usuario from public.publicaciones p where p.id = publicacion)));
drop policy "seguir" on public.seguimientos;
create policy "seguir" on public.seguimientos for insert to authenticated with check (seguidor = (select auth.uid()) and not public.hay_bloqueo(seguido));
drop policy "crear desafio" on public.desafios;
create policy "crear desafio" on public.desafios for insert to authenticated with check (retador = (select auth.uid()) and not public.hay_bloqueo(rival));
drop policy "invitar" on public.parejas;
create policy "invitar" on public.parejas for insert to authenticated with check (a = (select auth.uid()) and estado = 'pendiente' and not public.hay_bloqueo(b));

-- al bloquear se rompen seguimientos y racha entre ambos
create function privado.t_bloqueo() returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.seguimientos where (seguidor = new.bloqueador and seguido = new.bloqueado) or (seguidor = new.bloqueado and seguido = new.bloqueador);
  delete from public.parejas where (a = new.bloqueador and b = new.bloqueado) or (a = new.bloqueado and b = new.bloqueador);
  return new;
end;
$$;
create trigger al_bloquear after insert on public.bloqueos for each row execute function privado.t_bloqueo();
