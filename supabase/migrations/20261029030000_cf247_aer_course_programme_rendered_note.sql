-- CF-247 AER programme (Platform Admin decision 29 Oct 2026 09:57, "Continue the full AER programme", items 3 and 4; admin
-- docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W17-W18, added 29 Oct 2026).
-- 1. Course-level reading widened to the approved provider plan as a measured, settings-controlled programme on the existing Enrich fields
--    lane (B1 rules unchanged: stored official course page, strong identity, quote on the page, a band only when printed, no English-test
--    rows, no inferred international applicability, one Layer 4 course_entry_first_read item a course).
--    * entry.course_read_providers (the plan's course-level providers in priority order: Monash and QUT publish requirements on course
--      pages only, RMIT's band ladder needs printed course bands, then the plan's other Australian providers), entry.course_batch_size
--      (50 courses a batch) and entry.course_read_cost_usd (the cost estimate used until 20 course reads are measured).
--    * security.course_entry_programme_v1: per provider eligible, read, waiting, in Layer 4, admitted, held and remaining courses, the
--      measured cost a course and the OpenRouter balance against its existing credit floor (Toolsets & limits).
--    * security.course_entry_batch_v1: a preview (count and estimated cost), then one bounded batch: one Enrich fields task, never more than
--      entry.course_batch_size courses, only courses never read, refused while an earlier course read waits, when AI is stopped, or when the
--      estimate would take the balance below the credit floor. Platform Admin only (Catalogue › Entry requirements › Course entry
--      requirements › Course-level reading).
-- 2. Step C no-table outcome (ENTRY-REQUIREMENTS-IMPLEMENTATION.md Part 3, route C): a rendered page read with no requirements table opens a
--    Layer 4 note in the existing vocabulary (entry_matrix_first_run / entry_matrix_change, status pending, no rows). Approving it confirms
--    "no matrix published here" (the website says "contact the provider"); it admits and supersedes nothing. The three rendered reads that
--    already ended with no rows (Newcastle, Griffith, Victoria University of Wellington) get their note now (bounded at 5).
-- Replaces: public.admin_aer, public.svc_entry_matrix_record, security.entry_matrix_review_apply_v1 (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, Layer 4 field or status.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- ---------------------------------------------------------------- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.course_read_providers', 'Course entry requirements: providers read',
  'Providers whose course pages are read for academic entry requirements, in the order batches take them. Only courses of countries in "Course entry requirements: countries read" are read.', 'list',
  '["543b87b8-f0dd-4bc7-80d6-76252cfaabec", "2c4f515c-c146-4e90-ba8a-294130aa1f40", "8e1adb6c-e069-43db-9584-bd054255e702",
    "0a42da16-8df1-4439-a929-4dfdd04b6d83", "1719c3ba-1ddf-483e-935e-c750124ba99c", "188103a5-1aba-4f99-bd3e-0416659086d3", "22657140-1cb0-4fa7-91df-90518ea8b35b",
    "349da14b-66b1-4c57-9dfd-6f9c36412432", "62e61a02-9fcb-4c5e-bb11-1c43bed6eee6", "68022bdf-43e8-44b3-ac14-e9eed9f71e83", "9109fe0c-9f44-4e2d-a136-eb00dec24701",
    "982fb12f-41ed-4358-9d1b-d7422b3089dd", "9cc8ef21-52ec-4c18-849a-598ba1072459", "9d22a19e-c3f7-4012-b738-17bc0b481e7f", "bac82321-ded7-4e10-a71d-b18f3ae4d1c7",
    "de2201a1-69ee-40ff-b6aa-0e54e535e6c0", "de6d32b0-f91b-4dd0-a3da-a542f1aba5f2", "e47a940d-186f-4a17-bb22-2b794b73248c", "e55396d2-869a-46ef-9d17-841c7eab1313",
    "1822b40a-8b13-44dc-8c37-106ae31bb447", "36086f5e-9fe0-4878-aa40-1897a7d8cb24"]'::jsonb,
  null, null, 'providers', 915, 'Entry requirements', 'security.course_entry_programme_v1, security.course_entry_batch_v1',
  'CF-247 AER programme 29 Oct 2026 (Platform Admin decision 09:57 item 3): the approved plan''s Australian providers; Monash and QUT (course pages only) and RMIT (band ladder) first'),
 ('pipeline', 'entry.course_batch_size', 'Course entry requirements: courses a batch', 'The most courses one "Read next batch" asks for. Each course read opens one Layer 4 item.', 'number',
  to_jsonb(50), 1, 200, 'courses', 916, 'Entry requirements', 'security.course_entry_batch_v1',
  'CF-247 AER programme 29 Oct 2026 (Platform Admin decision 09:57 item 3): bounded batches, never an all-course run'),
 ('pipeline', 'entry.course_read_cost_usd', 'Course entry requirements: estimated cost a course', 'The cost a course read is estimated at until 20 course reads have been measured; after that the measured average is used.', 'number',
  to_jsonb(0.005), 0.001, 0.1, 'USD a course', 917, 'Entry requirements', 'security.course_entry_programme_v1, security.course_entry_batch_v1',
  'CF-247 AER programme 29 Oct 2026: the BH126 reads cost US$0.0024 and US$0.0045')
