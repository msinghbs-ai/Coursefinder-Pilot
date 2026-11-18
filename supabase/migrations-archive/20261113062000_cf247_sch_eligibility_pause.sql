-- CF-247 F-SCH.01: the eligibility reader goes back to shadow (sch_elig.apply_on 0) and the eight unpublished admissions it made after activation
-- (20261113061000) are withdrawn. Post-activation check, live 12 Nov 2026 16:55 AEDT: of the 9 international or both proofs acted on, 8 admitted a
-- scholarship (none published yet) and at least four proofs did not prove that this scholarship is open to international students:
--   UTS Andrew and Lina Gullotta Community Pharmacy Award: the quote is a course name ("Master of Pharmacy (International) (C04253)");
--   Bond Judge John Newton Mooting Scholarships: the quote is the site-wide scholarship banner ("for both domestic and international applicants");
--   UNBC Graduate Entrance Research Scholarship: the quote is a general awards-application instruction on an overview page;
--   "New Zealand Scholarship" (NZQA secondary qualification) under Port and Crane Academy, whose recorded website is NZQA's: not a scholarship of
--   that provider.
-- The shadow validation of 16:30 missed these shapes; the proof must be tightened before the reader acts again (separate change, shadow first).
-- Every admission is withdrawn through the existing rule (security.scholarship_admission_withdraw_v1: unpublished, admitted from a provider page),
-- including the Sydney ones whose page tags may be navigation; a proven record is admitted again by the corrected reader. Nothing was published.
-- Replaces: the live mode of the eligibility reader (back to shadow). Retires: nothing.

update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       reason = 'F-SCH.01 12 Nov 2026 16:55: false positives after activation (course name, site banner, overview page, wrong provider); back to shadow'
 where toolset_key = 'pipeline' and key = 'sch_elig.apply_on' and value is distinct from to_jsonb(0);

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'setting_changed', 'sch_elig.apply_on 1 -> 0 (eligibility reader back to shadow; 8 unpublished admissions withdrawn)',
        jsonb_build_object('key', 'sch_elig.apply_on', 'from', 1, 'to', 0, 'false_positive_shapes', jsonb_build_array('course name with (International)', 'site-wide banner', 'overview page instruction', 'provider website recorded as NZQA'),
                           'published', 0, 'migration', '20261113062000'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

select security.scholarship_admission_withdraw_v1(c.admitted_scholarship_id,
         jsonb_build_object('reasons', jsonb_build_array('eligibility_proof_not_specific'), 'by', 'F-SCH.01 post-activation check 12 Nov 2026', 'migration', '20261113062000', 'candidate', c.id))
  from pipeline.scholarship_eligibility_reads r join pipeline.scholarship_page_candidates c on c.id = r.candidate_id
 where r.outcome = 'proven' and r.applied->>'mode' = 'live' and r.applied->>'action' = 'admit' and c.admitted_scholarship_id is not null;
