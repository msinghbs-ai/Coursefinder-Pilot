-- CF-247 (20 Oct 2026). Platform Admin 07:02: "work out the logic and streamline the intended operation by layer 4, Flagged Unis should
-- come here for unflag as well ... anything that needs attention or intervention should come to Layer 4, define its return path".
-- Choices (07:40): "By university", "Yes, all of them", "Inbox, at the bottom", "After 30 days held". Design: admin repo
-- docs/platform/LAYER4-INBOX-DESIGN.md.
-- Layer 4 Inbox: one list of everything that needs a person, built from the existing sources (no data moves):
--   course_link (pipeline.layer4_review_items), held_scholarship (pipeline.scholarship_ai_reviews), website_needed, too_few_pages,
--   nothing_ready, central_to_approve, onboarding_failed (latest onboarding stopped), pages_not_found, site_down (provider flags; site
--   down only after layer4.site_down_days), not_offered, not_on_site, fee_check (course and adapter flags), counsellor_report
--   (pipeline.data_flags 'reported'). Universities in the CRICOS-only group are left out of the onboarding kinds.
-- Each kind names its choices and where each choice sends the item (return path). public.admin_layer4_inbox: summary, universities,
-- items, decide. decide routes each choice to the existing action (layer4_review_decide, admin_scholarship_ai review_decide,
-- admin_provider_website_set, the flag release (security.flag_release_v1), admin_adapter_build build and set_wave, admin_provider_onboarding retry,
-- admin_provider_archive, admin_course_edit archive, admin_counsellor_reports close), which keep their own role checks and logs.
-- Replaces: nothing (the Review queue, AI could not decide and Websites to find tabs stay until the Inbox has run 14 days)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.site_down_days', 'Days a website may be down before a person is asked', 'A website that does not answer is checked again by itself; after this many days held it also comes to Layer 4 (change the website, archive or keep waiting).', 'number', to_jsonb(30), 3, 180, 'days', 328, 'CF-247, Platform Admin 20 Oct 2026 "After 30 days held"', 'Layer 4', 'public.admin_layer4_inbox'),
 ('pipeline', 'layer4.target_days', 'Days an item may wait in Layer 4', 'Items waiting longer than this are highlighted.', 'number', to_jsonb(7), 1, 60, 'days', 329, 'CF-247 Layer 4 design 20 Oct 2026', 'Layer 4', 'public.admin_layer4_inbox')
on conflict (toolset_key, key) do nothing;

