-- CF-247 AER technical holds, part 1: a printed requirement is never lost to its score field, and a held read is recovered from what is already stored
-- (Platform Admin mandate 7 Nov 2026 21:57; development agent, branch cf247-aer-technical-holds). Nothing is read, fetched, spent, approved or admitted.
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 7 Nov 2026 about 22:00 AEDT). 605 waiting AER items, 184 ready or review-ready, 421 technical:
--   162 cut at the row limit (RMIT 94 at limit 6; QUT 38; Monash 15; MIT 5; Auckland 4; AUT 3; EIT 2; Ara 1)
--   150 dropped printed requirements (gate class drops_uncovered)     45 shared page     25 row level     39 matrix runs     (1 stale row-level)
-- Defects behind the 150 and part of the 162 (security.enrich_entry_record_v1, md5 7faf2de4c2afe0a671f8f54c4a140fe4):
--   1. A requirement whose structured score had no printed basis was dropped WHOLE (reason score_without_basis), although its quote, kind and text were
--      verified on the page and its confidence passed. A band with no printed form is only nulled (note band_not_printed); a score is held to the same
--      rule by nulling the number and its basis. 1,709 such drops sit in the waiting items (105 items), for example "a bachelor degree with a GPA of at
--      least 2.5 (out of 4.0)": the printed requirement was lost, E13 then held the read as incomplete, and a corrected read lost it the same way
--      (35+ corrected reads refused: "still drops 1 printed requirement"). The B1 rule (no numeric score without its basis) still holds: the number is
--      not stored; the requirement and its quote are.
--   2. The same printed requirement read twice with different score fields counted twice towards the row limit (Diploma of Commerce 111278B: two
--      identical VCE English quotes). A requirement is one row.
-- Why a held read can be recovered without another AI read (stored evidence, evidence the platform already paid for):
--   * a read refused by the row limit keeps every row it read (field_enrich_items.value.rows_read) and the rows past the limit with their kind and quote
--     (value.dropped, reason over_row_limit); a read dropped for score_without_basis keeps kind and quote. Both passed every other reader check.
--   * simulated read only on the live gate (security.course_entry_correction_check_v1 over the stored rows): 76 of 421 held reads pass E13 once the
--     rows are put back (RMIT 61: 17 need no setting change, 17 need a row limit of 7 to 9, 15 of 10 to 12, 12 of 13 to 18; others 15), and the
--     Diploma of Commerce stored read (9 rows) passes with entry.max_rows_by_provider for RMIT at 9 or more.
--   * LIVE RANGE: entry.max_rows_per_course has range 1 to 10 and security.course_entry_max_rows_v1 ignores a university value outside that range, so RMIT
--     cannot be set above 10 today (its reads need up to 19): the setting's maximum must be raised first (Platform Admin).
--   * Matrix: 20 waiting ANU runs (165 rows) are held by D-R3 because the reader stored the provider rank as the qualification minimum and the printed
--     indicative score as the band; section 6b puts them the right way round on rows still waiting (original kept in pipeline.aer_row_repairs).
-- What (all md5-guarded; one edit of a live function, new functions, two new tables, one job, settings):
--   1. security.enrich_entry_record_v1: score_without_basis keeps the row with the score and basis nulled (note score_without_basis); a repeated
--      requirement (same kind, same quote in letters and digits) is one row.
--   2. security.aer_replay_plan_v1(item) (stable, read only): the rows a waiting course read would have if it were put back together from stored records,
--      the row limit they need, and the verdict of the existing D-R2 check on them (same page, complete, no shared page, no lock, no claim, no decision).
--   3. security.aer_replay_apply_v1(item): runs that plan through the existing governed path, with no AI read: a request in pipeline.aer_read_supersessions
--      (history kept), security.enrich_entry_record_v1 (all E13 and D-R2 checks, row limit included), and only when the replacement is complete does the
--      waiting item become superseded and a NEW waiting Layer 4 item carry the rows. A person still approves or rejects it: nothing is admitted.
--   4. security.aer_replay_v1(preview): the job's step. Plans a bounded scan of waiting reads (pipeline.aer_replay_checks stops an unchanged plan being
--      judged again), applies the ones that pass within batch.aer_replay a run, aer.replay_per_provider a university a run and aer.replay_daily_max a day.
--   4b. security.aer_matrix_rank_repair_v1 (section 6b), called by the same step.
--   5. Job aer-replay (catalogued, G1) at :33, command free of numbers (G2). aer.replay_on = 1 (no spend; replaces one waiting item with one; the 600
--      limit is unchanged). A Platform Admin may set it to 0.
-- Not changed: aer.schedule_layer4_max (600), entry.max_rows_per_course (6), entry.max_rows_by_provider ([]), every other setting and switch, the daily
-- read cap, the consumer API, E13, D-R2, D-R3. No Firecrawl or AI call. Nothing is dropped or deleted.
-- Overlap with PR #875 (open, not merged, not depended on): #875 edits security.aer_recovery_rule_v1 (row-limit eligibility), security.aer_schedule_held_v1
-- (held-step order) and security.progress_measure_v1. This file edits none of them. Part 2 (20261107130100) edits the rule's row-limit clause too and
-- would conflict with #875 on its md5 guard; merge one of the two, not both.
-- Before -> after (live, 7 Nov 2026 22:10 AEDT):
--   security.enrich_entry_record_v1(bigint,jsonb) 7faf2de4c2afe0a671f8f54c4a140fe4 -> b39d83dfd8bbd3c7e4708a6904c6599d
-- Replaces: security.enrich_entry_record_v1 (same name; md5-guarded edit). The held step's corrected AI read of items a replay can recover is superseded by the replay in part 2.
-- Retires: nothing

