-- CF-247 (Decision 227, 2 Oct 2026). English requirements from the university's own English language policy
-- (Platform Admin, 16:42, by multiple choice: "English from uni policy"), following the Decision 162 precedent
-- (provider default by study level plus named exceptions).
--  * A proposal parsed from a policy document (parser provider-policy-v0.2.0) is planned course by course:
--      - a course the policy names with its own requirement (exact title) gets that requirement;
--      - a single-award undergraduate (bachelor, honours, associate degree) or postgraduate coursework (graduate
--        certificate, graduate diploma, coursework masters) course gets the policy's default for its level;
--      - held back, never defaulted: research degrees, double degrees, exit awards, other levels (diplomas,
--        certificates, professional and non-award study), a course whose title is named in the policy or close to a
--        name in it (the policy may set a different requirement), and a level the policy gives no default for.
--  * Written only where the course has no English requirement at all (hand-entered values and course-page values are
--    never overwritten), is not set by hand, has no English review open, no AI check in progress and no course page
--    still waiting to be read. Where a course already has a value the plan shows whether it agrees or differs.
--  * Nothing is written until a Platform Admin approves the proposal. Approved proposals are applied again every six
--    hours to courses that become eligible (new courses, pages read since).
--  * Admin read (Pipeline Operator and above) and decide (Platform Admin) functions; calendar proposals can be approved
--    too (used by the semester-to-month step, Decision 228).

-- 1. a document that names courses with their own requirement is a proposal even without a level default
do $p$
declare s text; d text;
  o1 text := $o$when f.kind = 'english_policy' and coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb then 'proposed'$o$;
  n1 text := $n$when f.kind = 'english_policy' and (coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb
           or exists (select 1 from jsonb_array_elements(coalesce(p_parsed->'exceptions', '[]'::jsonb)) e
                       where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0)) then 'proposed'$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'svc_provider_policy_record';
  if md5(s) is distinct from '022be783d783c36b24c34722dfe4ed40' then raise exception 'svc_provider_policy_record changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

-- 2. the plan, course by course (one function used by preview, approval and the six-hourly job)
create or replace function security.provider_english_plan_v1(p_proposal_id uuid)
returns table(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
language plpgsql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security' as $f$
declare x pipeline.provider_policy_proposals%rowtype;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  return query
  with nk as (
    select security.english_title_key(n) k, null::jsonb reqs from jsonb_array_elements_text(coalesce(x.proposal->'named', '[]'::jsonb)) n
    union all
    select security.english_title_key(e->>'name'), case when jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0 then e->'reqs' end
      from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e),
  named as (select * from nk where length(nk.k) >= 4),
  c as (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl,
           case when sl.code in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when sl.code in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate' end grp,
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = co.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = co.id) any_row,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = co.id and i.field_code = 'course_english' and i.status = 'pending') in_review,
           exists (select 1 from pipeline.layer3_fact_handoffs h left join pipeline.layer3_work_items w on w.id = h.work_item_id
                    where h.course_id = co.id and h.task_class = 'provider_english_validation'
                      and (h.work_item_id is null or w.status in ('interpreting', 'validated', 'queued', 'pending'))) in_l3,
           exists (select 1 from pipeline.coverage_course_pages g where g.course_id = co.id and g.status in ('bound', 'ambiguous')
                      and (g.read_status is null or g.read_status = 'needs_render')) page_waiting
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  m as (
    select c.*,
           (select jsonb_agg(distinct named.reqs) from named where named.k = c.k and named.reqs is not null) exact_reqs,
           exists (select 1 from named where named.k = c.k) exact_named,
           exists (select 1 from named where named.k <> c.k and (position(named.k in c.k) > 0 or position(c.k in named.k) > 0
                                                                 or security.english_title_overlap(c.k, named.k) >= 0.75)) close_named,
           case when c.grp is not null then x.proposal->'defaults'->c.grp end dflt
      from c),
  p as (
    select m.*,
           case when m.lvl is null then 'held|study level unknown'
                when m.lvl in ('doctorate', 'masters_research') then 'held|research degree'
                when m.t ~* 'exit award' then 'held|exit award only'
                when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'held|double degree'
                when m.exact_reqs is not null and jsonb_array_length(m.exact_reqs) > 1 then 'held|the policy gives this course more than one requirement'
                when m.exact_reqs is not null then 'named|'
                when m.exact_named or m.close_named then 'held|named in the policy (it may have its own requirement)'
                when m.grp is null then 'held|level not covered by the policy default'
                when m.dflt is null or jsonb_typeof(m.dflt) <> 'array' then 'held|the policy gives no default for this level'
                else 'default|' end pr
      from m),
  q as (
    select p.*, split_part(p.pr, '|', 1) pl, nullif(split_part(p.pr, '|', 2), '') rs,
           case when p.pr like 'named|%' then p.exact_reqs->0 when p.pr like 'default|%' then p.dflt end reqs
      from p)
  select q.id, q.t, q.lvl, q.pl, q.rs, q.reqs, q.ex,
         case when q.pl = 'held' then 'held'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code')) then 'agrees'
              when q.any_row then 'other_value'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $f$;
