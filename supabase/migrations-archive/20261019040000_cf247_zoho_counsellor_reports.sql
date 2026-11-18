-- CF-247 (19 Oct 2026). Counsellor reports from Zoho. Platform Admin 14:51: "Can I add some control for counsellor in zohoncreator or crm to
-- flag or comment to pass on to studsearch platform admin for specific record. For example, missing field value, correct english requirement
-- or fees or any fields reportable." Choice: "Approve all (Recommended)".
-- Consumer API change approved: Platform Admin, 19 Oct 2026 14:51, "Approve all (Recommended)": Zoho API v2 report action extended (CRICOS code accepted; institutes, campuses and contacts; issue, suggested value, source link; more fields) and new action report_status. Additive only: no existing field, action or behaviour of either API changes, and no consumer API function is altered (zoho_edge_report_v1, used by Zoho v1, is unchanged).
-- 1 public.zoho_v2_report(jsonb): a report on a course, institute (provider), campus or contact. The record is found by its id, its CRICOS
--   code (courses and institutes) or the id Zoho holds from sync. Fault fixed: a course named only by its CRICOS code (e.g. 082960F) was not
--   found by zoho_edge_report_v1. The same report sent twice by the same counsellor within a day returns the first one.
--   The value held at the time of the report is kept with it, so the Platform Admin sees what the counsellor saw.
-- 2 public.zoho_v2_report_status(jsonb): Zoho asks for the outcome of its reports: open, fixed or not_changed, with the reason and date.
-- 3 public.admin_counsellor_reports(text, jsonb): the Counsellor reports screen (Coverage & completeness › Reports): list, counts, and
--   Fixed / Not changed with a reason. Reports are rows of pipeline.data_flags (flag_code 'reported'); nothing new is stored elsewhere.
-- Replaces: nothing (zoho-api-v2 now calls zoho_v2_report instead of zoho_edge_report_v1 for its report action; v1 keeps zoho_edge_report_v1)
-- Retires: nothing
-- Nothing dropped or deleted.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'reports.resolve_min_rank', 'Role that can close counsellor reports', 'The lowest role rank that can mark a counsellor report Fixed or Not changed (4 pipeline operator, 5 admin, 6 platform admin). Every assigned role can read them.', 'number', to_jsonb(4), 3, 6, 'role rank', 812, 'CF-247 19 Oct 2026: counsellor reports from Zoho', 'Zoho API', 'public.admin_counsellor_reports'),
 ('pipeline', 'reports.status_batch_max', 'Report outcomes asked for in one call', 'Zoho API v2 report_status: the most report ids one call may ask about.', 'number', to_jsonb(100), 10, 500, 'reports', 813, 'CF-247 19 Oct 2026: counsellor reports from Zoho', 'Zoho API', 'public.zoho_v2_report_status')
on conflict (toolset_key, key) do nothing;

