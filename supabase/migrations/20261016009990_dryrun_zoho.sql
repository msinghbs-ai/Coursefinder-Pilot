-- CF-247 (23 Oct 2026). Platform Admin 08:4x chose "Through the AI fee reader (Recommended)": a fee read from a course's own page is
-- admitted through the AI fee reader, with the same pinned model and checks as fee schedules (quote on the page, match confidence, title
-- agreement, usual range, held fee); a row that passes is admitted, the rest go to Layer 4. Found: since Layer 3 was retired (12 Oct)
-- nothing admitted a fee read from a course's own page outside universities with an adapter (about 1,800 pages across AU, NZ and CA
-- with an international fee read and none held; 238 of them NZ with a safe reading).
-- 1 pipeline.fee_reader_queue takes a course page as well as a fee page (course_id, evidence_id). For a course page, fact_source_id
--   (not null, no foreign key) holds the page copy's evidence id, so the reader's rows and findings stay keyed per page version and
--   every existing column rule stays.
-- 2 security.fee_course_pages_enqueue_v1: the fee reader's tick queues each course page version that shows one international fee
--   (security.coverage_tuition_target_v1), or whose adapter fee reading is excluded for that course (University of Auckland: 58
--   catalogue pages excluded on 7 Oct because the pattern read the low end of a range or a whole-programme fee), for a course with no fee held, where the page's proof admits tuition for the country
--   (Settings › Identify the page) and the country is in fees.countries. Settings fees.course_pages (on/off) and
--   fees.course_pages_per_tick.
-- 3 public.svc_fee_ai_next gives a course page with that one course as the course list (course_page true; the worker reads the
--   stored page as text). public.svc_fee_ai_record takes the page address, copy and hash from the course page (md5-guarded edits).
-- Replaces: nothing (public.svc_fee_ai_next replaced in full after an md5 check; public.svc_fee_ai_record and security.fee_reader_tick_v1 edited in place, md5-guarded)
-- Retires: nothing

-- 1 queue and rows take a course page -----------------------------------------------------------------------------------------------
alter table pipeline.fee_reader_queue add column if not exists course_id uuid;
alter table pipeline.fee_reader_queue add column if not exists evidence_id uuid;
do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'fee_reader_queue_page_or_course') then
    alter table pipeline.fee_reader_queue add constraint fee_reader_queue_page_or_course check (course_id is null or (evidence_id is not null and fact_source_id = evidence_id));
  end if;
end $do$;
create unique index if not exists fee_reader_queue_course_hash on pipeline.fee_reader_queue(course_id, content_hash) where course_id is not null;
comment on column pipeline.fee_reader_queue.course_id is 'CF-247 23 Oct 2026: a course''s own page read by the AI fee reader (with evidence_id, its stored copy); empty for a fee page. For a course page fact_source_id holds the same evidence id.';

-- settings (G2) -------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'fees.course_pages', 'Fee reader: read course pages', 'When on (1), a course page that shows one international fee, for a course with no fee held, is read by the AI fee reader. The page''s proof must admit tuition for its country (Settings › Identify the page) and the country must be in Fee reader: countries.', 'number', '1'::jsonb, '0', '1', 'on/off', 341, 'Enrichment', 'job fee-reader', 'Platform Admin 23 Oct 2026: course page fees through the AI fee reader'),
       ('pipeline', 'fees.course_pages_per_tick', 'Fee reader: course pages queued a run', 'Course pages the fee reader''s job adds to its queue each run (every 10 minutes).', 'number', '40'::jsonb, '1', '500', 'pages', 348, 'Job sizes', 'job fee-reader', 'Platform Admin 23 Oct 2026: course page fees through the AI fee reader')
on conflict (toolset_key, key) do nothing;

