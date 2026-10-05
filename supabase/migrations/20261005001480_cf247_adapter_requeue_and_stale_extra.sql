-- CF-247 Decision 254 (5 Oct 2026). Two fixes found by the wave 9 adapter runs.
-- 1. Applying a text-only adapter (no page data) sent every needs_render page back for a Firecrawl read on each apply
--    (UBC 22, NorthTec 43, Southern Cross), spending credits for pages the adapter cannot read. Pages are now sent back
--    only for adapters that read page data. The worker's own reading of needs_render pages is unchanged.
-- 2. A page kept test-only extra fields (adapter_extra) after the adapter stopped making them (Newcastle 172 pages).
--    The adapter's page record now clears adapter_extra when the new reading has none.
-- md5-guarded snippet patches, each snippet found exactly once. No text value in this file contains a semicolon.

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_requeue_v1(uuid,text)'::regprocedure) is distinct from 'b6f154cf41b044f040937b6b813e4a44' then
    raise exception 'uni_adapter_requeue_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.uni_adapter_requeue_v1(uuid,text)'::regprocedure);
  v_pairs := array[
    array[$s$where pg.provider_id = p_provider_id and (pg.read_status = 'needs_render' or$s$,
          $s$where pg.provider_id = p_provider_id and exists (select 1 from pipeline.uni_adapters u0 where u0.provider_id = pg.provider_id and coalesce(u0.json_source, '') <> '') and (pg.read_status = 'needs_render' or$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure) is distinct from 'ea43d20c3596cb8a2d909f2860952f1d' then
    raise exception 'svc_adapter_page_record changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$if p_candidates ? 'adapter_extra' then v_c := v_c || jsonb_build_object('adapter_extra', p_candidates->'adapter_extra')$s$,
          $s$if true then v_c := (v_c - 'adapter_extra') || case when p_candidates ? 'adapter_extra' then jsonb_build_object('adapter_extra', p_candidates->'adapter_extra') else '{}'::jsonb end$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
