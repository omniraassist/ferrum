-- Ferrum: foto de club e invitaciones. Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-notificaciones.sql y supabase-perfil.sql.

alter table public.clubes add column foto text check (foto ~ '^[0-9a-f-]{36}/[a-z0-9]+\.jpg$');
create policy "cambiar mi club" on public.clubes for update to authenticated
  using (creador = (select auth.uid())) with check (creador = (select auth.uid()));

create table public.club_invitaciones (
  id uuid primary key default gen_random_uuid(),
  club uuid not null references public.clubes (id) on delete cascade,
  de uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  para uuid not null references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (club, para),
  check (de <> para)
);
alter table public.club_invitaciones enable row level security;
create policy "ver mis invitaciones" on public.club_invitaciones for select to authenticated
  using (de = (select auth.uid()) or para = (select auth.uid()));
create policy "invitar al club" on public.club_invitaciones for insert to authenticated with check (
  de = (select auth.uid()) and not public.hay_bloqueo(para)
  and exists (select 1 from public.club_miembros m where m.club = club_invitaciones.club and m.usuario = (select auth.uid())));
create policy "responder invitacion" on public.club_invitaciones for delete to authenticated
  using (de = (select auth.uid()) or para = (select auth.uid()));

create function privado.t_invitacion() returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.avisar(new.para, privado.nombre(new.de) || ' te invita a un club', (select nombre from public.clubes where id = new.club));
  return new;
end;
$$;
create trigger aviso_invitacion after insert on public.club_invitaciones for each row execute function privado.t_invitacion();
