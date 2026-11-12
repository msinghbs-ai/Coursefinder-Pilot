-- CF-247 F-SCH.01: the eligibility reader acts on proven sentences (sch_elig.apply_on 1), the separate recorded activation step after shadow validation
-- (Platform Admin 12 Nov 2026 11:50 decision 2: "After validation succeeds, automatically activate processing for evidence-proven cases through the
-- existing authorised scholarship admission policy"; directive 12 Nov 2026 16:12 §5).
-- Shadow validation, live 12 Nov 2026 16:30 AEDT (worker v0.76.0 proof rule): 16 proven reads of about 1,150 read (US$0.13). 10 domestic-only
-- proofs, every quote a citizenship or residency condition (or an Aboriginal and Torres Strait Islander condition): all correct. 6 international or
-- both proofs: 4 name international applicants on a single scholarship page (Sydney x3, "(domestic) ... (international)" tags and "or an International
-- student"; "a successful international applicant"); 1 is a Canadian awards overview (UNBC) and 1 an NZQA secondary qualification page attributed to
-- another provider: both readings of who may apply are true, and neither can be admitted, because the admission rule this step hands them to refuses a
-- listing page and a page off the provider's own site. No proof would admit a scholarship wrongly. Live, a proof is only handed back to
-- security.scholarship_admit_from_provider_page_v1, which checks every rule again; a domestic proof records the case domestic_only; silent pages
-- stay unresolved (sch_elig.silent_resolves stays 0).
-- Replaces: the shadow mode of the eligibility reader. Retires: nothing.

update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(), updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       reason = 'F-SCH.01 live 12 Nov 2026: shadow validation passed (16 proofs, no wrong admission possible); acts through the existing admission rule'
 where toolset_key = 'pipeline' and key = 'sch_elig.apply_on' and value is distinct from to_jsonb(1);

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'setting_changed', 'sch_elig.apply_on 0 -> 1 (eligibility reader acts on proven sentences)',
        jsonb_build_object('key', 'sch_elig.apply_on', 'from', 0, 'to', 1, 'proofs', 16, 'domestic', 10, 'international_or_both', 6, 'wrong_admissions_possible', 0,
                           'authority', 'Platform Admin 12 Nov 2026 11:50 decision 2; directive 12 Nov 2026 16:12', 'migration', '20261113061000'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

-- the proven reads recorded in shadow are acted on once, live (silent reads change nothing while silent_resolves is 0, so they are left as recorded)
update pipeline.scholarship_eligibility_reads set applied = null, updated_at = now()
 where outcome = 'proven' and applied->>'mode' = 'shadow';
