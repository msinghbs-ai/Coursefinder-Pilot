-- CF-247 s851 and s852 (Platform Admin 20 Nov 2026 15:11 AEDT, chat S1-Fees-Intakes): a $0 deterministic reader of the international tuition fee, the intake
-- months and the application closing date that stored course pages state in words, its gated promotion and a scheduled sweep.
-- Baseline read live (rolled-back probes, 20 Nov 2026 15:20 AEDT), active published courses: AU 24,013 (intakes 9,522, deadlines 53, stored page text 14,431);
--   NZ 6,514 (international fee 1,491, intakes 2,221, deadlines 33 = 0.5%); CA 3,814 (international fee 732, intakes 1,688, deadlines 214).
-- How it works (no model, no Firecrawl, no new public object):
--   1 Job fid-det-sweep (every minute; it acts every fid.run_every_minutes) records the worker replies that have come back, then, when no batch is out, takes the next
--     fid.batch_size courses (100 to 250) in scope (the fee reader's countries and provider types, published) whose bound course page is stored and that miss an
--     international fee, an intake or a deadline, by an indexed keyset on course id, and sends them to coverage-sweep mode fid_det_read in calls of fid.items_per_call.
--   2 The worker (read only) reads each stored page and returns readings with verbatim quotes (fid-det-reader.ts, fid-det-v1.0). The reply is read back from
--     pg_net's response table by the next run; nothing calls into the database from the worker.
--   3 security.fid_det_record_v1 gates every reading. Admitted only when 100% verified: the quote is on the page (checked by the worker), the page is the course's
--     bound page now (page identity) and the country's identity rule accepts its proof for the field, the value is complete (amount, the country's currency and a
--     per-year basis; a calendar month; a full closing date in the same clause as its closing words, inside its intake's window), nothing is held for the field
--     (no overwrite) and no manual lock is set (the table guard checks again). Fees and intakes are written by the one governed write,
--     security.coverage_apply_course_v1 (country currency, fee floor and tuition identity checks); deadlines fill only an empty deadline of the intake they belong to.
--     A fee per semester, per unit or for the whole course, two different yearly figures, or an old fee year go to Layer 4 (provider_current_tuition_validation,
--     with the reason in words), at most fid.layer4_per_run a run. Rolling admission statements are recorded with their quote and write nothing.
--   4 Search: the course source is approved for the fee and intake domains and one search refresh is requested, so search.course_documents carries the new values.
-- G1: job fid-det-sweep is catalogued and in the component register. G2: every size, window and limit is a setting (pipeline toolset, Fees and intakes section);
--   the job command has no number. G3: no consumer API object; checked before and after (75 functions, 48 relations, no drift). AI spend: none (no model is called).
-- Parity: live head 20261120143000 (2,219 rows) read 20 Nov 2026 15:16 AEDT; lane block s850 to s859 (migrations 20261120153000 to 155900). Renumbered twice
--   (16:05 and 17:20 AEDT) as other lanes merged above that slot (S1-AER 20261120163000, S1-Structure 20261120163500 and 20261120172000, S1-ELR 20261120170000):
--   now 20261120175000 and 20261120175100, above the newest migration on main (repo-first parity, merge check).
-- Replaces: nothing (the AI fee reader keeps reading fee schedule pages; this reads course pages without a model).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: set fid.sweep_on to 0 (the job then does nothing); a paste file unschedules the job. Values it admitted carry source_fee_key / source_intake_key 'fid-det' and
--   their reading rows, so they can be listed and withdrawn by a person.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'fid.sweep_on', 'Deterministic fee, intake and deadline reader: on',
   '1 reads stored course pages for international fees, intake months and closing dates with no model and admits only fully verified values; 0 stops the sweep (nothing else changes).',
   'number', to_jsonb(1), 0, 1, 'on/off', 990, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s852 (Platform Admin 20 Nov 2026 15:11)'),
  ('pipeline', 'fid.run_every_minutes', 'Deterministic fee, intake and deadline reader: run every',
   'The sweep job is called each minute and sends a new batch this often (when the last batch has come back).',
   'number', to_jsonb(5), 2, 120, 'minutes', 991, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s852'),
  ('pipeline', 'fid.batch_size', 'Deterministic fee, intake and deadline reader: courses a batch',
   'Courses with a stored course page and a missing fee, intake or deadline read in one batch.',
   'number', to_jsonb(150), 100, 250, 'courses', 992, 'Fees and intakes', 'fid-det-sweep (security.fid_det_batch_v1)', 'CF-247 s852'),
  ('pipeline', 'fid.items_per_call', 'Deterministic fee, intake and deadline reader: pages a worker call',
   'Stored pages sent to one coverage-sweep call (the worker reads at most 40).',
   'number', to_jsonb(30), 5, 40, 'pages', 993, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s852'),
  ('pipeline', 'fid.reply_wait_minutes', 'Deterministic fee, intake and deadline reader: wait for a reply',
   'A batch whose worker replies have not come back after this long is closed as expired and its pages are offered again in a later pass.',
   'number', to_jsonb(15), 5, 120, 'minutes', 994, 'Fees and intakes', 'fid-det-sweep (security.fid_det_tick_v1)', 'CF-247 s852'),
  ('pipeline', 'fid.layer4_per_run', 'Deterministic fee, intake and deadline reader: Layer 4 items a run',
   'Fees that need a person (per semester, per unit or whole-course figures, two different yearly figures, an old fee year) raised in Layer 4 in one run; the rest wait for a later run.',
   'number', to_jsonb(20), 0, 200, 'items', 995, 'Fees and intakes', 'security.fid_det_record_v1', 'CF-247 s851'),
  ('pipeline', 'fid.deadline_past_days', 'Deterministic deadline: oldest closing date kept',
   'A closing date for an intake with no year or start date is admitted only if it is no more than this many days in the past.',
   'number', to_jsonb(31), 0, 365, 'days', 996, 'Fees and intakes', 'security.fid_det_record_v1', 'CF-247 s851'),
  ('pipeline', 'fid.deadline_ahead_days', 'Deterministic deadline: furthest closing date kept',
   'A closing date for an intake with no year or start date is admitted only if it is no more than this many days ahead.',
   'number', to_jsonb(550), 30, 1000, 'days', 997, 'Fees and intakes', 'security.fid_det_record_v1', 'CF-247 s851')
on conflict (toolset_key, key) do nothing;

-- tables
create table if not exists pipeline.fid_det_runs (
  id bigserial primary key,
  request_id bigint,
  items integer not null,
  state text not null default 'sent' check (state in ('sent', 'recorded', 'failed', 'expired')),
  sent_at timestamptz not null default now(),
  recorded_at timestamptz,
  result jsonb
);
create index if not exists fid_det_runs_open on pipeline.fid_det_runs (sent_at) where state = 'sent';
alter table pipeline.fid_det_runs enable row level security;
revoke all on table pipeline.fid_det_runs from public, anon, authenticated;
comment on table pipeline.fid_det_runs is 'CF-247 s852: one row per coverage-sweep fid_det_read call sent by job fid-det-sweep (pg_net request id, pages sent, state, what the record step did). The reply is read back from net._http_response.';

create table if not exists pipeline.fid_det_pages (
  course_id uuid not null,
  evidence_id uuid not null,
  extractor text not null,
  run_id bigint,
  read_at timestamptz not null default now(),
  chars integer,
  sha256 text,
  error text,
  readings integer not null default 0,
  outcome jsonb not null default '{}'::jsonb,
  primary key (course_id, evidence_id, extractor)
);
alter table pipeline.fid_det_pages enable row level security;
revoke all on table pipeline.fid_det_pages from public, anon, authenticated;
comment on table pipeline.fid_det_pages is 'CF-247 s851: one row per stored course page the deterministic fee, intake and deadline reader has read at an extractor version (so a page is not read again until it changes or the reader does), with what was admitted, raised or held.';

create table if not exists pipeline.fid_det_readings (
  id bigserial primary key,
  course_id uuid not null,
  evidence_id uuid not null,
  extractor text not null,
  kind text not null check (kind in ('fee', 'intake', 'deadline', 'ambiguous')),
  value jsonb not null,
  quote text not null,
  outcome text not null,
  reason text,
  layer4_item uuid,
  created_at timestamptz not null default now()
);
create index if not exists fid_det_readings_course on pipeline.fid_det_readings (course_id);
create index if not exists fid_det_readings_outcome on pipeline.fid_det_readings (kind, outcome);
alter table pipeline.fid_det_readings enable row level security;
revoke all on table pipeline.fid_det_readings from public, anon, authenticated;
comment on table pipeline.fid_det_readings is 'CF-247 s851: every reading of the deterministic fee, intake and deadline reader with its verbatim quote and outcome (admitted, layer4, held_value, locked, identity, incomplete, rolling, not_tied_to_intake, outside_window, ambiguous, waiting).';

create table if not exists pipeline.fid_det_state (
  id smallint primary key default 1 check (id = 1),
  cursor_course uuid not null default '00000000-0000-0000-0000-000000000000',
  pass integer not null default 1,
  updated_at timestamptz not null default now()
);
insert into pipeline.fid_det_state(id) values (1) on conflict (id) do nothing;
alter table pipeline.fid_det_state enable row level security;
revoke all on table pipeline.fid_det_state from public, anon, authenticated;
comment on table pipeline.fid_det_state is 'CF-247 s852: the keyset cursor of the deterministic fee, intake and deadline sweep (last course id sent, pass number); one row.';

-- the next batch: courses in scope whose bound page is stored, with a gap, not yet read at this extractor version (keyset on course id)
create or replace function security.fid_det_batch_v1(p_limit integer, p_extractor text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_cur uuid; v_scope uuid[]; v_cc jsonb; r record; v_last uuid; v_seen int := 0; v_out jsonb := '[]'::jsonb;
        v_lim int := greatest(1, least(coalesce(p_limit, 150), 250));  -- fixed: the batch bound of the request (setting fid.batch_size is 100 to 250)
begin
  select cursor_course into v_cur from pipeline.fid_det_state where id = 1;
  -- the fee reader's scope (countries, provider types), published providers only, read once
  select array_agg(p.id), jsonb_object_agg(p.id, k.iso_alpha2) into v_scope, v_cc
    from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
   where k.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.countries')
     and coalesce(t.code, 'other') in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.provider_types')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  -- an indexed keyset over the bound stored pages; each candidate's gap is checked by its own indexed lookups (no table-wide scan of fees or intakes)
  for r in
    select g.course_id, g.evidence_id, g.provider_id, e.storage_path
      from pipeline.coverage_course_pages g
      join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
      join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
     where g.course_id > v_cur and g.status = 'bound' and g.evidence_id is not null and g.read_status is not null and g.provider_id = any(v_scope)
     order by g.course_id
     limit v_lim * 2  -- fixed: a scan window of two batches, so one call stays short however many courses have no gap
  loop
    v_seen := v_seen + 1; v_last := r.course_id;
    continue when exists (select 1 from pipeline.fid_det_pages d where d.course_id = r.course_id and d.evidence_id = r.evidence_id and d.extractor = p_extractor
                                and d.error is null and not coalesce((d.outcome->>'retry')::boolean, false));
    continue when exists (select 1 from catalogue.course_fees f where f.course_id = r.course_id and f.status in ('active', 'unverified') and f.fee_type = 'provider_current_tuition')
              and exists (select 1 from catalogue.course_intakes i where i.course_id = r.course_id and i.status = 'active' and i.application_deadline is not null);
    v_out := v_out || jsonb_build_object('course_id', r.course_id, 'evidence_id', r.evidence_id, 'storage_path', r.storage_path, 'country', v_cc->>(r.provider_id::text));
    exit when jsonb_array_length(v_out) >= v_lim;
  end loop;
  if v_seen = 0 then
    update pipeline.fid_det_state set cursor_course = '00000000-0000-0000-0000-000000000000', pass = pass + 1, updated_at = now() where id = 1 and cursor_course <> '00000000-0000-0000-0000-000000000000';
  else
    update pipeline.fid_det_state set cursor_course = v_last, updated_at = now() where id = 1;
  end if;
  return v_out;
end $function$;
comment on function security.fid_det_batch_v1(integer, text) is 'CF-247 s852: the next batch for the deterministic fee, intake and deadline reader (keyset on course id; the cursor wraps to a new pass when nothing is left after it).';

-- the gate: records one worker reply and admits what is fully verified
create or replace function security.fid_det_record_v1(p_run bigint, p_body jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  pg jsonb; rd jsonb; c record; v_src uuid; v_ext text := p_body->>'extractor'; v_year int := extract(year from now() at time zone 'Australia/Melbourne')::int;
  v_l4_cap int := security.pipeline_num_v1('fid.layer4_per_run', 20)::int; v_l4 int := 0;
  v_past int := security.pipeline_num_v1('fid.deadline_past_days', 31)::int; v_ahead int := security.pipeline_num_v1('fid.deadline_ahead_days', 550)::int;
  v_max_before int := security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)::int;
  v_out jsonb := '{}'::jsonb; v_pages int := 0; v_any boolean := false; v_fee_in boolean := false; v_itk_in boolean := false;
  v_annual jsonb[]; v_fees jsonb[]; v_months text[]; v_itk_year int; v_itk_years int[]; v_res jsonb; v_outcome text; v_reason text; v_item uuid; v_targets uuid[]; v_date date;
  v_page jsonb; v_cc text; v_cur text; v_held boolean; v_lock boolean;
begin
  if v_ext is null or jsonb_typeof(p_body->'pages') <> 'array' then raise exception 'fid_det_record_v1: no extractor or pages in the reply'; end if;
  for pg in select value from jsonb_array_elements(p_body->'pages') loop
    v_pages := v_pages + 1; v_page := '{}'::jsonb;
    insert into pipeline.fid_det_pages(course_id, evidence_id, extractor, run_id, chars, sha256, error, readings)
    values ((pg->>'course_id')::uuid, (pg->>'evidence_id')::uuid, v_ext, p_run, nullif(pg->>'chars', '')::int, pg->>'sha256', left(pg->>'error', 300),
            coalesce(jsonb_array_length(pg->'readings'), 0))
    on conflict (course_id, evidence_id, extractor) do update
      set run_id = excluded.run_id, read_at = now(), chars = excluded.chars, sha256 = excluded.sha256, error = excluded.error, readings = excluded.readings, outcome = '{}'::jsonb
      where pipeline.fid_det_pages.error is not null or coalesce((pipeline.fid_det_pages.outcome->>'retry')::boolean, false);
    if not found then continue; end if;  -- this page was recorded already (a reply read twice)
    if pg ? 'error' then
      -- a page the worker could not read keeps its error and is offered again in a later pass (security.fid_det_batch_v1)
      v_out := jsonb_set(v_out, '{read_error}', to_jsonb(coalesce((v_out->>'read_error')::int, 0) + 1));
      continue;
    end if;
    -- the course, its country currency and its bound page now (page identity)
    select co.id, co.provider_id, k.iso_alpha2 cc, a.currency_code cur, g.evidence_id bound_ev, g.identity_basis, g.basis bind_basis, g.url, e.content_hash
      into c
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
      left join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
      left join pipeline.coverage_course_pages g on g.course_id = co.id and g.status = 'bound'
      left join pipeline.evidence_artifacts e on e.id = g.evidence_id
     where co.id = (pg->>'course_id')::uuid;
    v_cc := c.cc; v_cur := c.cur;
    v_src := case when c.id is not null then security.coverage_sweep_source(c.provider_id) end;
    -- ambiguity notes from the worker are kept as readings (no value)
    for rd in select value from jsonb_array_elements(coalesce(pg->'ambiguous', '[]'::jsonb)) loop
      insert into pipeline.fid_det_readings(course_id, evidence_id, extractor, kind, value, quote, outcome, reason)
      values ((pg->>'course_id')::uuid, (pg->>'evidence_id')::uuid, v_ext, 'ambiguous', '{}'::jsonb, left(rd #>> '{}', 320), 'ambiguous', left(rd #>> '{}', 300));
    end loop;
    v_annual := '{}'; v_fees := '{}'; v_months := '{}'; v_itk_years := '{}';
    for rd in select value from jsonb_array_elements(coalesce(pg->'readings', '[]'::jsonb)) loop
      if coalesce(btrim(rd->>'quote'), '') = '' then continue; end if;
      if rd->>'kind' = 'fee' then
        v_fees := array_append(v_fees, rd);
        if rd->>'basis' = 'annual' then v_annual := array_append(v_annual, rd); end if;
      elsif rd->>'kind' = 'intake' then
        v_months := v_months || array(select jsonb_array_elements_text(coalesce(rd->'months', '[]'::jsonb)));
        if nullif(rd->>'year', '') is not null then v_itk_years := array_append(v_itk_years, (rd->>'year')::int); end if;
      end if;
    end loop;
    v_months := array(select distinct m from unnest(v_months) m where m in ('January','February','March','April','May','June','July','August','September','October','November','December'));

    -- FEE --------------------------------------------------------------------------------------------------------------------------------------------
    if cardinality(v_fees) > 0 then
      v_held := exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.fee_type = 'provider_current_tuition' and f.status in ('active', 'unverified'));
      v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'tuition');
      v_outcome := null; v_reason := null; v_item := null;
      if c.id is null or v_src is null or v_cur is null then v_outcome := 'incomplete'; v_reason := 'course or its country admission rule not found';
      elsif v_held then v_outcome := 'held_value'; v_reason := 'an international fee is already held (no overwrite)';
      elsif v_lock then v_outcome := 'locked'; v_reason := 'the fee is locked by a person';
      elsif c.bound_ev is distinct from (pg->>'evidence_id')::uuid then v_outcome := 'identity'; v_reason := 'the page read is no longer the course''s bound page';
      elsif coalesce(c.bind_basis, '') <> 'manual' and c.identity_basis is not null and c.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, c.identity_basis, 'tuition') then
        v_outcome := 'identity'; v_reason := 'the country''s tuition rule does not accept the page''s proof (' || c.identity_basis || ')';
      elsif cardinality(v_annual) = 1 and (v_annual[1]->>'currency') = v_cur and (v_annual[1]->>'amount')::numeric > 0
            and coalesce((v_annual[1]->>'fee_year')::int, v_year) >= v_year - 1
            and not exists (select 1 from jsonb_array_elements(coalesce(pg->'ambiguous', '[]'::jsonb)) a where a #>> '{}' like 'fee:%') then
        begin
          v_res := security.coverage_apply_course_v1(c.id, v_src, (pg->>'evidence_id')::uuid, c.url, coalesce(c.content_hash, pg->>'sha256'),
                     jsonb_build_object('fee_amount', round((v_annual[1]->>'amount')::numeric, 2), 'currency_code', v_cur, 'fee_year', nullif(v_annual[1]->>'fee_year', ''),
                                        'fee_basis', 'annual', 'fee_notes', left('Deterministic fee reader ' || v_ext || ' (course page ' || coalesce(c.url, '') || '): "' || (v_annual[1]->>'quote') || '"', 500)));
          if coalesce((v_res->>'fees_applied')::int, 0) = 1 then v_outcome := 'admitted'; v_fee_in := true;
          else v_outcome := 'layer4'; v_reason := case when (v_res->>'fee_quarantined_identity')::boolean then 'quarantined at the write by the tuition identity check' else 'below the country fee floor: quarantined to Layer 4' end; end if;
        exception when others then v_outcome := 'incomplete'; v_reason := left('not admitted: ' || sqlerrm, 300);
        end;
      else
        -- needs a person: another basis, two yearly figures, a currency that is not the country's, or an old fee year
        v_reason := case when cardinality(v_annual) > 1 then 'two or more different yearly international fees on the course page'
                         when cardinality(v_annual) = 1 and (v_annual[1]->>'currency') is distinct from v_cur then 'the fee is printed in ' || (v_annual[1]->>'currency') || ', not ' || coalesce(v_cur, 'the country currency')
                         when cardinality(v_annual) = 1 and (v_annual[1]->>'fee_year')::int < v_year - 1 then 'the yearly fee is for ' || (v_annual[1]->>'fee_year') || ', an old fee year'
                         when cardinality(v_annual) = 1 then 'the course page prints other fee figures beside the yearly one'
                         else 'the course page gives the international fee ' || replace(v_fees[1]->>'basis', '_', ' ') || ', not per year' end;
        if v_l4 < v_l4_cap and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = c.id
                                                and l.field_code = 'provider_current_tuition_validation' and l.status = 'pending') then
          insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
          values ('course', c.id, 'provider_current_tuition_validation', (pg->>'evidence_id')::uuid, '{}'::jsonb,
                  jsonb_build_object('amount', (v_fees[1]->>'amount')::numeric, 'currency_code', v_fees[1]->>'currency', 'basis', v_fees[1]->>'basis', 'audience', 'international',
                                     'fee_year', nullif(v_fees[1]->>'fee_year', '')),
                  jsonb_build_object('page', c.url, 'source', 'deterministic fee reader', 'quote', v_fees[1]->>'quote', 'extractor', v_ext,
                                     'readings', (select jsonb_agg(jsonb_build_object('amount', x->'amount', 'currency', x->'currency', 'basis', x->'basis', 'fee_year', x->'fee_year', 'quote', x->'quote')) from unnest(v_fees) x)),
                  '{}'::jsonb, 'pending', 'Deterministic fee reader: ' || v_reason || '. Please confirm the yearly international fee from the quoted page.', 'CF-CHG-20260915-247 s851')
          returning id into v_item;
          v_l4 := v_l4 + 1; v_outcome := 'layer4';
        else
          v_outcome := 'waiting'; v_reason := v_reason || case when v_l4 >= v_l4_cap then ' (Layer 4 places used this run)' else ' (a fee item is already waiting in Layer 4)' end;
          -- a page waiting for a Layer 4 place is read again in a later pass
          if v_l4 >= v_l4_cap then v_page := v_page || jsonb_build_object('retry', true); end if;
        end if;
      end if;
      insert into pipeline.fid_det_readings(course_id, evidence_id, extractor, kind, value, quote, outcome, reason, layer4_item)
      select c.id, (pg->>'evidence_id')::uuid, v_ext, 'fee', x - 'quote' - 'kind', left(x->>'quote', 320), v_outcome, v_reason, v_item from unnest(v_fees) x
       where c.id is not null;
      v_page := v_page || jsonb_build_object('fee', v_outcome);
      v_out := jsonb_set(v_out, array['fee_' || v_outcome], to_jsonb(coalesce((v_out->>('fee_' || v_outcome))::int, 0) + 1));
    end if;

    -- INTAKES ----------------------------------------------------------------------------------------------------------------------------------------
    if exists (select 1 from jsonb_array_elements(coalesce(pg->'readings', '[]'::jsonb)) r where r->>'kind' = 'intake') and c.id is not null then
      v_held := exists (select 1 from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active');
      v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'intakes');
      v_itk_years := array(select distinct y from unnest(v_itk_years) y);
      v_itk_year := case when cardinality(v_itk_years) = 1 then v_itk_years[1] end;
      v_outcome := null; v_reason := null;
      if v_held then v_outcome := 'held_value'; v_reason := 'intakes are already held (no overwrite)';
      elsif v_lock then v_outcome := 'locked'; v_reason := 'intakes are locked by a person';
      elsif cardinality(v_months) = 0 then v_outcome := 'incomplete'; v_reason := 'the page names study periods (trimester, semester or term) but no calendar month';
      elsif cardinality(v_months) > 6 then v_outcome := 'incomplete'; v_reason := 'more than six months named: a calendar, not intakes';
      elsif c.bound_ev is distinct from (pg->>'evidence_id')::uuid then v_outcome := 'identity'; v_reason := 'the page read is no longer the course''s bound page';
      elsif coalesce(c.bind_basis, '') <> 'manual' and c.identity_basis is not null and c.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, c.identity_basis, 'intakes') then
        v_outcome := 'identity'; v_reason := 'the country''s intake rule does not accept the page''s proof (' || c.identity_basis || ')';
      elsif v_itk_year is not null and v_itk_year < v_year then v_outcome := 'incomplete'; v_reason := 'the intakes are for ' || v_itk_year || ', a past year';
      else
        begin
          v_res := security.coverage_apply_course_v1(c.id, v_src, (pg->>'evidence_id')::uuid, c.url, coalesce(c.content_hash, pg->>'sha256'),
                     jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'intake_year', v_itk_year, 'source_intake_key', 'fid-det:' || coalesce(v_itk_year::text, 'current') || ':' || lower(m))) from unnest(v_months) m)));
          v_outcome := case when coalesce((v_res->>'intakes_applied')::int, 0) > 0 then 'admitted' else 'incomplete' end;
          if v_outcome = 'admitted' then v_itk_in := true; end if;
        exception when others then v_outcome := 'incomplete'; v_reason := left('not admitted: ' || sqlerrm, 300);
        end;
      end if;
      insert into pipeline.fid_det_readings(course_id, evidence_id, extractor, kind, value, quote, outcome, reason)
      select c.id, (pg->>'evidence_id')::uuid, v_ext, 'intake', r - 'quote' - 'kind', left(r->>'quote', 320), v_outcome, v_reason
        from jsonb_array_elements(pg->'readings') r where r->>'kind' = 'intake';
      v_page := v_page || jsonb_build_object('intake', v_outcome);
      v_out := jsonb_set(v_out, array['intake_' || v_outcome], to_jsonb(coalesce((v_out->>('intake_' || v_outcome))::int, 0) + 1));
    end if;

    -- DEADLINES (after intakes, so a deadline can belong to an intake admitted from the same page) ---------------------------------------------------
    for rd in select r from jsonb_array_elements(coalesce(pg->'readings', '[]'::jsonb)) r where r->>'kind' = 'deadline' and c.id is not null loop
      v_outcome := null; v_reason := null; v_date := null; v_targets := '{}';
      if coalesce((rd->>'rolling')::boolean, false) then v_outcome := 'rolling'; v_reason := 'the page says applications are rolling (no date to hold)';
      elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'intakes') then v_outcome := 'locked'; v_reason := 'intakes are locked by a person';
      elsif c.bound_ev is distinct from (pg->>'evidence_id')::uuid then v_outcome := 'identity'; v_reason := 'the page read is no longer the course''s bound page';
      else
        begin v_date := (rd->>'date')::date; exception when others then v_date := null; end;
        if v_date is null then v_outcome := 'incomplete'; v_reason := 'no full closing date';
        elsif not security.course_deadline_in_quote_v1(v_date, rd->>'quote') then v_outcome := 'incomplete'; v_reason := 'the closing words and the date are not one clause';
        else
          if nullif(btrim(rd->>'intake_hint'), '') is not null then
            select coalesce(array_agg(i.id), '{}') into v_targets from catalogue.course_intakes i
             where i.course_id = c.id and i.status = 'active' and security.course_deadline_intake_match_v1(i.intake_label, i.intake_year, rd->>'intake_hint');
          else
            select coalesce(array_agg(i.id), '{}') into v_targets from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active';
          end if;
          if cardinality(v_targets) <> 1 then v_outcome := 'not_tied_to_intake'; v_reason := case when cardinality(v_targets) = 0 then 'no active intake the date belongs to' else 'the date is not tied to one intake' end;
          elsif exists (select 1 from catalogue.course_intakes i where i.id = v_targets[1] and i.application_deadline is not null) then v_outcome := 'held_value'; v_reason := 'a deadline is already held (no overwrite)';
          elsif exists (select 1 from catalogue.course_intakes i where i.id = v_targets[1]
                          and ((i.start_date is not null and (v_date > i.start_date or v_date < i.start_date - v_max_before))
                               or (i.start_date is null and i.intake_year is not null and (v_date < make_date(i.intake_year - 1, 1, 1) or v_date > make_date(i.intake_year, 12, 31)))
                               or (i.start_date is null and i.intake_year is null and (v_date < current_date - v_past or v_date > current_date + v_ahead)))) then
            v_outcome := 'outside_window'; v_reason := 'the date is outside the intake''s window';
          else
            update catalogue.course_intakes set application_deadline = v_date where id = v_targets[1] and application_deadline is null;
            if found then v_outcome := 'admitted'; v_any := true; else v_outcome := 'held_value'; v_reason := 'not written (held or locked)'; end if;
          end if;
        end if;
      end if;
      insert into pipeline.fid_det_readings(course_id, evidence_id, extractor, kind, value, quote, outcome, reason)
      values (c.id, (pg->>'evidence_id')::uuid, v_ext, 'deadline', rd - 'quote' - 'kind', left(rd->>'quote', 320), v_outcome, v_reason);
      v_page := v_page || jsonb_build_object('deadline', v_outcome);
      v_out := jsonb_set(v_out, array['deadline_' || v_outcome], to_jsonb(coalesce((v_out->>('deadline_' || v_outcome))::int, 0) + 1));
    end loop;
    update pipeline.fid_det_pages set outcome = v_page where course_id = (pg->>'course_id')::uuid and evidence_id = (pg->>'evidence_id')::uuid and extractor = v_ext;
    -- the course source is approved for the domains it now feeds, so the search document carries the values
    if v_src is not null and v_fee_in then
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
      select 'courses', 'provider_current_tuition', v_src, 'approved', 'CF-CHG-20260915-247 s851 (deterministic fee reader, Platform Admin 20 Nov 2026 15:11)', now(), now(), now()
       where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = v_src);
    end if;
    if v_src is not null and v_itk_in then
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
      select 'courses', 'course_intake', v_src, 'approved', 'CF-CHG-20260915-247 s851 (deterministic intake reader, Platform Admin 20 Nov 2026 15:11)', now(), now(), now()
       where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_intake' and g.source_id = v_src);
    end if;
    v_any := v_any or v_fee_in or v_itk_in; v_fee_in := false; v_itk_in := false;
  end loop;
  if v_any then
    insert into search.refresh_requests(requested_by) select 'deterministic fee, intake and deadline reader'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'deterministic fee, intake and deadline reader');
  end if;
  return jsonb_build_object('pages', v_pages, 'layer4_raised', v_l4) || v_out;
