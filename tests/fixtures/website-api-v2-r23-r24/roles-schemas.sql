-- Roles and schemas as on the live project (Supabase roles anon, authenticated, service_role; auth.role() as Supabase defines it).
do $r$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end $r$;
create schema extensions; create schema catalogue; create schema ref; create schema pipeline; create schema security; create schema search;
create schema scholarship; create schema api; create schema pim; create schema auth; create schema ranking; create schema integration;
create function extensions.gen_random_uuid() returns uuid language sql volatile as $$ select pg_catalog.gen_random_uuid() $$;
create function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
