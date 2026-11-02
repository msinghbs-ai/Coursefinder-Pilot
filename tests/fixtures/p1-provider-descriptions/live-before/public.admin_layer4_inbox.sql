CREATE OR REPLACE FUNCTION public.admin_layer4_inbox(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_kinds jsonb := security.layer4_inbox_kinds_v1(); v_kind text; v_ref text; v_choice text; v_reason text; v_value text; v_pid uuid;
        v_target int := security.pipeline_num_v1('layer4.target_days', 7)::int; v_actor text; v_lim int; v_off int; v_q text; v_r jsonb; v_c jsonb; v_det jsonb; v_out jsonb; v_ids uuid[]; v_event bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds
  v_q := nullif(btrim(p_args->>'q'), '');

  if p_action in ('summary', 'universities', 'items') then
    create temp table if not exists _l4 on commit drop as select * from security.layer4_inbox_items_v1();
    if p_action = 'summary' then
      return jsonb_build_object('kinds', v_kinds, 'target_days', v_target, 'rank', v_rank,
        'by_kind', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('n', k.n, 'oldest', k.oldest, 'late', k.late)), '{}'::jsonb)
                      from (select kind, count(*) n, min(created_at) oldest, count(*) filter (where created_at < now() - make_interval(days => v_target)) late from _l4 group by 1) k),
        'total', (select count(*) from _l4), 'universities', (select count(distinct provider_id) from _l4 where provider_id is not null),
        'late', (select count(*) from _l4 where created_at < now() - make_interval(days => v_target)));
    elsif p_action = 'universities' then
      return (with u as (
        select i.provider_id, coalesce(p.display_name, p.canonical_name, 'Platform') name, k.iso_alpha2::text country,
               (select count(*) from catalogue.courses c where c.provider_id = i.provider_id and c.lifecycle_status = 'active') courses,
               count(*) n, min(i.created_at) oldest,
               min((v_kinds->i.kind->>'order')::int) first_order
          from _l4 i left join catalogue.providers p on p.id = i.provider_id left join ref.countries k on k.id = p.country_id
         where (nullif(p_args->>'kind', '') is null or i.kind = p_args->>'kind')
           and (nullif(p_args->>'country', '') is null or k.iso_alpha2 = p_args->>'country')
           and (v_q is null or coalesce(p.display_name, p.canonical_name, '') ilike '%' || v_q || '%')
         group by 1, 2, 3)
        select jsonb_build_object('total', (select count(*) from u), 'limit', v_lim, 'offset', v_off,
          'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'name', z.name, 'country', z.country, 'courses', z.courses, 'n', z.n, 'oldest', z.oldest,
                     'late', z.oldest < now() - make_interval(days => v_target),
                     'by_kind', (select jsonb_object_agg(i2.kind, i2.c) from (select kind, count(*) c from _l4 x where x.provider_id is not distinct from z.provider_id group by 1) i2))
                   order by z.first_order, z.courses desc nulls last, z.name)
            from (select * from u order by first_order, courses desc nulls last, name limit v_lim offset v_off) z), '[]'::jsonb)));
    else
      return (with x as (
        select i.*, coalesce(p.display_name, p.canonical_name) provider, (v_kinds->i.kind->>'order')::int o
          from _l4 i left join catalogue.providers p on p.id = i.provider_id
         where (nullif(p_args->>'provider_id', '') is null or i.provider_id = (p_args->>'provider_id')::uuid)
           and (nullif(p_args->>'kind', '') is null or i.kind = p_args->>'kind')
           and (p_args ? 'provider_id' or p_args ? 'kind'))
        select jsonb_build_object('total', (select count(*) from x), 'items', coalesce((select jsonb_agg(jsonb_build_object(
                 'kind', z.kind, 'ref', z.ref, 'provider_id', z.provider_id, 'provider', z.provider, 'subject', z.subject, 'why', z.why, 'suggestion', z.suggestion,
                 'created_at', z.created_at, 'late', z.created_at < now() - make_interval(days => v_target), 'detail', z.detail, 'o', z.o) order by z.o, z.created_at, z.kind, z.ref)
               from (select * from x
                      -- UR-04 (1 Nov 2026): a stable position (kind order, created, kind, ref) so every item is reached once, oldest first
                      where not (p_args ? 'after_ref')
                         or (x.o, x.created_at, x.kind, x.ref) > ((p_args->>'after_o')::int, (p_args->>'after_at')::timestamptz, p_args->>'after_kind', p_args->>'after_ref')
                      order by o, created_at, kind, ref limit v_lim offset v_off) z), '[]'::jsonb),
          'before', (select count(*) from x where p_args ? 'after_ref'
                       and (x.o, x.created_at, x.kind, x.ref) <= ((p_args->>'after_o')::int, (p_args->>'after_at')::timestamptz, p_args->>'after_kind', p_args->>'after_ref'))));
    end if;
  end if;

  -- CF-247 20 Oct 2026: the decisions taken here, newest first (replaces the old Review queue history)
  if p_action = 'decided' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('at', e.created_at, 'kind', e.detail->>'kind', 'choice', e.detail->>'choice', 'value', e.detail->>'value',
             'reason', e.detail->>'reason', 'provider_id', e.detail->>'provider_id',
             'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id::text = e.detail->>'provider_id'),
             'by', (select u.email from auth.users u where u.id::text = e.actor::text)) order by e.id desc)
           from (select * from pipeline.admin_control_events x where x.area = 'layer4' and x.action = 'inbox_decide' order by x.id desc limit v_lim offset v_off) e), '[]'::jsonb));
  end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;
  v_kind := p_args->>'kind'; v_ref := p_args->>'ref'; v_choice := p_args->>'choice'; v_value := nullif(btrim(p_args->>'value'), '');
  v_c := (select c from jsonb_array_elements(v_kinds->v_kind->'choices') c where c->>'key' = v_choice);
  if v_c is null then raise exception 'unknown choice % for %', v_choice, v_kind; end if;
  if v_c ? 'link' then raise exception 'this choice opens another screen'; end if;
  if v_rank < coalesce((v_c->>'rank')::int, 4) then raise exception 'your role cannot make this choice' using errcode = '42501'; end if;  -- fixed: university and value choices need Pipeline Operator or above unless the choice names a higher rank
  v_reason := coalesce(nullif(btrim(p_args->>'reason'), ''), v_c->>'reason', '');
  if length(v_reason) < 4 then raise exception 'give a reason (kept with the decision)'; end if;
  if v_c->>'input' = 'url' and (v_value is null or v_value !~* '^https?://[^\s/]+\.[^\s]+$') then raise exception 'enter the full web address (https://…)'; end if;
  select i.provider_id, i.detail into v_pid, v_det from security.layer4_inbox_items_v1() i where i.kind = v_kind and i.ref = v_ref;
  if v_det is null then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;

  -- SS-016 fee check (1 Nov 2026): an address on a fee-check item was taken as a plain Approve and admitted the proposed fee (46 decisions
  -- on 30 Oct). A fee check is admitted or not; a different course page is set on the course record.
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition_validation' and v_choice = 'enter' then
    raise exception 'this is a fee check: admit the proposed fee or do not admit it. A different course page is set on the course record';
  end if;

  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee (identity re-verification quarantine, fee floor) is not a link decision
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition' and v_choice in ('use', 'enter') then
    if v_choice = 'use' then raise exception 'this item holds a fee, not a new page: enter the course page''s address, or keep the page we hold'; end if;
    v_r := security.layer4_fee_item_rebind_v1(v_ref::uuid, v_value, v_reason);
  elsif v_kind in ('no_page_first_run', 'conjoint_first_run') then
    -- hotfix 26 Oct 2026: a university's first run (no page published / conjoint rule); applied by security.no_page_review_apply_v1
    if v_choice = 'has_page' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the sample courses that have their own page';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the sample courses that have their own page'; end if;
      if exists (select 1 from unnest(v_ids) x(id) where not exists (select 1 from pipeline.course_no_page n where n.review_item_id = v_ref::uuid and n.course_id = x.id)) then
        raise exception 'a ticked course is not in this sample';
      end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid,
             case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case v_choice when 'has_page' then jsonb_build_object('has_page_course_ids', to_jsonb(v_ids))
                           when 'parent' then jsonb_build_object('parent_url', v_value) end);
  elsif v_kind = 'aer_review' then
    -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): one AER item at a time; Approve except sends the ticked rows to leave out
    if v_choice = 'approve_except' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the rows to leave out';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the rows to leave out'; end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case when v_choice = 'approve_except' then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ids)) end);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,
                                       case when v_choice = 'enter' then to_jsonb(v_value) end);
  elsif v_kind = 'held_scholarship' then
    v_r := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                         'extraction_id', v_det->'extraction_id', 'reason', v_reason));
  elsif v_kind = 'provider_departure' then  -- CF-247 20 Oct 2026: from the retired Review queue (Provider departures); Platform Admin
    if v_choice = 'merged' then
      select array_agg(p.id) into v_ids from catalogue.providers p
       where p.lifecycle_status = 'active' and p.id <> v_pid and p.country_id = (select q.country_id from catalogue.providers q where q.id = v_pid)
         and (lower(coalesce(p.display_name, p.canonical_name)) = lower(v_value)
              or p.id in (select r.provider_id from catalogue.provider_registrations r where upper(r.registration_code) = upper(v_value)));
      if coalesce(array_length(v_ids, 1), 0) <> 1 then raise exception 'enter the successor''s exact name or its CRICOS or NZQA code (% found)', coalesce(array_length(v_ids, 1), 0); end if;
    end if;
    v_r := public.layer4_provider_departure_decide(v_ref::bigint, v_choice, case when v_choice = 'merged' then v_ids[1] end, v_reason);
  elsif v_kind = 'counsellor_report' then  -- CF-247 20 Oct 2026: closed here (Coverage › Counsellor reports retired); Zoho reads the outcome back
    v_r := public.admin_counsellor_reports('close', jsonb_build_object('ids', jsonb_build_array(v_ref), 'outcome', case v_choice when 'report_fixed' then 'fixed' else 'not_changed' end, 'reason', v_reason));
  elsif v_choice = 'website' then
    v_r := public.admin_provider_website_set(v_pid, v_value);
    if v_kind in ('pages_not_found', 'site_down') then
      v_r := v_r || jsonb_build_object('released', security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: website changed to ' || v_value || '. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false));
    end if;
  elsif v_choice in ('release', 'keep') then
    v_r := security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  elsif v_choice = 'wait' then
    update pipeline.enrichment_flags set flagged_at = now() where id = (v_det->>'flag_id')::bigint;  -- asked again after the waiting period
    v_r := jsonb_build_object('waiting', true);
  elsif v_choice = 'cricos_only' then
    v_r := public.admin_adapter_build('set_wave', jsonb_build_object('wave', 'cricos-only', 'provider_ids', jsonb_build_array(v_pid)));
  elsif v_choice = 'rebuild' then
    v_r := public.admin_adapter_build('build', jsonb_build_object('provider_ids', jsonb_build_array(v_pid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'retry' then
    v_r := public.admin_provider_onboarding('retry', jsonb_build_object('ids', jsonb_build_array((v_det->>'onboarding_id')::uuid), 'reason', 'Layer 4: ' || v_reason));
  elsif v_choice = 'archive' then
    v_r := public.admin_provider_archive(v_pid, 'Layer 4: ' || v_reason, false);
  elsif v_choice = 'archive_course' then
    v_r := public.admin_course_edit((v_det->>'course_id')::uuid, 'archive', jsonb_build_object('reason', 'Layer 4: ' || v_reason));
    perform security.flag_release_v1((v_det->>'flag_id')::bigint, v_actor, 'person', 'Layer 4: course archived. ' || v_reason, jsonb_build_object('user_id', auth.uid()), false);
  else
    raise exception 'choice % is not handled', v_choice;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())
  returning id into v_event;
  -- UR-06 (1 Nov 2026): the reply names the audit event and what the decision actually did, read back from its destination
  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r));
end $function$
;