end $function$;
comment on function security.fid_det_record_v1(bigint, jsonb) is 'CF-247 s851: records one fid_det_read worker reply and admits only fully verified fees, intakes and deadlines (quote on page, bound page identity and country rule, complete value, nothing held, no lock); fees that need a person go to Layer 4 with the reason in words.';

-- the sweep: record replies that came back, then send the next batch
create or replace function security.fid_det_tick_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare r record; v_resp record; v_items jsonb; v_call jsonb; v_per int; v_n int; v_sent int := 0; v_rec jsonb := '[]'::jsonb; v_req bigint; v_run bigint;
        v_ext constant text := 'fid-det-v1.0';  -- fixed: the extractor version this database records (fid-det-reader.ts FID_DET_VERSION)
        v_settle jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('fid_det_tick')) then return jsonb_build_object('skipped', 'a run is already going'); end if;
  -- s850: AI fee reader items whose third lease ran out are settled here every minute (cheap, indexed by state)
  v_settle := security.fee_reader_queue_settle_v1();
  if security.pipeline_num_v1('fid.sweep_on', 1) < 1 then return jsonb_build_object('skipped', 'switched off (fid.sweep_on)', 'fee_reader', v_settle); end if;
  -- 1 replies that have come back
  for r in select * from pipeline.fid_det_runs where state = 'sent' order by id loop
    select status_code, content, timed_out, error_msg into v_resp from net._http_response where id = r.request_id;
    if not found then
      if r.sent_at < now() - make_interval(mins => security.pipeline_num_v1('fid.reply_wait_minutes', 15)::int) then
        update pipeline.fid_det_runs set state = 'expired', recorded_at = now(), result = jsonb_build_object('reason', 'no reply in time') where id = r.id;
      end if;
      continue;
    end if;
    if v_resp.status_code is distinct from 200 or v_resp.content is null then
      update pipeline.fid_det_runs set state = 'failed', recorded_at = now(), result = jsonb_build_object('status', v_resp.status_code, 'error', left(coalesce(v_resp.error_msg, v_resp.content, ''), 300)) where id = r.id;
      continue;
    end if;
    begin
      v_call := v_resp.content::jsonb;
      if v_call->>'extractor' is distinct from v_ext then raise exception 'the worker answered with extractor % (expected %)', v_call->>'extractor', v_ext; end if;
      v_call := security.fid_det_record_v1(r.id, v_call);
      update pipeline.fid_det_runs set state = 'recorded', recorded_at = now(), result = v_call where id = r.id;
      v_rec := v_rec || v_call;
    exception when others then
      update pipeline.fid_det_runs set state = 'failed', recorded_at = now(), result = jsonb_build_object('error', left(sqlerrm, 300)) where id = r.id;
    end;
  end loop;
  -- 2 a new batch on its minute, when none is out
  if (extract(epoch from date_trunc('minute', now())) / 60)::bigint % greatest(security.pipeline_num_v1('fid.run_every_minutes', 5)::int, 1) <> 0
     or exists (select 1 from pipeline.fid_det_runs where state = 'sent') then
    return jsonb_build_object('recorded', v_rec, 'sent', 0, 'fee_reader', v_settle);
  end if;
  v_items := security.fid_det_batch_v1(security.pipeline_num_v1('fid.batch_size', 150)::int, v_ext);
  v_per := greatest(5, least(security.pipeline_num_v1('fid.items_per_call', 30)::int, 40));  -- fixed: the worker reads at most 40 pages a call
  v_n := jsonb_array_length(v_items);
  for i in 0 .. greatest(0, (v_n - 1) / v_per) loop
    exit when v_n = 0;
    insert into pipeline.fid_det_runs(items) values (least(v_per, v_n - i * v_per)) returning id into v_run;
    v_req := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fid_det_read', 'run_id', v_run,
               'items', (select jsonb_agg(x) from jsonb_array_elements(v_items) with ordinality t(x, o) where o > i * v_per and o <= (i + 1) * v_per)));
    update pipeline.fid_det_runs set request_id = v_req where id = v_run;
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('recorded', v_rec, 'sent', v_sent, 'pages', v_n, 'fee_reader', v_settle);
end $function$;
comment on function security.fid_det_tick_v1() is 'CF-247 s852: job fid-det-sweep. Settles exhausted AI fee reader items (s850), records the fid_det_read replies that came back, then sends the next batch of stored course pages with a fee, intake or deadline gap. $0: no model, no Firecrawl.';

