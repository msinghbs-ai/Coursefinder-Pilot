revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) from public,anon;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text) to authenticated,service_role;
