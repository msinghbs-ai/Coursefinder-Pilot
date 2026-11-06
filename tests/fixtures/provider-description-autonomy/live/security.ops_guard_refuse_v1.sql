CREATE OR REPLACE FUNCTION security.ops_guard_refuse_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- Fires only while a remedy or verification runs (trigger WHEN security.ops_remedy_guard_active_v1()). TG_ARGV[0] names what is protected.
begin
  raise exception 'ops guard: a remedy cannot change % (%.%; that is a release or a Platform Admin decision)', TG_ARGV[0], TG_TABLE_SCHEMA, TG_TABLE_NAME using errcode = '42501';
end $function$