-- 1 report
CREATE OR REPLACE FUNCTION public.zoho_v2_report(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_entity text := lower(btrim(coalesce(p_body->>'entity', 'course')));
  v_ident text; v_field text := lower(btrim(coalesce(p_body->>'field', 'other')));
  v_issue text := lower(btrim(coalesce(p_body->>'issue', 'wrong')));
  v_note text := btrim(coalesce(p_body->>'note', ''));
  v_suggest text := nullif(left(btrim(coalesce(p_body->>'suggested_value', '')), 500), '');  -- fixed: input length cap
  v_url text := nullif(btrim(coalesce(p_body->>'source_url', '')), '');
  v_rep jsonb := coalesce(p_body->'reporter', '{}'::jsonb);
  v_ref uuid; v_key text; v_item jsonb; v_label text; v_prov text; v_id uuid; v_path text; v_fields text[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_entity not in ('course', 'provider', 'campus', 'contact') then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'entity must be course, provider, campus or contact')); end if;
  v_ident := btrim(coalesce(case v_entity
    when 'course' then coalesce(nullif(p_body->>'course_id', ''), nullif(p_body->>'cricos_course_code', ''), p_body->>'identifier')
    when 'provider' then coalesce(nullif(p_body->>'provider_id', ''), nullif(p_body->>'cricos_provider_code', ''), p_body->>'identifier')
    when 'campus' then coalesce(nullif(p_body->>'campus_id', ''), p_body->>'identifier')
    else coalesce(nullif(p_body->>'contact_id', ''), p_body->>'identifier') end, ''));
  if v_ident = '' or length(v_ident) > 200 then  -- fixed: input length cap
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'the record''s id or CRICOS code is required')); end if;
  if length(v_note) < 3 then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'a note of at least 3 characters is required')); end if;
  if v_url is not null and (v_url !~* '^https?://' or length(v_url) > 500) then  -- fixed: input length cap
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'source_url must be a web address')); end if;
  if v_issue not in ('missing', 'wrong', 'out_of_date') then v_issue := 'wrong'; end if;
  v_fields := case v_entity
    when 'course' then array['official_url', 'intakes', 'english', 'tuition', 'scholarship', 'title', 'duration', 'delivery', 'campus', 'study_level', 'study_area', 'entry_requirements', 'cricos_code', 'other']
    when 'provider' then array['name', 'website', 'phone', 'email', 'address', 'logo', 'institution_type', 'cricos_code', 'other']
    when 'campus' then array['name', 'address', 'phone', 'website', 'other']
    else array['name', 'title', 'email', 'phone', 'other'] end;
  if v_field = 'fees' then v_field := 'tuition'; end if;
  if not (v_field = any (v_fields)) then v_field := 'other'; end if;

  -- the record as Zoho holds it (Australia, from sync), then the catalogue (courses and institutes of every country)
  select z.ref_id, z.item_key, z.item into v_ref, v_key, v_item
    from pipeline.zoho_sync_items z
   where z.entity = v_entity and z.removed_at is null
     and (z.item_key = lower(v_ident) or z.ref_id::text = lower(v_ident)
          or (v_entity = 'course' and z.item->>'cricos_course_code' = upper(v_ident))
          or (v_entity = 'provider' and z.item->>'cricos_provider_code' = upper(v_ident)))
   order by z.seq desc limit 1;
  if v_ref is null and v_entity = 'course' then
    select c.id, c.stable_key into v_ref, v_key from catalogue.courses c where c.id::text = lower(v_ident) or c.stable_key = lower(v_ident) limit 1;
  elsif v_ref is null and v_entity = 'provider' then
    select p.id, p.stable_key into v_ref, v_key from catalogue.providers p where p.id::text = lower(v_ident) or p.stable_key = lower(v_ident) limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error', jsonb_build_object('code', 'NOT_FOUND')); end if;

  if v_entity = 'course' and v_item is null then
    select coalesce(c.display_title, c.canonical_title), coalesce(p.display_name, p.canonical_name) into v_label, v_prov
      from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = v_ref;
  elsif v_entity = 'provider' and v_item is null then
    select coalesce(p.display_name, p.canonical_name) into v_label from catalogue.providers p where p.id = v_ref;
  else
    v_label := coalesce(v_item->>'title', v_item->>'name');
    v_prov := coalesce(v_item->'provider'->>'name', v_item->>'provider_name');
  end if;
  v_path := case v_entity || ':' || v_field
    when 'course:english' then 'english_requirements' when 'course:tuition' then 'tuition' when 'course:intakes' then 'intakes'
    when 'course:official_url' then 'official_url' when 'course:title' then 'title' when 'course:duration' then 'duration_months'
    when 'course:delivery' then 'delivery_modes' when 'course:scholarship' then 'scholarship_count' when 'course:campus' then 'campuses'
    when 'course:study_level' then 'study_level' when 'course:study_area' then 'study_area' when 'course:entry_requirements' then 'entry_requirements'
    when 'course:cricos_code' then 'cricos_course_code' when 'provider:cricos_code' then 'cricos_provider_code'
    when 'provider:address' then 'city' when 'campus:address' then 'address_line1'
    else case when v_field <> 'other' then v_field end end;

  -- the same report twice from the same counsellor within a day: the first one
  select f.id into v_id from pipeline.data_flags f
   where f.flag_code = 'reported' and f.status = 'open' and f.entity_type = v_entity and f.entity_id = v_ref and f.field_code = v_field
     and f.detail->>'note' = left(v_note, 1000) and coalesce(f.detail->'reporter'->>'email', '') = coalesce(v_rep->>'email', '')
     and f.created_at > now() - interval '1 day'  -- fixed: repeat window for a double click or a retry
   limit 1;
  if v_id is null then
    insert into pipeline.data_flags(entity_type, entity_id, field_code, flag_code, detail, status, change_control_ref)
    values (v_entity, v_ref, v_field, 'reported',
            jsonb_build_object('note', left(v_note, 1000), 'source', 'zoho', 'api', 'zoho-v2', 'issue', v_issue, 'suggested_value', v_suggest, 'source_url', v_url,
              'reporter', jsonb_build_object('name', left(coalesce(v_rep->>'name', ''), 120), 'email', left(coalesce(v_rep->>'email', ''), 160), 'ref', left(coalesce(v_rep->>'ref', ''), 120)),
              'key', v_key, 'identifier', v_ident, 'label', v_label, 'provider_name', v_prov,
              'value_at_report', case when v_path is not null and v_item is not null then v_item->v_path end,
              'quotes', jsonb_build_array(left(v_note, 1000))),
            'open', 'CF-247')
    returning id into v_id;
  end if;
  return jsonb_build_object('flag_id', v_id, 'entity', v_entity, 'id', v_key, 'field', v_field, 'issue', v_issue, 'status', 'open')
         || case when v_entity = 'course' then jsonb_build_object('course_id', v_key) else '{}'::jsonb end;
