-- M2.4.2 — invalidate pre-detail-verification RMIT discovery decisions.
-- Preserve Evidence, provider attempts, timestamps and prior status in match_basis.
-- The v1.3.0 discovery worker must re-evaluate these Courses and select only when
-- the current first-party Course detail page contains the expected CRICOS code.

begin;

update pipeline.layer2_course_discovery_candidates
set match_basis=coalesce(match_basis,'{}'::jsonb)||jsonb_build_object(
      'pre_detail_verification_status',status,
      'invalidated_by_worker','layer2-scope-discover-scheduled-v1.3.0'
    ),
    status='candidate',
    selected=false,
    blocker=case
      when blocker is null then 'Selection/evaluation invalidated pending current first-party detail-page CRICOS verification.'
      else blocker||' | invalidated pending current first-party detail-page CRICOS verification.'
    end
where source_profile_version_id=(
    select current_version_id
    from pipeline.layer2_source_profiles
    where profile_key='au-rmit-course-detail'
  )
  and status in ('exact_match','likely_match','ambiguous','identity_mismatch','current_page_not_found')
  and coalesce(match_basis->>'worker_version','')<>'layer2-scope-discover-scheduled-v1.3.0';

commit;
