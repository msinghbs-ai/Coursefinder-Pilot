-- Supabase built-ins that the captured production definitions name but that are not part of a prod-parity capture.
-- Local stand-ins only: the extensions schema (pgcrypto's gen_random_uuid, the default of course_english_requirements.id) and auth.role()/auth.uid(),
-- which the service functions read only when the caller is not postgres. Nothing here is a production object being reproduced.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;
create or replace function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
