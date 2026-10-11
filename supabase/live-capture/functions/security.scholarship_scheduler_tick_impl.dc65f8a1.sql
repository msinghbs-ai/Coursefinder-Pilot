CREATE OR REPLACE FUNCTION security.scholarship_scheduler_tick_impl(p_now timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare
  r record;
  v_dispatch jsonb;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if current_user not in('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  for r in
    select s.*
    from pipeline.scholarship_etl_schedules s
    where s.enabled
      and s.next_due_at<=p_now
      and exists(
        select 1
        from pipeline.scholarship_source_qualifications q
        where q.source_key=s.source_key and q.qualification_status='qualified'
      )
    order by s.next_due_at,s.feed
    limit greatest(1,least(coalesce(p_limit,5),10))
    for update skip locked
  loop
    begin
      v_dispatch:=pipeline.svc_pilot_invoke_scholarship_edge(
        jsonb_strip_nulls(jsonb_build_object(
          'mode',r.mode,
          'feed',r.feed,
          'max_records',r.max_records,
          'page_start',r.page_start,
          'page_end',r.page_end
        ))
      );

      update pipeline.scholarship_etl_schedules
      set last_dispatched_at=p_now,
          last_request_id=nullif(v_dispatch->>'request_id','')::bigint,
          last_nonce=nullif(v_dispatch->>'nonce','')::uuid,
          last_dispatch=v_dispatch,
          last_error=null,
          next_due_at=p_now+make_interval(hours=>cadence_hours),
          updated_at=p_now
      where feed=r.feed;

      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'feed',r.feed,'status','dispatched','request_id',v_dispatch->>'request_id',
        'next_due_at',p_now+make_interval(hours=>r.cadence_hours)
      ));
      v_count:=v_count+1;
    exception when others then
      update pipeline.scholarship_etl_schedules
      set last_error=sqlerrm,next_due_at=p_now+interval '1 hour',updated_at=p_now
      where feed=r.feed;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('feed',r.feed,'status','failed','error',sqlerrm));
    end;
  end loop;

  return jsonb_build_object('ok',true,'dispatched_count',v_count,'results',v_results);
end $function$
