begin;

-- CF-CHG-20260910-093 corrective follow-up.
-- Public scheduler workflow wrappers are SECURITY INVOKER, so authenticated callers
-- require EXECUTE on the independently rank-gated private bridge functions.
-- This mirrors the accepted CF-092 browser-proxy call chain; anon/public remain denied.

grant execute on function security.scheduler_workflow_scope_options_v1_browser_bridge(text,text,uuid,text,integer,integer) to authenticated;
grant execute on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) to authenticated;
grant execute on function security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text) to authenticated;

revoke all on function security.scheduler_workflow_scope_options_v1_browser_bridge(text,text,uuid,text,integer,integer) from anon;
revoke all on function security.scheduler_workflow_preview_v1_browser_bridge(text,text,text,uuid) from anon;
revoke all on function security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text) from anon;

commit;
