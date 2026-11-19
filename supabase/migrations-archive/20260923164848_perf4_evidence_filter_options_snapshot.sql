-- PERF-4: Evidence screen dropdown options served from a snapshot.
-- security.admin_evidence_filter_options() made five full passes over ~32k Evidence
-- items (one calling a helper per row) on every screen open: 6.5 s cold, and together
-- with the list read it exceeded the 8 s limit ("canceling statement due to statement
-- timeout" with an empty Evidence screen). The options change rarely.
-- Same pattern as PERF-1: service-only compute, refreshed every 15 minutes, read keeps
-- its name, role check and output, and falls back to live if the snapshot is over
-- 60 minutes old. The compute body is generated from the live definition by guarded
-- substitution (sign-in checks removed only), so the options are identical.

alter table security.admin_summary_snapshots drop constraint if exists admin_summary_snapshots_snapshot_key_check;
alter table security.admin_summary_snapshots add constraint admin_summary_snapshots_snapshot_key_check
  check (snapshot_key in ('dashboard','layer_status_summary','evidence_filters'));

do $mig$
declare d text;
  a1 text := 'CREATE OR REPLACE FUNCTION security.admin_evidence_filter_options()';
  b1 text := 'CREATE OR REPLACE FUNCTION security.admin_evidence_filter_options_compute()';
  a2 text := E'  if auth.uid() is null then raise exception ''authentication required'' using errcode=''42501''; end if;\n  select security.current_role_rank() into v_rank;\n  if v_rank<3 then raise exception ''curator role required'' using errcode=''42501''; end if;\n';
begin
  if to_regprocedure('security.admin_evidence_filter_options_compute()') is not null then return; end if;
  d := pg_get_functiondef('security.admin_evidence_filter_options()'::regprocedure);
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  execute replace(replace(d,a1,b1),a2,'');
end $mig$;

create or replace function security.admin_evidence_filter_options_refresh()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security'
as $function$
declare v_caller text; t timestamptz; v jsonb; ms int;
begin
  v_caller := coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  t := clock_timestamp(); v := security.admin_evidence_filter_options_compute(); ms := round(extract(epoch from clock_timestamp()-t)*1000);
  insert into security.admin_summary_snapshots(snapshot_key,payload,computed_at,compute_ms) values('evidence_filters',v,now(),ms)
  on conflict(snapshot_key) do update set payload=excluded.payload, computed_at=excluded.computed_at, compute_ms=excluded.compute_ms;
  return jsonb_build_object('ok',true,'compute_ms',ms);
end $function$;

create or replace function security.admin_evidence_filter_options()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','auth'
as $function$
declare v_rank integer:=0; v_payload jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  select payload into v_payload from security.admin_summary_snapshots
  where snapshot_key='evidence_filters' and computed_at > now() - interval '60 minutes';
  if v_payload is not null then return v_payload; end if;
  return security.admin_evidence_filter_options_compute();
end $function$;

revoke all on function security.admin_evidence_filter_options_compute() from public, anon, authenticated;
revoke all on function security.admin_evidence_filter_options_refresh() from public, anon, authenticated;
grant execute on function security.admin_evidence_filter_options_compute() to service_role;
grant execute on function security.admin_evidence_filter_options_refresh() to service_role;

select cron.unschedule(jobid) from cron.job where jobname='evidence-filter-options-refresh';
select cron.schedule('evidence-filter-options-refresh', '4-59/15 * * * *', $cron$select security.admin_evidence_filter_options_refresh();$cron$);

select security.admin_evidence_filter_options_refresh();
