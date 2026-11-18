-- CF-247 S670 AER shared pages: a refused binding is not a claim on the page of a course a person bound by hand either (Platform Admin, 18 Nov 2026 17:52, session S2-BOOST-AER:
-- "The 8 Nov exclusion of hand-locked bindings was only a conservative default; extend the rule (s670) to release the ~15 hand-bound items where every other course sharing that
-- page has already been rejected by the identity check"). Variant twins and every page another course is bound or ambiguous on stay held (same directive: "Keep variant twins held").
-- Guards: E13 shared-page hold (entry.shared_page_hold), G2 (the hand-lock rule and the basis list are settings), G3 (no consumer API object, table or column is touched),
--   Decision 260 (housekeeping), Decision 276 (no AER v1 reader, word list or threshold is changed; aer.machine_min_confidence and aer.machine_min_quote_chars are untouched).
-- Replaces: security.course_entry_shared_page_v1 (same name and signature; md5-guarded edit of one clause)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 18 Nov 2026 17:55 AEDT; admin docs/platform/2026-11-18-aer-held-items-classification.md). Of the waiting course reads held
-- because the stored page is also another programme's page, 20 have ONLY refused (mismatch) bindings of other courses on the page: 14 are bound by hand (identity basis manual),
-- 4 by cricos_code and 2 by exact_title, and all 20 carry a hand lock on the page address. All 20 are held for this reason alone. The rule of 8 Nov 2026 (migration 20261108030000)
-- already ignores a refused binding for a strongly identified course, but kept the old rule for a hand binding and for any course with a hand lock.
-- What this changes (one clause of one function, two settings):
--   * the hand lock keeps the old rule only while entry.shared_page_hand_lock_holds is 1. It is created at 0: a hand lock no longer makes a refused binding count. 1 restores 8 Nov exactly.
--   * entry.shared_page_own_bases gains manual, only where the list still holds the 8 Nov default (a list someone changed is left as it is).
-- Not changed: a course another course is BOUND or AMBIGUOUS on stays held (ladders, stream siblings, pace and duration twins); a course whose own binding is refused, ambiguous or on
--   a basis outside the list keeps the old rule; the gate, the machine rule and its thresholds, the audit sample, every decision path. Nothing is read, fetched, spent, re-bound or deleted
--   here. A released read is then judged by the rules already in force (the gate, aer.machine_mode, the 5% audit sample).
-- Before -> after:
--   security.course_entry_shared_page_v1(uuid) 7b43d0c61419ec08ea2fbb2889b1f444 -> 077bf1637e515fc08e837f581767a1ac

do $g$
begin
  if to_regprocedure('security.course_entry_shared_page_v1(uuid)') is null or to_regclass('pipeline.manual_locks') is null then
    raise exception 'needs security.course_entry_shared_page_v1 (migration 20261108030000) and pipeline.manual_locks';
  end if;
end $g$;

-- 1 settings (G2) -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.shared_page_hand_lock_holds', 'Entry requirements: a hand lock keeps refused bindings counting',
  '1: a course with a hand lock on its page address counts refused bindings of other courses as sharing its page (the rule of 8 Nov 2026). 0: a hand lock makes no difference; a refused binding is not a claim on the page.',
  'number', '0'::jsonb, 0, 1, 'on/off', 1472, 'Entry requirements', 'security.course_entry_shared_page_v1',
  'CF-247 S670 (Platform Admin 18 Nov 2026 17:52): the hand-lock exclusion of 8 Nov was a conservative default')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings
   set value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level", "manual"]'::jsonb,
       reason = 'CF-247 S670 (Platform Admin 18 Nov 2026 17:52): a course bound by hand ignores refused bindings on its page', updated_at = now()
 where toolset_key = 'pipeline' and key = 'entry.shared_page_own_bases'
   and value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level"]'::jsonb;

-- 2 the edit, md5-guarded ----------------------------------------------------------------------------------------------------------------------
do $edit$
declare v_sig constant text := 'security.course_entry_shared_page_v1(uuid)'; v_before constant text := '7b43d0c61419ec08ea2fbb2889b1f444';
        v_def text := pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%entry.shared_page_hand_lock_holds%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o$          or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g1.course_id and l.field in ('official_url', 'course_url')))$o$;
  v_new := $n$          -- CF-247 S670 (18 Nov 2026): the hand lock keeps the old rule only while entry.shared_page_hand_lock_holds is 1
          or (security.pipeline_num_v1('entry.shared_page_hand_lock_holds', 0) >= 1
              and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g1.course_id and l.field in ('official_url', 'course_url'))))$n$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', v_sig, v_c; end if;
  execute replace(v_def, v_old, v_new);
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure));
end $edit$;

comment on function security.course_entry_shared_page_v1(uuid) is 'CF-247 E13 (factored out by D-R2; edits of 8 and 18 Nov 2026): the differently named programmes whose stored page is also this course''s page (entry.shared_page_hold). A binding the identity check refused (mismatch) does not count for a course that is itself bound on a basis in entry.shared_page_own_bases (entry.shared_page_count_statuses); a hand lock on the page address keeps the old rule only while entry.shared_page_hand_lock_holds is 1.';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'entry_requirements', 'shared_page_rule', 'security.course_entry_shared_page_v1',
       jsonb_build_object('change', 'a refused (mismatch) binding no longer makes a page shared for a course bound by hand or carrying a hand lock',
                          'settings', jsonb_build_array('entry.shared_page_hand_lock_holds', 'entry.shared_page_own_bases'), 'before_md5', '7b43d0c61419ec08ea2fbb2889b1f444',
                          'authority', 'Platform Admin 18 Nov 2026 17:52 (S2-BOOST-AER)', 'migration', '20261118220000'), null
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'entry_requirements' and e.action = 'shared_page_rule' and e.detail->>'migration' = '20261118220000');