on conflict (toolset_key, key) do nothing;

-- ---------------------------------------------------------------- the programme: eligibility and counts (read)
create or replace function security.course_entry_eligible_v1() returns table(course_id uuid, provider_id uuid, prio bigint, title text)
language sql stable security definer set search_path to '' as $$
  with scope as (select (e.v)::uuid pid, e.o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) with ordinality e(v, o))
  select c.id, c.provider_id, scope.o, c.canonical_title
    from catalogue.courses c
    join scope on scope.pid = c.provider_id
    join catalogue.providers p on p.id = c.provider_id
    join ref.countries k on k.id = p.country_id
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
   where c.lifecycle_status = 'active'
     and coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb) ? k.iso_alpha2
     and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
$$;
revoke all on function security.course_entry_eligible_v1() from public, anon, authenticated;
comment on function security.course_entry_eligible_v1() is 'CF-247 AER course-level programme (29 Oct 2026): courses whose stored official page and strong identity admit an entry-requirements read (B1), in the plan''s priority order. Owner only.';

create or replace function security.course_entry_cost_v1() returns numeric
language sql stable security definer set search_path to '' as $$
  -- the measured average once 20 course reads have cost something; the setting until then
  select case when count(*) >= 20 then avg(f.cost_usd) else security.pipeline_num_v1('entry.course_read_cost_usd', 0.005) end  -- fixed: 20 reads before the average is trusted
    from pipeline.field_enrich_items f where f.field = 'entry_requirements' and coalesce(f.cost_usd, 0) > 0
$$;
revoke all on function security.course_entry_cost_v1() from public, anon, authenticated;

create or replace function security.course_entry_programme_v1(p_can_batch boolean) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_cost numeric := security.course_entry_cost_v1(); v_rows jsonb; v_bal numeric; v_floor numeric;
begin
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  with el as (select * from security.course_entry_eligible_v1()),
  scope as (select (e.v)::uuid pid, e.o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) with ordinality e(v, o)),
  it as (select f.course_id, bool_or(f.state in ('queued', 'waiting', 'ai', 'leased')) waiting, bool_or(f.state = 'review') review,
                bool_or(f.state = 'filled') filled, bool_or(f.state = 'skipped') skipped, sum(coalesce(f.cost_usd, 0)) cost
           from pipeline.field_enrich_items f where f.field = 'entry_requirements' group by f.course_id),
  rq as (select x.course_id, count(*) filter (where x.status = 'proposed') proposed, count(*) filter (where x.status = 'active') active,
                count(*) filter (where x.status in ('inactive', 'unverified')) held from catalogue.course_entry_requirements x group by x.course_id),
  per as (select scope.pid, scope.o, coalesce(p.display_name, p.canonical_name) provider_name, k.iso_alpha2 country,
                 count(el.course_id) eligible,
                 count(el.course_id) filter (where it.course_id is not null and not it.waiting) read,
                 count(el.course_id) filter (where it.waiting) waiting,
                 count(el.course_id) filter (where coalesce(rq.proposed, 0) > 0) in_layer4,
                 coalesce(sum(rq.proposed), 0) proposed_rows,
                 count(el.course_id) filter (where coalesce(rq.active, 0) > 0) admitted,
                 coalesce(sum(rq.active), 0) active_rows,
                 count(el.course_id) filter (where it.course_id is not null and not it.waiting and coalesce(rq.proposed, 0) = 0 and coalesce(rq.active, 0) = 0) no_rows,
                 count(el.course_id) filter (where it.course_id is null) remaining,
                 coalesce(sum(it.cost), 0) spent
            from scope join catalogue.providers p on p.id = scope.pid left join ref.countries k on k.id = p.country_id
            left join el on el.provider_id = scope.pid left join it on it.course_id = el.course_id left join rq on rq.course_id = el.course_id
           group by scope.pid, scope.o, p.display_name, p.canonical_name, k.iso_alpha2)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', pid, 'provider_name', provider_name, 'country', country, 'eligible', eligible, 'read', read, 'waiting', waiting,
           'in_layer4', in_layer4, 'proposed_rows', proposed_rows, 'admitted', admitted, 'active_rows', active_rows, 'no_rows', no_rows, 'remaining', remaining,
           'spent_usd', round(spent, 4), 'estimate_remaining_usd', round(remaining * v_cost, 2)) order by o), '[]'::jsonb) into v_rows from per;
  return jsonb_build_object('providers', v_rows, 'cost_per_course_usd', round(v_cost, 5),
    'cost_basis', case when (select count(*) from pipeline.field_enrich_items f where f.field = 'entry_requirements' and coalesce(f.cost_usd, 0) > 0) >= 20 then 'measured' else 'setting' end,
    'batch_size', security.pipeline_num_v1('entry.course_batch_size', 50)::int, 'balance_usd', v_bal, 'floor_usd', v_floor,
    'countries', coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb),
    'ai_allowed', security.ai_use_allowed_v1('enrich_fields'),
    'waiting', (select count(*) from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')),
    'can_batch', p_can_batch);