end $function$;

-- 2 outcome of reports
CREATE OR REPLACE FUNCTION public.zoho_v2_report_status(p_flag_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ids text[]; v_max int := greatest(security.pipeline_num_v1('reports.status_batch_max', 100)::int, 1);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_flag_ids) is distinct from 'array' then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'flag_ids must be a list')); end if;
  v_ids := array(select btrim(x) from jsonb_array_elements_text(p_flag_ids) x);
  if cardinality(v_ids) = 0 or cardinality(v_ids) > v_max then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', format('flag_ids must hold 1 to %s ids', v_max))); end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('flag_id', f.id, 'entity', f.entity_type, 'id', f.detail->>'key', 'field', f.field_code,
        'status', case f.status when 'open' then 'open' when 'corrected' then 'fixed' else 'not_changed' end,
        'reason', f.resolution->>'reason', 'reported_at', f.created_at, 'closed_at', f.resolved_at) order by f.created_at)
      from pipeline.data_flags f where f.flag_code = 'reported' and f.detail->>'source' = 'zoho' and f.id::text = any (v_ids)), '[]'::jsonb),
    'not_found', coalesce((select jsonb_agg(x) from unnest(v_ids) x
      where not exists (select 1 from pipeline.data_flags f where f.flag_code = 'reported' and f.detail->>'source' = 'zoho' and f.id::text = x)), '[]'::jsonb));
end $function$;

revoke execute on function public.zoho_v2_report(jsonb), public.zoho_v2_report_status(jsonb) from public, anon, authenticated;

