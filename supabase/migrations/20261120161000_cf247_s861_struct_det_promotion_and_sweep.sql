-- CF-247 s861 (session S1-Structure-Outcomes, Platform Admin 20 Nov 2026 15:19 and 15:22 AEDT: "close duration, study mode, delivery and regulatory code gaps
-- from stored pages and registers", $0 AI and $0 Firecrawl; lane block s860 to s869, migrations 20261120160000 to 20261120162900).
-- Baseline read live 20 Nov 2026 15:26 AEDT (rolled-back GitHub Actions dry run, no interactive SQL; search.course_documents joined to catalogue.courses):
--   AU 24,013 courses: no duration 0, no study load 24, no study mode 20, CRICOS course code 24,013 (complete; nothing for this change to add).
--   NZ 6,514: no duration 4,080 (647 with a stored page), no study load 4,186 (690), no study mode 3,386 (262); NZQA course code 6,514.
--   CA 3,814: no duration 2,458 (1,151 with a stored page), no study load 2,368 (977), no study mode 1,204 (152); provider DLI 3,814; PGWP 0.
--   Manual locks 7,585.
-- What this adds, all beside the existing model (G3: nothing the website or Zoho reads changes shape; 75 functions and 48 relations, checked below;
-- every new object is in schema pipeline or security):
--   pipeline.struct_det_pages        one row for each stored course page read by struct-det-v1.0 and what became of it;
--   pipeline.struct_det_readings     each reading with its verbatim quote (duration, study_load, delivery_mode, and notes the reader does not admit);
--   pipeline.struct_det_outcomes     one row for each course, field and page decided: admitted (with the value before and after), locked, held, sent to Layer 4;
--   pipeline.struct_det_sweep_calls  each worker call the sweep sent (pg_net request id) and whether its answer has been collected;
--   security.struct_det_record_v1    the idempotent writer of pages and readings (called by the sweep);
--   security.struct_det_promote_v1   admits a value only when every reading of the field on the page agrees, the course holds no value (no overwrite), no manual
--                                    lock covers the field, the page is the course's bound page with an identity that admits course facts, and no other course is
--                                    bound to the same page (a shared page is never split); a disagreement or a shared page goes to Layer 4 with a plain reason;
--   security.struct_det_sweep_v1     the self-sustaining sweep: collects finished worker answers, records them, sends the next stored pages of courses with a gap
--                                    (mode struct_det_read, no model, no Firecrawl), then promotes. Job struct-det-sweep, every 5 minutes.
-- Admitted values: catalogue.courses.duration_value and duration_unit (years, months, weeks or semesters, the units the catalogue already holds), study_load with
-- study_load_source 'provider_page' and the page's evidence id, and delivery_mode (on_campus, online, blended, on_campus_and_online). Each admitted course is asked
-- to be rebuilt in search.course_documents through the existing search-course-refresh job.
-- Not admitted here, by design: NZQF level and credits (no catalogue field holds them), trimester and credit-point lengths (not a catalogue unit), PGWP
-- eligibility (no register of eligible programmes is held). They are reported as gaps, not invented.
-- Parity before writing (read live 20 Nov 2026 15:26 AEDT): head 20261120143000; numbered above Pilot #1423 (20261120160000, S1-AER) inside this lane's block.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create table if not exists pipeline.struct_det_pages (
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  chars       integer,
  sha256      text,
  readings    integer not null default 0,
  read_error  text,
  outcome     text,
  outcome_at  timestamptz,
  read_at     timestamptz not null default now(),
  primary key (course_id, evidence_id, extractor)
);
comment on table pipeline.struct_det_pages is 'CF-247 s861: each stored course page the deterministic course structure reader (struct-det-v1.0: duration, study load, delivery mode; no model, no fetch) has read, and the outcome of its promotion (done, no_reading, read_error, page_changed, no_bound_page, course_not_active, layer4_full until Layer 4 has room). Lets the sweep resume where it stopped and read a new page copy when one lands.';
alter table pipeline.struct_det_pages enable row level security;
revoke all on pipeline.struct_det_pages from public, anon, authenticated;
create index if not exists struct_det_pages_open on pipeline.struct_det_pages (read_at) where outcome is null and readings > 0;

