-- Ferrum: notificaciones en el móvil y rachas en pareja.
-- Plantilla sin secretos: __SECRETO__ se sustituye al ejecutarlo. Va después de supabase-desafios.sql.

create extension if not exists pg_net with schema extensions;

create table public.suscripciones (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) <= 800),
  p256dh text not null check (char_length(p256dh) <= 200),
  auth text not null check (char_length(auth) <= 100),
  creado timestamptz not null default now()
);
alter table public.suscripciones enable row level security;
create policy "ver mis suscripciones" on public.suscripciones for select to authenticated using (usuario = (select auth.uid()));
create policy "crear mi suscripcion" on public.suscripciones for insert to authenticated with check (usuario = (select auth.uid()));
create policy "cambiar mi suscripcion" on public.suscripciones for update to authenticated using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));
create policy "borrar mi suscripcion" on public.suscripciones for delete to authenticated using (usuario = (select auth.uid()));

create table public.parejas (
  id uuid primary key default gen_random_uuid(),
  a uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  b uuid not null references public.perfiles (id) on delete cascade,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'activa')),
  creado timestamptz not null default now(),
  check (a <> b)
);
create unique index parejas_unica on public.parejas (least(a, b), greatest(a, b));
alter table public.parejas enable row level security;
create policy "leer parejas" on public.parejas for select to authenticated using (true);
create policy "invitar" on public.parejas for insert to authenticated with check (a = (select auth.uid()) and estado = 'pendiente');
create policy "aceptar" on public.parejas for update to authenticated using (b = (select auth.uid())) with check (b = (select auth.uid()));
create policy "romper" on public.parejas for delete to authenticated using (a = (select auth.uid()) or b = (select auth.uid()));

create schema if not exists privado;
revoke all on schema privado from public, anon, authenticated;

create function privado.avisar(destino uuid, titulo text, cuerpo text) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://gtwtowgamogybcbtlvwq.supabase.co/functions/v1/avisar',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-ferrum', '__SECRETO__'),
    body := jsonb_build_object('usuario', destino, 'titulo', titulo, 'cuerpo', cuerpo)
  );
exception when others then null; -- un aviso fallido nunca debe impedir guardar
end;
$$;

create function privado.nombre(u uuid) returns text language sql security definer set search_path = ''
as $$ select coalesce((select nombre from public.perfiles where id = u), 'Alguien'); $$;

create function privado.t_fuerza() returns trigger language plpgsql security definer set search_path = ''
as $$
declare d uuid; t text;
begin
  select usuario, titulo into d, t from public.publicaciones where id = new.publicacion;
  if d is not null and d <> new.usuario then perform privado.avisar(d, privado.nombre(new.usuario) || ' te ha dado fuerza', t); end if;
  return new;
end;
$$;
create trigger aviso_fuerza after insert on public.fuerzas for each row execute function privado.t_fuerza();

create function privado.t_comentario() returns trigger language plpgsql security definer set search_path = ''
as $$
declare d uuid;
begin
  select usuario into d from public.publicaciones where id = new.publicacion;
  if d is not null and d <> new.usuario then perform privado.avisar(d, privado.nombre(new.usuario) || ' ha comentado', left(new.texto, 120)); end if;
  return new;
end;
$$;
create trigger aviso_comentario after insert on public.comentarios for each row execute function privado.t_comentario();

create function privado.t_seguir() returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.avisar(new.seguido, privado.nombre(new.seguidor) || ' te sigue', 'Entra a ver su perfil');
  return new;
end;
$$;
create trigger aviso_seguir after insert on public.seguimientos for each row execute function privado.t_seguir();

create function privado.t_desafio() returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform privado.avisar(new.rival, privado.nombre(new.retador) || ' ha desafiado tu sesión', new.titulo);
  elsif old.estado = 'activo' and new.estado = 'ganado' then
    perform privado.avisar(new.rival, privado.nombre(new.retador) || ' ha superado tu sesión', new.puntos_retador || '–' || new.puntos_rival || '. Toca revancha.');
  elsif old.estado = 'activo' and new.estado = 'perdido' then
    perform privado.avisar(new.rival, privado.nombre(new.retador) || ' no ha podido contigo', new.puntos_retador || '–' || new.puntos_rival || ' en ' || new.titulo);
  end if;
  return new;
end;
$$;
create trigger aviso_desafio after insert or update on public.desafios for each row execute function privado.t_desafio();

create function privado.t_pareja() returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then perform privado.avisar(new.b, privado.nombre(new.a) || ' quiere una racha contigo', 'Acéptala en Inicio');
  elsif old.estado = 'pendiente' and new.estado = 'activa' then perform privado.avisar(new.a, privado.nombre(new.b) || ' ha aceptado tu racha', 'Si uno falla, se rompe para los dos'); end if;
  return new;
end;
$$;
create trigger aviso_pareja after insert or update on public.parejas for each row execute function privado.t_pareja();

-- corona perdida: solo cuando alguien cruza por primera vez al líder
create function privado.t_corona() returns trigger language plpgsql security definer set search_path = ''
as $$
declare l record; mio numeric := case when tg_op = 'UPDATE' then old.rm else 0 end;
begin
  select usuario, rm into l from public.marcas where clave = new.clave and usuario <> new.usuario order by rm desc limit 1;
  if l.usuario is not null and new.rm > l.rm and mio <= l.rm then
    perform privado.avisar(l.usuario, privado.nombre(new.usuario) || ' te ha quitado la corona', new.nombre);
  end if;
  return new;
end;
$$;
create trigger aviso_corona_nueva after insert on public.marcas for each row execute function privado.t_corona();
create trigger aviso_corona_cambio before update on public.marcas for each row execute function privado.t_corona();
