-- M2.4.2 — enable weekly Course refresh only for UQ after accepted full-run evidence.
-- RMIT remains disabled until v1.3.0 full rerun acceptance; Federation remains paused/source-limited.

begin;

update pipeline.refresh_policies rp
set enabled=true,
    next_due_at=now()+rp.cadence_interval,
    updated_at=now(),
    change_control_ref='CF-CHG-20260827-044'
from pipeline.layer2_source_profiles p
where rp.source_profile_id=p.id
  and rp.layer=2
  and rp.entity_id is null
  and p.profile_key='au-uq-course-catalogue';

update pipeline.layer2_execution_policies ep
set schedule_mode='weekly',
    next_run_at=now()+interval '7 days',
    updated_at=now()
from pipeline.layer2_source_profiles p
where ep.profile_id=p.id
  and p.profile_key='au-uq-course-catalogue';

commit;