create table if not exists pipeline.struct_det_readings (
  id          bigint generated always as identity primary key,
  course_id   uuid not null references catalogue.courses(id) on delete cascade,
  evidence_id uuid not null,
  extractor   text not null,
  field       text not null check (field in ('duration', 'study_load', 'delivery_mode', 'other')),
  value       jsonb not null,
  quote       text not null check (length(quote) between 3 and 400),
  label       text,
  strength    text not null check (strength in ('labelled', 'stated')),
  collapsed   boolean not null default false,
  created_at  timestamptz not null default now()
);
comment on table pipeline.struct_det_readings is 'CF-247 s861: course structure readings (duration, study_load, delivery_mode, and notes such as a range or a credit-point length that are never admitted) read deterministically from a stored course page, each with its verbatim quote and, when the value sits on its own line, its label. collapsed marks a line of a table of several courses: never admitted.';
create unique index if not exists struct_det_readings_one on pipeline.struct_det_readings (course_id, evidence_id, extractor, field, md5(value::text), md5(quote));
create index if not exists struct_det_readings_course on pipeline.struct_det_readings (course_id, evidence_id);
alter table pipeline.struct_det_readings enable row level security;
revoke all on pipeline.struct_det_readings from public, anon, authenticated;

create table if not exists pipeline.struct_det_outcomes (
  course_id      uuid not null references catalogue.courses(id) on delete cascade,
  field          text not null check (field in ('duration', 'study_load', 'delivery_mode')),
  evidence_id    uuid not null,
  extractor      text not null,
  outcome        text not null,
  value          jsonb,
  before_value   jsonb,
  quote          text,
  review_item_id uuid,
  decided_at     timestamptz not null default now(),
  primary key (course_id, field, evidence_id, extractor)
);
comment on table pipeline.struct_det_outcomes is 'CF-247 s861: what the structure promoter decided for each course, field and stored page: admitted (value before and after, with the quote), has_value (no overwrite), locked, identity_not_admitted, provider_hidden, layer4_conflict, layer4_shared_page, layer4_full. The audit and rollback trail of every admitted value.';
alter table pipeline.struct_det_outcomes enable row level security;
revoke all on pipeline.struct_det_outcomes from public, anon, authenticated;
create index if not exists struct_det_outcomes_admitted on pipeline.struct_det_outcomes (decided_at) where outcome = 'admitted';

create table if not exists pipeline.struct_det_sweep_calls (
  request_id   bigint primary key,
  course_ids   jsonb not null,
  sent_at      timestamptz not null default now(),
  collected_at timestamptz,
  status       text,
  pages        integer,
  readings     integer
);
comment on table pipeline.struct_det_sweep_calls is 'CF-247 s861: each worker call (mode struct_det_read) the job struct-det-sweep sent, by pg_net request id, with its collected answer (ok, failed, lost or wrong_extractor). Keeps the sweep from sending a page twice while its answer is open.';
alter table pipeline.struct_det_sweep_calls enable row level security;
revoke all on pipeline.struct_det_sweep_calls from public, anon, authenticated;
create index if not exists struct_det_sweep_calls_open on pipeline.struct_det_sweep_calls (sent_at) where collected_at is null;

-- 1. the writer: pages and readings; an unknown field is skipped, never stored
create or replace function security.struct_det_record_v1(p_pages jsonb) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare v_pages int := 0; v_readings int := 0; p jsonb; r jsonb; v_n int; v_rs jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  for p in select * from jsonb_array_elements(p_pages) loop
    if not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = (p->>'course_id')::uuid and g.evidence_id = (p->>'evidence_id')::uuid) then continue; end if;
    if p ? 'error' then
      continue when p->>'error' = 'call_time_used';  -- the worker ran out of time for this page: it is sent again
      insert into pipeline.struct_det_pages (course_id, evidence_id, extractor, readings, read_error, outcome, outcome_at)
      values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', 0, left(p->>'error', 160), 'read_error', now())
      on conflict (course_id, evidence_id, extractor) do nothing;
      continue;
    end if;
    v_rs := case when jsonb_typeof(p->'readings') = 'array' then p->'readings' else '[]'::jsonb end;
    insert into pipeline.struct_det_pages (course_id, evidence_id, extractor, chars, sha256, readings, outcome, outcome_at)
    values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', (p->>'chars')::int, p->>'sha256',
            (select count(*) from jsonb_array_elements(v_rs) x where x->>'key' in ('duration', 'study_load', 'delivery_mode')),
            case when not exists (select 1 from jsonb_array_elements(v_rs) x where x->>'key' in ('duration', 'study_load', 'delivery_mode')) then 'no_reading' end,
            case when not exists (select 1 from jsonb_array_elements(v_rs) x where x->>'key' in ('duration', 'study_load', 'delivery_mode')) then now() end)
    on conflict (course_id, evidence_id, extractor) do nothing;
    get diagnostics v_n = row_count; v_pages := v_pages + v_n;
    if v_n = 0 then continue; end if;
    for r in select * from jsonb_array_elements(v_rs) loop
      continue when r->>'key' not in ('duration', 'study_load', 'delivery_mode', 'other') or coalesce(length(r->>'quote'), 0) not between 3 and 400
                 or coalesce(r->>'strength', '') not in ('labelled', 'stated') or jsonb_typeof(r->'value') <> 'object';
      insert into pipeline.struct_det_readings (course_id, evidence_id, extractor, field, value, quote, label, strength, collapsed)
      values ((p->>'course_id')::uuid, (p->>'evidence_id')::uuid, p->>'extractor', r->>'key', r->'value', r->>'quote', left(r->>'label', 80), r->>'strength',
              coalesce((r->>'collapsed')::boolean, false))
      on conflict do nothing;
      get diagnostics v_n = row_count; v_readings := v_readings + v_n;
    end loop;
  end loop;
  return jsonb_build_object('pages', v_pages, 'readings', v_readings);
