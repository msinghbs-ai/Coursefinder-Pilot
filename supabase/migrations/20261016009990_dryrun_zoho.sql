-- CF-247 (23 Oct 2026). Platform Admin 07:16: "I want audit and logging of exactly what happened and was tried to fetch nz Auckland
-- university data in the screenshot. Atleast I can make decision where the gap is." 07:24: "Feature request, read course pages with ai
-- button courses, that can run specific course page if course page is changed and still in adapter course changes that were wrong had
-- no course has no resolution."
-- 1 public.admin_course_audit(course): everything recorded for one course, newest first in each part: its page (how it was found,
--   bound, read, refused), every page read kept as evidence, the page searches and the AI page match tries with what they chose,
--   page relinks, every field the AI fill tried with its result and reason, every field admission or refusal, fee reader rows,
--   cross-check findings, credential reads, scope changes, values held now (fees, intakes, English, campuses, duration, delivery,
--   international), values set by hand, and every Read with AI request.
-- 2 public.admin_course_read_now(course, reason): "Read with AI". The course's page is read again on the next page-reader run
--   (first in line), and an AI fill task is made for this one course for the fields it does not hold (campus, duration, delivery,
--   study level, field of study, open to international students). With no page found yet, the page search and AI page match keep
--   looking and the answer says so. Logged in pipeline.admin_control_events (area course, action read_now).
-- Replaces: nothing
-- Retires: nothing

create or replace function public.admin_course_audit(p_course_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_c record;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select c.id, c.canonical_title, c.course_code, c.lifecycle_status, c.course_url, c.provider_id, p.display_name provider, security.coverage_country(c.provider_id) country,
         sl.code level, c.duration_value, c.duration_unit, c.delivery_mode, c.open_to_international, c.created_at
    into v_c from catalogue.courses c join catalogue.providers p on p.id = c.provider_id left join ref.study_levels sl on sl.id = c.study_level_id where c.id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  return jsonb_build_object(
    'course', to_jsonb(v_c),
    'page', (select to_jsonb(x) from (select pg.url, pg.basis, pg.status, pg.read_status, pg.read_at, pg.http_status, pg.fetched_via, pg.identity_basis, pg.read_attempts, pg.bound_at, pg.next_read_at
                                         from pipeline.coverage_course_pages pg where pg.course_id = p_course_id) x),
    'reads', (select coalesce(jsonb_agg(to_jsonb(x) order by x.at desc), '[]'::jsonb) from (
               select e.captured_at at, e.source_url url, e.metadata->>'fetched_via' via, e.metadata->>'identity_basis' identity, e.id evidence_id
                 from pipeline.evidence_artifacts e where e.metadata->>'course_id' = p_course_id::text order by e.captured_at desc limit 20) x),  -- fixed: the latest reads are enough to see what happened
    'searches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
               select s.stage, s.state, s.query, s.attempts, s.results, s.bound_url, s.queued_at, s.done_at from pipeline.course_link_search s where s.course_id = p_course_id) x),
    'ai_match', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
               select q.attempt, q.state, q.chosen_url, jsonb_array_length(coalesce(q.candidates, '[]'::jsonb)) candidates, q.answer->>'reason' reason, q.answer->>'error' error, q.answer->>'refused' refused,
                      q.model, q.cost_usd, q.created_at, q.decided_at from pipeline.coverage_ai_match q where q.course_id = p_course_id) x),
    'relinks', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
               select r.old_url, r.new_url, r.reason, r.at from pipeline.page_link_repairs r where r.course_id = p_course_id
               union all select l.old_url, l.result_url, coalesce(l.reason, l.state), coalesce(l.decided_at, l.started_at) from pipeline.course_relink l where l.course_id = p_course_id) x),
    'field_fills', (select coalesce(jsonb_agg(to_jsonb(x) order by x.updated_at desc), '[]'::jsonb) from (
               select i.field, i.state, i.source, i.value, left(i.quote, 300) quote, i.reason, i.attempts, i.cost_usd, i.updated_at from pipeline.field_enrich_items i where i.course_id = p_course_id) x),
    'admissions', (select coalesce(jsonb_agg(to_jsonb(x) order by x.decided_at desc), '[]'::jsonb) from (
               select a.field_key, a.status, a.reason_code, a.decided_at, left(a.candidate_payload::text, 300) candidate from pipeline.layer2_field_admissions a where a.course_id = p_course_id order by a.decided_at desc limit 50) x),  -- fixed: the latest admissions
    'fee_rows', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
               select f.amount_min, f.amount_max, f.currency_code, f.unit, f.audience, f.fee_year, f.outcome, f.note, left(f.quote, 300) quote, f.created_at from pipeline.fee_reader_rows f where f.course_id = p_course_id) x),
    'crosschecks', (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
               select k.field, k.held_value, k.page_value, k.state, left(k.quote, 300) quote, k.found_at from pipeline.field_crosscheck_findings k where k.course_id = p_course_id) x),
    'credential', (select to_jsonb(x) from (select r.outcome, r.study_level_code, r.basis, r.read_at from pipeline.course_credential_reads r where r.course_id = p_course_id) x),
    'scope', (select coalesce(jsonb_agg(to_jsonb(x) order by x.at desc), '[]'::jsonb) from (
               select s.at, s.from_status, s.to_status, s.rule, s.scope_tag from pipeline.course_scope_changes s where s.course_id = p_course_id) x),
    'held', jsonb_build_object(
       'fees', (select coalesce(jsonb_agg(jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'audience', f.audience, 'basis', f.basis, 'year', f.fee_year, 'status', f.status)), '[]'::jsonb) from catalogue.course_fees f where f.course_id = p_course_id),
       'intakes', (select coalesce(jsonb_agg(jsonb_build_object('label', i.intake_label, 'year', i.intake_year, 'status', i.status)), '[]'::jsonb) from catalogue.course_intakes i where i.course_id = p_course_id),
       'english', (select coalesce(jsonb_agg(jsonb_build_object('test', t.name, 'overall', e.overall_score, 'status', e.status)), '[]'::jsonb) from catalogue.course_english_requirements e left join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id),
       'campuses', (select coalesce(jsonb_agg(k.name), '[]'::jsonb) from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id where cc.course_id = p_course_id)),
    'locks', (select coalesce(jsonb_agg(jsonb_build_object('field', l.field, 'mode', l.mode, 'at', l.set_at)), '[]'::jsonb) from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p_course_id),
    'read_now', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'detail', e.detail) order by e.created_at desc), '[]'::jsonb) from pipeline.admin_control_events e where e.area = 'course' and e.action = 'read_now' and e.target = p_course_id::text),
    'can_read_now', v_rank >= 3);
