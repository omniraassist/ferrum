-- Ferrum: el administrador restablece contraseñas desde la app (el correo gratis de Supabase no llega a los usuarios).
-- Pegar entero en Supabase → SQL Editor → Run. Solo funciona para la cuenta de Xavitus.

create function public.admin_cuentas() returns table (id uuid, nombre text, email text, anonima boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is distinct from 'c61a90cb-1fe2-4a4a-bd92-005937218ed9'::uuid then raise exception 'solo admin'; end if;
  return query select p.id, p.nombre, u.email::text, coalesce(u.is_anonymous, false)
    from public.perfiles p join auth.users u on u.id = p.id order by lower(p.nombre);
end;
$$;

create function public.admin_restablecer(objetivo uuid, correo text, clave text) returns void
language plpgsql security definer set search_path = ''
as $$
declare c text := nullif(lower(btrim(correo)), '');
begin
  if (select auth.uid()) is distinct from 'c61a90cb-1fe2-4a4a-bd92-005937218ed9'::uuid then raise exception 'solo admin'; end if;
  if char_length(clave) < 8 then raise exception 'clave corta'; end if;
  if c is null and (select email from auth.users where id = objetivo) is null then raise exception 'falta correo'; end if;
  if c is not null and exists (select 1 from auth.users where lower(email) = c and id <> objetivo) then raise exception 'correo usado'; end if;
  update auth.users set encrypted_password = extensions.crypt(clave, extensions.gen_salt('bf')),
    email = coalesce(c, email), email_confirmed_at = coalesce(email_confirmed_at, now()), is_anonymous = false,
    raw_app_meta_data = raw_app_meta_data || '{"provider":"email","providers":["email"]}'::jsonb, updated_at = now()
    where id = objetivo;
  if not found then raise exception 'no existe'; end if;
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    select objetivo::text, objetivo, jsonb_build_object('sub', objetivo::text, 'email', u.email, 'email_verified', true, 'phone_verified', false), 'email', now(), now(), now()
    from auth.users u where u.id = objetivo
    and not exists (select 1 from auth.identities i where i.user_id = objetivo and i.provider = 'email');
  update auth.identities set identity_data = identity_data || jsonb_build_object('email', (select email from auth.users where id = objetivo))
    where user_id = objetivo and provider = 'email';
end;
$$;

revoke execute on function public.admin_cuentas() from public, anon;
revoke execute on function public.admin_restablecer(uuid, text, text) from public, anon;
grant execute on function public.admin_cuentas() to authenticated;
grant execute on function public.admin_restablecer(uuid, text, text) to authenticated;
