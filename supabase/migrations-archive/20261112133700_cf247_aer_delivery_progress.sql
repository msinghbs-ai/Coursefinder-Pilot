-- CF-247 F-AER.04 AER delivery reported through the existing Data Delivery screen (Platform Admin decision delivery item 6, 11 Nov 2026, SS-017 / Operating Model v1.12:
-- "Report gains, gaps, spend and failures through the existing Data Delivery screen ... Success is sustained, source-backed AER coverage across the eligible catalogue").
-- Guards: G1 (no job added), G2 (no new operational value: windows are the screen's own 24 hours, marked fixed), G3 (no consumer API object read or changed), Decision 260.
-- What: security.data_delivery_aer_progress_v1 NEW (read only): the discovery campaign (providers asked, new and usable sources, no entry page, credits, spare credits today
--   and the spare room now, cost per usable source), machine admission (course reads and country tables or qualification rows: mode, admitted in all and in 24 hours,
--   shadow results, the latest validation, declines by reason), corrected reads (open, refused and replaced in 24 hours), gains in 24 hours (rows made active) and failures
--   (sources that cannot be fetched, reads held as unreadable). public.admin_aer_delivery_progress NEW (Curator and above, the Data Delivery screen's rank): the screen's
--   AER panel reads it on its own, beside the panel's existing read.
-- Why not inside security.data_delivery_v1: measured on live (11 Nov 2026 21:40 AEDT) that read takes 17.3 s cold and 7.1 s warm against the 8 s statement limit of signed-in
--   users (security.data_delivery_aer_v1 alone 5.8 s); this read takes about 0.3 s and is kept out of it, so it adds nothing to that time and shows even when that read is slow.
-- Replaces: nothing (no existing definition is edited).
-- Retires: nothing.
-- Reversal: none needed (read only); the panel's stage shows Not measured without it.

do $g$ begin
  if to_regprocedure('security.aer_discovery_metrics_v1()') is null or to_regprocedure('security.current_role_rank()') is null
     or to_regclass('pipeline.aer_machine_admissions') is null or to_regclass('pipeline.aer_matrix_machine_validations') is null or to_regclass('pipeline.aer_matrix_machine_admissions') is null or to_regclass('pipeline.aer_read_supersessions') is null
  then raise exception 'an object this change reads is missing'; end if;
end $g$;

create or replace function security.data_delivery_aer_progress_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_day timestamptz := now() - interval '24 hours';  -- fixed: the screen's 24-hour window
        v_m jsonb;
begin
  v_m := security.aer_discovery_metrics_v1();
  return jsonb_build_object(
    'campaign', (v_m - 'spare' - 'by_outcome') || jsonb_build_object('spare_room', v_m->'spare'->'room', 'spare_why', v_m->'spare'->>'why',
                  'state', (select c.state from pipeline.aer_discovery_campaigns c order by c.id desc limit 1),
                  'credit_cap', security.pipeline_num_v1('aer.discovery_campaign_credit_cap', 10000)),
    'machine', jsonb_build_object(
      'course', jsonb_build_object('mode', security.pipeline_num_v1('aer.machine_mode', 0),
                  'admitted', (select count(*) from pipeline.aer_machine_admissions a where a.mode = 'admit' and a.outcome = 'admitted' and a.withdrawn_at is null),
                  'admitted_24h', (select count(*) from pipeline.aer_machine_admissions a where a.mode = 'admit' and a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at >= v_day)),
      'matrix', jsonb_build_object('mode', security.pipeline_num_v1('aer.matrix_machine_mode', 0),
                  'admitted', (select count(*) from pipeline.aer_matrix_machine_admissions a where a.mode = 'admit' and a.outcome = 'admitted' and a.withdrawn_at is null),
                  'admitted_24h', (select count(*) from pipeline.aer_matrix_machine_admissions a where a.mode = 'admit' and a.outcome = 'admitted' and a.withdrawn_at is null and a.created_at >= v_day),
                  'providers', (select count(distinct a.provider_id) from pipeline.aer_matrix_machine_admissions a where a.mode = 'admit' and a.outcome = 'admitted' and a.withdrawn_at is null),
                  'shadow', (select count(*) from pipeline.aer_matrix_machine_admissions a where a.mode = 'shadow'),
                  'shadow_would_admit', (select count(*) from pipeline.aer_matrix_machine_admissions a where a.mode = 'shadow' and a.outcome = 'would_admit'),
                  'validation', (select jsonb_build_object('passed', v.passed, 'at', v.validated_at) from pipeline.aer_matrix_machine_validations v order by v.validated_at desc limit 1),
                  'declines', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.r, 'n', z.n) order by z.n desc), '[]'::jsonb)
                                 from (select left(a.reason, 120) r, count(*) n from pipeline.aer_matrix_machine_admissions a where a.outcome = 'declined' and a.created_at >= v_day group by 1 order by 2 desc limit 6) z))),
    'corrected_reads', jsonb_build_object('open', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'requested'),
                  'refused_24h', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'refused' and s.closed_at >= v_day),
                  'replaced_24h', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'superseded' and s.closed_at >= v_day)),
    'gains_24h', jsonb_build_object('course_rows', (select count(*) from catalogue.course_entry_requirements r where r.status = 'active' and r.updated_at >= v_day),
                  'matrix_rows', (select count(*) from catalogue.provider_entry_matrix r where r.status = 'active' and r.updated_at >= v_day),
                  'qualification_rows', (select count(*) from catalogue.provider_qualification_requirements r where r.status = 'active' and r.updated_at >= v_day),
                  'providers_with_new_matrix', (select count(distinct r.provider_id) from catalogue.provider_entry_matrix r where r.status = 'active' and r.updated_at >= v_day)),
    'failures', jsonb_build_object('sources_not_fetched', (select count(*) from pipeline.entry_matrix_sources s where s.status in ('failed', 'robots_disallowed')),
                  'sources_blocked', (select coalesce(jsonb_object_agg(z.e, z.n), '{}'::jsonb) from (select coalesce(s.error, s.status) e, count(*) n from pipeline.entry_matrix_sources s where s.status in ('failed', 'robots_disallowed') group by 1) z),
                  'reads_held_unreadable', (select count(*) from pipeline.entry_matrix_runs r where r.state = 'failed')));
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $f$;
revoke all on function security.data_delivery_aer_progress_v1() from public, anon, authenticated;
comment on function security.data_delivery_aer_progress_v1() is 'CF-247 F-AER.04 (delivery item 6): AER discovery campaign, machine admission, corrected reads, 24-hour gains and failures, for the Data Delivery screen (public.admin_aer_delivery_progress). Read only.';

