-- CF-247 IQ-00067 (P1, Platform Admin mandate 3 Nov 2026 15:52 §9): job coverage-admit failed every run from 13:53 AEDT. One rule-decided
-- official page for a course whose page was set by hand reached security.layer4_course_link_apply_impl, which refuses it (E15 lock rule, correct),
-- and the raise rolled back the whole batch: no official_url or English admission happened while it lasted.
--
-- Root cause (live evidence, read-only, 3 Nov 2026 15:55-16:08 AEDT):
--   * the only differing row the batch decides by rule is University of Auckland course 950d06f3-fd85-45a5-9370-5e601ea973b1, locked by hand on
--     5 Oct 2026 (official_url and course_url). Held page .../find-a-study-option/bachelor-nursing-science.html; proposed page the same address
--     with "/1000.html" appended. security.course_page_rule_v1 reads that as "the held page is a listing; the course's own page under it becomes
--     official" (take), so the batch called the link apply, which raised.
--   * the proposal is new: the course-page search bound that address at 13:46:14 (pipeline.course_link_search: title search, requested 13:45:00.609)
--     and the reader read it at 13:46:55 (coverage-sweep-v0.5.6). The search was queued by admin job beaf6ab0 (course_page_find, "Find course pages:
--     University of Auckland (181 courses)"), started by enrich plan run 3b5eac66 (enrich_plan_tick_v1, 13:45:00). Its course list includes locked
--     courses: 94 of today's course-page searches are for courses locked by hand.
--   * not Release A: course-relink decided this course "absent" at 00:24 and the source-proof feed never routed it (no request row); the feed
--     already routes locked courses to "locked". La Trobe item 32e38e6f (pending since 02:53 AEDT, not 13:53) is pending and never applied: not
--     the trigger.
--   * admissions held back: none beyond that row. The plan's 40 write rows (36 official pages, 4 English) were all read before 13:43 and are the
--     same 40 the 13:33 and 13:43 runs counted as written: the writes do not stick, so the rows return every run. 36 of the 40 courses carry a
--     manual lock; those whose locked field is the admitted one are now held as manual_lock instead of being offered again each run.
--   * nothing persisted from the failed runs (one statement each): no consumer API baselines, Layer 4 items, rule decisions, qualifications or
--     links since 13:43, and pipeline.job_input_marks for coverage-admit is unchanged since the 13:43 run.
--
-- The change (in the admission path this workstream owns; the lock rule and admission validation are unchanged):
--   1 a course whose field is locked by hand is never offered to apply. Before the batch, its rows are held with the named reason manual_lock in
--     pipeline.coverage_admission_holds (one row a course, field and proposal) and leave the batch: not written, not raised to Layer 4, not
--     decided by rule.
--   2 one item never aborts the batch. Each rule decision (Layer 4 item, link apply, decision) runs in its own block; a refusal rolls that item
--     back, holds it as apply_refused with the error, and the batch goes on. A write refused by the apply is held the same way (that loop was
--     already isolated). The refusals a run are bounded (admit.item_error_limit); a refused proposal is not retried for
--     admit.refused_recheck_hours unless it changes. A run stopped at the limit is marked "more" (coverage_admission_gated_v1), so the next run
--     is not skipped for "no new input".
--   3 the root cause lock_conflict_in_batch and two remedies are registered through workstream A's contract (security.ops_root_cause_register_v1,
--     security.ops_remedy_register_v1): the release remedy (this change) and an auto remedy that asks for a full admission pass on the next run and
--     verifies it committed.
-- Activation: ships ON. It only holds rows that the lock already refuses, records outcomes and stops one refusal from aborting the batch; it admits
-- nothing the job did not already admit, spends nothing and switches no new behaviour on. admit.item_error_limit and admit.refused_recheck_hours
-- are settings (Settings > Pipeline settings).
--
-- md5 (before = live, read 3 Nov 2026 15:57 AEDT; after = this edit):
--   security.coverage_admission_apply_v1(integer,text,text[]) 2e85e6cbb5d2e64ea1b50fe490c4da76 -> c11a5e76bbaddf8ef5715fb2a3540c6d
--   security.coverage_admission_gated_v1(text,integer,text,text[]) 4e4e7f9ae2bb5e177774f1e394fdfe0d -> adc4cf19720f361fbce223eb64297ba0 (a run stopped at the
--     refusal limit counts as "more", so the next run is not skipped)
-- Not edited (live md5 unchanged): security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text) 75a53dbbcd5e20e1018a05b61f6763aa (the E15 lock refusal stays as it is for a
--   person's approval), security.course_page_rule_v1(text,text) b441e4c76d9bc401dd1604c23456e952.
-- Interface requests (not edited here): workstream D (enrich_plan_v1 / the course_page_find task) and the course-page search lane leave courses
-- locked by hand out of a course-page search; workstream B owns the rule reading of ".html/<n>.html" addresses.
-- Consumer API: not touched (G3). Nothing dropped or deleted.
-- Replaces: security.coverage_admission_apply_v1, security.coverage_admission_gated_v1 (same names; md5-guarded edits)
-- Retires: nothing

do $guard$ begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'IQ-00067 needs workstream A''s operations contract (migration 20261104010000) first: pipeline.ops_remedies does not exist';
  end if;
end $guard$;

-- an edit applied once, only from the definition it was written against (the 20261103050000 helper)
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

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'admit.item_error_limit', 'Coverage admission: refused items a run',
  'An item the apply refuses is held with its reason and the batch goes on. After this many refusals in one run the batch stops and the rest waits for the next run.',
  'number', '25'::jsonb, '1', '500', 'items', 640, 'Admission',
  'security.coverage_admission_apply_v1 (jobs coverage-admit, coverage-admit-intakes)', 'IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): one bad item never aborts the batch'),
 ('pipeline', 'admit.refused_recheck_hours', 'Coverage admission: retry a refused item after',
  'A proposal the apply refused is not tried again for this many hours, unless the proposal changes. It stays held with its reason meanwhile.',
  'number', '24'::jsonb, '1', '168', 'hours', 641, 'Admission',
  'security.coverage_admission_apply_v1 (jobs coverage-admit, coverage-admit-intakes)', 'IQ-00067: a refused item is not retried every ten minutes'),
 ('pipeline', 'admit.remedy_max_attempts', 'Coverage admission remedy: attempts',
  'How many times the operations controller may ask for a full coverage admission pass for one issue (remedy coverage_admit_recheck).',
  'number', '3'::jsonb, '1', '10', 'attempts', 642, 'Admission',
  'pipeline.ops_remedies coverage_admit_recheck (operations controller)', 'IQ-00067: bounded automatic remedy'),
 ('pipeline', 'admit.remedy_cooldown_minutes', 'Coverage admission remedy: wait between attempts',
  'Minutes between two attempts of the coverage_admit_recheck remedy on the same issue.',
  'number', '20'::jsonb, '10', '1440', 'minutes', 643, 'Admission',
  'pipeline.ops_remedies coverage_admit_recheck (operations controller)', 'IQ-00067: bounded automatic remedy')
