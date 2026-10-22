-- CF-247 (23 Oct 2026). Platform Admin 09:03: "Can we increase the fee reader setting, to get through faster and procced what maximum
-- system can handle. Does the change course url goes to ai, can we push it as priority from course page."
-- Measured: 8 course pages read by the AI fee reader in 11 seconds (about US$0.003 a page); the limit was the job (every 10 minutes,
-- at most 10 pages a run, 2 at a time), about 60 pages an hour against about 250 NZ course pages waiting. A course page changed by a
-- person was read again at once, but its fee went to the AI fee reader only when the course held no fee, and no AI fill followed.
-- 1 Speed: job fee-reader runs every 2 minutes; a run reads up to fees.pages_per_run pages (range now 1 to 40, set to 40),
--   fees.concurrency at a time (new setting, 1 to 8, 4). svc_fee_ai_next caps a call at the pages-a-run setting.
-- 2 First in line from the course page: Read with AI and a changed official course page (Course drawer › Official page) record a
--   fee request (pipeline.fee_course_requests). Once the page has been read after the request, its fee is read by the AI fee reader
--   first in line (queue priority), even when a fee is held: the same admission checks apply, a different fee held from another
--   source goes to Layer 4. The AI fill for the course waits for the new page (field items 'waiting') instead of reading the old copy.
-- Replaces: nothing (svc_fee_ai_next and security.fee_course_pages_enqueue_v1 replaced in full after an md5 check; security.fee_reader_tick_v1,
--   public.admin_course_read_now and public.admin_course_edit edited in place, md5-guarded)
-- Retires: nothing

-- settings (G2) -------------------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set max_value = '40', value = '40'::jsonb, reason = 'Platform Admin 23 Oct 2026 09:03: as fast as the system can handle', updated_at = now()
 where toolset_key = 'pipeline' and key = 'fees.pages_per_run';
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting', 'pipeline.fees.pages_per_run', jsonb_build_object('before', 10, 'after', 40, 'range', '1 to 40', 'reason', 'Platform Admin 23 Oct 2026 09:03: as fast as the system can handle (migration 20261023010000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'fees.concurrency', 'Fee reader: pages read at once', 'How many pages one worker call sends to the AI at the same time.', 'number', '4'::jsonb, '1', '8', 'pages', 349, 'Job sizes', 'job fee-reader', 'Platform Admin 23 Oct 2026 09:03: as fast as the system can handle')
on conflict (toolset_key, key) do nothing;

-- 2 fee requests from the course page ----------------------------------------------------------------------------------------------
create table if not exists pipeline.fee_course_requests (
  course_id uuid primary key,
  requested_at timestamptz not null default now(),
  requested_by uuid,
  reason text,
  queued_at timestamptz,
  outcome text
);
comment on table pipeline.fee_course_requests is 'CF-247 23 Oct 2026 (Platform Admin 09:03 "push it as priority from course page"): a course whose fee the AI fee reader reads first in line once its page has been read after the request (Read with AI, or a changed official page). outcome: queued, not_admitted (the page''s proof does not admit tuition, or the country is not read), page_not_read.';
alter table pipeline.fee_course_requests enable row level security;
alter table pipeline.fee_reader_queue add column if not exists priority int not null default 0;
comment on column pipeline.fee_reader_queue.priority is 'CF-247 23 Oct 2026: 1 for a course page a person asked for (pipeline.fee_course_requests); read before the rest.';

do $do$ begin
  if md5(pg_get_functiondef('security.fee_course_pages_enqueue_v1()'::regprocedure)) <> '48e2950fd49dadf9c067b9298b021b3e' then
    raise exception 'security.fee_course_pages_enqueue_v1 is not the expected version (md5 %)', md5(pg_get_functiondef('security.fee_course_pages_enqueue_v1()'::regprocedure)); end if;