do $g$
begin
  if to_regprocedure('security.enrich_entry_record_v1(bigint,jsonb)') is null or to_regprocedure('security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)') is null
     or to_regclass('pipeline.aer_read_supersessions') is null or to_regclass('pipeline.automation_catalogue') is null then
    raise exception 'needs E13, D-R2 (security.course_entry_correction_check_v1) and the automation catalogue';
  end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 the reader: a score without its printed basis is nulled, never the whole requirement; a repeated requirement is one row
select pg_temp.edit_once('security.enrich_entry_record_v1(bigint,jsonb)', '7faf2de4c2afe0a671f8f54c4a140fe4', 'b39d83dfd8bbd3c7e4708a6904c6599d', array[
  [$e$      v_drop := v_drop || jsonb_build_object('reason', 'score_without_basis', 'kind', v_kind, 'quote', v_q); continue;$e$,
   $e$      -- 7 Nov 2026 (AER technical holds): the requirement is printed and verified, only its number has no printed basis: keep the requirement, store no number
      v_notes := v_notes || jsonb_build_object('note', 'score_without_basis', 'score', v_score, 'basis', v_basis, 'quote', v_q);
      v_score := null; v_basis := null;$e$],
  [$e$    v_keep := v_keep || jsonb_build_object('kind', v_kind, 'audience', v_aud, 'description', coalesce(nullif(v_d, ''), v_q), 'min_grade'$e$,
   $e$    -- 7 Nov 2026 (AER technical holds): the same requirement printed twice is one row (it counts once towards the row limit)
    if exists (select 1 from jsonb_array_elements(v_keep) k where k->>'kind' = v_kind
                 and lower(regexp_replace(coalesce(k->>'quote', ''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(v_q, '[^[:alnum:]]', '', 'g'))) then continue; end if;
    v_keep := v_keep || jsonb_build_object('kind', v_kind, 'audience', v_aud, 'description', coalesce(nullif(v_d, ''), v_q), 'min_grade'$e$]],
  array[1, 1]);

-- 2 settings (G2: label, range, unit, used_by; changed on Settings > Pipeline settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.replay_on', 'Entry requirements: recover held reads from stored records',
  '1 puts a held course read back together from what is already stored (the rows it read, the rows cut at the row limit, the requirements dropped for a score with no printed basis), checks it with the same E13 and D-R2 rules and, when it is complete, replaces the waiting read with a new waiting read for a person. 0 stops it. No AI read, no page fetch, no spend; nothing is approved.',
  'number', to_jsonb(1), 0, 1, 'switch', 1481, 'Entry requirements', 'security.aer_replay_v1; job aer-replay', 'Mandate 7 Nov 2026 21:57 (recover technically held AER items automatically; Layer 4 admission authority is kept)'),
 ('pipeline', 'batch.aer_replay', 'Entry requirements: reads recovered from stored records a run', 'The most held reads one run of job aer-replay replaces.',
  'number', to_jsonb(10), 1, 100, 'reads', 1482, 'Entry requirements', 'security.aer_replay_v1; job aer-replay', 'Mandate 7 Nov 2026 21:57'),
 ('pipeline', 'aer.replay_per_provider', 'Entry requirements: reads recovered from stored records, per university a run', 'No university takes more than this many places in one run.',
  'number', to_jsonb(5), 1, 50, 'reads', 1483, 'Entry requirements', 'security.aer_replay_v1', 'Mandate 7 Nov 2026 21:57'),
 ('pipeline', 'aer.replay_daily_max', 'Entry requirements: reads recovered from stored records a day', 'Counted over the last 24 hours.',
  'number', to_jsonb(100), 1, 1000, 'reads', 1484, 'Entry requirements', 'security.aer_replay_v1', 'Mandate 7 Nov 2026 21:57'),
 ('pipeline', 'aer.replay_scan', 'Entry requirements: waiting reads judged for recovery a run', 'The oldest-checked waiting course reads looked at in one run (a plan that has not changed is not judged again).',
  'number', to_jsonb(60), 5, 500, 'reads', 1485, 'Entry requirements', 'security.aer_replay_v1', 'Mandate 7 Nov 2026 21:57')
on conflict (toolset_key, key) do nothing;

-- 3 the record of what was judged (an unchanged plan is not judged again)
create table if not exists pipeline.aer_replay_checks (
  item_id uuid primary key references pipeline.layer4_review_items(id) on delete cascade,
  condition_key text not null,
  checked_at timestamptz not null default now(),
  ok boolean not null,
  why text,
  rows_needed integer,
  row_limit integer,
  outcome text
);
comment on table pipeline.aer_replay_checks is 'CF-247 AER technical holds (7 Nov 2026): the last judgement of whether a waiting course read can be put back together from stored records (security.aer_replay_plan_v1), with the key of the records and settings it was judged on. A key that has not changed is not judged again. Written only by security.aer_replay_v1.';
alter table pipeline.aer_replay_checks enable row level security;
revoke all on pipeline.aer_replay_checks from public, anon, authenticated;

-- 4 the plan: what a waiting course read would be, put back together from stored records. Stable, writes nothing.
create or replace function security.aer_replay_plan_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 AER technical holds (mandate 7 Nov 2026 21:57). Source of the rows, in order: the newest stored read of this course that kept its rows
-- (field_enrich_items.value.rows_read, a corrected read refused or held at the row limit) read after the stored copy of the page was captured; otherwise
-- the waiting item's own proposed rows. To them are added the rows the reader set aside only for a reason that does not question the row itself
-- (over_row_limit, score_without_basis: kind and quote were verified, confidence passed), each once. Every other dropped row stays dropped.
declare r pipeline.layer4_review_items; g record; f record; pgp record; v_rows jsonb; v_drop jsonb; v_extra jsonb; v_rest jsonb; v_all jsonb; v_n int; v_lim int; v_chk jsonb;
        v_conf numeric := security.pipeline_num_v1('entry.min_confidence', 0.8); v_cc text; v_src text; v_busy text; v_ev timestamptz;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.status <> 'pending' or r.field_code <> 'course_entry_first_read' then return jsonb_build_object('item', p_item, 'ok', false, 'why', 'not a waiting course entry read'); end if;
  select c.provider_id, c.lifecycle_status = 'active' act into g from catalogue.courses c where c.id = r.entity_id;
  if g.provider_id is null or not g.act then return jsonb_build_object('item', p_item, 'ok', false, 'why', 'the course is no longer active'); end if;
  select pg.url, pg.evidence_id into pgp from pipeline.coverage_course_pages pg where pg.course_id = r.entity_id;
  if pgp.url is null or pgp.url is distinct from r.proposed_value->>'url' then return jsonb_build_object('item', p_item, 'ok', false, 'why', 'the course is bound to another page: a new first read, not a recovery'); end if;
  v_busy := case when exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then 'a corrected read of this item is waiting for the reader'
                 when exists (select 1 from pipeline.field_enrich_items e where e.course_id = r.entity_id and e.field = 'entry_requirements' and e.state in ('queued', 'waiting', 'ai', 'leased'))
                   then 'a read of this course is in progress' end;
  if v_busy is not null then return jsonb_build_object('item', p_item, 'ok', false, 'why', v_busy); end if;
  select e.captured_at into v_ev from pipeline.evidence_artifacts e where e.id = pgp.evidence_id;
  -- the newest stored read that kept its rows and was read after this copy of the page was captured
  select e.id, e.value into f from pipeline.field_enrich_items e
   where e.course_id = r.entity_id and e.field = 'entry_requirements' and e.value ? 'rows_read' and jsonb_array_length(e.value->'rows_read') > 0
     and (e.evidence_id is not distinct from (select pg.evidence_id from pipeline.coverage_course_pages pg where pg.course_id = r.entity_id)
          or (e.evidence_id is null and (v_ev is null or e.updated_at >= v_ev)))
   order by e.updated_at desc limit 1;
  if f.id is not null then
    v_src := 'stored read ' || f.id; v_rows := f.value->'rows_read'; v_drop := coalesce(f.value->'dropped', '[]'::jsonb);
  else
    v_src := 'the waiting read';
    select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'quote', x.quote, 'description', x.description, 'confidence', x.confidence, 'min_grade', x.min_grade,
                                                 'min_entry_score', x.min_entry_score, 'min_entry_score_basis', x.min_entry_score_basis, 'benchmark_band', x.benchmark_band) order by x.created_at, x.id), '[]'::jsonb)
      into v_rows from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed';
    v_drop := coalesce(r.proposed_value->'dropped', '[]'::jsonb);
    if jsonb_array_length(v_rows) = 0 then return jsonb_build_object('item', p_item, 'ok', false, 'why', 'the waiting read keeps no row and no stored read exists'); end if;
  end if;
  -- the rows set aside only for the row limit or an unprinted score basis, once each
  select coalesce(jsonb_agg(jsonb_build_object('kind', d->>'kind', 'quote', d->>'quote', 'description', d->>'quote', 'confidence', v_conf)), '[]'::jsonb) into v_extra
    from (select distinct on (lower(regexp_replace(coalesce(d1->>'quote', ''), '[^[:alnum:]]', '', 'g'))) d1 d from jsonb_array_elements(v_drop) d1
           where d1->>'reason' in ('over_row_limit', 'score_without_basis') and length(coalesce(d1->>'quote', '')) >= 4 and (d1->>'kind') is not null
             and not exists (select 1 from jsonb_array_elements(v_rows) k
                               where lower(regexp_replace(coalesce(k->>'quote', ''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(coalesce(d1->>'quote', ''), '[^[:alnum:]]', '', 'g')))
           order by lower(regexp_replace(coalesce(d1->>'quote', ''), '[^[:alnum:]]', '', 'g'))) z;
  select coalesce(jsonb_agg(d), '[]'::jsonb) into v_rest from jsonb_array_elements(v_drop) d where d->>'reason' not in ('over_row_limit', 'score_without_basis');
  v_all := v_rows || v_extra; v_n := jsonb_array_length(v_all); v_lim := security.course_entry_max_rows_v1(g.provider_id); v_cc := security.coverage_country(g.provider_id);
  -- the audience the reader would give each row (its own rule: the quote's own words)
  select coalesce(jsonb_agg(x || jsonb_build_object('audience',
           case when coalesce(x->>'quote', '') ~* '\m(international|overseas)\M' then 'international'
                when coalesce(x->>'quote', '') ~* '(\mVCE\M|\mATAR\M|\mVTAC\M|\mSTAT\M|Australian Year 12)' then 'domestic'
                when v_cc = 'NZ' and coalesce(x->>'quote', '') ~* '(\mNCEA\M|University Entrance|\mUE\M)' then 'domestic' else 'all' end)), '[]'::jsonb)
    into v_all from jsonb_array_elements(v_all) x;
  v_chk := security.course_entry_correction_check_v1(p_item, r.entity_id, pgp.url, v_all, v_rest);
  return jsonb_build_object('item', p_item, 'ok', v_n <= v_lim and coalesce((v_chk->>'ok')::boolean, false),
    'why', case when v_n > v_lim then format('the read has %s requirements and the row limit is %s: entry.max_rows_by_provider for this university needs at least %s', v_n, v_lim, v_n)
                when not coalesce((v_chk->>'ok')::boolean, false) then v_chk->>'why' end,
    'source', v_src, 'provider_id', g.provider_id, 'course_id', r.entity_id, 'rows', v_all, 'dropped', v_rest, 'rows_needed', v_n, 'row_limit', v_lim,
    'check_ok', coalesce((v_chk->>'ok')::boolean, false),
    'condition_key', md5(concat_ws('|', v_src, v_n::text, v_lim::text, jsonb_array_length(v_rest)::text, coalesce(v_chk->>'why', ''), coalesce(f.id::text, ''))));
end $function$;
revoke all on function security.aer_replay_plan_v1(uuid) from public, anon, authenticated;
comment on function security.aer_replay_plan_v1(uuid) is 'CF-247 AER technical holds (7 Nov 2026): the rows a waiting course read would have if put back together from stored records, the row limit they need and the verdict of the D-R2 check on them. Stable; writes nothing.';

-- 5 the apply: the existing governed path with no AI read
create or replace function security.aer_replay_apply_v1(p_item uuid, p_plan jsonb default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 AER technical holds: records the request (history), runs the plan through security.enrich_entry_record_v1 (all E13 and D-R2 checks, row limit
-- included), and returns the outcome. The waiting item becomes superseded only when the replacement is complete; a person still decides the new item.
declare p jsonb := coalesce(p_plan, security.aer_replay_plan_v1(p_item)); r pipeline.layer4_review_items; v_job uuid; v_enrich bigint; v_sup uuid; v_res text; v_new uuid; v_state text;
begin
  if not coalesce((p->>'ok')::boolean, false) then return jsonb_build_object('item', p_item, 'applied', false, 'why', p->>'why'); end if;
  select * into r from pipeline.layer4_review_items where id = p_item for update;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'done', left('Entry requirements · replay of the stored read of item ' || p_item, 200),
          jsonb_build_object('replay', true, 'entry_read', true, 'ai', false, 'scraper', false, 'provider_ids', jsonb_build_array(p->>'provider_id'), 'course_ids', jsonb_build_array(p->>'course_id'),
                             'fields', jsonb_build_array('entry_requirements')),
          jsonb_build_object('done', 1, 'total', 1), null, 'Replay of stored read for Layer 4 item ' || p_item || ' (no AI read): ' || (p->>'source'), '1 course')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason)
  values (v_job, (p->>'provider_id')::uuid, (p->>'course_id')::uuid, 'entry_requirements', 'skipped', 'replay of a stored read: no AI')
  returning id into v_enrich;
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason)
  values (p_item, r.entity_id, r.proposed_value->>'url', r.evidence_id, v_enrich, v_job, null,
          left('Replay of the stored read (no AI): ' || (p->>'source') || '; ' || jsonb_array_length(p->'rows') || ' requirement(s)', 500))
  returning id into v_sup;
  v_res := security.enrich_entry_record_v1(v_enrich, jsonb_build_object('model', 'stored-read-replay', 'worker', 'aer_replay', 'prompt_version', 'none',
             'value', jsonb_build_object('rows', p->'rows', 'dropped', p->'dropped', 'coverage', jsonb_build_object('basis', 'stored read replay', 'complete', true))));
  select s.state, s.new_item_id into v_state, v_new from pipeline.aer_read_supersessions s where s.id = v_sup;
  return jsonb_build_object('item', p_item, 'applied', v_state = 'superseded', 'result', v_res, 'request', v_sup, 'state', v_state, 'new_item', v_new, 'rows', jsonb_array_length(p->'rows'),
                            'why', case when v_state <> 'superseded' then (select s.outcome from pipeline.aer_read_supersessions s where s.id = v_sup) end);
end $function$;
revoke all on function security.aer_replay_apply_v1(uuid, jsonb) from public, anon, authenticated;
comment on function security.aer_replay_apply_v1(uuid, jsonb) is 'CF-247 AER technical holds (7 Nov 2026): puts a waiting course read back together from stored records and passes it through security.enrich_entry_record_v1 (E13, D-R2). No AI read. A person still decides the new item.';

-- 6 the step of the job
create or replace function security.aer_replay_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 AER technical holds: judges a bounded scan of waiting course reads that are not complete and not on a shared page, and replaces the ones that
-- can be recovered from stored records. aer.replay_on = 0 stops it; the preview writes nothing and ignores the switch.
declare r record; p jsonb; a jsonb; v_scan int := security.pipeline_num_v1('aer.replay_scan', 60)::int; v_batch int := security.pipeline_num_v1('batch.aer_replay', 10)::int;
        v_per int := security.pipeline_num_v1('aer.replay_per_provider', 5)::int; v_left int := security.pipeline_num_v1('aer.replay_daily_max', 100)::int
                     - (select count(*) from pipeline.aer_read_supersessions s where s.reason like 'Replay of the stored read%' and s.requested_at > now() - interval '1 day');  -- fixed: the daily cap is counted over the last 24 hours
        v_done int := 0; v_judged int := 0; v_can int := 0; v_wait int := 0; v_out jsonb := '[]'::jsonb; v_byp jsonb := '{}'::jsonb; v_key text; v_mx jsonb;
begin
  if not p_preview and security.pipeline_num_v1('aer.replay_on', 1) < 1 then return jsonb_build_object('held', 'aer.replay_on is 0'); end if;
  begin v_mx := security.aer_matrix_rank_repair_v1(p_preview);
  exception when others then v_mx := jsonb_build_object('error', left(sqlerrm, 200));
  end;
  for r in select i.id, c.provider_id from pipeline.layer4_review_items i
             join pipeline.layer4_item_readiness x on x.item_id = i.id
             join catalogue.courses c on c.id = i.entity_id
             left join pipeline.aer_replay_checks k on k.item_id = i.id
            where i.status = 'pending' and i.field_code = 'course_entry_first_read' and x.gate is not null and not coalesce((x.gate->>'complete')::boolean, false)
              and jsonb_array_length(coalesce(x.gate->'shared_page', '[]'::jsonb)) = 0
              and (jsonb_array_length(coalesce(x.gate->'drops_uncovered', '[]'::jsonb)) > 0 or coalesce((x.gate->>'rows_cut')::int, 0) > 0)
            order by k.checked_at nulls first, i.created_at, i.id limit v_scan loop
    p := security.aer_replay_plan_v1(r.id); v_judged := v_judged + 1; v_key := p->>'condition_key';
    if coalesce((p->>'ok')::boolean, false) then
      v_can := v_can + 1;
      if not p_preview and v_done < v_batch and v_left > v_done and coalesce((v_byp->>(r.provider_id::text))::int, 0) < v_per then
        begin
          a := security.aer_replay_apply_v1(r.id, p);
        exception when others then a := jsonb_build_object('item', r.id, 'applied', false, 'why', left(sqlerrm, 200));
        end;
        v_done := v_done + 1; v_byp := jsonb_set(v_byp, array[r.provider_id::text], to_jsonb(coalesce((v_byp->>(r.provider_id::text))::int, 0) + 1));
        v_out := v_out || jsonb_build_array(a);
      else v_wait := v_wait + 1; end if;
    end if;
    if not p_preview then
      insert into pipeline.aer_replay_checks(item_id, condition_key, checked_at, ok, why, rows_needed, row_limit, outcome)
      values (r.id, coalesce(v_key, '-'), now(), coalesce((p->>'ok')::boolean, false), left(p->>'why', 500), (p->>'rows_needed')::int, (p->>'row_limit')::int,
              case when jsonb_array_length(v_out) > 0 and v_out->-1->>'item' = r.id::text then left(v_out->-1->>'result', 100) end)
      on conflict (item_id) do update set condition_key = excluded.condition_key, checked_at = excluded.checked_at, ok = excluded.ok, why = excluded.why,
             rows_needed = excluded.rows_needed, row_limit = excluded.row_limit, outcome = excluded.outcome;
    elsif coalesce((p->>'ok')::boolean, false) then
      v_out := v_out || jsonb_build_array(jsonb_build_object('item', r.id, 'would_replace', true, 'rows', p->'rows_needed'));
    end if;
  end loop;
  return jsonb_build_object('preview', p_preview, 'judged', v_judged, 'can_be_recovered', v_can, 'replaced', case when p_preview then 0 else v_done end, 'waiting_for_room', v_wait, 'results', v_out, 'matrix_rank_repair', v_mx);
end $function$;
revoke all on function security.aer_replay_v1(boolean) from public, anon, authenticated;
comment on function security.aer_replay_v1(boolean) is 'CF-247 AER technical holds (7 Nov 2026): job aer-replay. Replaces waiting course reads that can be put back together from stored records and pass E13 and D-R2; no AI read; a person decides each new item. aer.replay_on = 0 stops it.';

-- 6b waiting matrix rows whose provider rank was stored as the qualification's minimum (ANU "Program Required Entrance Rank: 70 | Indicative score required: 2.9")
-- Live: 20 waiting ANU runs (11 of 11 rows flagged each, 165 rows) are held by D-R3: the reader stored the rank (70) as the minimum on the rank scale and
-- the printed indicative score (2.9) as the band, the reverse of what the page means. D-R3's own accepted shape (tests/fixtures/aer-dr2-dr3) is the
-- indicative score as the value (min_grade its printed text), the rank as the band. Approve except would leave out every row. This puts the two back the
-- right way round on rows still waiting for a person, keeping the original in pipeline.aer_row_repairs; the gate then judges them as for any other run.
create table if not exists pipeline.aer_row_repairs (
  id uuid primary key default gen_random_uuid(),
  repaired_at timestamptz not null default now(),
  table_name text not null,
  row_id uuid not null,
  run_id uuid,
  rule text not null,
  before jsonb not null,
  after jsonb not null
);
comment on table pipeline.aer_row_repairs is 'CF-247 AER technical holds (7 Nov 2026): the value of a waiting (proposed) record before and after a deterministic repair, with the rule. Written only by security.aer_matrix_rank_repair_v1. Nothing here changes an admitted record.';
alter table pipeline.aer_row_repairs enable row level security;
revoke all on pipeline.aer_row_repairs from public, anon, authenticated;

create or replace function security.aer_matrix_rank_repair_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Rows still waiting (status proposed) in waiting matrix runs, scale rank, with the rank words and the score words in their quote and a number in the band:
-- value = the printed indicative score (in the quote), min_grade = that number, scale points, band = the rank. Admitted rows are never touched.
declare v_rank text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_rank_words'), '[]'::jsonb)) w where btrim(w) <> '');
        v_score text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_score_words'), '[]'::jsonb)) w where btrim(w) <> '');
        r record; v_n int := 0; v_runs uuid[] := '{}';
begin
  if v_rank is null or v_score is null then return jsonb_build_object('rows', 0, 'runs', 0); end if;
  for r in select m.id, m.run_id, m.min_value, m.min_grade, m.grade_scale, m.benchmark_band, m.quote, (regexp_match(m.benchmark_band, '[0-9]+(?:\.[0-9]+)?'))[1] sc
             from catalogue.provider_entry_matrix m
            where m.status = 'proposed' and m.grade_scale = 'rank' and m.min_value is not null and m.benchmark_band is not null
              and m.run_id in (select (i.proposed_value->>'run_id')::uuid from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code like 'entry_matrix%')
              and coalesce(m.quote, '') ~* v_rank and coalesce(m.quote, '') ~* v_score
              and (regexp_match(m.benchmark_band, '[0-9]+(?:\.[0-9]+)?'))[1] is not null
              and strpos(coalesce(m.quote, ''), (regexp_match(m.benchmark_band, '[0-9]+(?:\.[0-9]+)?'))[1]) > 0
              and strpos(coalesce(m.quote, ''), trim_scale(m.min_value)::text) > 0 loop
    v_n := v_n + 1; v_runs := v_runs || r.run_id;
    if not p_preview then
      insert into pipeline.aer_row_repairs(table_name, row_id, run_id, rule, before, after)
      values ('catalogue.provider_entry_matrix', r.id, r.run_id, 'rank_swapped_with_indicative_score',
              jsonb_build_object('min_value', r.min_value, 'min_grade', r.min_grade, 'grade_scale', r.grade_scale, 'benchmark_band', r.benchmark_band),
              jsonb_build_object('min_value', r.sc::numeric, 'min_grade', r.sc, 'grade_scale', 'points', 'benchmark_band', trim_scale(r.min_value)::text));
      update catalogue.provider_entry_matrix set min_value = r.sc::numeric, min_grade = r.sc, grade_scale = 'points', benchmark_band = trim_scale(r.min_value)::text, updated_at = now()
       where id = r.id and status = 'proposed';
    end if;
  end loop;
  return jsonb_build_object('rows', v_n, 'runs', (select count(distinct x) from unnest(v_runs) x), 'preview', p_preview);
end $function$;
revoke all on function security.aer_matrix_rank_repair_v1(boolean) from public, anon, authenticated;
comment on function security.aer_matrix_rank_repair_v1(boolean) is 'CF-247 AER technical holds (7 Nov 2026): puts a provider rank stored as the qualification minimum (and the printed indicative score stored as the band) the right way round on matrix rows still waiting for a person; the original is kept in pipeline.aer_row_repairs. Never touches an admitted row.';

-- 7 the job (G1: catalogued first). Hourly at :33; no number in its command (G2)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-replay', 'Platform upkeep', 428, 'AER recovery from stored records',
  'At :33: replaces held course entry reads that can be put back together from rows already stored (rows cut at the row limit, requirements dropped for a score with no printed basis) with a new waiting read for a person, after the same E13 and D-R2 checks, in batches of batch.aer_replay. No AI read, no page fetch, no spend; nothing is approved or admitted. aer.replay_on turns it off.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'aer-replay') then
    perform cron.schedule('aer-replay', '33 * * * *', $c$select security.aer_replay_v1(false)$c$);
  end if;
end $j$;

do $p$
begin
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-replay') then raise exception 'post-check: job aer-replay is catalogued'; end if;
  if position('score_without_basis' in pg_get_functiondef('security.enrich_entry_record_v1(bigint,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the reader'; end if;
end $p$;
