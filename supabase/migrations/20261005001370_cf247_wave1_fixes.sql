-- CF-247 Decision 254 (5 Oct 2026). Fixes from wave 1 (Melbourne, Macquarie, Canterbury, Simon Fraser, ANU).
--   * A corrected adapter pattern left the earlier adapter reading in place when the new pattern no longer matched
--     (Canterbury Bachelor of Health Sciences kept a 2025 fee, ANU kept four per-unit fees). The page record now takes
--     out an adapter reading the adapter no longer makes.
--   * Applying an adapter sent pages refused after a Firecrawl read back to the reader every time, and the reader read
--     them again through Firecrawl (Macquarie: 21 credits on pages already known to be wrong). A page is now sent back
--     once only.
--   * Worker v0.17.2: page-data list filter [field=value] and a page-data fee counted as the adapter's reading.
-- md5-guarded whole replacements. No text value in this file contains a semicolon.

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure) is distinct from '9385154b9d476d484c7e13e5c84c6f74' then
    raise exception 'svc_adapter_page_record changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_requeue_v1(uuid,text)'::regprocedure) is distinct from '7dec88595da9b47df5cbb7e0d1a43f07' then
    raise exception 'uni_adapter_requeue_v1 changed, not replacing'; end if;
end $g$;
create or replace function public.svc_adapter_page_record(p_course_id uuid, p_identity text, p_how text, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_pg pipeline.coverage_course_pages%rowtype; v_c jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_identity not in ('adapter_code', 'adapter_title') or p_candidates is null then return 'nothing'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = p_course_id;
  if v_pg.course_id is null or v_pg.evidence_id is null then return 'no_page'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  if v_pg.read_status = 'identity_mismatch' then
    update pipeline.coverage_course_pages set read_status = 'read', status = 'bound', identity_basis = p_identity, candidates = p_candidates || jsonb_build_object('final_url', v_pg.url), next_read_at = now() + interval '90 days' where course_id = p_course_id and read_status = 'identity_mismatch';
    update pipeline.search_pass_links set state = 'verified', updated_at = now() where course_id = p_course_id and bound_url = v_pg.url;
  elsif v_pg.read_status = 'read' and v_pg.identity_basis is not null then
    v_c := coalesce(v_pg.candidates, '{}'::jsonb);
    -- 5 Oct: an earlier adapter reading the adapter no longer makes is taken out, so a corrected pattern leaves no stale value
    if v_c->>'intakes_by' = 'adapter' and coalesce(p_candidates->>'intakes_by', '') <> 'adapter' then v_c := v_c - 'intakes' - 'intake_context' - 'intakes_by'; end if;
    if v_c->>'fee_by' = 'adapter' and coalesce(p_candidates->>'fee_by', '') <> 'adapter' then v_c := v_c - 'fee' - 'fee_by'; end if;
    if v_c->>'english_by' = 'adapter' and coalesce(p_candidates->>'english_by', '') <> 'adapter' then v_c := v_c - 'english' - 'english_by'; end if;
    -- v0.16.0: the adapter's own reading (marked intakes_by, english_by, fee_by) replaces the general reader's
    if p_candidates->>'intakes_by' = 'adapter' and jsonb_array_length(coalesce(p_candidates->'intakes', '[]'::jsonb)) > 0 then v_c := v_c || jsonb_build_object('intakes', p_candidates->'intakes', 'intake_context', p_candidates->'intake_context', 'intakes_by', 'adapter');
    elsif jsonb_array_length(coalesce(v_c->'intakes', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(p_candidates->'intakes', '[]'::jsonb)) > 0 then v_c := v_c || jsonb_build_object('intakes', p_candidates->'intakes', 'intake_context', p_candidates->'intake_context'); end if;
    if p_candidates->>'english_by' = 'adapter' and p_candidates->'english' ? 'ielts_overall' then v_c := v_c || jsonb_build_object('english', p_candidates->'english', 'english_by', 'adapter');
    elsif coalesce(v_c->'english'->>'ielts_overall', v_c->'english'->>'pte_overall', v_c->'english'->>'toefl_overall') is null and coalesce(p_candidates->'english'->>'ielts_overall', p_candidates->'english'->>'pte_overall', p_candidates->'english'->>'toefl_overall') is not null then v_c := v_c || jsonb_build_object('english', p_candidates->'english'); end if;
    if p_candidates->>'fee_by' = 'adapter' and coalesce(p_candidates->'fee'->>'value', '') <> '' then v_c := v_c || jsonb_build_object('fee', p_candidates->'fee', 'fee_by', 'adapter');
    elsif coalesce(v_c->'fee'->>'value', '') = '' and coalesce(p_candidates->'fee'->>'value', '') <> '' then v_c := v_c || jsonb_build_object('fee', p_candidates->'fee'); end if;
    if p_candidates ? 'adapter_extra' then v_c := v_c || jsonb_build_object('adapter_extra', p_candidates->'adapter_extra'); end if;
    if v_c = coalesce(v_pg.candidates, '{}'::jsonb) then return 'no_new_field'; end if;
    update pipeline.coverage_course_pages set candidates = v_c || jsonb_build_object('adapter', true) where course_id = p_course_id;
  else
    return 'not_applicable';
  end if;
  insert into pipeline.uni_adapter_results(provider_id, course_id, before_read_status, before_identity, identity, how, fields)
    values (v_pg.provider_id, p_course_id, v_pg.read_status, v_pg.identity_basis, p_identity, p_how, jsonb_build_object('intakes', p_candidates->'intakes', 'intakes_by', p_candidates->'intakes_by', 'english', p_candidates->'english'->'ielts_overall', 'fee', p_candidates->'fee'->'value', 'extra', p_candidates->'adapter_extra'));
  return case when v_pg.read_status = 'identity_mismatch' then 'confirmed' else 'fields_added' end;
end $f$;
revoke all on function public.svc_adapter_page_record(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_page_record(uuid, text, text, jsonb) to service_role;

create or replace function security.uni_adapter_requeue_v1(p_provider_id uuid, p_reason text) returns int
language plpgsql security definer set search_path = '' as $f$
declare n int; v_ids uuid[];
begin
  -- 5 Oct: a page refused after a Firecrawl read is sent back once only (it is read again through Firecrawl)
  v_ids := array(select pg.course_id from pipeline.coverage_course_pages pg
                  where pg.provider_id = p_provider_id and (pg.read_status = 'needs_render' or (pg.read_status = 'identity_mismatch' and pg.fetched_via = 'firecrawl' and not exists (select 1 from pipeline.page_link_repairs x where x.course_id = pg.course_id and x.reason like 'university adapter: page read again%')))
                    and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url'));
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, 'university adapter: page read again (' || p_reason || ')'
    from pipeline.coverage_course_pages pg where pg.course_id = any (v_ids);
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', next_read_at = now(), leased_until = null where pg.course_id = any (v_ids);
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_requeue_v1(uuid, text) from public, anon, authenticated;
