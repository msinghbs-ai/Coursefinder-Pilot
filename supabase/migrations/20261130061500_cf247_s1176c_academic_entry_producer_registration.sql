-- CF-247 s1176c (S1-RM-Design; DR-16 Priority 3 item 1, SS-Programme-Control 27 Nov 2026 00:08 AEDT: "Academic entry producer registration ...
-- Rehearse the existing 'coverage' reader classification and measure its impact on planner priorities and coverage states before release").
--
-- Defect: pipeline.field_register.academic_entry carried reader = 'none' ("Not measured here yet") although academic entry has automatic producers:
-- the planner's academic_entry step queues course entry reads (s1274) for the scheduled course entry reader (s1261, coverage-sweep worker), and
-- the entry-matrix readers. With 'none', security.pim_record_trace_v1 diagnosed every missing entry as a software defect, and
-- security.course_coverage_build_v1 and security.field_stalled_v1 reported 'no_reader' instead of the page state.
-- Change: reader = 'coverage' (the existing classification for fields filled by the coverage pipeline readers; the CHECK allows register, coverage,
-- enrich, none) and the producer named in fills. Nothing else changes; the coverage build re-states courses over its normal cycle
-- (batch.course_coverage_courses, about 90 minutes for every course).
-- Measured in a rolled-back rehearsal on live data (27 Nov 2026 00:20 AEDT), 3,998 courses at 198 providers rebuilt:
--   academic entry states of the 2,562 courses without entry: not_on_page 1,118, site_known 1,078, page_found 290, blocked 63, no_website 13
--   (all were no_reader);
--   planner priority (security.enrich_plan_priority_v1): eligible gaps 155,231 -> 157,603 (+1.5%), 162 providers changed, largest +207,
--   no provider added or removed, top 50 overlap 49 of 50. Reversible by setting the reader back.
-- G1: no job. G2: no setting. G3: no consumer object; 75/48 asserted. Locks and cron asserted. Nothing dropped. US$0.
-- Replaces: the academic_entry row's reader 'none' and its fills text in pipeline.field_register.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the register row

do $c$
declare v jsonb := security.consumer_api_check_v1(); n_locks bigint := (select count(*) from pipeline.manual_locks); n_cron bigint := (select count(*) from cron.job where active); n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  update pipeline.field_register
     set reader = 'coverage',
         fills = 'Planner academic entry step (s1274) queues course entry reads for the scheduled course entry reader (s1261, coverage-sweep) and the entry-matrix readers; admitted by AER machine admission or Layer 4',
         reason = 'CF-247 s1176c: academic entry has automatic producers (s1274, s1261); reader none made missing entry read as a software defect and no_reader',
         updated_at = now()
   where field = 'academic_entry' and reader = 'none';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'guard: academic_entry register row not found with reader none (% rows)', n; end if;
  v := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < n_locks then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) <> n_cron then raise exception 'guard: the scheduler changed'; end if;
end $c$;