-- 3 the screen
CREATE OR REPLACE FUNCTION public.admin_counsellor_reports(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_can boolean; v_actor text; v_reason text; v_outcome text; v_n int; v_lim int; v_off int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  v_can := v_rank >= security.pipeline_num_v1('reports.resolve_min_rank', 4)::int;
  v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds of the screen
  if p_action = 'list' then
    return (with x as (
      select f.*, count(*) over () total from pipeline.data_flags f
       where f.flag_code = 'reported'
         and (coalesce(p_args->>'status', 'open') = 'all' or f.status = case coalesce(p_args->>'status', 'open') when 'fixed' then 'corrected' when 'not_changed' then 'confirmed' else 'open' end)
         and (nullif(p_args->>'entity', '') is null or f.entity_type = p_args->>'entity')
         and (nullif(p_args->>'q', '') is null or concat_ws(' ', f.detail->>'label', f.detail->>'provider_name', f.detail->>'note', f.detail->>'key', f.detail->'reporter'->>'name', f.detail->'reporter'->>'email') ilike '%' || (p_args->>'q') || '%')
       order by f.created_at desc limit v_lim offset v_off)
      select jsonb_build_object('can_change', v_can, 'total', coalesce(max(x.total), 0),
        'counts', (select jsonb_build_object('open', count(*) filter (where status = 'open'), 'fixed', count(*) filter (where status = 'corrected'),
                     'not_changed', count(*) filter (where status in ('confirmed', 'removed')), 'last_7_days', count(*) filter (where created_at > now() - interval '7 days'))
                     from pipeline.data_flags where flag_code = 'reported'),
        'items', coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'entity', x.entity_type, 'key', x.detail->>'key', 'label', x.detail->>'label',
          'provider_name', x.detail->>'provider_name', 'field', x.field_code, 'issue', x.detail->>'issue', 'note', x.detail->>'note',
          'suggested_value', x.detail->>'suggested_value', 'source_url', x.detail->>'source_url', 'value_at_report', x.detail->'value_at_report',
          'reporter', x.detail->'reporter', 'source', x.detail->>'source', 'reported_at', x.created_at,
          'status', case x.status when 'open' then 'open' when 'corrected' then 'fixed' else 'not_changed' end,
          'reason', x.resolution->>'reason', 'closed_by', x.resolution->>'by', 'closed_at', x.resolved_at) order by x.created_at desc), '[]'::jsonb)) from x);
  elsif p_action = 'close' then
    if not v_can then raise exception 'your role cannot close counsellor reports' using errcode = '42501'; end if;
    v_outcome := p_args->>'outcome';
    if v_outcome not in ('fixed', 'not_changed') then raise exception 'outcome must be fixed or not_changed'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (Zoho shows it to the counsellor)'; end if;
    v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
    update pipeline.data_flags f set status = case v_outcome when 'fixed' then 'corrected' else 'confirmed' end, resolved_at = now(), resolved_by = auth.uid(),
           resolution = jsonb_build_object('outcome', v_outcome, 'reason', left(v_reason, 1000), 'by', v_actor)
     where f.flag_code = 'reported' and f.status = 'open' and f.id::text in (select jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)));
    get diagnostics v_n = row_count;
    return jsonb_build_object('closed', v_n, 'outcome', v_outcome);
  end if;
  raise exception 'unknown action %', p_action;
end $function$;
revoke execute on function public.admin_counsellor_reports(text, jsonb) from public, anon;
grant execute on function public.admin_counsellor_reports(text, jsonb) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.zoho_v2_report', 'Zoho API', 'Counsellor report on a course, institute, campus or contact (Zoho API v2 report)', 'active', '20261019040000'),
 ('function', 'public.zoho_v2_report_status', 'Zoho API', 'Outcome of counsellor reports (Zoho API v2 report_status)', 'active', '20261019040000'),
 ('function', 'public.admin_counsellor_reports', 'Operations', 'Counsellor reports screen: list and close', 'active', '20261019040000')
on conflict (kind, name) do nothing;

do $post$
declare r jsonb;
begin
  -- the fault: a course named by its CRICOS code alone is found (no row is written: the check runs on a missing note)
  r := public.zoho_v2_report('{"cricos_course_code":"082960F","note":"x"}'::jsonb);
  if r->'error'->>'code' <> 'INVALID_INPUT' then raise exception 'post-check: note rule'; end if;
  if (public.zoho_v2_report('{"cricos_course_code":"NOPE00X","note":"post-check"}'::jsonb))->'error'->>'code' <> 'NOT_FOUND' then raise exception 'post-check: not found'; end if;
  if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'post-check: consumer API drift'; end if;
end $post$;
