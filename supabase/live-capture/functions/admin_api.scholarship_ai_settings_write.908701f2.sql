CREATE OR REPLACE FUNCTION admin_api.scholarship_ai_settings_write(p_country_code text, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_rank int:=security.scholarship_ai_role_rank(); v_actor uuid:=auth.uid(); v_country text:=upper(p_country_code); v_p uuid; v_row pipeline.scholarship_ai_settings%rowtype;
begin
 if v_rank<5 then raise exception 'PIM Admin role required' using errcode='42501'; end if;
 if p_patch ? 'default_profile_id' then v_p:=nullif(p_patch->>'default_profile_id','')::uuid; end if;
 insert into pipeline.scholarship_ai_settings(country_code) values(v_country) on conflict do nothing;
 update pipeline.scholarship_ai_settings set
   enabled=case when p_patch?'enabled' then (p_patch->>'enabled')::boolean else enabled end,
   schedule_on_change=case when p_patch?'schedule_on_change' then (p_patch->>'schedule_on_change')::boolean else schedule_on_change end,
   default_task_class=coalesce(nullif(p_patch->>'default_task_class',''),default_task_class),
   default_profile_id=case when p_patch?'default_profile_id' then v_p else default_profile_id end,
   max_records_per_run=case when p_patch?'max_records_per_run' then least(greatest((p_patch->>'max_records_per_run')::int,1),200) else max_records_per_run end,
   daily_budget_usd=case when p_patch?'daily_budget_usd' then greatest((p_patch->>'daily_budget_usd')::numeric,0) else daily_budget_usd end,
   schedule_actor=case when coalesce((p_patch->>'schedule_on_change')::boolean,schedule_on_change) then v_actor else null end,
   updated_by=v_actor,updated_at=now(),metadata=metadata||jsonb_build_object('change_control_ref','CF-CHG-20260906-221')
 where country_code=v_country returning * into v_row;
 return to_jsonb(v_row)-'schedule_actor'-'updated_by';
end $function$
