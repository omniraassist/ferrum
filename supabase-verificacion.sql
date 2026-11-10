-- Ferrum: verificación de récords con vídeo grabado en la app.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-notificaciones.sql y supabase-perfil.sql.
-- Todo el estado lo decide el servidor: la app solo llama a funciones, nunca escribe el estado de un intento.

create table public.staff (
  gym text not null check (char_length(gym) <= 60),
  usuario uuid not null references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  primary key (gym, usuario)
);

create table public.intentos (
  id uuid primary key default gen_random_uuid(),
  usuario uuid not null references public.perfiles (id) on delete cascade,
  gym text not null check (char_length(gym) <= 60),
  clave text not null check (char_length(clave) <= 80),
  nombre text not null check (char_length(nombre) <= 80),
  peso numeric not null check (peso > 0 and peso <= 1000),
  reps numeric not null check (reps > 0 and reps <= 100),
  rm numeric generated always as (round(peso * (1 + reps / 30.0), 1)) stored,
  codigo text not null check (codigo ~ '^[A-Z0-9]{4}$'),
  ruta text check (ruta ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(mp4|webm)$'),
  estado text not null default 'grabando' check (estado in ('grabando', 'pendiente', 'verificada', 'rechazada', 'revision')),
  creado timestamptz not null default now(),
  enviado timestamptz,
  decidido timestamptz
);
create index intentos_gym on public.intentos (gym, estado);
create index intentos_usuario on public.intentos (usuario, clave);

create table public.votos (
  intento uuid not null references public.intentos (id) on delete cascade,
  votante uuid not null references public.perfiles (id) on delete cascade,
  valido boolean not null,
  motivo text check (char_length(motivo) <= 60),
  staff boolean not null default false,
  creado timestamptz not null default now(),
  primary key (intento, votante)
);

create table public.reportes (
  intento uuid not null references public.intentos (id) on delete cascade,
  usuario uuid not null references public.perfiles (id) on delete cascade,
  motivo text check (char_length(motivo) <= 60),
  creado timestamptz not null default now(),
  primary key (intento, usuario)
);

create table public.vetos (
  usuario uuid primary key references public.perfiles (id) on delete cascade,
  hasta timestamptz not null
);

alter table public.staff enable row level security;
alter table public.intentos enable row level security;
alter table public.votos enable row level security;
alter table public.reportes enable row level security;
alter table public.vetos enable row level security;

create policy "ver staff" on public.staff for select to authenticated using (true);
create policy "ver intentos" on public.intentos for select to authenticated using (estado <> 'grabando' or usuario = (select auth.uid()));
create policy "ver votos" on public.votos for select to authenticated using (true);
create policy "ver mis reportes" on public.reportes for select to authenticated using (usuario = (select auth.uid()) or (select auth.uid()) = 'c61a90cb-1fe2-4a4a-bd92-005937218ed9');
create policy "ver mi veto" on public.vetos for select to authenticated using (usuario = (select auth.uid()));

-- ayudantes
create function public.es_staff(g text) returns boolean language sql stable security definer set search_path = ''
as $$ select (select auth.uid()) = 'c61a90cb-1fe2-4a4a-bd92-005937218ed9'
  or exists (select 1 from public.staff s where s.gym = g and s.usuario = (select auth.uid())); $$;

create function public.puede_ver_video(nombre text) returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.intentos i where i.ruta = $1 and (
  i.usuario = (select auth.uid())
  or public.es_staff(i.gym)
  or (select p.gimnasio from public.perfiles p where p.id = (select auth.uid())) = i.gym)); $$;
revoke execute on function public.es_staff(text), public.puede_ver_video(text) from public, anon;
grant execute on function public.es_staff(text), public.puede_ver_video(text) to authenticated;

-- vídeos privados: solo los ve tu gimnasio
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verificacion', 'verificacion', false, 41943040, array['video/mp4', 'video/webm']);