on conflict (toolset_key, key) do nothing;

-- 2. the held outcomes --------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.coverage_admission_holds (
  course_id uuid not null,
  attribute text not null,
  proposed_md5 text not null,
  proposed jsonb,
  page_url text,
  plan_action text not null check (plan_action in ('write', 'differs')),
  reason text not null check (reason in ('manual_lock', 'apply_refused')),
  detail jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  seen_count int not null default 1,
  primary key (course_id, attribute, proposed_md5)
);
comment on table pipeline.coverage_admission_holds is 'CF-247 IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): coverage admission rows that were not applied, with the named reason. manual_lock: the course''s field was set by hand (pipeline.manual_locks), so the row is never offered to apply; apply_refused: the apply refused the item (detail holds the error) and the batch went on. One row a course, field and proposal (bounded); last_seen_at and seen_count show it is still held. Written by security.coverage_admission_apply_v1; read by the operations controller and reports. Never read by the consumer API.';
create index if not exists coverage_admission_holds_seen_idx on pipeline.coverage_admission_holds (reason, last_seen_at desc);
alter table pipeline.coverage_admission_holds enable row level security;
revoke all on pipeline.coverage_admission_holds from public, anon, authenticated;

create or replace function security.coverage_admission_lock_fields_v1(p_attribute text) returns text[]
language sql immutable set search_path to '' as $function$
  -- IQ-00067: the manual_locks fields that hold an admission attribute (the link apply's own lock fields for the page, plus a whole-record lock)
  select case p_attribute
    when 'official_url' then array['official_url', 'course_url', 'all']
    when 'english' then array['english', 'english_requirements', 'all']
    when 'intakes' then array['intakes', 'intake', 'all']
    else array['all'] end
$function$;
revoke all on function security.coverage_admission_lock_fields_v1(text) from public, anon, authenticated;

create or replace function security.coverage_admission_hold_v1(p_course uuid, p_props jsonb, p_page text, p_action text, p_reason text, p_detail jsonb)
returns void language sql security definer set search_path to '' as $function$
  -- IQ-00067: hold each attribute of an admission item with its reason (p_props: attribute -> proposed value); one row a course, field and proposal
  insert into pipeline.coverage_admission_holds as h(course_id, attribute, proposed_md5, proposed, page_url, plan_action, reason, detail)
  select p_course, k.key, md5(k.value::text), k.value, p_page, p_action, p_reason, coalesce(p_detail, '{}'::jsonb) from jsonb_each(p_props) k
  on conflict (course_id, attribute, proposed_md5) do update
     set last_seen_at = now(), seen_count = h.seen_count + 1, reason = excluded.reason, detail = excluded.detail, plan_action = excluded.plan_action, page_url = excluded.page_url
$function$;
revoke all on function security.coverage_admission_hold_v1(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

-- 3. the admission path (md5-guarded) ---------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.coverage_admission_apply_v1(integer,text,text[])', '2e85e6cbb5d2e64ea1b50fe490c4da76', 'c11a5e76bbaddf8ef5715fb2a3540c6d', array[
 [$o$v_rule text;  -- fixed: the system automation account (Decision 263)
begin
$o$, $n$v_rule text;  -- fixed: the system automation account (Decision 263)
        v_lock int := 0; v_held int := 0; v_skip int := 0; v_stop boolean := false;
        v_cap int := greatest(1, security.pipeline_num_v1('admit.item_error_limit', 25)::int);
        v_recheck interval := make_interval(hours => security.pipeline_num_v1('admit.refused_recheck_hours', 24)::int);
begin
$n$],
 [$o$  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;
$o$, $n$  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;

  -- IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): a course whose page, English requirement or intakes were set by hand is never offered to
  -- apply. Its rows are held with the named reason manual_lock (pipeline.coverage_admission_holds) and leave the batch: not written, not raised
  -- to Layer 4, not decided by rule. The lock rule itself (security.layer4_course_link_apply_impl) is unchanged.
  insert into pipeline.coverage_admission_holds as h(course_id, attribute, proposed_md5, proposed, page_url, plan_action, reason, detail)
  select distinct on (a.course_id, a.attribute, md5(a.proposed::text)) a.course_id, a.attribute, md5(a.proposed::text), a.proposed, a.page_url, a.action,
         'manual_lock', jsonb_build_object('lock_fields', k.f, 'current', a.current)
    from _adm a cross join lateral (select array_agg(l.field order by l.field) f from pipeline.manual_locks l
                                     where l.entity = 'course' and l.entity_id = a.course_id and l.field = any (security.coverage_admission_lock_fields_v1(a.attribute))) k
   where k.f is not null
  on conflict (course_id, attribute, proposed_md5) do update
     set last_seen_at = now(), seen_count = h.seen_count + 1, reason = excluded.reason, detail = excluded.detail, plan_action = excluded.plan_action;
  get diagnostics v_lock = row_count; delete from _adm a where exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = a.course_id
                                      and l.field = any (security.coverage_admission_lock_fields_v1(a.attribute)));
  -- IQ-00067: a proposal the apply refused waits admit.refused_recheck_hours before it is tried again, unless it changes
  v_skip := 0; delete from _adm a where exists (select 1 from pipeline.coverage_admission_holds h where h.course_id = a.course_id and h.attribute = a.attribute
                                      and h.proposed_md5 = md5(a.proposed::text) and h.reason = 'apply_refused' and h.last_seen_at > now() - v_recheck);
  get diagnostics v_skip = row_count;
  if not exists (select 1 from _adm) then
    return jsonb_build_object('written',0,'layer4',0,'held_manual_lock',v_lock,'refused_waiting',v_skip);
  end if;
$n$],
 [$o$    exception when others then v_err:=v_err+1; v_last:=left(sqlerrm,200);
    end;
  end loop;
$o$, $n$    exception when others then v_err:=v_err+1; v_last:=left(sqlerrm,200);
      -- IQ-00067: the refused item is held with its reason and the batch goes on, up to admit.item_error_limit refusals a run
      perform security.coverage_admission_hold_v1(r.course_id, r.props, r.page_url, 'write', 'apply_refused',
                jsonb_build_object('error', left(sqlerrm, 500), 'sqlstate', sqlstate));
      v_held := v_held + 1;
      if v_held >= v_cap then v_stop := true; end if;
    end;
    exit when v_stop;
  end loop;
$n$],
 [$o$                                and i.proposed_value=a.proposed) loop
    v_rule := case$o$, $n$                                and i.proposed_value=a.proposed) loop
    exit when v_stop;
    begin
    v_rule := case$n$],
 [$o$      v_auto := v_auto + 1;
    end if;
  end loop;
$o$, $n$      v_auto := v_auto + 1;
    end if;
    exception when others then
      -- IQ-00067 (Platform Admin 3 Nov 2026 15:52 §9): one item never aborts the batch. Its Layer 4 item, link and decision roll back together;
      -- the item is held with the refusal named, and the batch goes on, up to admit.item_error_limit refusals a run
      v_err := v_err + 1; v_last := left(sqlerrm, 200);
      perform security.coverage_admission_hold_v1(r.course_id, jsonb_build_object(r.attribute, r.proposed), r.page_url, 'differs', 'apply_refused',
                jsonb_build_object('error', left(sqlerrm, 500), 'sqlstate', sqlstate, 'rule', v_rule, 'current', r.current));
      v_held := v_held + 1;
      if v_held >= v_cap then v_stop := true; end if;
    end;
  end loop;
$n$],
 [$o$'layer4',v_l4,'decided_by_rule',v_auto);$o$,
  $n$'layer4',v_l4,'decided_by_rule',v_auto,
                            'held_manual_lock',v_lock,'held_refused',v_held,'refused_waiting',v_skip,'stopped_at_limit',v_stop);$n$]
]::text[][], array[1, 1, 1, 1, 1, 1]);

