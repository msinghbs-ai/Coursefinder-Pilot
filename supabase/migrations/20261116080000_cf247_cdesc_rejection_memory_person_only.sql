-- CF-247 F-CDESC: the course description machine rule's rejection memory counts person decisions only (Platform Admin 16 Nov 2026 11:32,
-- approving the read-only finding of 11:09: "Fix the course_description_first_read admission rule so only genuine human decisions count as
-- rejected_before_course ... and bump the rule version so those 1,167 pending v2 items are re-evaluated cleanly against all remaining checks").
--
-- Finding (read only, 16 Nov 2026 11:00-11:09 AEDT): no new course description reading had started since 02:48, because
-- security.enrich_course_text_gaps_v1 starts none while enrich.course_description_pending_global_max (1,500) first descriptions wait in
-- Layer 4, and 1,831 waited. 1,167 of them were declined by security.course_description_machine_check_v1 as rejected_before_course ("A person
-- decided against an earlier description for this course"). Every earlier item of those 1,167 courses had status 'superseded': 1,421 rows by
-- security.cdesc_prompt_supersede_v1 when cdesc-source-grounded-v2 was released (15 Nov), 132 by another CF-247 path. None was decided by a
-- person and none was a v2 reading. The rule's three rejection-memory tests ("status not in ('pending', 'approved', 'edited_approved')") read
-- 'superseded', the platform's own decision, as a person's.
--
--   1. security.course_description_machine_check_v1: the three rejection-memory tests (by course, by page, by text) also leave out
--      'superseded'. A person's decision (rejected, edited_rejected, returned or any other status a person sets) still counts, exactly as before.
--   2. The rule version becomes cdesc-machine-v2: v_rule in course_description_machine_check_v1 and course_description_machine_admit_v1 (written
--      to the admissions ledger), the policy stamp's prefix in course_description_machine_policy_stamp_v1, the supersession note in
--      cdesc_prompt_supersede_v1 and the rule named by course_description_machine_shadow_v1. The new stamp makes
--      security.course_description_machine_settle_v1 (job course-description-machine) evaluate every waiting item again, within its own time box,
--      against all the other checks (copied sentences, identity binding, wording, figures, duplicates, evidence age). Nothing is admitted by this
--      migration; the job admits what passes, as it does today. The held readings are looked at once again by security.cdesc_recheck_held_v1
--      under the new stamp (their text check does not change here, so it only marks them).
-- Each edit is guarded by the md5 of the live function body (pg_proc.prosrc) before and after, and must match the stated number of times.
-- Not changed: no setting (enrich.course_description_pending_global_max stays 1,500; enrich.course_description_machine_on stays 1), no job,
-- route, model, cascade, cap or table. AER v1 is not touched (Decision 276).
-- G1: no new job. G2: no new value (no number added). G3: no consumer API object is read or changed (security.consumer_api_check_v1() before
-- and after, same result).
-- Replaces: security.course_description_machine_check_v1(uuid), security.course_description_machine_admit_v1(uuid,text),
--   security.course_description_machine_policy_stamp_v1(), security.cdesc_prompt_supersede_v1(), security.course_description_machine_shadow_v1(integer,integer)
--   (same names and signatures; md5-guarded edits in place).
-- Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

-- G3 before: the consumer API matches its baseline (checked_at left out of the comparison)
select set_config('cf247.cdesc_rm_api_before', (security.consumer_api_check_v1() - 'checked_at')::text, true);

-- the edit helper (this transaction only): every pair must match its stated count; the body md5 is checked before and after
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[], p_counts int[]) returns text language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_def text; v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig::regprocedure), chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> p_counts[i] then raise exception '%: edit % must match % time(s), found %', p_sig, i, p_counts[i], v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '%: body md5 after the edit is %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': edited';
end $f$;

