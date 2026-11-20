-- CF-247 S1-AER s835 (Platform Admin 20 Nov 2026 15:08 AEDT, "Correction & Scope Clarification": AER is academic only, English has its own pipeline; "enable automated deterministic AER promotion and an autonomous scheduled sweep at $0").
-- Replaces: the s815 shadow writer security.aer_det_record_v1 and its tables pipeline.aer_det_pages and pipeline.aer_det_readings (they held English tests beside academic ones; nothing reads them now, the runner scripts/aer-det-read.mjs writes the new tables). They are left in place, nothing is dropped (a drop goes to the Platform Admin as a paste file after the 14 day retention window).
-- Retires: nothing (the AI and Boost aer_entry readers stay shadow only, Decision 276; S677 and the 6 provider entry-matrix changes are not touched).
-- What this adds, all beside the existing model (nothing the website or Zoho reads is touched; G3 unchanged at 75 functions and 48 relations; every new object is in schema pipeline or security):
--   pipeline.aer_det_academic_pages     one row for each stored page read by aer-det-v1.3 (academic entry only), the other requirement lines the reader does not read, and what became of the page (outcome);
--   pipeline.aer_det_academic_readings  each academic reading with its verbatim quote (atar, year12, ncea_l3, university_entrance, ib, alevel, india_board, ca_secondary, bachelor_gpa; never an English test);
--   pipeline.aer_det_sweep_calls        each worker call the sweep sent (pg_net request id) and whether its answer has been collected;
--   security.aer_det_record_v2          the idempotent writer of the two tables above (called by the sweep and by the workflow aer-det-read.yml);
--   security.aer_det_propose_v1         turns a page's readings into ordinary proposed course entry rows and one Layer 4 course_entry_first_read item (reader aer_det). It admits nothing: the unchanged
--                                       security.aer_machine_check_v1 and the job aer-machine-admission (verbatim quote, page identity, completeness gate, manual locks, no-overwrite, 5% audit sample) decide, or a person does;
--   security.aer_det_sweep_v1           the self-sustaining sweep: collects finished worker answers, records them, sends the next stored pages to the worker (mode aer_det_read, no model, no Firecrawl), then proposes. Job aer-det-sweep, every 5 minutes;
--   settings (G2, Settings > Pipeline settings, section Admission checks): batch.aer_det_read raised to 40; aer_det.sweep_on, sweep_calls, sweep_max_open, call_lost_minutes, propose_on, propose_max_pending, propose_per_run, confidence_stated, confidence_mentioned.
-- A page that prints a prerequisite, portfolio, interview, work experience or bridging line the reader does not read is carried as a dropped requirement (reason det_other_requirement), which the completeness gate holds for a person.
set local lock_timeout = '5s';

create table if not exists pipeline.aer_det_academic_pages (
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  chars       integer,
  sha256      text,
  readings    integer not null default 0,
  uncovered   jsonb not null default '[]'::jsonb,
  read_error  text,
  outcome     text,
  outcome_at  timestamptz,
  read_at     timestamptz not null default now(),
  primary key (course_id, evidence_id, extractor)
);
comment on table pipeline.aer_det_academic_pages is 'CF-247 s835: each stored course page the deterministic academic entry reader (aer-det-v1.3, no model, no fetch, no English test) has read, the other requirement lines it did not read, and the outcome of its proposal (proposed, locked, has_active, earlier_read, not_admitted, held_*). Lets the sweep resume where it stopped.';
alter table pipeline.aer_det_academic_pages enable row level security;
revoke all on pipeline.aer_det_academic_pages from public, anon, authenticated;
create index if not exists aer_det_academic_pages_open on pipeline.aer_det_academic_pages (read_at) where outcome is null and readings > 0;