create policy "subir intento" on storage.objects for insert to authenticated with check (
  bucket_id = 'verificacion'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (select 1 from public.intentos i where i.usuario = (select auth.uid()) and i.estado = 'grabando'
    and split_part(storage.filename(name), '.', 1) = i.id::text)
);
create policy "ver intento" on storage.objects for select to authenticated using (bucket_id = 'verificacion' and public.puede_ver_video(name));
create policy "borrar mi intento" on storage.objects for delete to authenticated using (
  bucket_id = 'verificacion' and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- 1. empezar: el servidor da el código que saldrá grabado en el vídeo
create function public.empezar_intento(clave_ text, nombre_ text, peso_ numeric, reps_ numeric) returns table (id uuid, codigo text)
language plpgsql security definer set search_path = ''
as $$
declare yo uuid := auth.uid(); g text; c text; nuevo uuid;
begin
  select p.gimnasio into g from public.perfiles p where p.id = yo;
  if g is null or g = '' then raise exception 'sin gimnasio'; end if;
  if (select count(*) from public.intentos i where i.usuario = yo and i.creado > now() - interval '1 day') >= 8 then raise exception 'demasiados intentos'; end if;
  delete from public.intentos i where i.usuario = yo and i.estado = 'grabando' and i.creado < now() - interval '1 hour';
  c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 4));
  insert into public.intentos (usuario, gym, clave, nombre, peso, reps, codigo)
  values (yo, g, clave_, nombre_, peso_, reps_, c) returning intentos.id into nuevo;
  return query select nuevo, c;
end;
$$;

-- 2. enviar: el vídeo tiene que haberse subido en los 20 minutos siguientes a pedir el código
create function public.enviar_intento(intento_ uuid, peso_ numeric, reps_ numeric, ext text) returns void
language plpgsql security definer set search_path = ''
as $$
declare yo uuid := auth.uid(); i public.intentos; r text; subido timestamptz; m record;
begin
  select * into i from public.intentos where id = intento_ and usuario = yo and estado = 'grabando';
  if i.id is null then raise exception 'no existe'; end if;
  if ext not in ('mp4', 'webm') then raise exception 'formato'; end if;
  r := yo::text || '/' || i.id::text || '.' || ext;
  select o.created_at into subido from storage.objects o where o.bucket_id = 'verificacion' and o.name = r;
  if subido is null then raise exception 'sin video'; end if;
  if subido > i.creado + interval '20 minutes' then raise exception 'caducado'; end if;
  update public.intentos set ruta = r, peso = peso_, reps = reps_, estado = 'pendiente', enviado = now() where id = i.id;
  for m in select p.id from public.perfiles p where p.gimnasio = i.gym and p.id <> yo
    union select s.usuario from public.staff s where s.gym = i.gym and s.usuario <> yo loop
    perform privado.avisar(m.id, privado.nombre(yo) || ' va a por récord', i.nombre || ': ' || peso_ || ' kg × ' || reps_ || '. Entra a validarlo.');
  end loop;
end;
$$;

-- 3. votar: 2 compañeros del gimnasio o 1 del staff
create function public.votar_intento(intento_ uuid, valido_ boolean, motivo_ text) returns text
language plpgsql security definer set search_path = ''
as $$
declare yo uuid := auth.uid(); i public.intentos; st boolean; nsi int; nno int; nuevo text;
begin
  select * into i from public.intentos where id = intento_;
  if i.id is null or i.estado <> 'pendiente' then raise exception 'ya decidido'; end if;
  if i.usuario = yo then raise exception 'es tuyo'; end if;
  if exists (select 1 from public.bloqueos b where (b.bloqueador = yo and b.bloqueado = i.usuario) or (b.bloqueado = yo and b.bloqueador = i.usuario)) then raise exception 'bloqueo'; end if;
  st := public.es_staff(i.gym);
  if not st then
    if coalesce((select p.gimnasio from public.perfiles p where p.id = yo), '') <> i.gym then raise exception 'otro gimnasio'; end if;
    if (select u.created_at from auth.users u where u.id = yo) > now() - interval '14 days' then raise exception 'cuenta nueva'; end if;
    if (select count(*) from public.sesiones s where s.usuario = yo and s.doc is not null) < 5 then raise exception 'pocas sesiones'; end if;
    if exists (select 1 from public.vetos v where v.usuario = yo and v.hasta > now()) then raise exception 'vetado'; end if;
    if valido_ and (select count(*) from public.votos v join public.intentos x on x.id = v.intento
      where v.votante = yo and x.usuario = i.usuario and v.valido and v.creado > now() - interval '30 days') >= 3 then raise exception 'limite persona'; end if;
  end if;
  insert into public.votos (intento, votante, valido, motivo, staff) values (i.id, yo, valido_, left(motivo_, 60), st);
  select count(*) filter (where v.valido), count(*) filter (where not v.valido) into nsi, nno from public.votos v where v.intento = i.id;
  nuevo := case when st then (case when valido_ then 'verificada' else 'rechazada' end)
    when nsi >= 2 then 'verificada' when nno >= 2 then 'rechazada' else 'pendiente' end;
  if nuevo <> 'pendiente' then
    update public.intentos set estado = nuevo, decidido = now() where id = i.id;
    perform privado.avisar(i.usuario, case when nuevo = 'verificada' then 'Récord verificado' else 'Récord no validado' end,
      i.nombre || ': ' || i.peso || ' kg × ' || i.reps || case when nuevo = 'verificada' then '. Ya cuenta para las coronas.' else '. Puedes volver a intentarlo.' end);
  end if;
  return nuevo;