-- 1 and 2. The machine check: person decisions only, rule cdesc-machine-v2
select pg_temp.edit_all('security.course_description_machine_check_v1(uuid)', '2a5b91aa6b93b920bbb80df9920aca09', '1be689ae7ed55af7899088257c35e331',
  array[$o$status not in ('pending', 'approved', 'edited_approved')$o$,
        $o$-- rejection memory: by course, by page, by text, and a withdrawn machine admission$o$,
        $o$v_rule constant text := 'cdesc-machine-v1';$o$],
  array[$n$status not in ('pending', 'approved', 'edited_approved', 'superseded')$n$,
        $n$-- rejection memory: by course, by page, by text, and a withdrawn machine admission. Person decisions only (cdesc-machine-v2, 16 Nov 2026): 'superseded' is the platform's own decision$n$,
        $n$v_rule constant text := 'cdesc-machine-v2';$n$],
  array[3, 1, 1]);

-- 2. The rule version everywhere it is named
select pg_temp.edit_all('security.course_description_machine_admit_v1(uuid,text)', '569f3ceb95c3d31b378ce7288b7abd24', 'ee3f9e557e87e2929f31a6985cb1d6e2',
  array[$o$v_rule constant text := 'cdesc-machine-v1';$o$], array[$n$v_rule constant text := 'cdesc-machine-v2';$n$], array[1]);
select pg_temp.edit_all('security.course_description_machine_policy_stamp_v1()', '420842097d4cda058b2c744d63cbb800', 'd089bbeb8fc9232c9872e4f515a6e299',
  array[$o$md5('cdesc-machine-v1|' ||$o$], array[$n$md5('cdesc-machine-v2|' ||$n$], array[1]);
select pg_temp.edit_all('security.cdesc_prompt_supersede_v1()', 'db97aa04ee17a3541c9d67736b4cafb9', 'b55a93822f9713d57b9f9fd88ac42bef',
  array[$o$declined for good by cdesc-machine-v1;$o$], array[$n$declined for good by cdesc-machine-v2;$n$], array[1]);
select pg_temp.edit_all('security.course_description_machine_shadow_v1(integer,integer)', '1f2c9de63a477ec918e6f8ea4e144813', '0e8fafc0f5204871a31455b5456baa8d',
  array[$o$'rule', 'cdesc-machine-v1',$o$], array[$n$'rule', 'cdesc-machine-v2',$n$], array[1]);

-- 3. Post-checks: the rule reads person decisions only, the version moved everywhere, nothing else moved
do $c$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_check_v1(uuid)'::regprocedure);
begin
  if (length(v_src) - length(replace(v_src, $s$'edited_approved', 'superseded')$s$, ''))) / length($s$'edited_approved', 'superseded')$s$) <> 3 then
    raise exception 'post-check: the three rejection-memory tests leave out superseded';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'security' and p.prosrc like '%cdesc-machine-v1%'
                and p.proname in ('course_description_machine_check_v1', 'course_description_machine_admit_v1', 'course_description_machine_policy_stamp_v1',
                                  'cdesc_prompt_supersede_v1', 'course_description_machine_shadow_v1')) then
    raise exception 'post-check: the rule version is cdesc-machine-v2 in every function that names it';
  end if;
  if security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) <> 1500 or security.pipeline_num_v1('enrich.course_description_machine_on', 0) <> 1 then
    raise exception 'post-check: the back-pressure limit and the machine switch are unchanged';
  end if;
  if (security.consumer_api_check_v1() - 'checked_at')::text is distinct from current_setting('cf247.cdesc_rm_api_before', true) then
    raise exception 'post-check (G3): the consumer API check result changed';
  end if;
  if coalesce(current_setting('cf247.cdesc_rm_api_before', true)::jsonb->'drift', '[]'::jsonb) not in ('[]'::jsonb, '{}'::jsonb, 'null'::jsonb) then
    raise exception 'post-check (G3): the consumer API differs from its baseline';
  end if;
end $c$;