create table if not exists pipeline.aer_det_academic_readings (
  id          bigint generated always as identity primary key,
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  test_key    text not null check (test_key in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa')),
  value       jsonb not null,
  quote       text not null check (length(quote) between 8 and 400),
  strength    text not null check (strength in ('stated_minimum', 'mentioned')),
  created_at  timestamptz not null default now()
);
comment on table pipeline.aer_det_academic_readings is 'CF-247 s835: academic entry readings (ATAR, Year 12, NCEA Level 3, University Entrance, IB, A-level, Indian boards, Canadian average, bachelor GPA) read deterministically from a stored course page, each with its verbatim quote. English tests are never held here (their own pipeline). Admission is only through Layer 4 and the unchanged machine rule.';
create unique index if not exists aer_det_academic_readings_one on pipeline.aer_det_academic_readings (course_id, evidence_id, extractor, test_key, md5(quote));
create index if not exists aer_det_academic_readings_course on pipeline.aer_det_academic_readings (course_id, evidence_id);
alter table pipeline.aer_det_academic_readings enable row level security;
revoke all on pipeline.aer_det_academic_readings from public, anon, authenticated;

create table if not exists pipeline.aer_det_sweep_calls (
  request_id   bigint primary key,
  course_ids   jsonb not null,
  sent_at      timestamptz not null default now(),
  collected_at timestamptz,
  status       text,
  pages        integer,
  readings     integer
);
comment on table pipeline.aer_det_sweep_calls is 'CF-247 s835: each worker call (mode aer_det_read) the job aer-det-sweep sent, by pg_net request id, with its collected answer (status ok, failed, lost or wrong_extractor). Keeps the sweep from sending a page twice while its answer is open.';
alter table pipeline.aer_det_sweep_calls enable row level security;
revoke all on pipeline.aer_det_sweep_calls from public, anon, authenticated;
create index if not exists aer_det_sweep_calls_open on pipeline.aer_det_sweep_calls (sent_at) where collected_at is null;

-- 1. the writer: academic readings only; an unknown key is skipped, never stored
create or replace function security.aer_det_record_v2(p_pages jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare v_pages int := 0; v_readings int := 0; p jsonb; r jsonb; v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  for p in select * from jsonb_array_elements(p_pages) loop
    if not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = (p->>'course_id')::uuid and g.evidence_id = (p->>'evidence_id')::uuid) then continue; end if;
    if p ? 'error' then
      continue when p->>'error' = 'call_time_used';  -- the worker ran out of time for this page: it is sent again
      insert into pipeline.aer_det_academic_pages (course_id, evidence_id, extractor, readings, read_error, outcome, outcome_at)
      values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', 0, left(p->>'error', 160), 'read_error', now())
      on conflict (course_id, evidence_id, extractor) do nothing;
      continue;
    end if;
    insert into pipeline.aer_det_academic_pages (course_id, evidence_id, extractor, chars, sha256, readings, uncovered, outcome, outcome_at)
    values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', (p->>'chars')::int, p->>'sha256',
            (select count(*) from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) x where x->>'key' in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa')),
            case when jsonb_typeof(p->'uncovered') = 'array' then p->'uncovered' else '[]'::jsonb end,
            case when jsonb_array_length(coalesce(p->'readings', '[]'::jsonb)) = 0 then 'no_reading' end,
            case when jsonb_array_length(coalesce(p->'readings', '[]'::jsonb)) = 0 then now() end)
    on conflict (course_id, evidence_id, extractor) do nothing;
    get diagnostics v_n = row_count; v_pages := v_pages + v_n;
    if v_n = 0 then continue; end if;
    for r in select * from jsonb_array_elements(coalesce(p->'readings', '[]'::jsonb)) loop
      continue when r->>'key' not in ('atar','year12','ncea_l3','university_entrance','ib','alevel','india_board','ca_secondary','bachelor_gpa');
      insert into pipeline.aer_det_academic_readings (course_id, evidence_id, extractor, test_key, value, quote, strength)
      values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', r->>'key', r->'value', r->>'quote', r->>'strength')
      on conflict do nothing;
      get diagnostics v_n = row_count; v_readings := v_readings + v_n;
    end loop;
  end loop;
  return jsonb_build_object('pages', v_pages, 'readings', v_readings);
end $f$;
comment on function security.aer_det_record_v2(jsonb) is 'CF-247 s835: records pages read by the deterministic academic entry reader and their readings, idempotently. Writes only pipeline.aer_det_academic_pages and pipeline.aer_det_academic_readings; an English test or any other key is never stored.';
revoke all on function security.aer_det_record_v2(jsonb) from public, anon, authenticated;