-- what the reader has done (read only; Platform health and the reports read it)
create or replace function security.fid_det_status_v1()
returns jsonb language sql stable security definer set search_path = '' as $function$
  select jsonb_build_object(
    'extractor', 'fid-det-v1.0',
    'pages_read', (select count(*) from pipeline.fid_det_pages where extractor = 'fid-det-v1.0'),
    'runs', (select jsonb_object_agg(state, n) from (select state, count(*) n from pipeline.fid_det_runs group by 1) z),
    'last_recorded', (select max(recorded_at) from pipeline.fid_det_runs where state = 'recorded'),
    'readings', (select jsonb_object_agg(kind || ':' || outcome, n) from (select kind, outcome, count(*) n from pipeline.fid_det_readings where extractor = 'fid-det-v1.0' group by 1, 2) z),
    'state', (select to_jsonb(s) from pipeline.fid_det_state s where s.id = 1))
$function$;
comment on function security.fid_det_status_v1() is 'CF-247 s852: read-only summary of the deterministic fee, intake and deadline reader (pages read, runs by state, readings by kind and outcome, cursor).';

-- the watchdog sees the sweep like the other queues (Platform health)
insert into pipeline.queue_watch(key, label, area, purpose, sort, jobnames, tools, pending_sql, progress_sql, done_sql, failed_sql, exhausted_sql, enabled)
select 'fid_det', 'Deterministic fee, intake and deadline reader', 'Fees and intakes', 'Stored course pages read for international fees, intake months and closing dates with no model', coalesce((select max(sort) from pipeline.queue_watch), 0) + 1, array['fid-det-sweep'], '{}'::text[],
       'select count(*) from pipeline.fid_det_runs where state = ''sent''',
       'select max(recorded_at) from pipeline.fid_det_runs where state = ''recorded''',
       'select count(*) from pipeline.fid_det_runs where state = ''recorded'' and recorded_at >= $1',
       'select count(*) from pipeline.fid_det_runs where state in (''failed'', ''expired'') and recorded_at >= $1',
       'select 0::bigint', true
 where not exists (select 1 from pipeline.queue_watch where key = 'fid_det');