end $$;
revoke all on function security.course_entry_programme_v1(boolean) from public, anon, authenticated;
comment on function security.course_entry_programme_v1(boolean) is 'CF-247 AER course-level programme (29 Oct 2026): per-provider eligible, read, waiting, Layer 4, admitted, no-row and remaining courses, cost and balance. Read through public.admin_aer(''course_programme''). Owner only.';

-- ---------------------------------------------------------------- one bounded batch (preview first)
create or replace function security.course_entry_batch_v1(p_provider uuid, p_size int, p_reason text, p_actor uuid, p_preview boolean default true) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_max int := security.pipeline_num_v1('entry.course_batch_size', 50)::int; v_n int; v_ids uuid[]; v_cost numeric := security.course_entry_cost_v1();
        v_bal numeric; v_floor numeric; v_est numeric; v_job uuid; v_reason text := btrim(coalesce(p_reason, '')); v_prov jsonb; v_wait int;
begin
  v_n := greatest(1, least(coalesce(p_size, v_max), v_max));
  select array_agg(z.course_id order by z.prio, z.title, z.course_id), jsonb_object_agg(z.pname, z.k) into v_ids, v_prov from (
    select q.course_id, q.prio, q.title, coalesce(p.display_name, p.canonical_name) pname, count(*) over (partition by q.provider_id) k
      from (select el.* from security.course_entry_eligible_v1() el
             where (p_provider is null or el.provider_id = p_provider)
               and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = el.course_id and f.field = 'entry_requirements')
             order by el.prio, el.title, el.course_id limit v_n) q
      join catalogue.providers p on p.id = q.provider_id) z;
  v_est := round(coalesce(array_length(v_ids, 1), 0) * v_cost, 4);
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  select count(*) into v_wait from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  if p_preview then
    return jsonb_build_object('preview', true, 'courses', coalesce(array_length(v_ids, 1), 0), 'providers', coalesce(v_prov, '{}'::jsonb), 'estimate_usd', v_est,
      'cost_per_course_usd', round(v_cost, 5), 'balance_usd', v_bal, 'floor_usd', v_floor, 'batch_size', v_max, 'waiting', v_wait,
      'refusal', case when coalesce(array_length(v_ids, 1), 0) = 0 then 'no course is left to read for this choice'
                      when v_wait > 0 then 'an earlier course read is still waiting; the next batch follows it'
                      when not security.ai_use_allowed_v1('enrich_fields') then 'AI reading is stopped (AI limits)'
                      when v_bal is not null and v_bal - v_est < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end);
  end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)' using errcode = '22023'; end if;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no course is left to read for this choice' using errcode = '22023'; end if;
  if v_wait > 0 then raise exception 'an earlier course read is still waiting (% courses); the next batch follows it', v_wait using errcode = '22023'; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'AI reading is stopped (AI limits); nothing was asked' using errcode = '22023'; end if;
  if v_bal is not null and v_bal - v_est < v_floor then
    raise exception 'the estimate (US$%) would take the OpenRouter balance (US$%) below its floor (US$%); nothing was asked', v_est, round(v_bal, 2), v_floor using errcode = '22023'; end if;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || array_length(v_ids, 1) || ' courses', 200),
          jsonb_build_object('read_now', true, 'entry_read', true, 'entry_batch', true, 'countries', '[]'::jsonb,
                             'provider_ids', (select jsonb_agg(distinct c.provider_id) from catalogue.courses c where c.id = any (v_ids)), 'course_ids', to_jsonb(v_ids),
                             'fields', jsonb_build_array('entry_requirements'), 'ai', true, 'scraper', false, 'estimate_usd', v_est),
          jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), p_actor, v_reason, array_length(v_ids, 1) || ' courses')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
  select v_job, c.provider_id, c.id, 'entry_requirements', 'queued' from catalogue.courses c where c.id = any (v_ids)
  on conflict do nothing;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_requirements', 'course_batch', v_job::text, jsonb_build_object('courses', array_length(v_ids, 1), 'providers', v_prov, 'estimate_usd', v_est, 'reason', v_reason), p_actor);
  return jsonb_build_object('ok', true, 'job_id', v_job, 'courses', array_length(v_ids, 1), 'providers', v_prov, 'estimate_usd', v_est);
