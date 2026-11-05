-- Ferrum: ligas con ascensos y descensos, rival de la semana y aviso del domingo.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-notificaciones.sql.

create extension if not exists pg_cron;

-- solo el servidor escribe aquí: nadie puede subirse de liga a sí mismo
create table public.ligas (
  usuario uuid primary key references public.perfiles (id) on delete cascade,
  liga smallint not null default 0 check (liga between 0 and 5),
  rival uuid references public.perfiles (id) on delete set null,
  semana date,
  cambio smallint not null default 0,
  ganados integer not null default 0
);
alter table public.ligas enable row level security;
create policy "leer ligas" on public.ligas for select to authenticated using (true);
insert into public.ligas (usuario) select id from public.perfiles on conflict do nothing;

create function privado.t_liga_nueva() returns trigger language plpgsql security definer set search_path = ''
as $$ begin insert into public.ligas (usuario) values (new.id) on conflict do nothing; return new; end; $$;
create trigger liga_nueva after insert on public.perfiles for each row execute function privado.t_liga_nueva();

-- el resumen lo escribe cada usuario, así que se lee con cuidado
create function privado.xp(r jsonb, s date) returns integer language sql immutable set search_path = ''
as $$ select case when r->>'semana' = s::text and r->>'xps' ~ '^[0-9]{1,7}$' then (r->>'xps')::integer else 0 end; $$;
create function privado.lunes() returns date language sql stable set search_path = ''
as $$ select date_trunc('week', now() at time zone 'Europe/Madrid')::date; $$;

create function privado.asignar_rivales() returns void language plpgsql security definer set search_path = ''
as $$
declare s date := privado.lunes();
begin
  with o as (
    select l.usuario, row_number() over w as rn, lead(l.usuario) over w as sig, lag(l.usuario) over w as ant, first_value(l.usuario) over w as primero
    from public.ligas l join public.perfiles p on p.id = l.usuario
    window w as (order by l.liga desc, privado.xp(p.resumen, s - 7) desc, l.usuario)
  )
  update public.ligas l set semana = s,
    rival = case when o.rn % 2 = 1 then coalesce(o.sig, nullif(o.primero, o.usuario)) else o.ant end
  from o where o.usuario = l.usuario;
  perform privado.avisar(l.usuario, 'Tu rival de la semana', privado.nombre(l.rival) || '. Gana quien sume más XP.')
  from public.ligas l where l.rival is not null;
end;
$$;

create function privado.cerrar_semana() returns void language plpgsql security definer set search_path = ''
as $$
declare s date := privado.lunes() - 7;
begin
  update public.ligas l set ganados = ganados + 1
  from public.perfiles yo, public.perfiles el
  where yo.id = l.usuario and el.id = l.rival and l.semana = s and privado.xp(yo.resumen, s) > privado.xp(el.resumen, s);

  with t as (
    select l.usuario, privado.xp(p.resumen, s) as xp,
      row_number() over (partition by l.liga order by privado.xp(p.resumen, s) desc, l.usuario) as pos,
      count(*) over (partition by l.liga) as n
    from public.ligas l join public.perfiles p on p.id = l.usuario
  )
  update public.ligas l set cambio = case
    when t.xp > 0 and t.pos <= greatest(1, ceil(t.n * .3)) and l.liga < 5 then 1
    when l.liga > 0 and (t.xp = 0 or (t.n >= 3 and t.pos > t.n - ceil(t.n * .3))) then -1
    else 0 end
  from t where t.usuario = l.usuario;

  update public.ligas set liga = liga + cambio;
  perform privado.avisar(usuario, case when cambio = 1 then '¡Has subido de liga!' else 'Has bajado de liga' end, 'Entra a ver tu nueva liga')
  from public.ligas where cambio <> 0;
  perform privado.asignar_rivales();
end;
$$;

create function privado.aviso_domingo() returns void language plpgsql security definer set search_path = ''
as $$
declare s date := privado.lunes(); u record; hecho boolean; racha integer; p record;
begin
  for u in select distinct pf.id, pf.resumen from public.perfiles pf join public.suscripciones x on x.usuario = pf.id loop
    hecho := privado.xp(u.resumen, s) > 0;
    racha := case when u.resumen->>'racha' ~ '^[0-9]{1,4}$' then (u.resumen->>'racha')::integer else 0 end;
    if not hecho and racha > 0 then
      perform privado.avisar(u.id, 'Tu racha de ' || racha || ' semanas acaba hoy', 'Entrena antes de medianoche para no perderla');
    end if;
  end loop;
  for p in select q.a, q.b, pa.resumen as ra, pb.resumen as rb from public.parejas q join public.perfiles pa on pa.id = q.a join public.perfiles pb on pb.id = q.b where q.estado = 'activa' loop
    if privado.xp(p.ra, s) > 0 and privado.xp(p.rb, s) = 0 then perform privado.avisar(p.b, privado.nombre(p.a) || ' ya ha entrenado, faltas tú', 'Vuestra racha depende de ti');
    elsif privado.xp(p.rb, s) > 0 and privado.xp(p.ra, s) = 0 then perform privado.avisar(p.a, privado.nombre(p.b) || ' ya ha entrenado, faltas tú', 'Vuestra racha depende de ti'); end if;
  end loop;
end;
$$;

select privado.asignar_rivales();
select cron.schedule('ferrum-cierre-semana', '10 23 * * 0', 'select privado.cerrar_semana()');
select cron.schedule('ferrum-aviso-domingo', '0 17 * * 0', 'select privado.aviso_domingo()');