-- the job (G1)
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('fid-det-sweep', 'Fees and intakes', 6, 'Deterministic fee, intake and deadline reader',
  'Every minute: settles AI fee reader items that used their three tries, records the deterministic reader''s replies, and every few minutes (setting Deterministic fee, intake and deadline reader: run every) sends the next batch of stored course pages that miss an international fee, an intake or a deadline. No model and no Firecrawl ($0). Only fully verified values are admitted; fees that need a person go to Layer 4. Switch off with the setting Deterministic fee, intake and deadline reader: on.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('fid-det-sweep', '* * * * *', 'select security.fid_det_tick_v1()')
where not exists (select 1 from cron.job where jobname = 'fid-det-sweep');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'fid-det-sweep', 'Layer 2', 'Fees and intakes', 'Sends stored course pages to the deterministic fee, intake and deadline reader and records its replies', 'active', '{}', '20261120175100'),
  ('table', 'pipeline.fid_det_runs', 'Layer 2', 'Fees and intakes', 'One row per deterministic reader worker call', 'active', '{}', '20261120175100'),
  ('table', 'pipeline.fid_det_pages', 'Layer 2', 'Fees and intakes', 'Stored course pages read by the deterministic reader', 'active', '{}', '20261120175100'),
  ('table', 'pipeline.fid_det_readings', 'Layer 2', 'Fees and intakes', 'Readings of the deterministic reader with quotes and outcomes', 'active', '{}', '20261120175100'),
  ('table', 'pipeline.fid_det_state', 'Layer 2', 'Fees and intakes', 'Keyset cursor of the deterministic sweep', 'active', '{}', '20261120175100'),
  ('function', 'security.fid_det_tick_v1', 'Layer 2', 'Fees and intakes', 'The deterministic sweep job', 'active', '{}', '20261120175100'),
  ('function', 'security.fid_det_batch_v1', 'Layer 2', 'Fees and intakes', 'The next batch of stored pages with a gap', 'active', '{}', '20261120175100'),
  ('function', 'security.fid_det_record_v1', 'Layer 2', 'Fees and intakes', 'Gates and admits deterministic readings', 'active', '{}', '20261120175100'),
  ('function', 'security.fid_det_status_v1', 'Layer 2', 'Fees and intakes', 'Read-only summary of the deterministic reader', 'active', '{}', '20261120175100')