-- 2. the proposer: ordinary proposed rows plus one Layer 4 first read item, decided by the unchanged gates
create or replace function security.aer_det_propose_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_ext constant text := 'aer-det-v1.3';  -- fixed: the reader version this proposer takes readings from; a new reader version ships with its own migration
  v_on int := security.pipeline_num_v1('aer_det.propose_on', 1)::int;
  v_cap int := security.pipeline_num_v1('aer_det.propose_max_pending', 400)::int;
  v_per int := security.pipeline_num_v1('aer_det.propose_per_run', 50)::int;
  v_cs numeric := security.pipeline_num_v1('aer_det.confidence_stated', 0.9);
  v_cm numeric := security.pipeline_num_v1('aer_det.confidence_mentioned', 0.7);
  v_pending int; v_room int; v_done int := 0; v_checked int := 0; v_out jsonb := '{}'::jsonb;
  pg record; g record; rd record; u text;
  v_outcome text; v_max int; v_keep jsonb; v_drop jsonb; v_other boolean; v_n int; v_ids uuid[]; v_id uuid; v_review uuid; v_cc text;
  v_q text; v_kind text; v_desc text; v_score numeric; v_basis text; v_grade text; v_aud text; v_conf numeric; x jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_on <> 1 then return jsonb_build_object('held', 'propose_off'); end if;
  select count(*) into v_pending from pipeline.layer4_review_items where field_code = 'course_entry_first_read' and status = 'pending' and proposed_value->>'reader' = 'aer_det';
  v_room := least(v_per, v_cap - v_pending);
  if v_room <= 0 then return jsonb_build_object('held', 'pending_cap', 'pending', v_pending); end if;
  for pg in select a.course_id, a.evidence_id, a.uncovered, c.provider_id
              from pipeline.aer_det_academic_pages a join catalogue.courses c on c.id = a.course_id and c.lifecycle_status = 'active'
             where a.extractor = v_ext and a.readings > 0 and a.outcome is null order by a.read_at loop
    exit when v_done >= v_room;
    v_checked := v_checked + 1; v_outcome := null;
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = pg.course_id and l.field in ('entry_requirements', 'all')) then v_outcome := 'locked';
    elsif exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pg.provider_id) then v_outcome := 'provider_hidden';
    elsif exists (select 1 from catalogue.course_entry_requirements r where r.course_id = pg.course_id and r.status in ('active', 'proposed')) then v_outcome := 'has_rows';
    elsif exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = pg.course_id and r.field_code = 'course_entry_first_read') then v_outcome := 'earlier_read';
    end if;
    if v_outcome is null then
      select p.provider_id, p.identity_basis, p.url, p.evidence_id, e.captured_at into g
        from pipeline.coverage_course_pages p left join pipeline.evidence_artifacts e on e.id = p.evidence_id where p.course_id = pg.course_id and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
      if g.evidence_id is null then v_outcome := 'no_bound_page';
      elsif g.evidence_id is distinct from pg.evidence_id then v_outcome := 'page_changed';
      elsif not security.coverage_identity_allowed(pg.provider_id, g.identity_basis, 'entry_requirements') then v_outcome := 'not_admitted';
      elsif jsonb_array_length(security.course_entry_shared_page_v1(pg.course_id)) > 0 then v_outcome := 'held_shared_page';
      end if;
    end if;
    if v_outcome is null then
      v_cc := security.coverage_country(pg.provider_id); v_keep := '[]'::jsonb; v_drop := '[]'::jsonb; v_other := false;
      for rd in select * from pipeline.aer_det_academic_readings where course_id = pg.course_id and evidence_id = pg.evidence_id and extractor = v_ext order by id loop
        v_q := rd.quote;
        if length(v_q) > 300 then v_drop := v_drop || jsonb_build_object('reason', 'det_other_requirement', 'kind', 'general_note', 'quote', left(v_q, 300)); continue; end if;
        if security.course_entry_variant_v1(pg.course_id, v_q) is not null then v_other := true; exit; end if;
        v_kind := 'minimum_grade'; v_score := null; v_basis := null; v_grade := null; v_desc := null;
        if rd.test_key = 'atar' then v_score := (rd.value->>'atar')::numeric; v_basis := 'ATAR'; v_desc := 'Minimum ATAR of ' || (rd.value->>'atar');
        elsif rd.test_key = 'year12' and rd.value ? 'value' then v_score := (rd.value->>'value')::numeric; v_basis := rd.value->>'basis'; v_desc := 'Year 12 minimum ' || coalesce(v_basis, 'result') || ' of ' || (rd.value->>'value');
        elsif rd.test_key = 'year12' then v_grade := rd.value->>'grade'; v_desc := 'Year 12 grade ' || v_grade || ' or higher';
        elsif rd.test_key = 'ncea_l3' then v_kind := 'prior_qualification'; v_score := (rd.value->>'credits')::numeric; v_basis := 'credits'; v_desc := 'NCEA Level 3 with ' || (rd.value->>'credits') || ' credits';
        elsif rd.test_key = 'university_entrance' then v_kind := 'prior_qualification'; v_score := (rd.value->>'credits')::numeric; v_basis := 'credits'; v_desc := 'University Entrance with ' || (rd.value->>'credits') || ' credits';
        elsif rd.test_key = 'ib' then v_kind := 'prior_qualification'; v_score := (rd.value->>'points')::numeric; v_basis := 'points'; v_desc := 'International Baccalaureate Diploma with ' || (rd.value->>'points') || ' points';
        elsif rd.test_key = 'alevel' then v_grade := rd.value->>'grades'; v_desc := 'GCE A-levels with grades ' || v_grade;
        elsif rd.test_key = 'india_board' then v_score := (rd.value->>'average_percent')::numeric; v_basis := case when lower(v_q) like '%per cent%' then 'per cent' when lower(v_q) like '%percent%' then 'percent' else '%' end; v_desc := 'Indian school board average of ' || (rd.value->>'average_percent') || ' per cent';
        elsif rd.test_key = 'ca_secondary' then v_score := (rd.value->>'average_percent')::numeric; v_basis := case when lower(v_q) like '%per cent%' then 'per cent' else '%' end; v_desc := 'Secondary school average of ' || (rd.value->>'average_percent') || ' per cent';
        elsif rd.test_key = 'bachelor_gpa' then v_score := (rd.value->>'gpa')::numeric; v_basis := case when lower(v_q) like '%gpa%' then 'GPA' else 'grade point average' end; v_desc := 'Bachelor degree GPA of ' || (rd.value->>'gpa');
        end if;
        -- no numeric score without its basis: both the number and the basis words are printed in the quote (B1 rule, as the reader of the AI route)
        if v_score is not null and (v_basis is null or strpos(lower(regexp_replace(v_q, '\s+', ' ', 'g')), lower(v_basis)) = 0
                                    or not exists (select 1 from regexp_matches(v_q, '([0-9]+(\.[0-9]+)?)', 'g') m where m[1]::numeric = v_score)) then
          v_score := null; v_basis := null;
        end if;
        v_aud := case when v_q ~* '\m(international|overseas)\M' then 'international'
                      when v_q ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic'
                      when v_cc = 'NZ' and v_q ~* '(\mNCEA\M|University Entrance|\mUE\M)' then 'domestic' else 'all' end;
        v_conf := case rd.strength when 'stated_minimum' then v_cs else v_cm end;
        v_keep := v_keep || jsonb_build_object('kind', v_kind, 'audience', v_aud, 'description', v_desc, 'min_grade', v_grade, 'min_entry_score', v_score, 'min_entry_score_basis', v_basis, 'quote', v_q, 'confidence', v_conf, 'test_key', rd.test_key);
      end loop;
      if v_other then v_outcome := 'held_other_programme';
      else
        v_max := security.course_entry_max_rows_v1(pg.provider_id); v_n := jsonb_array_length(v_keep);
        if v_n = 0 then v_outcome := 'no_row';
        elsif v_n > v_max then v_outcome := 'held_over_row_limit';
        end if;
      end if;
    end if;
    if v_outcome is not null then
      update pipeline.aer_det_academic_pages set outcome = v_outcome, outcome_at = now() where course_id = pg.course_id and evidence_id = pg.evidence_id and extractor = v_ext;
      v_out := jsonb_set(v_out, array[v_outcome], to_jsonb(coalesce((v_out->>v_outcome)::int, 0) + 1));
      continue;
    end if;
    -- the other requirement lines the reader does not read: carried as dropped requirements, which the completeness gate holds for a person
    for u in select jsonb_array_elements_text(pg.uncovered) loop
      v_drop := v_drop || jsonb_build_object('reason', 'det_other_requirement', 'kind', 'subject_prerequisite', 'quote', left(u, 300));
    end loop;
    v_ids := '{}';
    for x in select * from jsonb_array_elements(v_keep) loop
      insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_grade, min_entry_score, min_entry_score_basis, quote, source_url, evidence_id, confidence, as_at, status, provenance)
      values (pg.course_id, x->>'kind', x->>'audience', x->>'description', x->>'min_grade', (x->>'min_entry_score')::numeric, x->>'min_entry_score_basis', x->>'quote',
              g.url, pg.evidence_id, (x->>'confidence')::numeric, coalesce(g.captured_at::date, current_date), 'proposed',
              jsonb_build_object('reader', 'aer_det', 'extractor', v_ext, 'test_key', x->>'test_key', 'field', 'entry_requirements'))
      returning id into v_id;
      v_ids := v_ids || v_id;
    end loop;
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', pg.course_id, 'course_entry_first_read', pg.evidence_id,
            jsonb_build_object('active_rows', 0),
            jsonb_build_object('reader', 'aer_det', 'extractor', v_ext, 'url', g.url, 'rows', cardinality(v_ids), 'limit', v_max, 'dropped', v_drop, 'notes', '[]'::jsonb,
              'sample', (select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'audience', r.audience, 'description', r.description, 'min_entry_score', r.min_entry_score,
                                           'min_entry_score_basis', r.min_entry_score_basis, 'quote', r.quote) order by r.kind) from catalogue.course_entry_requirements r where r.id = any (v_ids))),
            jsonb_build_object('source', 'deterministic academic entry reader', 'page', g.url, 'identity_basis', g.identity_basis),
            jsonb_build_object('reader', 'aer_det', 'extractor', v_ext),
            'pending', 'Course entry requirements first read by the deterministic academic reader (' || v_ext || '): the machine rule aer-machine-v1 admits it when every check passes, otherwise a person decides', 'CF-CHG-20260915-247')
    returning id into v_review;
    update catalogue.course_entry_requirements set provenance = provenance || jsonb_build_object('review_item_id', v_review) where id = any (v_ids);
    update pipeline.aer_det_academic_pages set outcome = 'proposed', outcome_at = now() where course_id = pg.course_id and evidence_id = pg.evidence_id and extractor = v_ext;
    v_done := v_done + 1;
  end loop;
  return jsonb_build_object('proposed', v_done, 'checked', v_checked, 'not_proposed', v_out, 'pending_before', v_pending);
