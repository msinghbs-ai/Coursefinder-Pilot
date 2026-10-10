CREATE OR REPLACE FUNCTION pipeline.trg_layer1_seen_departures()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_res jsonb;
begin
  if new.status='completed' and old.status is distinct from 'completed' and new.mode='apply'
     and exists (select 1 from pipeline.layer1_source_operations o where o.source_id=new.source_id and o.seen_tracking_since is not null) then
    begin
      v_res:=security.layer1_seen_departures_v1(new.id,false,null);
    exception when others then
      v_res:=jsonb_build_object('status','failed','error',left(sqlerrm,300));
    end;
    update pipeline.layer1_run_queue set result=coalesce(result,'{}'::jsonb)||jsonb_build_object('departures',v_res) where id=new.id;
  end if;
  return null;
end $function$
