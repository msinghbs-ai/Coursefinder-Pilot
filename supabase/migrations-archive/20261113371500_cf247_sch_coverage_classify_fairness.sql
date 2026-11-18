-- CF-247 F-SCH.14: fair scholarship coverage classification - no provider waits days for re-classification behind others
-- (Platform Admin S2-Scholarship directive 13 Nov 2026 23:07, Priority 1; Developer Requirements v2.30 F-SCH.14).
-- Why (live, 13 Nov 2026 12:05 UTC): 2,561 providers are in scope, at 40 an hour (batch.sch_coverage_classify) - a full cycle of 64 hours. The
--   127 providers with an integration issue came first each time they were due (every 6 h, about 21 an hour), so the other 2,434 shared about
--   19 an hour: a 5-day cycle. 2,321 were overdue, the oldest last classified 9 Nov 09:29 UTC. 18 award-value Layer 4 cases whose scholarships
--   were already published could not close, because their providers (16, among them UBC, Auckland, RMIT, Curtin) had not been re-classified
--   since 9-12 Nov. They were re-classified at 12:08 UTC with the scheduler's own function scoped to those 16 providers: all 55 published
--   value cases now meet their existing closure condition (published_verified) for the HAR re-check.
-- Change (selection order of the hourly run only; what classification decides is unchanged):
--   1. new providers first; 2. then any provider whose open scholarship Layer 4 case or pending AI review waits on its re-classification, and
--   any provider not classified within sch_cov.max_age_hours (36); 3. then providers with an integration issue; 4. then the rest, oldest first.
--   batch.sch_coverage_classify 40 -> 120 (a run of 40 took 26-49 s including the provider coverage snapshot): a full cycle in about 22 h.
-- Settings: sch_cov.max_age_hours (36 hours, 12-168, new); batch.sch_coverage_classify 40 -> 120 (reason recorded).
-- Replaces: security.scholarship_coverage_classify_v1(uuid[]) (same name and signature; md5-guarded edit of the live text).
-- Retires: the fingerprint-first selection order (replaced in place).

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'sch_cov.max_age_hours', 'Scholarship coverage: longest wait for re-classification',
        'A provider not classified for this long is taken with the providers whose Layer 4 cases wait on re-classification, ahead of the routine order, so no provider is stranded behind others.',
        'number', '36'::jsonb, 12, 168, 'hours', 1451, 'F-SCH.14 (13 Nov 2026): providers waited up to 4 days; 18 published value cases could not close', 'Scholarship coverage recovery',
        'security.scholarship_coverage_classify_v1')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set value = '120'::jsonb, updated_at = now(),
       reason = 'F-SCH.14 (13 Nov 2026): 2,561 providers at 40 an hour was a 64-hour cycle (5 days for providers without an issue); 120 gives about 22 hours. A run of 40 took 26-49 s.'
 where toolset_key = 'pipeline' and key = 'batch.sch_coverage_classify' and value = '40'::jsonb;
insert into pipeline.admin_control_events(area, action, target, detail)
values ('scholarship_coverage', 'setting_changed', 'batch.sch_coverage_classify',
        jsonb_build_object('from', 40, 'to', 120, 'by', 'migration 20261113371500', 'reason', 'F-SCH.14 classification fairness'));

select pg_temp.edit_n('security.scholarship_coverage_classify_v1(uuid[])', '3892bf5f123f2ec48eca72616b0015c8', array[
  array[$o$       order by (c.provider_id is null) desc, (l.issue_fingerprint is not null) desc, c.classified_at nulls first, l.provider_id$o$,
        $n$       -- F-SCH.14 (13 Nov 2026): new first; then providers whose open scholarship Layer 4 case or pending AI review waits on re-classification,
       -- or not classified within sch_cov.max_age_hours; then providers with an integration issue; then the rest, oldest first
       order by case when c.provider_id is null then 0
                     when c.classified_at < v_now - make_interval(hours => security.pipeline_num_v1('sch_cov.max_age_hours', 36)::int)
                       or exists (select 1 from pipeline.layer4_interventions i where i.provider_id = l.provider_id and i.lane like 'sch%' and i.status = 'awaiting_input')
                       or exists (select 1 from pipeline.scholarship_ai_reviews r where r.provider_id = l.provider_id and r.status = 'pending') then 1
                     when l.issue_fingerprint is not null then 2 else 3 end,
                c.classified_at nulls first, l.provider_id$n$]
], array[1]);
