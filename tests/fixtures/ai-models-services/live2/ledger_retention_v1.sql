CREATE OR REPLACE FUNCTION security.ledger_retention_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n_ledger int; n_zy int; n_h int; n_ui int;
begin
  delete from pipeline.mode_outcome_ledger where run_at < now() - make_interval(days => security.pipeline_num_v1('retention.mode_outcome_ledger_days', 90)::int);
  get diagnostics n_ledger = row_count;
  delete from pipeline.zero_yield_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.zero_yield_snapshots_days', 90)::int);
  get diagnostics n_zy = row_count;
  delete from pipeline.health_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.health_snapshots_days', 90)::int);
  get diagnostics n_h = row_count;
  delete from pipeline.ui_error_log where at < now() - make_interval(days => security.pipeline_num_v1('retention.ui_error_log_days', 90)::int);
  get diagnostics n_ui = row_count;
  return jsonb_build_object('mode_outcome_ledger', n_ledger, 'zero_yield_snapshots', n_zy, 'health_snapshots', n_h, 'ui_error_log', n_ui);
end $function$