-- 2 queue course pages ------------------------------------------------------------------------------------------------------------
create or replace function security.fee_course_pages_enqueue_v1()
 returns int
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v int := 0;
begin
  if security.pipeline_num_v1('fees.course_pages', 1) < 1 then return 0; end if;
  insert into pipeline.fee_reader_queue(fact_source_id, course_id, provider_id, evidence_id, content_hash)
  select g.evidence_id, g.course_id, g.provider_id, g.evidence_id, coalesce(e.content_hash, g.evidence_id::text)
    from pipeline.coverage_course_pages g
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
    join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
    join catalogue.providers p on p.id = g.provider_id join ref.countries k on k.id = p.country_id
   where g.status = 'bound' and g.read_status = 'read'
     and ((g.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb and security.coverage_tuition_target_v1(g.candidates->'fee') is not null)
          -- an adapter's fee reading the university's adapter may not admit for this course (adapter exclusion, e.g. Auckland 7 Oct:
          -- the low end of a range, a whole-programme fee): the AI reads the page and tells annual from whole-programme fees
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
  return v;
end $function$;
revoke execute on function security.fee_course_pages_enqueue_v1() from public, anon, authenticated;

do $do$
declare v_def text := pg_get_functiondef('security.fee_reader_tick_v1()'::regprocedure);
  v_old text := $o$  -- 4 the worker, while there is work and AI budget$o$;
  v_new text := $n$  -- 2b course pages that show one international fee for a course with no fee held (CF-247 23 Oct 2026)
  v_queued := v_queued + security.fee_course_pages_enqueue_v1();

  -- 4 the worker, while there is work and AI budget$n$;
begin
  if md5(v_def) <> '34313a3d7e235480a242c4201db236f9' then raise exception 'security.fee_reader_tick_v1 is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee reader tick: expected one worker step'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- 3 what the worker reads -----------------------------------------------------------------------------------------------------------
do $do$ begin
  if md5(pg_get_functiondef('public.svc_fee_ai_next(integer)'::regprocedure)) <> '1b611d09d01d976a4ba9304930322c81' then
    raise exception 'public.svc_fee_ai_next is not the expected version (md5 %)', md5(pg_get_functiondef('public.svc_fee_ai_next(integer)'::regprocedure)); end if;
end $do$;
create or replace function public.svc_fee_ai_next(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb := '[]'::jsonb; q record;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  for q in
    update pipeline.fee_reader_queue x set state = 'leased', leased_until = now() + interval '4 minutes', attempts = attempts + 1  -- fixed: lease longer than one worker call
     where x.id in (select y.id from pipeline.fee_reader_queue y
                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries
                       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = y.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
                     order by y.created_at limit greatest(1, least(coalesce(p_limit, 3), 10)) for update skip locked)
    returning x.*
  loop
    v := v || (
      select jsonb_build_object(
        'queue_id', q.id, 'source_id', coalesce(f.id, q.fact_source_id), 'url', coalesce(f.url, ce.source_url, cg.url), 'storage_path', coalesce(e.storage_path, ce.storage_path),
        -- CF-247 23 Oct 2026: a course's own page; the worker reads the stored page as text and the course list is that one course
        'course_page', q.course_id is not null,
        'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
        'profile', (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2),
        'model', (select s.model_identifier from pipeline.central_ai_settings s where s.id = 1),
        'model_code', (select s.model_code from pipeline.central_ai_settings s where s.id = 1),
        'page_chars', security.pipeline_num_v1('fees.page_chars', 40000)::int,
        'notes', case when q.course_id is null then (select r.notes from pipeline.fee_reader_recipes r where r.provider_id = q.provider_id) end,
        'findings', coalesce((select jsonb_agg(jsonb_build_object('kind', z.kind, 'detail', z.detail, 'times', z.times) order by z.last_seen desc)
                                from (select * from pipeline.fee_reader_findings x where x.provider_id = q.provider_id and x.resolved_at is null
                                      order by x.last_seen desc limit security.pipeline_num_v1('fees.findings_in_prompt', 10)::int) z), '[]'::jsonb),
        'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.canonical_title, 'level', sl.code) order by c.canonical_title)
                               from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
                              where c.provider_id = q.provider_id and c.lifecycle_status = 'active' and (q.course_id is null or c.id = q.course_id)), '[]'::jsonb))
        from catalogue.providers p join ref.countries k on k.id = p.country_id
        left join pipeline.provider_fact_sources f on f.id = q.fact_source_id and q.course_id is null
        left join pipeline.evidence_artifacts e on e.id = f.evidence_id
        left join pipeline.coverage_course_pages cg on cg.course_id = q.course_id
        left join pipeline.evidence_artifacts ce on ce.id = q.evidence_id
       where p.id = q.provider_id and (q.course_id is not null or f.id is not null));
  end loop;
  return v;