end $do$;
create or replace function security.fee_course_pages_enqueue_v1()
 returns int
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v int := 0; v2 int := 0; rq record; v_hash text;
begin
  if security.pipeline_num_v1('fees.course_pages', 1) < 1 then return 0; end if;
  -- a) requests from the course page, first in line, once the page was read after the request (a fee held does not stop them)
  for rq in
    select q.course_id, g.provider_id, g.evidence_id, g.identity_basis, e.content_hash, k.iso_alpha2 cc, g.read_at, q.requested_at
      from pipeline.fee_course_requests q
      join pipeline.coverage_course_pages g on g.course_id = q.course_id
      left join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
      join catalogue.providers p on p.id = g.provider_id join ref.countries k on k.id = p.country_id
     where q.queued_at is null
     for update of q skip locked
  loop
    if rq.read_at is null or rq.read_at < rq.requested_at or rq.evidence_id is null then
      if rq.requested_at < now() - make_interval(hours => security.pipeline_num_v1('enrich.wait_page_hours', 6)::int) then
        update pipeline.fee_course_requests set queued_at = now(), outcome = 'page_not_read' where course_id = rq.course_id;
      end if;
      continue;
    end if;
    if not security.coverage_identity_allowed(rq.provider_id, rq.identity_basis, 'tuition')
       or rq.cc not in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries') then
      update pipeline.fee_course_requests set queued_at = now(), outcome = 'not_admitted' where course_id = rq.course_id;
      continue;
    end if;
    v_hash := coalesce(rq.content_hash, rq.evidence_id::text);
    update pipeline.fee_reader_queue set state = 'queued', attempts = 0, leased_until = null, error = null, priority = 1
     where course_id = rq.course_id and content_hash = v_hash and state <> 'leased';
    if not found then
      insert into pipeline.fee_reader_queue(fact_source_id, course_id, provider_id, evidence_id, content_hash, priority)
      select rq.evidence_id, rq.course_id, rq.provider_id, rq.evidence_id, v_hash, 1
       where not exists (select 1 from pipeline.fee_reader_queue x where x.fact_source_id = rq.evidence_id and x.content_hash = v_hash);
    end if;
    update pipeline.fee_course_requests set queued_at = now(), outcome = 'queued' where course_id = rq.course_id;
    v2 := v2 + 1;
  end loop;

  -- b) course pages that show one international fee, or an adapter fee excluded for the course, for a course with no fee held
  insert into pipeline.fee_reader_queue(fact_source_id, course_id, provider_id, evidence_id, content_hash)
  select g.evidence_id, g.course_id, g.provider_id, g.evidence_id, coalesce(e.content_hash, g.evidence_id::text)
    from pipeline.coverage_course_pages g
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
    join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
    join catalogue.providers p on p.id = g.provider_id join ref.countries k on k.id = p.country_id
   where g.status = 'bound' and g.read_status = 'read'
     and ((g.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb and security.coverage_tuition_target_v1(g.candidates->'fee') is not null)
          or (g.candidates->>'fee_by' = 'adapter' and nullif(g.candidates->'fee'->>'value', '') is not null and security.uni_adapter_excluded(g.course_id, 'fee')))
     and k.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries')
     and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'tuition')
     and not exists (select 1 from catalogue.course_fees f where f.course_id = g.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active')
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = g.course_id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = g.provider_id)
     and not exists (select 1 from pipeline.fee_reader_queue q where q.course_id = g.course_id and q.content_hash = coalesce(e.content_hash, g.evidence_id::text))
   order by g.read_at desc
   limit security.pipeline_num_v1('fees.course_pages_per_tick', 40)::int
  on conflict do nothing;
  get diagnostics v = row_count;
  return v + v2;
end $function$;
revoke execute on function security.fee_course_pages_enqueue_v1() from public, anon, authenticated;

-- the worker call: pages a run and pages at once from settings ------------------------------------------------------------------
do $do$
declare v_def text := pg_get_functiondef('security.fee_reader_tick_v1()'::regprocedure);
  v_old text := $o$jsonb_build_object('mode', 'fee_ai', 'limit', security.pipeline_num_v1('fees.pages_per_run', 3)::int)$o$;
  v_new text := $n$jsonb_build_object('mode', 'fee_ai', 'limit', security.pipeline_num_v1('fees.pages_per_run', 3)::int, 'concurrency', security.pipeline_num_v1('fees.concurrency', 4)::int)$n$;
begin
  if md5(v_def) <> '57e348492b970fd359a4b7b32bd7c48e' then raise exception 'security.fee_reader_tick_v1 is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee reader tick: expected one worker call'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- the queue: first in line, a call capped by the pages-a-run setting ------------------------------------------------------------
do $do$
declare v_def text := pg_get_functiondef('public.svc_fee_ai_next(integer)'::regprocedure);
  v_old text := $o$order by y.created_at limit greatest(1, least(coalesce(p_limit, 3), 10)) for update skip locked)$o$;
  v_new text := $n$order by y.priority desc, y.created_at limit greatest(1, least(coalesce(p_limit, 3), security.pipeline_num_v1('fees.pages_per_run', 10)::int)) for update skip locked)$n$;