end;
$$;

-- 4. reportar: con 2 reportes vuelve a revisión y sale del ranking
create function public.reportar_intento(intento_ uuid, motivo_ text) returns void
language plpgsql security definer set search_path = ''
as $$
declare yo uuid := auth.uid(); i public.intentos;
begin
  select * into i from public.intentos where id = intento_;
  if i.id is null or i.estado <> 'verificada' then raise exception 'no verificada'; end if;
  if i.usuario = yo then raise exception 'es tuyo'; end if;
  insert into public.reportes (intento, usuario, motivo) values (i.id, yo, left(motivo_, 60)) on conflict do nothing;
  if (select count(*) from public.reportes r where r.intento = i.id) >= 2 then
    update public.intentos set estado = 'revision' where id = i.id;
    perform privado.avisar('c61a90cb-1fe2-4a4a-bd92-005937218ed9', 'Marca en revisión', privado.nombre(i.usuario) || ' · ' || i.nombre || ' ' || i.peso || ' kg × ' || i.reps);
  end if;
end;
$$;

-- 5. decidir (staff del gimnasio o admin). Si se tumba una marca ya verificada, quien la validó no puede validar en 30 días
create function public.decidir_intento(intento_ uuid, valido_ boolean) returns void
language plpgsql security definer set search_path = ''
as $$
declare i public.intentos;
begin
  select * into i from public.intentos where id = intento_;
  if i.id is null or i.estado not in ('pendiente', 'revision') then raise exception 'ya decidido'; end if;
  if not public.es_staff(i.gym) or i.usuario = auth.uid() then raise exception 'solo staff'; end if;
  if i.estado = 'revision' and not valido_ then
    insert into public.vetos (usuario, hasta) select v.votante, now() + interval '30 days' from public.votos v where v.intento = i.id and v.valido and not v.staff
    on conflict (usuario) do update set hasta = excluded.hasta;
  end if;
  delete from public.reportes where intento = i.id;
  update public.intentos set estado = case when valido_ then 'verificada' else 'rechazada' end, decidido = now() where id = i.id;
  perform privado.avisar(i.usuario, case when valido_ then 'Récord verificado' else 'Récord no validado' end, i.nombre || ': ' || i.peso || ' kg × ' || i.reps);
end;
$$;

-- 6. el vídeo de una marca superada o rechazada se borra para no llenar el espacio
create function public.quitar_video(intento_ uuid) returns void
language sql security definer set search_path = ''
as $$ update public.intentos set ruta = null where id = intento_ and usuario = auth.uid() and estado <> 'pendiente' and estado <> 'revision'; $$;

-- 7. staff: solo lo nombra el admin
create function public.poner_staff(gym_ text, usuario_ uuid, poner boolean) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() <> 'c61a90cb-1fe2-4a4a-bd92-005937218ed9' then raise exception 'solo admin'; end if;
  if poner then insert into public.staff (gym, usuario) values (gym_, usuario_) on conflict do nothing;
  else delete from public.staff where gym = gym_ and usuario = usuario_; end if;
end;
$$;

revoke execute on function public.empezar_intento(text, text, numeric, numeric), public.enviar_intento(uuid, numeric, numeric, text),
  public.votar_intento(uuid, boolean, text), public.reportar_intento(uuid, text), public.decidir_intento(uuid, boolean),
  public.quitar_video(uuid), public.poner_staff(text, uuid, boolean) from public, anon;
grant execute on function public.empezar_intento(text, text, numeric, numeric), public.enviar_intento(uuid, numeric, numeric, text),
  public.votar_intento(uuid, boolean, text), public.reportar_intento(uuid, text), public.decidir_intento(uuid, boolean),
  public.quitar_video(uuid), public.poner_staff(text, uuid, boolean) to authenticated;