end $$;
revoke all on function security.course_entry_batch_v1(uuid, int, text, uuid, boolean) from public, anon, authenticated;
comment on function security.course_entry_batch_v1(uuid, int, text, uuid, boolean) is 'CF-247 AER course-level programme (29 Oct 2026): preview, then one bounded Enrich fields task of never-read eligible courses (entry.course_batch_size), refused while a course read waits, when AI is stopped, or below the OpenRouter credit floor. Platform Admin through public.admin_aer(''course_batch''), or an approved programme migration. Owner only.';

-- ---------------------------------------------------------------- Step C: a rendered page with no requirements table opens a Layer 4 note
create or replace function security.entry_rendered_note_v1(p_run uuid) returns uuid
language plpgsql security definer set search_path to '' as $$
declare r pipeline.entry_matrix_runs%rowtype; f pipeline.entry_matrix_sources%rowtype; v_first boolean; v_item uuid;
begin
  select * into r from pipeline.entry_matrix_runs where id = p_run;
  select * into f from pipeline.entry_matrix_sources where id = r.source_id;
  if r.id is null or f.id is null or r.review_item_id is not null then return r.review_item_id; end if;
  v_first := not exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active');
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                           status, escalation_reason, change_control_ref)
  values ('provider', r.provider_id, case when v_first then 'entry_matrix_first_run' else 'entry_matrix_change' end, f.evidence_id,
          jsonb_build_object('active_rows', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active')),
          jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', 0, 'outcome', 'no_requirements_table', 'rendered', true,
                             'dropped', jsonb_array_length(coalesce(r.result->'dropped', '[]'::jsonb)), 'sample', '[]'::jsonb),
          jsonb_build_object('source', 'entry matrix reader (rendered page)', 'page', f.url, 'entry_matrix_source_id', f.id),
          jsonb_build_object('run_id', r.id, 'model', r.model_code),
          'pending',
          'Rendered page read: no requirements table found. Approve to confirm the provider publishes no matrix on this page (the website then says "contact the provider"); reject if the page does show one. No row is admitted or replaced either way.',
          'CF-CHG-20260915-247')
  returning id into v_item;
  update pipeline.entry_matrix_runs set review_item_id = v_item, result = coalesce(result, '{}'::jsonb) || jsonb_build_object('outcome', 'no_requirements_table'), updated_at = now()
   where id = r.id;
  return v_item;
end $$;
revoke all on function security.entry_rendered_note_v1(uuid) from public, anon, authenticated;
comment on function security.entry_rendered_note_v1(uuid) is 'CF-247 AER Step C (29 Oct 2026): a rendered entry page read with no requirements table opens one Layer 4 note (existing entry_matrix_first_run / entry_matrix_change vocabulary, no rows). Owner only.';