on conflict do nothing;

-- post-checks: the batch query answers fast, the gate admits a verified reading and holds the rest, and the consumer API has not moved
do $c$
declare v_t timestamptz; v_ms numeric; v_b jsonb; v_api jsonb := security.consumer_api_check_v1();
begin
  if not exists (select 1 from cron.job where jobname = 'fid-det-sweep' and active) then raise exception 'post-check: job fid-det-sweep is not scheduled'; end if;
  -- the batch query is timed warm (second call), as the sweep runs it every few minutes; the first call reads the pages into cache
  perform security.fid_det_batch_v1(security.pipeline_num_v1('fid.batch_size', 150)::int, 'fid-det-v1.0');
  update pipeline.fid_det_state set cursor_course = '00000000-0000-0000-0000-000000000000' where id = 1;
  v_t := clock_timestamp();
  v_b := security.fid_det_batch_v1(security.pipeline_num_v1('fid.batch_size', 150)::int, 'fid-det-v1.0');
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  update pipeline.fid_det_state set cursor_course = '00000000-0000-0000-0000-000000000000', pass = 1 where id = 1;  -- the probe batch is not counted as sent
  raise notice 's852 post-check: first batch % pages in % ms', jsonb_array_length(v_b), round(v_ms);
  if v_ms > 300 then raise exception 'post-check: the batch query took % ms (limit 300)', round(v_ms); end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