create or replace function public.admin_aer_delivery_progress()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;  -- fixed: the Data Delivery screen's rank (admin_layer23 data_delivery)
  return security.data_delivery_aer_progress_v1() || jsonb_build_object('counted_at', now());
end $f$;
revoke all on function public.admin_aer_delivery_progress() from public, anon;
grant execute on function public.admin_aer_delivery_progress() to authenticated;
comment on function public.admin_aer_delivery_progress() is 'CF-247 F-AER.04 (delivery item 6): Layer 2/3 › Operations, Data Delivery, AER panel stage 4 (discovery and admission). Curator and above; read only; never part of the consumer API.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.data_delivery_aer_progress_v1', 'Platform', 'Data Delivery: AER discovery, machine admission, corrected reads, gains and failures', 'active', '{}', '20261112133700'),
 ('function', 'public.admin_aer_delivery_progress', 'Platform', 'Data Delivery AER panel, stage 4 read (Curator and above)', 'active', '{}', '20261112133700')
on conflict do nothing;

do $post$ begin
  if (security.data_delivery_aer_progress_v1() ? 'known') then raise exception 'post-check: the progress read fails: %', security.data_delivery_aer_progress_v1()->>'reason'; end if;
  if not has_function_privilege('authenticated', 'public.admin_aer_delivery_progress()', 'execute') then raise exception 'post-check: the screen cannot read progress'; end if;
end $post$;
