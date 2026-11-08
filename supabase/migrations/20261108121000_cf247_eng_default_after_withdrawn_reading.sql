-- CF-247 English requirements (lane ENG, 8 Nov 2026): an approved provider default is applied to a course whose own page reading was withdrawn.
-- Why (live, read-only, 8 Nov 2026 03:30-04:40 UTC, project fxcwkweaxjtknorudmwp):
--   * security.provider_english_plan_v1 treats any English row of a course, whatever its status, as "the course has a reading" (any_row), so a course whose only rows
--     are withdrawn gets the outcome 'other_value' and is never written. That is right for a row the policy itself wrote and then withdrew (Decision 264 own-page rule,
--     a group binding that no longer reaches the course): rewriting it would undo the withdrawal. It is wrong for a course-page reading that was withdrawn (an identity
--     clean-up on 1-4 Oct 2026): the course now has no reading of its own, and the approved default for its level is exactly what Decision 227 provides for such a course.
--   * 44 active courses of 4 providers with an approved policy (UTS 37, Curtin 2, Chisholm 3, Newcastle 2 ...) are in that state; for 41 of them the withdrawn reading
--     scores the same IELTS as the approved default (so the default restates the value the course page gave), for 4 it differs. No course has a lock or a Layer 4 item.
--   * 492 active courses have only withdrawn rows; 422 of them are UNSW Sydney rows written from the Bengaluru page and withdrawn on purpose (they stay out of this change:
--     policy-written rows keep blocking, and UNSW has no approved default).
-- What:
--   1 Setting english.default_after_withdrawn_reading (G2; ships 0 = off, so nothing changes until the Controller or Platform Admin switches it on).
--   2 security.provider_english_plan_v1 (md5-guarded, three edits): with the setting on, withdrawn rows that a policy did NOT write no longer count as a reading
--     (any_row), and are compared with the default: where the withdrawn reading scores a test the default also gives, at a different score, the outcome is 'differs' (held,
--     shown, not written); otherwise the course is planned 'write' and provider_english_apply_v1 writes it through the same path as every other default. Locks, Layer 4
--     items in review, held levels (research, double degree, named courses, level not covered) and policy-written withdrawn rows are decided first and are unchanged.
--   Nothing else changes: the same functions apply, publish and flag the row (confidence 0.6 when the policy says some courses need more).
-- Consumer API: unchanged (G3). The rows are written by the existing apply path into catalogue.course_english_requirements, as every policy default is.
-- md5 (before = live 8 Nov 2026; after = local replay on PostgreSQL 16, tests/fixtures/eng-gap-recovery/run.sh):
--   security.provider_english_plan_v1(uuid)   b5b449dd54d885fe68b5085626531bd3 -> 6fec9e6515a347438b7ed07215cbd748
-- Replaces: security.provider_english_plan_v1(uuid) (md5-guarded edit of the live definition)
-- Retires: nothing.
-- Nothing is dropped or deleted by this migration.

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

-- 1 the setting (G2) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'english.default_after_withdrawn_reading', 'English: apply the provider default to a course whose own page reading was withdrawn',
 '1: a course whose only English rows are withdrawn readings from its own page (not rows the policy wrote) takes the approved default for its level, through the same apply path as every other default. Where the withdrawn reading scored a test the default also gives at a different score, the course is held and shown as differing, not written. Rows the policy itself wrote and then withdrew (own-page rule, group binding) keep blocking. Locks, Layer 4 items in review and held levels are decided first. 0: as before.',
 'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1030, 'English policies',
 'security.provider_english_plan_v1 (security.provider_english_apply_v1, job provider-english-defaults)',
 'CF-247 ENG, 8 Nov 2026: ships off (writes English values); 44 courses, 41 with the same IELTS as the withdrawn reading')
on conflict (toolset_key, key) do nothing;

-- 2 the plan ----------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.provider_english_plan_v1(uuid)', 'b5b449dd54d885fe68b5085626531bd3', '6fec9e6515a347438b7ed07215cbd748',
  array[
   array[$o$v_named jsonb; v_defaults jsonb;$o$,
         $n$v_named jsonb; v_defaults jsonb;
        -- CF-247 ENG 8 Nov 2026: english.default_after_withdrawn_reading (off = a withdrawn row of any kind counts as a reading, as before)
        v_wd_off boolean := security.pipeline_num_v1('english.default_after_withdrawn_reading', 0) < 1;$n$],
   array[$o$           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id) any_row,$o$,
         $n$           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id
                    and (v_wd_off or r.status = 'active' or coalesce(r.source_requirement_key, '') like 'policy:%')) any_row,
           -- the scores of withdrawn readings the course page gave (a policy's own withdrawn rows are not here: they keep blocking)
           case when v_wd_off then '{}'::jsonb else (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id
             where r.course_id = c0.id and r.status = 'withdrawn' and coalesce(r.source_requirement_key, '') not like 'policy:%') end wd_ex,$n$],
   array[$o$              when q.any_row then 'other_value'$o$,
         $n$              when q.any_row then 'other_value'
              when exists (select 1 from jsonb_array_elements(q.reqs) r where q.wd_ex ? (r->>'test_code') and (q.wd_ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'$n$]
  ], array[1, 1, 1]);