end $f$;
comment on function security.aer_det_propose_v1() is 'CF-247 s835: proposes the readings of pages read by aer-det-v1.3 as ordinary proposed course entry rows with one Layer 4 course_entry_first_read item each (reader aer_det). Skips a locked, hidden, already-read, already-ruled, other-programme or shared page. Admits nothing: the machine rule and Layer 4 decide.';
revoke all on function security.aer_det_propose_v1() from public, anon, authenticated;

-- 3. the sweep: collect, record, send, propose
create or replace function security.aer_det_sweep_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_ext constant text := 'aer-det-v1.3';  -- fixed: the reader version the worker must answer with (a worker still on an older version is refused, so nothing from it is recorded)
  v_on int := security.pipeline_num_v1('aer_det.sweep_on', 1)::int;
  v_calls int := security.pipeline_num_v1('aer_det.sweep_calls', 3)::int;
  v_max_open int := security.pipeline_num_v1('aer_det.sweep_max_open', 4)::int;
  v_lost int := security.pipeline_num_v1('aer_det.call_lost_minutes', 15)::int;
  v_per int := security.pipeline_num_v1('batch.aer_det_read', 40)::int;
  c record; resp record; v_body jsonb; v_pages jsonb; v_rec jsonb; v_open int; v_n int; v_sent int := 0; v_got int := 0; v_open_ids uuid[]; v_items jsonb; v_id bigint; v_prop jsonb := null; i int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('held', 'maintenance'); end if;
  -- 1. collect the answers of earlier calls
  for c in select * from pipeline.aer_det_sweep_calls where collected_at is null order by sent_at loop
    select r.status_code, r.timed_out, r.error_msg, r.content::text as content into resp from net._http_response r where r.id = c.request_id;
    if not found then
      if c.sent_at < now() - make_interval(mins => v_lost) then update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'lost' where request_id = c.request_id; end if;
      continue;
    end if;
    begin
      if resp.timed_out or resp.error_msg is not null or resp.status_code >= 300 then raise exception 'call failed'; end if;
      v_body := resp.content::jsonb;
      if v_body->>'extractor' is distinct from v_ext then
        update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'wrong_extractor' where request_id = c.request_id; continue;
      end if;
      select coalesce(jsonb_agg(p || jsonb_build_object('extractor', v_ext)), '[]'::jsonb) into v_pages from jsonb_array_elements(coalesce(v_body->'pages', '[]'::jsonb)) p;
      v_rec := security.aer_det_record_v2(v_pages);
      update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'ok', pages = (v_rec->>'pages')::int, readings = (v_rec->>'readings')::int where request_id = c.request_id;
      v_got := v_got + 1;
    exception when others then
      update pipeline.aer_det_sweep_calls set collected_at = now(), status = 'failed' where request_id = c.request_id;
    end;
  end loop;
  -- 2. send the next stored pages (the base is the one the workflow runner reads: a stored page of an active course that has no active rule)
  select count(*) into v_open from pipeline.aer_det_sweep_calls where collected_at is null;
  v_n := least(v_calls, v_max_open - v_open);
  if v_on = 1 and v_n > 0 then
    select coalesce(array_agg(x::uuid), '{}') into v_open_ids from pipeline.aer_det_sweep_calls o, jsonb_array_elements_text(o.course_ids) x where o.collected_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', t.course_id, 'evidence_id', t.evidence_id, 'storage_path', t.storage_path) order by t.course_id), '[]'::jsonb) into v_items
      from (select g.course_id, g.evidence_id, e.storage_path
              from pipeline.coverage_course_pages g
              join catalogue.courses c2 on c2.id = g.course_id and c2.lifecycle_status = 'active'
              join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
             where g.evidence_id is not null and g.read_status is not null and g.status = 'bound'
               and not (g.course_id = any (v_open_ids))
               and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = g.course_id and r.status = 'active')
               and not exists (select 1 from pipeline.aer_det_academic_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = v_ext)
             order by g.course_id limit v_per * v_n) t;
    for i in 0 .. v_n - 1 loop
      exit when i * v_per >= jsonb_array_length(v_items);
      select coalesce(jsonb_agg(e.item), '[]'::jsonb) into v_pages from jsonb_array_elements(v_items) with ordinality e(item, o) where e.o > i * v_per and e.o <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'aer_det_read', 'items', v_pages));
      insert into pipeline.aer_det_sweep_calls (request_id, course_ids, status) values (v_id, (select coalesce(jsonb_agg(p->>'course_id'), '[]'::jsonb) from jsonb_array_elements(v_pages) p), 'sent');
      v_sent := v_sent + 1;
    end loop;
  end if;
  -- 3. propose what has been read
  v_prop := security.aer_det_propose_v1();
  return jsonb_build_object('collected', v_got, 'calls_sent', v_sent, 'open_calls', v_open, 'propose', v_prop);