-- a run stopped at admit.item_error_limit has more to do: the next run is not skipped for "no new input"
select pg_temp.edit_once('security.coverage_admission_gated_v1(text,integer,text,text[])', '4e4e7f9ae2bb5e177774f1e394fdfe0d', 'adc4cf19720f361fbce223eb64297ba0', array[
 [$o$  v_more := coalesce((v->>'written')::int, 0) >= p_limit;$o$,
  $n$  v_more := coalesce((v->>'written')::int, 0) >= p_limit or coalesce((v->>'stopped_at_limit')::boolean, false);  -- IQ-00067: stopped at the refusal limit$n$]
]::text[][], array[1]);

-- 4. root cause and remedies through workstream A's contract ------------------------------------------------------------------------------------
create or replace function security.coverage_admit_recheck_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- IQ-00067 remedy coverage_admit_recheck (auto): the next scheduled coverage admission run does a full pass instead of skipping for "no new
-- input". It changes no rule, lock, setting or admission; the job and its gates decide as they always do.
declare v_before jsonb; v_n int;
begin
  select jsonb_object_agg(m.job_key, jsonb_build_object('last_full_at', m.last_full_at, 'last_result', m.last_result)) into v_before
    from pipeline.job_input_marks m where m.job_key in ('coverage-admit', 'coverage-admit-intakes');
  update pipeline.job_input_marks set last_full_at = null where job_key in ('coverage-admit', 'coverage-admit-intakes') and last_full_at is not null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'changed', v_n, 'evidence', jsonb_build_object('issue', p_issue, 'marks_before', v_before));