end $f$;
comment on function security.struct_det_record_v1(jsonb) is 'CF-247 s861: records pages read by the deterministic course structure reader and their readings, idempotently. Writes only pipeline.struct_det_pages and pipeline.struct_det_readings.';
revoke all on function security.struct_det_record_v1(jsonb) from public, anon, authenticated;

-- 2. the promoter: one agreed value per field, into an empty field only; anything doubtful goes to Layer 4 with its reason
create or replace function security.struct_det_promote_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_ext constant text := 'struct-det-v1.0';  -- fixed: the reader version this promoter takes readings from; a new reader version ships with its own migration
  v_on int := security.pipeline_num_v1('struct_det.promote_on', 1)::int;
  v_per int := security.pipeline_num_v1('struct_det.promote_per_run', 150)::int;
  v_stated int := security.pipeline_num_v1('struct_det.admit_stated', 1)::int;
  v_l4cap int := security.pipeline_num_v1('struct_det.layer4_max_pending', 200)::int;
  pg record; g record; c record; f text; v_vals jsonb; v_n int; v_q text; v_out text; v_before jsonb; v_item uuid; v_shared boolean;
  v_pages int := 0; v_adm jsonb := '{}'::jsonb; v_l4 int := 0; v_l4pending int; v_page_out text; v_touched boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_on <> 1 then return jsonb_build_object('held', 'promote_off'); end if;
  select count(*) into v_l4pending from pipeline.layer4_review_items i
   where i.status = 'pending' and i.field_code in ('duration', 'study_load', 'delivery_mode') and i.proposed_value->>'reader' = 'struct_det';
  -- pages held because Layer 4 was full are opened again, as many as Layer 4 now has room for
  if v_l4pending < v_l4cap then
    update pipeline.struct_det_pages a set outcome = null, outcome_at = null
     where (a.course_id, a.evidence_id, a.extractor) in (select b.course_id, b.evidence_id, b.extractor from pipeline.struct_det_pages b
                                                           where b.extractor = v_ext and b.outcome = 'layer4_full' order by b.outcome_at limit v_l4cap - v_l4pending);
  end if;
  for pg in select a.course_id, a.evidence_id from pipeline.struct_det_pages a
             where a.extractor = v_ext and a.readings > 0 and a.outcome is null order by a.read_at limit v_per loop
    v_pages := v_pages + 1; v_page_out := 'done'; v_touched := false;
    select co.id, co.provider_id, co.lifecycle_status, co.duration_value, co.duration_unit, co.study_load, co.delivery_mode into c from catalogue.courses co where co.id = pg.course_id;
    select p.identity_basis, p.evidence_id, p.url into g from pipeline.coverage_course_pages p
     where p.course_id = pg.course_id and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
    if c.id is null or c.lifecycle_status <> 'active' then v_page_out := 'course_not_active';
    elsif g.evidence_id is null then v_page_out := 'no_bound_page';
    elsif g.evidence_id is distinct from pg.evidence_id then v_page_out := 'page_changed';  -- the newer page is read by the sweep in its turn
    end if;
    if v_page_out = 'done' then
      v_shared := exists (select 1 from pipeline.coverage_course_pages o where o.course_id <> pg.course_id and o.status = 'bound'
                           and (o.evidence_id = pg.evidence_id or (g.url is not null and o.url = g.url)));
      foreach f in array array['duration', 'study_load', 'delivery_mode'] loop
        -- the distinct values the page gives for the field, from lines that are not part of a table of several courses
        select coalesce(jsonb_agg(distinct r.value), '[]'::jsonb), min(r.quote) into v_vals, v_q
          from pipeline.struct_det_readings r
         where r.course_id = pg.course_id and r.evidence_id = pg.evidence_id and r.extractor = v_ext and r.field = f and not r.collapsed
           and (r.strength = 'labelled' or v_stated = 1);
        v_n := jsonb_array_length(v_vals);
        continue when v_n = 0;
        v_before := case f when 'duration' then jsonb_build_object('value', c.duration_value, 'unit', c.duration_unit)
                           when 'study_load' then to_jsonb(c.study_load) else to_jsonb(c.delivery_mode) end;
        v_out := null; v_item := null;
        if (f = 'duration' and (c.duration_value is not null or c.duration_unit is not null)) or (f = 'study_load' and c.study_load is not null)
           or (f = 'delivery_mode' and (nullif(btrim(c.delivery_mode), '') is not null
                                        or exists (select 1 from catalogue.course_campuses cc where cc.course_id = c.id and nullif(btrim(cc.delivery_mode), '') is not null))) then
          v_out := 'has_value';  -- no overwrite: a value held by any source stays
        elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id
                       and l.field = any (case f when 'duration' then array['duration', 'duration_value', 'duration_unit', 'all']
                                                 when 'study_load' then array['study_load', 'study_load_source', 'study_load_evidence_id', 'all']
                                                 else array['delivery_mode', 'delivery', 'all'] end)) then v_out := 'locked';
        elsif exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id) then v_out := 'provider_hidden';
        elsif not security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'description') then v_out := 'identity_not_admitted';
        elsif v_n > 1 or v_shared then
          if exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c.id and i.field_code = f and i.status = 'pending') then v_out := 'layer4_open';
          elsif v_l4pending >= v_l4cap then v_out := 'layer4_full';  -- no outcome row: the page is decided again when Layer 4 has room
          else
            insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, escalation_reason, change_control_ref)
            values ('course', c.id, f, pg.evidence_id, v_before,
                    jsonb_build_object('reader', 'struct_det', 'extractor', v_ext, 'url', g.url, 'values', v_vals,
                                       'quotes', (select coalesce(jsonb_agg(jsonb_build_object('value', r.value, 'quote', r.quote, 'label', r.label)), '[]'::jsonb)
                                                    from pipeline.struct_det_readings r where r.course_id = c.id and r.evidence_id = pg.evidence_id and r.extractor = v_ext and r.field = f and not r.collapsed)),
                    case when v_n > 1 then 'The course page states more than one ' || replace(f, '_', ' ') || '; please choose the one that applies to this course.'
                         else 'This page is shared with other courses, so its ' || replace(f, '_', ' ') || ' may belong to another course; please confirm it applies to this course.' end,
                    'CF-CHG-20260915-247')
            returning id into v_item;
            v_l4 := v_l4 + 1; v_l4pending := v_l4pending + 1;
            v_out := case when v_n > 1 then 'layer4_conflict' else 'layer4_shared_page' end;
          end if;
        else
          if f = 'duration' then
            update catalogue.courses set duration_value = (v_vals->0->>'value')::numeric, duration_unit = v_vals->0->>'unit', updated_at = now()
             where id = c.id and duration_value is null and duration_unit is null;
          elsif f = 'study_load' then
            update catalogue.courses set study_load = v_vals->0->>'load', study_load_source = 'provider_page', study_load_evidence_id = pg.evidence_id, updated_at = now()
             where id = c.id and study_load is null;
          else
            update catalogue.courses set delivery_mode = v_vals->0->>'mode', updated_at = now() where id = c.id and nullif(btrim(delivery_mode), '') is null;
          end if;
          get diagnostics v_n = row_count;
          if v_n = 1 then
            v_out := 'admitted'; v_touched := true;
            v_adm := jsonb_set(v_adm, array[f], to_jsonb(coalesce((v_adm->>f)::int, 0) + 1));
          else v_out := 'has_value'; end if;
        end if;
        if v_out <> 'layer4_full' then
          insert into pipeline.struct_det_outcomes (course_id, field, evidence_id, extractor, outcome, value, before_value, quote, review_item_id)
          values (c.id, f, pg.evidence_id, v_ext, v_out, case when jsonb_array_length(v_vals) = 1 then v_vals->0 else v_vals end, v_before, v_q, v_item)
          on conflict (course_id, field, evidence_id, extractor) do nothing;
        else v_page_out := 'layer4_full';  -- opened again when Layer 4 has room; its other fields are already decided and recorded
        end if;
      end loop;
      if v_touched and not exists (select 1 from search.course_refresh_requests q where q.course_id = c.id and q.processed_at is null) then
        insert into search.course_refresh_requests (course_id, requested_at, requested_by) values (c.id, now(), 's861_struct_det');
      end if;
    end if;
    update pipeline.struct_det_pages set outcome = v_page_out, outcome_at = now() where course_id = pg.course_id and evidence_id = pg.evidence_id and extractor = v_ext;
  end loop;
  if v_adm <> '{}'::jsonb or v_l4 > 0 then
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'struct_det_promote', 'catalogue.courses (duration, study_load, delivery_mode)',
            jsonb_build_object('extractor', v_ext, 'pages', v_pages, 'admitted', v_adm, 'layer4', v_l4, 'spend', 'none (no model, no Firecrawl)',
                               'approved', 'Platform Admin 20 Nov 2026 15:19 AEDT (S1-Structure-Outcomes)'), null);
  end if;
  return jsonb_build_object('pages', v_pages, 'admitted', v_adm, 'layer4', v_l4);
