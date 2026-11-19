-- CF-247 Decision 254 (5 Oct 2026). Fix: a central English rule written out from an attached page (admin_provider_english_propose)
-- was marked superseded when the provider-facts job next read the same page and the parser recorded its own result
-- (usually "no values"). 10 written-out rules were lost this way (Adelaide University, AUT, Calgary, Lethbridge, Sydney,
-- QUT, Otago, Victoria University of Wellington, University of Victoria, Alberta). A parser result no longer supersedes a
-- written-out rule, and those 10, never decided by anyone, wait for approval again.
-- md5-guarded snippet patch, found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_provider_policy_record(uuid,jsonb)'::regprocedure) is distinct from '0e9d84766197643d2e40c8199916b8ed' then
    raise exception 'svc_provider_policy_record changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_provider_policy_record(uuid,jsonb)'::regprocedure);
  v_old := $s$and id <> v_id and status in ('proposed', 'no_values')$s$;
  v_new := $s$and id <> v_id and status in ('proposed', 'no_values') and parser <> 'written out from the central page'$s$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'supersede snippet not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $p$;

update pipeline.provider_policy_proposals set status = 'proposed', updated_at = now() where parser = 'written out from the central page' and status = 'superseded' and decided_by is null and decided_at is null;