begin
  if md5(v_def) <> '8d3e3bc86bed294b553f47c3c9a9dcab' then raise exception 'public.svc_fee_ai_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee next: expected one queue order'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- Read with AI: fee first in line; the AI fill waits for the new page ------------------------------------------------------------
do $do$
declare v_def text := pg_get_functiondef('public.admin_course_read_now(uuid,text)'::regprocedure);
  v_old text := $o$    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, v_c.provider_id, p_course_id, f from unnest(v_fields) f on conflict do nothing;$o$;
  v_new text := $n$    -- 23 Oct 2026 09:03: with the page being read again, the fields wait for the new page (not the old copy)
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
    select v_job, v_c.provider_id, p_course_id, f, case when v_page > 0 and f <> 'campus' then 'waiting' else 'queued' end from unnest(v_fields) f on conflict do nothing;$n$;
  v_old2 text := $o$  -- 2 an AI fill task for this course's missing fields$o$;
  v_new2 text := $n$  -- the AI fee reader reads this course's page first in line once it has been read again (Platform Admin 23 Oct 09:03)
  if v_page > 0 then
    insert into pipeline.fee_course_requests(course_id, requested_at, requested_by, reason) values (p_course_id, now(), auth.uid(), v_reason)
    on conflict (course_id) do update set requested_at = now(), requested_by = auth.uid(), reason = v_reason, queued_at = null, outcome = null;
  end if;
  -- 2 an AI fill task for this course's missing fields$n$;
begin
  if md5(v_def) <> '476599db53c431f06b8123f30d2355dc' then raise exception 'public.admin_course_read_now is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'read now: expected one item insert'; end if;
  if (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1 then raise exception 'read now: expected one fill step'; end if;
  execute replace(replace(v_def, v_old, v_new), v_old2, v_new2);
end $do$;

-- a changed official course page: Read with AI for it, with the new address as the reason ---------------------------------------
do $do$
declare v_def text := pg_get_functiondef('public.admin_course_edit(uuid,text,jsonb)'::regprocedure);
  v_old text := $o$perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');$o$;
  v_new text := $n$perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');
    -- 23 Oct 2026 (Platform Admin 09:03): the new page is read first in line, then its fee by the AI fee reader and the missing fields by the AI fill
    perform public.admin_course_read_now(p_course_id, left('Official page changed to ' || v_url || coalesce(' (' || v_reason || ')', ''), 500));$n$;
begin
  if md5(v_def) <> '2871afd49504d43d136ed110d7cd3873' then raise exception 'public.admin_course_edit is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'course edit: expected one official page lock'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- every 2 minutes ----------------------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = replace(description, 'Every 10 minutes:', 'Every 2 minutes:')
 where jobname = 'fee-reader' and description like 'Every 10 minutes:%';
select cron.alter_job((select jobid from cron.job where jobname = 'fee-reader'), schedule := '*/2 * * * *');

select 'fee reader every 2 minutes; course page requests first in line' ok;
do $t$ declare r jsonb; e jsonb; n int; it jsonb; begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  r := public.admin_course_read_now('ecae5b4f-0b13-4ef0-ad37-64f7ba208576', 'dry run: fee first in line');
  e := public.admin_course_edit('de70ae44-8eda-418a-a271-fd82bf5008e2', 'set_official_url', jsonb_build_object('url', 'https://study.auckland.ac.nz/ords/r/uoa/catalogue/program?p5_code=DipCom', 'reason', 'dry run'));
  update pipeline.coverage_course_pages set read_at = now() + interval '1 second' where course_id = 'ecae5b4f-0b13-4ef0-ad37-64f7ba208576';
  n := security.fee_course_pages_enqueue_v1();
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  it := public.svc_fee_ai_next(40)->0;
  raise exception 'DRYRUN OK %', jsonb_build_object('read_now', r, 'queued', n, 'first', jsonb_build_object('course', it->'courses'->0->>'title', 'url', it->>'url'),
    'requests', (select jsonb_agg(jsonb_build_object('c', course_id, 'o', outcome)) from pipeline.fee_course_requests),
    'waiting', (select jsonb_agg(jsonb_build_object('f', i.field, 's', i.state)) from pipeline.field_enrich_items i where i.job_id = (r->>'job_id')::uuid),
    'dipcom_job', (select count(*) from pipeline.admin_jobs j where j.title = 'Read with AI · Diploma in Commerce (Level 5)' and j.created_at > now() - interval '1 minute'),
    'sched', (select schedule from cron.job where jobname = 'fee-reader'), 'ppr', security.pipeline_num_v1('fees.pages_per_run', 0)); end $t$;
