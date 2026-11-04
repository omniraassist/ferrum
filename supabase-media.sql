-- Ferrum: fotos y vídeos, denuncias, leyendas y resumen público del perfil.
-- Pegar entero en Supabase → SQL Editor → Run. Va después de supabase-social.sql.

alter table public.marcas add column series90 integer not null default 0 check (series90 >= 0);
alter table public.perfiles add column resumen jsonb check (pg_column_size(resumen) < 2000);
create policy "cambiar mi perfil" on public.perfiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 31457280, array['image/jpeg', 'video/mp4', 'video/quicktime']);

create policy "ver media" on storage.objects for select to authenticated using (bucket_id = 'media');
-- máximo 40 archivos por persona, para que nadie llene el espacio de todos
create policy "subir media propia" on storage.objects for insert to authenticated with check (
  bucket_id = 'media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select count(*) from storage.objects o where o.bucket_id = 'media' and (storage.foldername(o.name))[1] = (select auth.uid())::text) < 40
);
create policy "borrar media propia" on storage.objects for delete to authenticated using (
  bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text
);

create table public.medios (
  id uuid primary key default gen_random_uuid(),
  publicacion uuid not null references public.publicaciones (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  ruta text not null check (ruta ~ '^[0-9a-f-]{36}/[a-z0-9]+\.(mp4|mov|jpg)$'),
  tipo text not null check (tipo in ('video', 'foto')),
  ejercicio text check (char_length(ejercicio) <= 80),
  serie integer check (serie between 1 and 100),
  etiqueta text check (char_length(etiqueta) <= 80),
  oculto boolean not null default false,
  creado timestamptz not null default now()
);
create index medios_publicacion on public.medios (publicacion);

create table public.denuncias (
  id uuid primary key default gen_random_uuid(),
  medio uuid not null references public.medios (id) on delete cascade,
  usuario uuid not null default auth.uid() references public.perfiles (id) on delete cascade,
  creado timestamptz not null default now(),
  unique (medio, usuario)
);

alter table public.medios enable row level security;
alter table public.denuncias enable row level security;

create policy "ver medios" on public.medios for select to authenticated using (not oculto or usuario = (select auth.uid()));
create policy "crear mis medios" on public.medios for insert to authenticated with check (
  usuario = (select auth.uid())
  and split_part(ruta, '/', 1) = (select auth.uid())::text
  and exists (select 1 from public.publicaciones p where p.id = publicacion and p.usuario = (select auth.uid()))
);
create policy "borrar mis medios" on public.medios for delete to authenticated using (usuario = (select auth.uid()));
create policy "denunciar" on public.denuncias for insert to authenticated with check (usuario = (select auth.uid()));

-- con 3 denuncias de personas distintas se oculta solo hasta que lo revises
create function public.ocultar_denunciado() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if (select count(*) from public.denuncias where medio = new.medio) >= 3 then
    update public.medios set oculto = true where id = new.medio;
  end if;
  return new;
end;
$$;
create trigger denuncia_oculta after insert on public.denuncias for each row execute function public.ocultar_denunciado();
