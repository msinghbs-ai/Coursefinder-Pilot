-- CF-247 G1: register the page-text job and its objects in pipeline.component_register (S2-Build, Platform Admin 18 Nov 2026 11:54: the 11:48 AEDT
-- telemetry sync flagged job 445 page-text as UNREGISTERED). Pilot #1252 (migration 20261118113000) catalogued the job in
-- pipeline.automation_catalogue (area Coverage sweep, "Page text for Boost") but wrote no component register rows. The job is still required: it
-- turns stored source snapshots into the page text Boost claims (537 converted, 519 claimed by Boost by 11:05 AEDT), and coverage-lane-dispatch
-- does not run it. Folding it into coverage-lane-dispatch is listed with the other single-mode coverage-sweep jobs for after Thursday's squash
-- (admin docs/CURRENT-STATE.md section 5).
-- Nothing else changes. G3 untouched.
-- Replaces: nothing.
-- Retires: nothing.

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Coverage sweep', v.purpose, 'active', '20261118113000'
  from (values
    ('job', 'page-text', 'L2 reading', 'Converts stored source snapshots of active courses lacking study load or description into page text for Boost, in boost.matrix order (coverage-sweep mode page_text, every 2 minutes, batch.page_text)'),
    ('table', 'pipeline.page_text_conversions', 'L2 reading', 'One row per stored snapshot converted (or tried) by job page-text: outcome, the text evidence written, claim lease'),
    ('function', 'public.svc_page_text_next_v1', 'L2 reading', 'Claims the next stored snapshots for job page-text in boost.matrix order'),
    ('function', 'public.svc_page_text_record_v1', 'L2 reading', 'Records page text evidence (provider_course_page_text) derived from a stored snapshot')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

do $$
begin
  if (select count(*) from pipeline.component_register where (kind, name) in (('job', 'page-text'), ('table', 'pipeline.page_text_conversions'),
        ('function', 'public.svc_page_text_next_v1'), ('function', 'public.svc_page_text_record_v1'))) <> 4 then  -- fixed: the four objects of the job
    raise exception 'post-check: page-text component register rows';
  end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'page-text') then raise exception 'post-check: page-text catalogue row'; end if;
end $$;