end $f$;
comment on function security.struct_det_promote_v1() is 'CF-247 s861: admits a course duration, study load or delivery mode read deterministically from its bound stored page only when every reading on the page agrees, the field is empty (no overwrite), no manual lock covers it, the page identity admits course facts and no other course shares the page; a disagreement or a shared page goes to Layer 4 with a plain reason (capped by struct_det.layer4_max_pending). Records every decision in pipeline.struct_det_outcomes and asks search.course_refresh_requests to rebuild each admitted course.';
revoke all on function security.struct_det_promote_v1() from public, anon, authenticated;

-- 3. the sweep: collect, send, promote
create or replace function security.struct_det_sweep_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_ext constant text := 'struct-det-v1.0';  -- fixed: the reader version the worker must answer with
  v_on int := security.pipeline_num_v1('struct_det.sweep_on', 1)::int;
  v_calls int := security.pipeline_num_v1('struct_det.sweep_calls', 2)::int;
  v_max_open int := security.pipeline_num_v1('struct_det.sweep_max_open', 3)::int;
  v_per int := security.pipeline_num_v1('struct_det.pages_per_call', 40)::int;
  v_lost int := security.pipeline_num_v1('struct_det.call_lost_minutes', 15)::int;
  c record; resp record; v_body jsonb; v_pages jsonb; v_rec jsonb; v_open int; v_n int; v_sent int := 0; v_got int := 0; v_open_ids uuid[]; v_items jsonb; v_id bigint; v_prop jsonb; i int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('held', 'maintenance'); end if;
  -- 1. collect the answers of earlier calls
  for c in select * from pipeline.struct_det_sweep_calls where collected_at is null order by sent_at loop
    select r.status_code, r.timed_out, r.error_msg, r.content::text as content into resp from net._http_response r where r.id = c.request_id;
    if not found then
      if c.sent_at < now() - make_interval(mins => v_lost) then update pipeline.struct_det_sweep_calls set collected_at = now(), status = 'lost' where request_id = c.request_id; end if;
      continue;
    end if;
    begin
      if resp.timed_out or resp.error_msg is not null or resp.status_code >= 300 then raise exception 'call failed'; end if;
      v_body := resp.content::jsonb;
      if v_body->>'extractor' is distinct from v_ext then
        update pipeline.struct_det_sweep_calls set collected_at = now(), status = 'wrong_extractor' where request_id = c.request_id; continue;
      end if;
      select coalesce(jsonb_agg(p || jsonb_build_object('extractor', v_ext)), '[]'::jsonb) into v_pages from jsonb_array_elements(coalesce(v_body->'pages', '[]'::jsonb)) p;
      v_rec := security.struct_det_record_v1(v_pages);
      update pipeline.struct_det_sweep_calls set collected_at = now(), status = 'ok', pages = (v_rec->>'pages')::int, readings = (v_rec->>'readings')::int where request_id = c.request_id;
      v_got := v_got + 1;
    exception when others then
      update pipeline.struct_det_sweep_calls set collected_at = now(), status = 'failed' where request_id = c.request_id;
    end;
  end loop;
  -- 2. send the next stored pages: the bound page of an active course that still lacks a duration, a study load or a study mode, not yet read in this version
  select count(*) into v_open from pipeline.struct_det_sweep_calls where collected_at is null;
  v_n := least(v_calls, v_max_open - v_open);
  if v_on = 1 and v_n > 0 then
    select coalesce(array_agg(x::uuid), '{}') into v_open_ids from pipeline.struct_det_sweep_calls o, jsonb_array_elements_text(o.course_ids) x where o.collected_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', t.course_id, 'evidence_id', t.evidence_id, 'storage_path', t.storage_path) order by t.course_id), '[]'::jsonb) into v_items
      from (select g.course_id, g.evidence_id, e.storage_path
              from pipeline.coverage_course_pages g
              join catalogue.courses c2 on c2.id = g.course_id and c2.lifecycle_status = 'active'
              join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
             where g.status = 'bound' and g.evidence_id is not null
               and (c2.duration_value is null or c2.study_load is null
                    or (nullif(btrim(c2.delivery_mode), '') is null and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = c2.id and nullif(btrim(cc.delivery_mode), '') is not null)))
               and not (g.course_id = any (v_open_ids))
               and not exists (select 1 from pipeline.struct_det_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = v_ext)
             order by g.course_id limit v_per * v_n) t;
    for i in 0 .. v_n - 1 loop
      exit when i * v_per >= jsonb_array_length(v_items);
      select coalesce(jsonb_agg(e.item), '[]'::jsonb) into v_pages from jsonb_array_elements(v_items) with ordinality e(item, o) where e.o > i * v_per and e.o <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'struct_det_read', 'items', v_pages));
      insert into pipeline.struct_det_sweep_calls (request_id, course_ids, status) values (v_id, (select coalesce(jsonb_agg(p->>'course_id'), '[]'::jsonb) from jsonb_array_elements(v_pages) p), 'sent');
      v_sent := v_sent + 1;
    end loop;
  end if;
  -- 3. promote what has been read
  v_prop := security.struct_det_promote_v1();
  return jsonb_build_object('collected', v_got, 'calls_sent', v_sent, 'open_calls', v_open, 'promote', v_prop);
