-- CF-247 Decision 253 (4 Oct 2026). A university adapter pattern that writes "any text" as (.|\s) gives the page reader
-- two ways to match every space. On a long page that does not match, trying them all ran the worker out of compute (one
-- Flinders preview, 11:10 UTC, no page changed). Such patterns are now refused when an adapter is saved or previewed. The
-- safe form is (?:.|\n) with a limit. [\s\S] was already refused (the database cannot read it).
-- No text value in this file contains a semicolon.

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_pattern_ok(text)'::regprocedure) is distinct from '55c5749c2ca4994a4549d99dad63b56e' then
    raise exception 'uni_adapter_pattern_ok changed, not replacing'; end if;
end $g$;
create or replace function security.uni_adapter_pattern_ok(p text) returns boolean
language plpgsql immutable set search_path = '' as $function$
begin
  if p is null or btrim(p) = '' then return true; end if;
  if position('.|\s' in p) > 0 or position('\s|.' in p) > 0 or position('.|\W' in p) > 0 or position('\S|\s' in p) > 0 or position('\s|\S' in p) > 0 then return false; end if;
  perform '' ~* p;
  return true;
exception when others then return false;
end $function$;
