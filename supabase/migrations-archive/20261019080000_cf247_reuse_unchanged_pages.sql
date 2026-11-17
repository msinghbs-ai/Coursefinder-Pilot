-- CF-247 (19 Oct 2026). Platform Admin 19:04: "how do we simplify evidence collection ... and store them efficiently without bloating the
-- DB"; 20:33: "refresh plan for evidence, plan and execute the next steps".
-- Found: a course page re-read almost always saved a new copy (95,059 copies for 32,709 pages), because the page's HTML changes on every
-- load (tokens, timestamps) even when its text does not. Coverage-sweep worker v0.32.0 hashes the page text (scripts and spacing left
-- out) and, when it is the same as the copy in use, keeps that copy: no file is stored and no evidence record is made.
-- 1 Setting evidence.reuse_unchanged_pages (1 on, 0 off): when off, every read stores a copy as before.
-- 2 public.svc_coverage_text_sha(uuid): the text hash of the copy a course's page uses now (null when the setting is off, the page is
--   not read, or the copy has no text hash yet; then the read stores a copy as before).
-- 3 public.svc_coverage_read_record: each new copy keeps its text hash (from the reader's candidates) in its details.
-- Replaces: public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb) (the text hash kept; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'evidence.reuse_unchanged_pages', 'Keep the copy when a course page has not changed', 'When a course page is read again and its text is the same as the copy in use, keep that copy instead of storing a new one (1 on, 0 off).', 'number', to_jsonb(1), 0, 1, 'on/off', 325, 'CF-247 19 Oct 2026: 95,059 copies for 32,709 pages', 'Storage & retention', 'public.svc_coverage_text_sha; coverage-sweep worker v0.32.0')
on conflict (toolset_key, key) do nothing;

CREATE OR REPLACE FUNCTION public.svc_coverage_text_sha(p_course_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select e.metadata->>'text_sha'
    from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id
   where g.course_id = p_course_id and g.read_status = 'read' and g.identity_basis is not null
     and security.pipeline_num_v1('evidence.reuse_unchanged_pages', 1) >= 1
$function$;
revoke execute on function public.svc_coverage_text_sha(uuid) from public, anon, authenticated;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'e0437f036b88f3a7231e99d5245c6ffe', array[
  array['''fetched_via'',p_fetched_via,''gzip'',true));',
        '''fetched_via'',p_fetched_via,''gzip'',true) || case when coalesce(p_candidates->>''text_sha'', '''') ~ ''^[0-9a-f]{64}$'' then jsonb_build_object(''text_sha'', p_candidates->>''text_sha'') else ''{}''::jsonb end);  -- 19 Oct 2026: text hash for unchanged-page reuse']
]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.svc_coverage_text_sha', 'L2 read', 'Text hash of the copy a course page uses now (unchanged-page reuse)', 'active', '20261019080000')
on conflict (kind, name) do nothing;

do $post$
begin
  if position('text_sha' in pg_get_functiondef('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: record'; end if;
  if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'post-check: consumer API drift'; end if;
end $post$;