end $f$;
comment on function security.struct_det_sweep_v1() is 'CF-247 s861: one tick of the job struct-det-sweep. Collects the answers of earlier worker calls (mode struct_det_read, no model, no Firecrawl), records the readings, sends the next stored pages of courses that lack a duration, study load or study mode, then promotes through security.struct_det_promote_v1. No AI or Firecrawl spend.';
revoke all on function security.struct_det_sweep_v1() from public, anon, authenticated;

-- 4. settings (G2, Settings > Pipeline settings, section Admission checks)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'struct_det.sweep_on', 'Course structure reader: sweep on', '1 lets the job struct-det-sweep send stored course pages to the deterministic structure reader (duration, study load, delivery mode); 0 stops sending (answers already sent are still collected and read pages still promoted).', 'number', to_jsonb(1), 0, 1, 'switch', 660, 'Admission checks', 'security.struct_det_sweep_v1', 'CF-247 s861 (Platform Admin 20 Nov 2026 15:19): autonomous scheduled sweep at $0'),
 ('pipeline', 'struct_det.sweep_calls', 'Course structure reader: worker calls a tick', 'Worker calls the sweep sends in one tick (every 5 minutes); each call carries Course structure reader: pages a call.', 'number', to_jsonb(2), 1, 6, 'calls', 661, 'Admission checks', 'security.struct_det_sweep_v1', 'CF-247 s861: about 960 pages an hour, inside the worker''s limits'),
 ('pipeline', 'struct_det.sweep_max_open', 'Course structure reader: calls open at once', 'The sweep sends no new call while this many are waiting for an answer.', 'number', to_jsonb(3), 1, 8, 'calls', 662, 'Admission checks', 'security.struct_det_sweep_v1', 'CF-247 s861: bounds parallel worker calls'),
 ('pipeline', 'struct_det.pages_per_call', 'Course structure reader: pages a call', 'Stored course pages sent to the worker in one call (the worker reads at most 40).', 'number', to_jsonb(40), 5, 40, 'pages', 663, 'Admission checks', 'security.struct_det_sweep_v1', 'CF-247 s861'),
 ('pipeline', 'struct_det.call_lost_minutes', 'Course structure reader: minutes before a call is counted lost', 'A worker call with no stored answer after this many minutes is counted lost and its pages are sent again.', 'number', to_jsonb(15), 5, 120, 'minutes', 664, 'Admission checks', 'security.struct_det_sweep_v1', 'CF-247 s861'),
 ('pipeline', 'struct_det.promote_on', 'Course structure reader: admit agreed values', '1 lets the sweep admit a duration, study load or delivery mode that every reading on the course''s own stored page agrees on, into an empty field only; 0 holds them (nothing is admitted or sent to Layer 4).', 'number', to_jsonb(1), 0, 1, 'switch', 665, 'Admission checks', 'security.struct_det_promote_v1', 'CF-247 s861 (Platform Admin 20 Nov 2026 15:19): automated deterministic promotion through the existing gates'),
 ('pipeline', 'struct_det.promote_per_run', 'Course structure reader: pages decided a tick', 'Most read pages decided in one tick of the sweep (each page decides up to three fields).', 'number', to_jsonb(150), 10, 250, 'pages', 666, 'Admission checks', 'security.struct_det_promote_v1', 'CF-247 s861: 100 to 250 courses a batch'),
 ('pipeline', 'struct_det.admit_stated', 'Course structure reader: admit sentence readings', '1 admits a length read from a sentence that ties it to full-time study ("3 years full-time"), as well as labelled lines; 0 admits labelled lines only.', 'number', to_jsonb(1), 0, 1, 'switch', 667, 'Admission checks', 'security.struct_det_promote_v1', 'CF-247 s861'),
 ('pipeline', 'struct_det.layer4_max_pending', 'Course structure reader: items waiting in Layer 4', 'No new structure item is sent to Layer 4 while this many wait there; the page stays open and is decided when there is room.', 'number', to_jsonb(200), 20, 2000, 'items', 668, 'Admission checks', 'security.struct_det_promote_v1', 'CF-247 s861: keeps Layer 4 from flooding')