-- every item that needs a person, one row each
CREATE OR REPLACE FUNCTION security.layer4_inbox_items_v1()
 RETURNS TABLE(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ob as (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
  cricos_only as (select b.provider_id from pipeline.adapter_builds b where b.wave = 'cricos-only'),
  held_pages as (select f.provider_id from pipeline.enrichment_flags f where f.entity = 'provider' and f.state = 'raised' and f.reason_code = 'course_pages_not_found')
  -- course links and other review items
  select 'course_link'::text, r.id::text, coalesce(c.provider_id, s.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title, s.name, r.field_code),
         coalesce(nullif(r.escalation_reason, ''), 'Needs a decision'), null::text, r.created_at,
         jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value)
    from pipeline.layer4_review_items r
    left join catalogue.courses c on r.entity_type = 'course' and c.id = r.entity_id
    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
   where r.status = 'pending'
  union all
  -- held scholarship pages, with the AI re-check
  select 'held_scholarship', r.id::text, r.provider_id,
         coalesce((select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = r.extraction_ids[array_upper(r.extraction_ids, 1)]), r.url),
         r.reason, r.recheck->>'why', r.created_at,
         jsonb_build_object('url', r.url, 'recommendation', r.recheck->>'recommendation', 'audience_quote', r.recheck->>'audience_quote', 'value_quote', r.recheck->>'value_quote',
                            'extraction_id', (select e.id from pipeline.scholarship_ai_extractions e where e.id = any (r.extraction_ids) and coalesce((e.answer->>'is_scholarship')::boolean, false) order by e.id desc limit 1))
    from pipeline.scholarship_ai_reviews r where r.status = 'pending'
  union all
  -- universities whose onboarding stopped and needs a person
  select case ob.stop_reason when 'no_website' then 'website_needed' when 'too_few_pages' then 'too_few_pages' when 'nothing_ready' then 'nothing_ready'
              when 'approve_central' then 'central_to_approve' else 'onboarding_failed' end,
         ob.id::text, ob.provider_id, null, coalesce(ob.note, ob.stop_reason), null, ob.updated_at,
         jsonb_build_object('stop_reason', ob.stop_reason, 'onboarding_id', ob.id)
    from ob
   where ob.status = 'stopped' and ob.stop_reason in ('no_website', 'too_few_pages', 'nothing_ready', 'approve_central', 'proposal_failed', 'capture_failed')
     and ob.provider_id not in (select provider_id from cricos_only)
     and not (ob.stop_reason = 'too_few_pages' and ob.provider_id in (select provider_id from held_pages))
  union all
  -- provider holds a person lifts
  select case f.reason_code when 'course_pages_not_found' then 'pages_not_found' when 'site_unreachable' then 'site_down' else 'fee_check' end,
         f.id::text, f.provider_id, null, f.reason, null, f.flagged_at, jsonb_build_object('flag_id', f.id, 'evidence', f.evidence)
    from pipeline.enrichment_flags f
   where f.entity = 'provider' and f.state = 'raised'
     and (f.reason_code in ('course_pages_not_found', 'adapter_fee_fails_check')
          or (f.reason_code = 'site_unreachable' and f.flagged_at < now() - make_interval(days => security.pipeline_num_v1('layer4.site_down_days', 30)::int)))
  union all
  -- course holds a person decides
  select case f.reason_code when 'not_offered' then 'not_offered' when 'not_on_provider_site' then 'not_on_site' else 'fee_check' end,
         f.id::text, coalesce(f.provider_id, c.provider_id), coalesce(nullif(c.display_title, ''), c.canonical_title), f.reason, null, f.flagged_at,
         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
   where f.entity = 'course' and f.state = 'raised' and f.reason_code in ('not_offered', 'not_on_provider_site', 'fee_crosscheck')
  union all
  -- counsellor reports from Zoho
  select 'counsellor_report', d.id::text, coalesce((select c.provider_id from catalogue.courses c where d.entity_type = 'course' and c.id = d.entity_id), case when d.entity_type = 'provider' then d.entity_id end),
         coalesce(d.detail->>'label', d.field_code), coalesce(d.detail->>'note', 'Reported by a counsellor'), null, d.created_at, d.detail
    from pipeline.data_flags d where d.flag_code = 'reported' and d.status = 'open'
$function$;
revoke execute on function security.layer4_inbox_items_v1() from public, anon, authenticated;

-- what each kind is, its choices and where each choice sends the item
CREATE OR REPLACE FUNCTION security.layer4_inbox_kinds_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{
   "course_link": {"label": "Course link", "order": 1, "choices": [
     {"key": "keep", "label": "Keep the page we hold", "returns": "Closed; the same pair of pages is not asked again"},
     {"key": "use", "label": "Use the new page", "returns": "The new page becomes the official page (a person''s value, never overwritten); it is read again and the adapter applies"},
     {"key": "enter", "label": "Enter another address", "input": "url", "returns": "That address becomes the official page; it is read again and the adapter applies"}]},
   "held_scholarship": {"label": "Held scholarship", "order": 2, "choices": [
     {"key": "publish", "label": "Publish", "returns": "Taken as for international students and offered; the hourly publish checks still apply"},
     {"key": "not_international", "label": "Not for international students", "reason": "The page does not say international students may apply", "returns": "Refused; the same page copy is not asked again"},
     {"key": "not_scholarship", "label": "Not a scholarship", "reason": "Not a scholarship page", "returns": "Refused; the same page copy is not asked again"}]},
   "website_needed": {"label": "Website needed", "order": 3, "choices": [
     {"key": "website", "label": "Enter the website", "input": "url", "returns": "Onboarding starts again from the website: its course pages are found and read, then the adapter is built"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No adapter and no credits; it keeps its register data"},
     {"key": "archive", "label": "Archive the university", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"}]},
   "pages_not_found": {"label": "Course pages not found", "order": 4, "choices": [
     {"key": "website", "label": "Change the website", "input": "url", "returns": "The hold is released, the site is mapped again and onboarding starts again"},
     {"key": "pages", "label": "Add page addresses", "link": "builder", "returns": "Opens the Adapter builder (2.1); release the hold here once pages are added"},
     {"key": "release", "label": "Release and try again", "rank": 4, "returns": "The hold is released; the site is mapped again and onboarding starts again"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "Stays held; labelled CRICOS data only"}]},
   "too_few_pages": {"label": "Too few course pages", "order": 5, "choices": [
     {"key": "pages", "label": "Add page addresses", "link": "builder", "returns": "Onboarding carries on by itself once 3 pages are read"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No adapter and no credits; it keeps its register data"}]},
   "nothing_ready": {"label": "Adapter has nothing ready", "order": 6, "choices": [
     {"key": "adapter", "label": "Open the adapter", "link": "builder", "returns": "Fix a pattern and qualify again; what passes is admitted"},
     {"key": "rebuild", "label": "Rebuild the adapter", "rank": 5, "returns": "Onboarding builds and qualifies the adapter again; what passes is admitted, then courses are enriched and scholarships found"},
     {"key": "cricos_only", "label": "CRICOS data only", "returns": "No more work on its adapter; it keeps its register data"}]},
   "central_to_approve": {"label": "Central pages to approve", "order": 7, "choices": [
     {"key": "open", "label": "Open the central pages", "link": "builder", "returns": "Approve or refuse each page; onboarding carries on by itself"}]},
   "onboarding_failed": {"label": "Adapter proposal failed", "order": 8, "choices": [
     {"key": "retry", "label": "Try again", "rank": 5, "returns": "Onboarding starts again from the step that stopped"},
     {"key": "builder", "label": "Build by hand", "link": "builder", "returns": "Opens the Adapter builder"}]},
   "site_down": {"label": "Website not answering", "order": 9, "choices": [
     {"key": "website", "label": "Change the website", "input": "url", "returns": "The hold is released and onboarding starts again from the website"},
     {"key": "archive", "label": "Archive the university", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "wait", "label": "Keep waiting", "returns": "Checked every 10 minutes as before; asked again in 30 days"}]},
   "not_offered": {"label": "Course not offered", "order": 10, "choices": [
     {"key": "archive_course", "label": "Archive the course", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "keep", "label": "Keep it", "returns": "The hold is released; the course stays as it is"}]},
   "fee_check": {"label": "Fee fails the check", "order": 11, "choices": [
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Enter or confirm the fee on the course"},
     {"key": "keep", "label": "Keep the CRICOS total", "returns": "The hold is released; the page fee stays out"}]},
   "counsellor_report": {"label": "Counsellor report", "order": 12, "choices": [
     {"key": "reports", "label": "Open the report", "link": "reports", "returns": "Close it as Fixed or Not changed; Zoho shows the outcome"}]},
   "not_on_site": {"label": "Course not on the university''s site", "order": 13, "choices": [
     {"key": "archive_course", "label": "Archive the course", "rank": 5, "returns": "Unpublished and hidden from the consumer API; reviewable on Archived"},
     {"key": "keep", "label": "Keep it", "returns": "The hold is released; CRICOS still lists it"},
     {"key": "course", "label": "Open the course", "link": "course", "returns": "Enter its page on the course"}]}
  }'::jsonb
$function$;

CREATE OR REPLACE FUNCTION public.admin_layer4_inbox(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_kinds jsonb := security.layer4_inbox_kinds_v1(); v_kind text; v_ref text; v_choice text; v_reason text; v_value text; v_pid uuid;
        v_target int := security.pipeline_num_v1('layer4.target_days', 7)::int; v_actor text; v_lim int; v_off int; v_q text; v_r jsonb; v_c jsonb; v_det jsonb; v_out jsonb;
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
                 'created_at', z.created_at, 'late', z.created_at < now() - make_interval(days => v_target), 'detail', z.detail) order by z.o, z.created_at)
               from (select * from x order by o, created_at limit v_lim offset v_off) z), '[]'::jsonb)));
    end if;
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

  if v_kind = 'course_link' then
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,
                                       case when v_choice = 'enter' then to_jsonb(v_value) end);
  elsif v_kind = 'held_scholarship' then
    v_r := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                         'extraction_id', v_det->'extraction_id', 'reason', v_reason));
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
  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref, jsonb_build_object('kind', v_kind, 'ref', v_ref, 'choice', v_choice, 'value', v_value, 'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid());
  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r);
end $function$;
revoke execute on function public.admin_layer4_inbox(text, jsonb) from public, anon;
grant execute on function public.admin_layer4_inbox(text, jsonb) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_layer4_inbox', 'Layer 4', 'Layer 4 Inbox: everything that needs a person, by university, with choices and return paths', 'active', '20261020040000'),
 ('function', 'security.layer4_inbox_items_v1', 'Layer 4', 'Layer 4 Inbox: items from every source that needs a person', 'active', '20261020040000'),
 ('function', 'security.layer4_inbox_kinds_v1', 'Layer 4', 'Layer 4 Inbox: kinds, choices and return paths', 'active', '20261020040000')
on conflict (kind, name) do nothing;