end $f$;
comment on function security.aer_det_sweep_v1() is 'CF-247 s835: one tick of the job aer-det-sweep. Collects the answers of earlier worker calls (mode aer_det_read, no model, no Firecrawl), records the academic readings, sends the next stored pages, then proposes the readings through security.aer_det_propose_v1. No AI or Firecrawl spend.';
revoke all on function security.aer_det_sweep_v1() from public, anon, authenticated;

-- 4. settings (G2); the reader sends 40 pages in one call
update pipeline.platform_toolset_settings
   set value = to_jsonb(40), reason = 'CF-247 s835 (Platform Admin 20 Nov 2026 15:08): the scheduled sweep sends the full call size; the shadow runs at 20 are done', updated_at = now()
 where toolset_key = 'pipeline' and key = 'batch.aer_det_read' and value = to_jsonb(20);

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer_det.sweep_on', 'Deterministic academic reader: sweep on', '1 lets the job aer-det-sweep send stored pages to the reader; 0 stops sending (answers already sent are still collected and read pages still proposed).', 'number', to_jsonb(1), 0, 1, 'switch', 645, 'Admission checks', 'security.aer_det_sweep_v1', 'CF-247 s835 (Platform Admin 20 Nov 2026 15:08): autonomous scheduled sweep at $0'),
 ('pipeline', 'aer_det.sweep_calls', 'Deterministic academic reader: worker calls a tick', 'Worker calls the sweep sends in one tick (every 5 minutes); each call carries the number of pages in Deterministic entry reader: pages a call.', 'number', to_jsonb(3), 1, 6, 'calls', 646, 'Admission checks', 'security.aer_det_sweep_v1', 'CF-247 s835: about 1,400 pages an hour, inside the worker''s limits'),
 ('pipeline', 'aer_det.sweep_max_open', 'Deterministic academic reader: calls open at once', 'The sweep sends no new call while this many are waiting for an answer.', 'number', to_jsonb(4), 1, 8, 'calls', 647, 'Admission checks', 'security.aer_det_sweep_v1', 'CF-247 s835: bounds parallel worker calls'),
 ('pipeline', 'aer_det.call_lost_minutes', 'Deterministic academic reader: minutes before a call is counted lost', 'A worker call with no stored answer after this many minutes is counted lost and its pages are sent again.', 'number', to_jsonb(15), 5, 120, 'minutes', 648, 'Admission checks', 'security.aer_det_sweep_v1', 'CF-247 s835: the worker answers within about 6 minutes'),
 ('pipeline', 'aer_det.propose_on', 'Deterministic academic reader: propose readings', '1 lets the sweep propose the readings of read pages to Layer 4 and the machine rule; 0 holds them (nothing is proposed).', 'number', to_jsonb(1), 0, 1, 'switch', 649, 'Admission checks', 'security.aer_det_propose_v1', 'CF-247 s835 (Platform Admin 20 Nov 2026 15:08): automated deterministic promotion through the existing gates'),
 ('pipeline', 'aer_det.propose_max_pending', 'Deterministic academic reader: items waiting in Layer 4', 'No new item is proposed while this many of its items wait in Layer 4 (the machine rule or a person decides them).', 'number', to_jsonb(400), 20, 2000, 'items', 650, 'Admission checks', 'security.aer_det_propose_v1', 'CF-247 s835: keeps Layer 4 from flooding; the machine rule admits 300 a day'),
 ('pipeline', 'aer_det.propose_per_run', 'Deterministic academic reader: items proposed a tick', 'Most courses proposed in one tick of the sweep.', 'number', to_jsonb(50), 1, 200, 'items', 651, 'Admission checks', 'security.aer_det_propose_v1', 'CF-247 s835'),
 ('pipeline', 'aer_det.confidence_stated', 'Deterministic academic reader: confidence of a stated minimum', 'Confidence written on a row whose quote itself says the value is a minimum or required. The machine rule needs at least aer.machine_min_confidence.', 'number', to_jsonb(0.9), 0.5, 1, 'confidence', 652, 'Admission checks', 'security.aer_det_propose_v1', 'CF-247 s835'),
 ('pipeline', 'aer_det.confidence_mentioned', 'Deterministic academic reader: confidence of a mention', 'Confidence written on a row whose quote names the value without saying it is a minimum. Below the machine rule''s minimum, so a person decides it in Layer 4.', 'number', to_jsonb(0.7), 0.5, 1, 'confidence', 653, 'Admission checks', 'security.aer_det_propose_v1', 'CF-247 s835')