on conflict do nothing;

-- 5. the job (G1) and the register
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('struct-det-sweep', 'Admission checks', 21, 'Course structure reader: sweep and admit',
  'Every 5 minutes: collects the answers of earlier worker calls, records the duration, study load and delivery mode readings of stored course pages (verbatim quotes, no model), sends the next stored pages of courses that still lack one of them, and admits a value into an empty field only when every reading on the course''s own page agrees, no manual lock covers it and no other course shares the page. Disagreements and shared pages go to Layer 4. No AI or Firecrawl spend. Switch off with Course structure reader: sweep on and admit agreed values.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('struct-det-sweep', '1-56/5 * * * *', 'select security.struct_det_sweep_v1()')
where not exists (select 1 from cron.job where jobname = 'struct-det-sweep');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'struct-det-sweep', 'Layer 3', 'Admission checks', 'Sweeps stored course pages with the deterministic course structure reader and admits agreed values, every 5 minutes', 'active', '{}', '20261120161000'),
  ('table', 'pipeline.struct_det_pages', 'Layer 3', 'Admission checks', 'Stored pages read by the course structure reader and what became of each', 'active', '{}', '20261120161000'),
  ('table', 'pipeline.struct_det_readings', 'Layer 3', 'Admission checks', 'Duration, study load and delivery mode readings with their verbatim quotes', 'active', '{}', '20261120161000'),
  ('table', 'pipeline.struct_det_outcomes', 'Layer 3', 'Admission checks', 'Each structure decision: admitted (before and after), held or sent to Layer 4', 'active', '{}', '20261120161000'),
  ('table', 'pipeline.struct_det_sweep_calls', 'Layer 3', 'Admission checks', 'Worker calls the structure sweep sent and their collected answers', 'active', '{}', '20261120161000'),
  ('function', 'security.struct_det_record_v1', 'Layer 3', 'Admission checks', 'Writes the readings of pages the course structure reader read', 'active', '{}', '20261120161000'),
  ('function', 'security.struct_det_promote_v1', 'Layer 3', 'Admission checks', 'Admits agreed structure values into empty fields, or sends them to Layer 4', 'active', '{}', '20261120161000'),
  ('function', 'security.struct_det_sweep_v1', 'Layer 3', 'Admission checks', 'One tick of the course structure reader sweep', 'active', '{}', '20261120161000')