revoke all on function security.provider_english_plan_v1(uuid) from public, anon, authenticated;

-- 3. apply an approved proposal (only the 'write' rows)
create or replace function security.provider_english_apply_v1(p_proposal_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search' as $f$
declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  if x.status <> 'approved' then raise exception 'proposal is not approved'; end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then raise exception 'the policy document has no stored evidence'; end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  for r in select * from security.provider_english_plan_v1(p_proposal_id) where outcome = 'write' loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash,
        jsonb_build_object('english_requirements', (select jsonb_agg(jsonb_build_object(
            'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
            'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
            'notes', case when r.plan = 'named' then 'From ' || v_name || '''s English language policy, which names this course (approved by a Platform Admin, Decision 227)'
                          else 'Default for ' || case when r.study_level in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate coursework' else 'undergraduate' end
                               || ' courses in ' || v_name || '''s English language policy (approved by a Platform Admin, Decision 227)' end))
          from jsonb_array_elements(r.requirements) q where q->>'test_code' in (select code from ref.english_tests))));
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('written', coalesce((apply_summary->>'written')::int, 0) + v_ok,
           'refused', v_err, 'last_error', v_last, 'last_applied_at', now()), updated_at = now()
   where id = p_proposal_id;
  return jsonb_build_object('written', v_ok, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.provider_english_apply_v1(uuid) from public, anon, authenticated;

create or replace function security.provider_english_apply_all_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare r record; v jsonb; v_total int := 0; v_n int := 0;
begin
  for r in select id from pipeline.provider_policy_proposals where kind = 'english_policy' and status = 'approved' order by decided_at loop
    v := security.provider_english_apply_v1(r.id); v_total := v_total + coalesce((v->>'written')::int, 0); v_n := v_n + 1;
  end loop;
  return jsonb_build_object('proposals', v_n, 'written', v_total);
end $f$;
revoke all on function security.provider_english_apply_all_v1() from public, anon, authenticated;

-- 4. read (Pipeline Operator and above)
create or replace function public.admin_provider_policies_read(p_kind text default 'english_policy', p_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  if p_kind not in ('english_policy', 'intake_calendar') then raise exception 'kind must be english_policy or intake_calendar'; end if;
  if p_id is not null then
    select jsonb_build_object('proposal', to_jsonb(x) - 'content_hash', 'provider', coalesce(p.display_name, p.canonical_name),
             'rows', case when x.kind = 'english_policy' then (select coalesce(jsonb_agg(jsonb_build_object('course_id', r.course_id, 'title', r.title, 'study_level', r.study_level,
                   'plan', r.plan, 'reason', r.reason, 'outcome', r.outcome, 'existing', r.existing,
                   'ielts', (select q->'overall_score' from jsonb_array_elements(r.requirements) q where q->>'test_code' = 'IELTS' limit 1))
                   order by case r.outcome when 'write' then 0 when 'differs' then 1 when 'agrees' then 2 else 3 end, r.title), '[]'::jsonb)
                   from security.provider_english_plan_v1(x.id) r) end)
      into v from pipeline.provider_policy_proposals x join catalogue.providers p on p.id = x.provider_id
     where x.id = p_id and x.kind = p_kind;
    if v is null then raise exception 'proposal not found'; end if;
    return v;
  end if;
  select jsonb_build_object(
    'can_decide', security.current_role_rank() >= 6,
    'totals', jsonb_build_object(
      'documents_found', (select count(*) from pipeline.provider_fact_sources f where f.kind = p_kind),
      'documents_read', (select count(*) from pipeline.provider_fact_sources f where f.kind = p_kind and f.status in ('read', 'parsed', 'no_values')),
      'providers_found', (select count(distinct f.provider_id) from pipeline.provider_fact_sources f where f.kind = p_kind),
      'no_values_by_style', (select coalesce(jsonb_object_agg(coalesce(style, 'none'), n), '{}'::jsonb) from (select style, count(*) n from pipeline.provider_policy_proposals
                               where kind = p_kind and status = 'no_values' group by 1) s)),
    'proposals', (select coalesce(jsonb_agg(jsonb_build_object(
         'id', x.id, 'provider_id', x.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
         'url', x.url, 'style', x.style, 'status', x.status, 'parser', x.parser, 'created_at', x.created_at,
         'decided_at', x.decided_at, 'decision_note', x.decision_note, 'apply_summary', x.apply_summary,
         'caveats', x.proposal->'caveats', 'conflicts', x.proposal->'conflicts',
         'defaults', x.proposal->'defaults', 'periods', x.proposal->'periods',
         'named_requirements', (select count(*) from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0),
         'named_courses', jsonb_array_length(coalesce(x.proposal->'named', '[]'::jsonb)),
         'plan', case when x.kind = 'english_policy' and x.status in ('proposed', 'approved')
                      then (select jsonb_object_agg(o, n) from (select r.outcome o, count(*) n from security.provider_english_plan_v1(x.id) r group by 1) s) end)
       order by (x.status = 'proposed') desc, coalesce(p.display_name, p.canonical_name)), '[]'::jsonb)
       from pipeline.provider_policy_proposals x join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id
      where x.kind = p_kind and x.status in ('proposed', 'approved', 'rejected'))) into v;
  return v;
end $f$;
revoke all on function public.admin_provider_policies_read(text, uuid) from public, anon;
grant execute on function public.admin_provider_policies_read(text, uuid) to authenticated;

-- 5. decide (Platform Admin): approving an English policy writes the plan's 'write' rows at once
create or replace function public.admin_provider_policy_decide(p_id uuid, p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare x pipeline.provider_policy_proposals%rowtype; v jsonb := '{}'::jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('approve', 'reject') then raise exception 'action must be approve or reject'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_id for update;
  if x.id is null then raise exception 'proposal not found'; end if;
  if x.status <> 'proposed' then raise exception 'already decided or not a proposal (%)', x.status; end if;
  update pipeline.provider_policy_proposals set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 500), updated_at = now() where id = p_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', p_action, x.kind || ': ' || x.url, jsonb_build_object('decision', 'Decision 227', 'proposal_id', x.id, 'provider_id', x.provider_id), auth.uid());
  if p_action = 'approve' and x.kind = 'english_policy' then v := security.provider_english_apply_v1(p_id); end if;
  return jsonb_build_object('status', case when p_action = 'approve' then 'approved' else 'rejected' end) || v;
end $f$;
revoke all on function public.admin_provider_policy_decide(uuid, text, text) from public, anon;
grant execute on function public.admin_provider_policy_decide(uuid, text, text) to authenticated;

-- 6. approved proposals are applied again every six hours (new courses, course pages read since)
select cron.schedule('provider-english-defaults', '23 */6 * * *', $$select security.provider_english_apply_all_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-english-defaults', 'Admission', 62, 'Apply approved English policies',
        'Gives courses the English requirement from their university''s approved English language policy: the course''s own requirement where the policy names it, otherwise the default for its level. Only courses with no English requirement, no review open and no page still to read; research, double degrees and courses the policy names are held back.', 5, false)
on conflict (jobname) do nothing;
update pipeline.automation_catalogue set label = 'Find and read fee schedules, English policies and calendars',
       description = 'Finds each university''s international fee schedule, English language policy and academic calendar on its own site and reads them as evidence (fee schedules only where the regulator does not publish fees). Fees, English defaults and semester dates are used only after a Platform Admin approves each document.'
 where jobname = 'provider-facts';
