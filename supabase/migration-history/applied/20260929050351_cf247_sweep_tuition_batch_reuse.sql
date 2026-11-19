do $p$
declare v text; o text; n text;
begin
  v:=pg_get_functiondef('public.svc_coverage_tuition_handoff_record(uuid,text,text,int)'::regprocedure);
  o:=$o$  select id into v_batch from pipeline.layer2_run_batches where idempotency_key=v_key;
  if v_batch is null then$o$;
  n:=$n$  -- one open batch for the sweep profile (the platform allows one active batch per profile); reused across days
  select b.id into v_batch from pipeline.layer2_run_batches b join pipeline.layer2_source_profiles p on p.id=b.profile_id
   where p.profile_key='au-coverage-sweep-course-pages' and b.status in ('queued','running') order by b.created_at limit 1 for update of b;
  if v_batch is null then
    perform pg_advisory_xact_lock(hashtext('coverage-sweep-l3-batch'));
    select b.id into v_batch from pipeline.layer2_run_batches b join pipeline.layer2_source_profiles p on p.id=b.profile_id
     where p.profile_key='au-coverage-sweep-course-pages' and b.status in ('queued','running') order by b.created_at limit 1;
  end if;
  if v_batch is null then$n$;
  if position(o in v)=0 then raise exception 'anchor not found'; end if;
  execute replace(v,o,n);
end $p$;
