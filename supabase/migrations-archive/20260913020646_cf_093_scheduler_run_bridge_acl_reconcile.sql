begin;

-- Reconcile repository source with the already-applied Pilot runtime ACL state.
-- Legacy v1 workflow Run now remains retired from authenticated browser use.
revoke all on function public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.scheduler_workflow_run_now_v1(text,text,text,uuid,text,text)
  to service_role;

revoke all on function security.scheduler_workflow_run_now_v1_browser_bridge(text,text,text,uuid,text,text)
  from public, anon, authenticated, service_role;

-- The Preview-token-bound v2 path is the only authenticated browser execution path.
revoke all on function public.scheduler_workflow_run_now_v2(uuid,text,text,text,uuid,text,text)
  from public, anon;
grant execute on function public.scheduler_workflow_run_now_v2(uuid,text,text,text,uuid,text,text)
  to authenticated, service_role;

revoke all on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)
  from public, anon;
grant execute on function security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)
  to authenticated, service_role;

commit;