end $function$;
revoke all on function public.admin_course_audit(uuid) from public, anon;
grant execute on function public.admin_course_audit(uuid) to authenticated;

create or replace function public.admin_course_read_now(p_course_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_c record; v_page int; v_job uuid; v_fields text[]; v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the request)'; end if;
  select c.id, c.provider_id, c.canonical_title, c.study_level_id, c.duration_value, c.delivery_mode, c.primary_field_id, c.open_to_international into v_c
    from catalogue.courses c where c.id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  -- 1 the page, read again first in line
  update pipeline.coverage_course_pages set next_read_at = now(), read_attempts = 0, leased_until = null
   where course_id = p_course_id and status in ('bound', 'ambiguous');
  get diagnostics v_page = row_count;
  if v_page > 0 and not exists (select 1 from pipeline.course_priority cp where cp.course_id = p_course_id) then
    insert into pipeline.course_priority(course_id, sort) values (p_course_id, 0);
  end if;
  -- 2 an AI fill task for this course's missing fields
  v_fields := array_remove(array[
    case when not exists (select 1 from catalogue.course_campuses x where x.course_id = p_course_id) then 'campus' end,
    case when v_c.duration_value is null then 'duration' end,
    case when v_c.study_level_id is null then 'level' end,
    case when nullif(btrim(v_c.delivery_mode), '') is null then 'delivery' end,
    case when v_c.primary_field_id is null then 'field_of_study' end,
    case when v_c.open_to_international is null then 'international' end], null);
  if cardinality(v_fields) > 0 then
    insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
    values ('enrich_fields', 'enrich', 'queued', left('Read with AI · ' || v_c.canonical_title, 200),
            jsonb_build_object('countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(v_c.provider_id), 'course_ids', jsonb_build_array(p_course_id), 'fields', to_jsonb(v_fields), 'ai', true, 'scraper', false),
            jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, '1 course')
    returning id into v_job;
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, v_c.provider_id, p_course_id, f from unnest(v_fields) f on conflict do nothing;
    if 'campus' = any (v_fields) then
      insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_job, v_c.provider_id, null, 'campus_list', 'waiting') on conflict do nothing;
    end if;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('course', 'read_now', p_course_id::text, jsonb_build_object('reason', v_reason, 'page_read_again', v_page > 0, 'ai_fields', to_jsonb(coalesce(v_fields, '{}')), 'job_id', v_job), auth.uid());
  return jsonb_build_object('page_read_again', v_page > 0, 'ai_fields', to_jsonb(coalesce(v_fields, '{}')), 'job_id', v_job,
    'note', case when v_page = 0 then 'No course page found yet: the page search and AI page match keep looking (see What happened).' end);
end $function$;
revoke all on function public.admin_course_read_now(uuid, text) from public, anon;
grant execute on function public.admin_course_read_now(uuid, text) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_course_audit', 'Platform', 'What happened to one course: pages, reads, searches, AI tries, field fills, admissions, values held', 'active', '{}', '20261023006000'),
 ('function', 'public.admin_course_read_now', 'Platform', 'Read with AI: read one course page again first in line and fill its missing fields with AI', 'active', '{}', '20261023006000')
on conflict (kind, name) do nothing;

select 'course audit and read with AI ready' ok;

do $t$ declare a jsonb; r jsonb; begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  a := public.admin_course_audit('500fc010-f941-4e24-b1a6-0e11a5f6fed0');
  r := public.admin_course_read_now('500fc010-f941-4e24-b1a6-0e11a5f6fed0', 'dry run test');
  raise exception 'DRYRUN OK %', jsonb_build_object('keys', (select jsonb_agg(k) from jsonb_object_keys(a) k), 'page', a->'page'->>'url', 'reads', jsonb_array_length(a->'reads'), 'ai', jsonb_array_length(a->'ai_match'), 'fills', jsonb_array_length(a->'field_fills'), 'held', a->'held', 'read_now', r,
    'job_items', (select count(*) from pipeline.field_enrich_items i where i.job_id = (r->>'job_id')::uuid)); end $t$;
