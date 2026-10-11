CREATE OR REPLACE FUNCTION admin_api.scholarship_runtime_settings_write(p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'pipeline', 'auth'
AS $function$
declare v_rank integer; v_uid uuid:=auth.uid(); v_country text:=upper(coalesce(nullif(p_patch->>'country_code',''),'AU')); v_row pipeline.scholarship_runtime_settings;
begin
 if v_uid is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
 insert into pipeline.scholarship_runtime_settings(country_code,enabled,detail_batch_limit,auto_dispatch,catalogue_refresh_hours,detail_refresh_hours,updated_by,updated_at,metadata)
 values(v_country,coalesce((p_patch->>'enabled')::boolean,true),least(greatest(coalesce(nullif(p_patch->>'detail_batch_limit','')::integer,25),1),100),coalesce((p_patch->>'auto_dispatch')::boolean,true),least(greatest(coalesce(nullif(p_patch->>'catalogue_refresh_hours','')::integer,168),1),2160),least(greatest(coalesce(nullif(p_patch->>'detail_refresh_hours','')::integer,168),1),2160),v_uid,now(),jsonb_build_object('international_only',true,'publication_authorised',false,'route_mode','managed','change_control_ref','CF-166'))
 on conflict(country_code) do update set enabled=excluded.enabled,detail_batch_limit=excluded.detail_batch_limit,auto_dispatch=excluded.auto_dispatch,catalogue_refresh_hours=excluded.catalogue_refresh_hours,detail_refresh_hours=excluded.detail_refresh_hours,updated_by=v_uid,updated_at=now(),metadata=excluded.metadata
 returning * into v_row;
 return to_jsonb(v_row)-'updated_by';
end $function$