on conflict do nothing;

-- 6. post-checks. The synthetic promotion runs inside a block that is rolled back (it raises P0099 at the end), so nothing it writes stays.
do $c$
declare
  v_api jsonb; v_course uuid; v_ev uuid; v_prop jsonb; v_t0 timestamptz; v_ms numeric; v_dur numeric; v_mode text; v_out text; v_cn int; v_req int;
begin
  if to_regclass('pipeline.struct_det_pages') is null or to_regclass('pipeline.struct_det_readings') is null or to_regclass('pipeline.struct_det_outcomes') is null
     or to_regclass('pipeline.struct_det_sweep_calls') is null then raise exception 'post-check: a table is missing'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'struct\_det.%') <> 9 then raise exception 'post-check: the nine struct_det settings are not all present'; end if;
  if not exists (select 1 from cron.job where jobname = 'struct-det-sweep' and active) then raise exception 'post-check: the job is not scheduled'; end if;
  if regexp_replace((select command from cron.job where jobname = 'struct-det-sweep'), '_v[0-9]+', '', 'g') ~ '[0-9]' then raise exception 'post-check: the job command holds a number (G2)'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'struct-det-sweep') then raise exception 'post-check: the job is not catalogued (G1)'; end if;

  -- the send query of one tick (timed): it must stay well inside a tick
  v_t0 := clock_timestamp();
  perform count(*) from (select g.course_id from pipeline.coverage_course_pages g
              join catalogue.courses c2 on c2.id = g.course_id and c2.lifecycle_status = 'active'
              join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
             where g.status = 'bound' and g.evidence_id is not null
               and (c2.duration_value is null or c2.study_load is null
                    or (nullif(btrim(c2.delivery_mode), '') is null and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = c2.id and nullif(btrim(cc.delivery_mode), '') is not null)))
               and not exists (select 1 from pipeline.struct_det_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = 'struct-det-v1.0')
             order by g.course_id limit 80) t;
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  raise notice 's861 send query: % ms', round(v_ms);

  -- a rolled back synthetic read of one eligible course with no duration and no study mode: the agreed duration is admitted, the disagreeing modes go to Layer 4
  select c.id, p.evidence_id into v_course, v_ev
    from catalogue.courses c
    join pipeline.coverage_course_pages p on p.course_id = c.id and p.status = 'bound' and p.evidence_id is not null
   where c.lifecycle_status = 'active' and c.duration_value is null and c.duration_unit is null and nullif(btrim(c.delivery_mode), '') is null
     and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = c.id and nullif(btrim(cc.delivery_mode), '') is not null)
     and security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'description')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id)
     and not exists (select 1 from pipeline.coverage_course_pages o where o.course_id <> c.id and o.status = 'bound' and (o.evidence_id = p.evidence_id or o.url = p.url))
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = c.id and r.status = 'pending' and r.field_code in ('duration', 'delivery_mode'))
     and p.bound_at = (select max(p2.bound_at) from pipeline.coverage_course_pages p2 where p2.course_id = c.id and p2.status = 'bound')
   order by c.id limit 1;
  if v_course is not null then
    begin
      insert into pipeline.struct_det_pages (course_id, evidence_id, extractor, chars, readings) values (v_course, v_ev, 'struct-det-v1.0', 100, 4);
      insert into pipeline.struct_det_readings (course_id, evidence_id, extractor, field, value, quote, label, strength, collapsed) values
        (v_course, v_ev, 'struct-det-v1.0', 'duration', '{"value": 3, "unit": "years"}', '3 years full-time', 'Duration', 'labelled', false),
        (v_course, v_ev, 'struct-det-v1.0', 'duration', '{"value": 2, "unit": "years"}', 'Bachelor of Arts | 2 years | Master of Arts | 1 year', null, 'labelled', true),
        (v_course, v_ev, 'struct-det-v1.0', 'delivery_mode', '{"mode": "online"}', 'Delivery: Online', null, 'labelled', false),
        (v_course, v_ev, 'struct-det-v1.0', 'delivery_mode', '{"mode": "on_campus"}', 'Study mode: On campus', null, 'labelled', false);
      v_prop := security.struct_det_promote_v1();
      select duration_value, delivery_mode into v_dur, v_mode from catalogue.courses where id = v_course;
      if v_dur is distinct from 3 then raise exception 'post-check: the agreed duration was not admitted (% / %)', v_dur, v_prop; end if;
      if v_mode is not null then raise exception 'post-check: a disagreeing delivery mode was admitted'; end if;
      select outcome into v_out from pipeline.struct_det_outcomes where course_id = v_course and field = 'delivery_mode';
      if v_out not in ('layer4_conflict', 'layer4_full', 'layer4_open') and v_out is not null then raise exception 'post-check: the disagreeing modes were not sent to Layer 4 (%)', v_out; end if;
      select count(*) into v_req from search.course_refresh_requests where course_id = v_course and processed_at is null;
      if v_req < 1 then raise exception 'post-check: the admitted course was not asked to be rebuilt in search'; end if;
      raise notice 's861 synthetic: %', v_prop;
      raise exception 'rollback of the synthetic read' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    select count(*) into v_cn from pipeline.struct_det_pages;
    if v_cn <> 0 or exists (select 1 from catalogue.courses where id = v_course and duration_value is not null) then raise exception 'post-check: the synthetic read was not rolled back'; end if;
  else
    raise notice 's861 synthetic: no eligible course found, the promotion check was skipped';
  end if;

  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