end $function$;
revoke all on function security.coverage_admit_recheck_v1(bigint) from public, anon, authenticated;

create or replace function security.coverage_admit_recheck_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- IQ-00067 remedy coverage_admit_recheck, verification: passed when a full coverage-admit run committed after the remedy acted. A failed run
-- rolls back and never moves last_full_at, so a later last_full_at proves a whole batch completed.
declare v_at timestamptz; m record;
begin
  select max(r.started_at) into v_at from pipeline.ops_remedy_runs r where r.issue_id = p_issue and r.remedy_code = 'coverage_admit_recheck';
  select * into m from pipeline.job_input_marks where job_key = 'coverage-admit';
  return jsonb_build_object('passed', v_at is not null and m.last_full_at is not null and m.last_full_at > v_at,
    'measure', jsonb_build_object('acted_at', v_at, 'last_full_at', m.last_full_at, 'last_result', m.last_result),
    'evidence', jsonb_build_object('held_manual_lock', (select count(*) from pipeline.coverage_admission_holds h where h.reason = 'manual_lock' and h.last_seen_at >= coalesce(v_at, now())),
                                   'held_refused', (select count(*) from pipeline.coverage_admission_holds h where h.reason = 'apply_refused' and h.last_seen_at >= coalesce(v_at, now()))));