select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', '15fb11f83f24859131866e564875157a', array[
  array[$o$  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows'$o$,
        $n$  -- Step C (29 Oct 2026): a rendered page (entry.render_hosts) read with no row opens a Layer 4 note; a person confirms "no matrix published here"
  if v_in = 0 and f.read_via = 'firecrawl'
     and coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(f.url from '^https?://(?:www\.)?([^/:?#]+)')) then
    v_item := security.entry_rendered_note_v1(r.id);
  end if;
  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows'$n$]], array[1]);

-- approving the note confirms the outcome only: nothing is admitted, quarantined or superseded
select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'f1152d19721585c7767a9c65ae1d76b5', array[
  array[$o$  if p_action = 'approve' then
    v_ex := $o$,
        $n$  -- Step C (29 Oct 2026): a rendered page with no requirements table; approval confirms "no matrix published here" and changes no row
  if r.rows_admitted = 0 and r.result->>'outcome' = 'no_requirements_table' then
    return jsonb_build_object('entry_matrix_run', r.id, 'admitted', 0, 'quarantined', 0, 'superseded', 0, 'outcome', 'no_requirements_table', 'decision', p_action);
  end if;
  if p_action = 'approve' then
    v_ex := $n$]], array[1]);

-- the rendered reads that already ended with no row get their note (bounded)
do $$ declare v_n int := 0; r record; begin
  for r in select x.id from pipeline.entry_matrix_runs x join pipeline.entry_matrix_sources f on f.id = x.source_id
            where x.state = 'done' and x.rows_admitted = 0 and x.review_item_id is null and f.read_via = 'firecrawl'
              and coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(f.url from '^https?://(?:www\.)?([^/:?#]+)'))
              and x.created_at = (select max(x2.created_at) from pipeline.entry_matrix_runs x2 where x2.source_id = x.source_id) loop
    perform security.entry_rendered_note_v1(r.id); v_n := v_n + 1;
  end loop;
  if v_n > 5 then raise exception 'expected at most 5 rendered no-table reads, found %', v_n; end if;
end $$;

-- ---------------------------------------------------------------- the workspace: Course-level reading (read for every role, batch for the Platform Admin)
select pg_temp.edit_n('public.admin_aer(text,jsonb)', 'bc7fe7800090daa1135c4087a93c2008', array[
  array[$o$  elsif p_action = 'options' then$o$,
        $n$  elsif p_action = 'course_programme' then
    -- W17 (29 Oct 2026): the course-level programme by provider, with cost and balance
    return security.course_entry_programme_v1(v_rank >= 6);

  elsif p_action = 'course_batch_preview' then
    -- W17: how many courses the next batch would read and what it is estimated to cost; asks nothing
    return security.course_entry_batch_v1((a->>'provider_id')::uuid, (a->>'size')::int, null, auth.uid(), true);

  elsif p_action = 'options' then$n$],
  array[$o$  if p_action not in ('update', 'add', 'lifecycle', 'reread') then raise exception 'unknown action %', p_action; end if;$o$,
        $n$  if p_action = 'course_batch' then
    -- W17: one bounded batch of course reads (Platform Admin); every course read goes to Layer 4
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    return security.course_entry_batch_v1((a->>'provider_id')::uuid, (a->>'size')::int, v_reason, auth.uid(), false);
  end if;
  if p_action not in ('update', 'add', 'lifecycle', 'reread') then raise exception 'unknown action %', p_action; end if;$n$],
  array[$o$'worker', r3.result->>'worker', 'review_item_id', r3.review_item_id,$o$,
        $n$'worker', r3.result->>'worker', 'outcome', r3.result->>'outcome', 'review_item_id', r3.review_item_id,$n$]], array[1, 1, 1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_entry_eligible_v1', 'Pipeline', 'AER course-level programme: courses eligible for an entry-requirements read (B1), in priority order', 'active', '{}', '20261029030000'),
 ('function', 'security.course_entry_cost_v1', 'Pipeline', 'AER course-level programme: cost a course read (measured, or the setting)', 'active', '{}', '20261029030000'),
 ('function', 'security.course_entry_programme_v1', 'Pipeline', 'AER course-level programme: per-provider counts, cost and balance', 'active', '{}', '20261029030000'),
 ('function', 'security.course_entry_batch_v1', 'Pipeline', 'AER course-level programme: preview and one bounded batch of course reads', 'active', '{}', '20261029030000'),
 ('function', 'security.entry_rendered_note_v1', 'Pipeline', 'AER Step C: Layer 4 note for a rendered page with no requirements table', 'active', '{}', '20261029030000')
on conflict do nothing;
