-- CF-201 — close stale Scholarship layer2_acquisition_v2 leases; never fabricate success.
update pipeline.jobs
set status='failed',
    completed_at=coalesce(completed_at,now()),
    error_text=trim(both '; ' from concat_ws('; ',nullif(error_text,''),'CF-201 stale Layer 2 Scholarship acquisition lease closed after >12h without terminal result')),
    payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('stale_closed_at',now(),'stale_close_reason','no terminal result after 12h','change_control_ref','CF-201')
where domain='scholarship'
  and job_type='layer2_acquisition_v2'
  and status='running'
  and started_at < now()-interval '12 hours';
comment on column pipeline.jobs.status is 'Operational job state. CF-201 closes only stale Scholarship layer2_acquisition_v2 running leases older than 12h as failed; it never fabricates success and retained Evidence remains authoritative.';