on conflict do nothing;

-- a page the reader did not read holds a read for a person
update pipeline.platform_toolset_settings
   set value = value || '"det_other_requirement"'::jsonb, reason = 'CF-247 s835: the deterministic academic reader carries the prerequisite, portfolio, interview and work experience lines it does not read as dropped requirements', updated_at = now()
 where toolset_key = 'pipeline' and key = 'entry.gate_hold_reasons' and jsonb_typeof(value) = 'array' and not (value ? 'det_other_requirement');

-- 5. the job (G1) and the register
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('aer-det-sweep', 'Admission checks', 20, 'Deterministic academic entry reader: sweep and propose',
  'Every 5 minutes: collects the answers of earlier worker calls, records the academic entry readings (ATAR, Year 12, NCEA Level 3, University Entrance, IB, A-level, Indian boards, Canadian average, bachelor GPA; never an English test), sends the next stored course pages to the reader and proposes what has been read as ordinary course entry reads. The machine rule aer-machine-v1 and Layer 4 decide; no AI or Firecrawl spend. Switch off with Deterministic academic reader: sweep on and propose readings.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('aer-det-sweep', '3-58/5 * * * *', 'select security.aer_det_sweep_v1()')
where not exists (select 1 from cron.job where jobname = 'aer-det-sweep');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'aer-det-sweep', 'Layer 3', 'Admission checks', 'Sweeps stored course pages with the deterministic academic entry reader and proposes the readings, every 5 minutes', 'active', '{}', '20261120163000'),
  ('table', 'pipeline.aer_det_academic_pages', 'Layer 3', 'Admission checks', 'Stored pages read by the deterministic academic entry reader and what became of each', 'active', '{}', '20261120163000'),
  ('table', 'pipeline.aer_det_academic_readings', 'Layer 3', 'Admission checks', 'Academic entry readings with their verbatim quotes (no English tests)', 'active', '{}', '20261120163000'),
  ('table', 'pipeline.aer_det_sweep_calls', 'Layer 3', 'Admission checks', 'Worker calls the sweep sent and their collected answers', 'active', '{}', '20261120163000'),
  ('function', 'security.aer_det_record_v2', 'Layer 3', 'Admission checks', 'Writes the academic readings of pages the deterministic reader read', 'active', '{}', '20261120163000'),
  ('function', 'security.aer_det_propose_v1', 'Layer 3', 'Admission checks', 'Proposes academic readings as course entry rows and a Layer 4 item', 'active', '{}', '20261120163000'),
  ('function', 'security.aer_det_sweep_v1', 'Layer 3', 'Admission checks', 'One tick of the deterministic academic reader sweep', 'active', '{}', '20261120163000')