end $function$;
revoke execute on function public.svc_fee_ai_next(int) from public, anon, authenticated;
grant execute on function public.svc_fee_ai_next(int) to service_role;

-- what the worker reports: a course page's address, copy and hash ----------------------------------------------------------------
do $do$
declare v_def text := pg_get_functiondef('public.svc_fee_ai_record(uuid,jsonb,numeric,text)'::regprocedure);
  v_old text := $o$  select * into f from pipeline.provider_fact_sources where id = q.fact_source_id;$o$;
  v_new text := $n$  select * into f from pipeline.provider_fact_sources where id = q.fact_source_id;
  -- CF-247 23 Oct 2026: a course's own page (no fee page): its address, stored copy and hash stand in for the fee page's
  if q.course_id is not null then
    select coalesce(e.source_url, g.url), q.evidence_id, q.content_hash, q.provider_id into f.url, f.evidence_id, f.content_hash, f.provider_id
      from pipeline.evidence_artifacts e left join pipeline.coverage_course_pages g on g.course_id = q.course_id where e.id = q.evidence_id;
  end if;$n$;
begin
  if md5(v_def) <> '1b76a14646fdbd90252b7dffb5e02e61' then raise exception 'public.svc_fee_ai_record is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee record: expected one fee page lookup'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_course_pages_enqueue_v1', 'Layer 2', 'Queue course pages with one international fee for the AI fee reader (course with no fee held, proof admits tuition)', 'active', '{}', '20261023009000')
on conflict (kind, name) do nothing;

select 'fee reader reads course pages' ok;
do $t$ declare n int; items jsonb; it jsonb; res jsonb; tgt jsonb; cid uuid; begin
  n := security.fee_course_pages_enqueue_v1();
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  update pipeline.fee_reader_queue set created_at = '2000-01-01' where course_id is not null and state = 'queued' and course_id = 'ecae5b4f-0b13-4ef0-ad37-64f7ba208576';
  items := public.svc_fee_ai_next(1);
  it := items->0; cid := (it->'courses'->0->>'id')::uuid;
  select security.coverage_tuition_target_v1(g.candidates->'fee') into tgt from pipeline.coverage_course_pages g where g.course_id = cid;
  res := public.svc_fee_ai_record((it->>'queue_id')::uuid, jsonb_build_object('rows', jsonb_build_array(jsonb_build_object('qualification', it->'courses'->0->>'title', 'subject', null, 'level', null,
            'amount_min', (tgt->>'amount')::numeric, 'amount_max', null, 'currency', 'NZD', 'unit', 'per_year', 'units_covered', null, 'audience', 'international', 'fee_year', 2026,
            'quote', 'test', 'course_id', cid, 'match_confidence', 0.95)), 'quotes_missing', 0, 'more_fee_pages', '[]'::jsonb, 'page_notes', '', 'model', it->>'model'), 0, null);
  raise exception 'DRYRUN OK %', jsonb_build_object('queued', n, 'has', (select count(*) from pipeline.fee_reader_queue where course_id = 'ecae5b4f-0b13-4ef0-ad37-64f7ba208576'), 'target', tgt, 'record', res,
     'fee', (select jsonb_agg(jsonb_build_object('a', f.amount, 'y', f.fee_year, 'b', f.basis, 'st', f.status)) from catalogue.course_fees f where f.course_id = cid and f.fee_type = 'provider_current_tuition'),
     'rows', (select jsonb_agg(jsonb_build_object('o', r.outcome, 'n', r.note)) from pipeline.fee_reader_rows r where r.queue_id = (it->>'queue_id')::uuid)); end $t$;