end $function$;
revoke all on function security.coverage_admit_recheck_verify_v1(bigint) from public, anon, authenticated;

select security.ops_root_cause_register_v1('lock_conflict_in_batch', jsonb_build_object(
  'class', 'rule',
  'title', 'A record locked by hand reached a batch apply, and the refusal aborted the whole batch',
  'description', 'A batch job offered a value for a field set by hand (pipeline.manual_locks); the apply refuses it, correctly, and the raise rolled back every other item in the batch. First seen IQ-00067: coverage-admit failed every run from 3 Nov 2026 13:53 AEDT. Fixed in the admission path by release 20261104080000 (locked rows held as manual_lock before apply; per-item isolation).',
  'detect', jsonb_build_object('kind', 'cron_failure', 'jobs', jsonb_build_array('coverage-admit', 'coverage-admit-intakes'),
                               'message_like', '%set by hand on the course record%', 'context_like', '%layer4_course_link_apply_impl%')));

select security.ops_remedy_register_v1('coverage_admit_lock_hold', jsonb_build_object(
  'title', 'Hold locked courses before the coverage admission apply; isolate each item',
  'treats', jsonb_build_array('lock_conflict_in_batch'), 'authority', 'release',
  'notes', 'IQ-00067 release 20261104080000: security.coverage_admission_apply_v1 holds manual_lock rows in pipeline.coverage_admission_holds and isolates each item (admit.item_error_limit). A recurrence in another batch apply needs the same change there.'));

select security.ops_remedy_register_v1('coverage_admit_recheck', jsonb_build_object(
  'title', 'Ask for a full coverage admission pass on the next run, then check it committed',
  'treats', jsonb_build_array('lock_conflict_in_batch'), 'authority', 'auto',
  'action_fn', 'security.coverage_admit_recheck_v1(bigint)', 'verify_fn', 'security.coverage_admit_recheck_verify_v1(bigint)',
  'max_attempts_key', 'admit.remedy_max_attempts', 'cooldown_key', 'admit.remedy_cooldown_minutes',
  'notes', 'IQ-00067: after the release the next run is full anyway; the remedy makes that explicit and verifies a whole batch committed (job_input_marks.last_full_at moved past the action).'));

-- 5. register ------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.coverage_admission_holds', 'Layer 2', 'Admission', 'Coverage admission rows not applied, with the named reason (manual_lock, apply_refused)', 'active', '{}', '20261104080000'),
 ('function', 'security.coverage_admission_lock_fields_v1', 'Layer 2', 'Admission', 'The manual lock fields that hold an admission attribute', 'active', '{}', '20261104080000'),
 ('function', 'security.coverage_admission_hold_v1', 'Layer 2', 'Admission', 'Holds an admission item with its reason', 'active', '{}', '20261104080000'),
 ('function', 'security.coverage_admit_recheck_v1', 'Layer 2', 'Operations', 'Remedy coverage_admit_recheck: full admission pass on the next run', 'active', '{}', '20261104080000'),
 ('function', 'security.coverage_admit_recheck_verify_v1', 'Layer 2', 'Operations', 'Remedy coverage_admit_recheck: verifies a full pass committed', 'active', '{}', '20261104080000')
on conflict (kind, name) do nothing;