on conflict do nothing;

-- 6. post-checks. The synthetic proposal runs inside a block that is rolled back (it raises P0099 at the end), so nothing it writes stays.
do $c$
declare
  v_api jsonb; v_course uuid; v_ev uuid; v_item uuid; v_rows int; v_outcome text; v_chk jsonb; v_prop jsonb; v_cn int;
begin
  if to_regclass('pipeline.aer_det_academic_pages') is null or to_regclass('pipeline.aer_det_academic_readings') is null or to_regclass('pipeline.aer_det_sweep_calls') is null then raise exception 'post-check: a table is missing'; end if;
  if security.pipeline_num_v1('batch.aer_det_read', 0) <> 40 then raise exception 'post-check: batch.aer_det_read is not 40'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'aer\_det.%') <> 9 then raise exception 'post-check: the nine aer_det settings are not all present'; end if;
  if not security.toolset_setting('pipeline', 'entry.gate_hold_reasons') ? 'det_other_requirement' then raise exception 'post-check: det_other_requirement does not hold a read'; end if;
  if not exists (select 1 from cron.job where jobname = 'aer-det-sweep' and active) then raise exception 'post-check: the job is not scheduled'; end if;
  if regexp_replace((select command from cron.job where jobname = 'aer-det-sweep'), '_v[0-9]+', '', 'g') ~ '[0-9]' then raise exception 'post-check: the job command holds a number (G2)'; end if;
  if (select count(*) from pipeline.aer_det_academic_readings) <> 0 then raise exception 'post-check: readings should start empty'; end if;

  -- a rolled back synthetic read of one eligible course: the proposal is ordinary rows plus one Layer 4 item, and the unchanged machine check answers on it
  select c.id, p.evidence_id into v_course, v_ev
    from catalogue.courses c join catalogue.providers pr on pr.id = c.provider_id
    join pipeline.coverage_course_pages p on p.course_id = c.id and p.status = 'bound' and p.evidence_id is not null
   where c.lifecycle_status = 'active'
     and security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'entry_requirements')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('entry_requirements', 'all'))
     and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = c.id)
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = c.id and r.field_code = 'course_entry_first_read')
   order by c.id limit 1;
  if v_course is not null then
    begin
      insert into pipeline.aer_det_academic_pages (course_id, evidence_id, extractor, chars, readings, uncovered) values (v_course, v_ev, 'aer-det-v1.3', 100, 1, '["Prerequisite: Mathematics Methods units 3 and 4."]'::jsonb);
      insert into pipeline.aer_det_academic_readings (course_id, evidence_id, extractor, test_key, value, quote, strength)
      values (v_course, v_ev, 'aer-det-v1.3', 'atar', '{"atar": 70, "basis": "ATAR"}'::jsonb, 'A minimum ATAR of 70 is required.', 'stated_minimum');
      v_prop := security.aer_det_propose_v1();
      select outcome into v_outcome from pipeline.aer_det_academic_pages where course_id = v_course and evidence_id = v_ev and extractor = 'aer-det-v1.3';
      if v_outcome = 'proposed' then
        select id into v_item from pipeline.layer4_review_items where entity_type = 'course' and entity_id = v_course and field_code = 'course_entry_first_read' and proposed_value->>'reader' = 'aer_det';
        select count(*) into v_rows from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_item::text and status = 'proposed' and provenance->>'reader' = 'aer_det';
        if v_item is null or v_rows <> 1 then raise exception 'post-check: the proposal is not one item with one row (%, %)', v_item, v_rows; end if;
        if exists (select 1 from catalogue.course_entry_requirements where course_id = v_course and (kind not in ('minimum_grade', 'prior_qualification') or description ~* 'ielts|toefl|pte|english')) then raise exception 'post-check: a non-academic row was proposed'; end if;
        v_chk := security.aer_machine_check_v1(v_item);
        -- the uncovered prerequisite line holds the read for a person: the machine rule must not admit it
        if coalesce((v_chk->>'ok')::boolean, false) then raise exception 'post-check: the machine rule admitted a read that dropped an uncovered prerequisite line'; end if;
        raise notice 's835 synthetic: proposed, machine rule says % (%)', v_chk->>'rule', left(coalesce(v_chk->>'reason', ''), 120);
      else
        raise notice 's835 synthetic: outcome % (the chosen course was not eligible)', v_outcome;
      end if;
      raise exception 'rollback of the synthetic read' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    select count(*) into v_cn from pipeline.aer_det_academic_pages;
    if v_cn <> 0 or exists (select 1 from catalogue.course_entry_requirements where provenance->>'reader' = 'aer_det') then raise exception 'post-check: the synthetic read was not rolled back'; end if;
  else
    raise notice 's835 synthetic: no eligible course found, the proposal check was skipped';
  end if;

  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
