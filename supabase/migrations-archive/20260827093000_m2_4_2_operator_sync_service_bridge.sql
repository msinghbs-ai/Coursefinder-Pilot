-- CF-CHG-20260827-044 / M2.4.2 A8
-- Browser execution is via authenticated Edge function layer2-sync-control.
drop function if exists public.layer2_operator_sync(text,uuid,integer);
create or replace function public.layer2_operator_sync_service(p_actor uuid,p_action text,p_profile_id uuid,p_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','security','pipeline','catalogue','ref'
as $function$
declare
  v_rank integer:=0; v_profile pipeline.layer2_source_profiles%rowtype; v_source pipeline.sources%rowtype;
  v_country text; v_provider_name text; v_catalogue integer:=0; v_queueable integer:=0; v_active uuid;
  v_batch_size integer:=10; v_items jsonb; v_batch uuid; v_req bigint; v_limit integer;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  select * into v_profile from pipeline.layer2_source_profiles where id=p_profile_id;
  if not found then raise exception 'profile not found' using errcode='22023'; end if;
  select * into v_source from pipeline.sources where id=v_profile.source_id;
  select c.iso_alpha2::text into v_country from ref.countries c where c.id=v_source.country_id;
  select p.canonical_name into v_provider_name from catalogue.providers p where p.id=v_source.provider_id;
  if v_profile.domain='course_facts' and v_source.provider_id is not null then
    select count(*) into v_catalogue from catalogue.courses c where c.provider_id=v_source.provider_id;
    select count(distinct d.course_id) into v_queueable from pipeline.layer2_course_discovery_candidates d where d.source_profile_version_id=v_profile.current_version_id and d.selected and d.discovered_url is not null;
  end if;
  select b.id into v_active from pipeline.layer2_run_batches b where b.profile_id=p_profile_id and b.status in ('queued','running','partial') order by b.created_at desc limit 1;
  select least(greatest(coalesce(ep.batch_size,10),1),100) into v_batch_size from pipeline.layer2_execution_policies ep where ep.profile_id=p_profile_id;
  v_batch_size:=coalesce(v_batch_size,10); v_limit:=least(greatest(coalesce(p_limit,v_batch_size),1),100);
  if p_action='preview' then return jsonb_build_object('ok',true,'profile_id',v_profile.id,'profile_key',v_profile.profile_key,'country_code',v_country,'provider_name',coalesce(v_provider_name,v_source.label),'source_label',v_source.label,'domain',v_profile.domain,'enabled',v_profile.enabled,'paused',v_profile.paused,'current_version_id',v_profile.current_version_id,'catalogue_count',v_catalogue,'queueable_count',v_queueable,'source_limited_count',greatest(v_catalogue-v_queueable,0),'active_batch_id',v_active,'batch_size',v_batch_size,'action',case when not v_profile.enabled or v_profile.paused then 'unavailable' when v_active is not null then 'running' when v_queueable=0 then 'discover' else 'sync' end); end if;
  if not v_profile.enabled or v_profile.paused then raise exception 'profile not executable' using errcode='22023'; end if;
  if upper(coalesce(v_country,''))='NZ' and v_profile.domain='course_facts' then raise exception 'NZ Layer 2 Course enrichment is deferred' using errcode='22023'; end if;
  if p_action='discover' then return security.layer2_discovery_dispatch(p_profile_id,least(v_limit,50)); end if;
  if p_action='sync' then
    if v_active is not null then return jsonb_build_object('ok',true,'status','already_running','batch_id',v_active); end if;
    if v_profile.domain<>'course_facts' then raise exception 'operator sync currently limited to authorised course_facts profiles' using errcode='22023'; end if;
    if v_queueable=0 then return security.layer2_discovery_dispatch(p_profile_id,least(v_limit,50)) || jsonb_build_object('status','discovery_started'); end if;
    with latest as (select distinct on (d.course_id) d.course_id,d.discovered_url from pipeline.layer2_course_discovery_candidates d where d.source_profile_version_id=v_profile.current_version_id and d.selected and d.discovered_url is not null order by d.course_id,d.created_at desc), chosen as (select l.course_id,l.discovered_url from latest l left join pipeline.layer2_run_items i on i.entity_id=l.course_id and i.entity_type='course' left join pipeline.layer2_run_batches b on b.id=i.batch_id and b.profile_id=p_profile_id and b.status in ('queued','running','partial') where b.id is null order by l.course_id limit v_limit) select jsonb_agg(jsonb_build_object('entity_type','course','entity_id',course_id,'source_url',discovered_url)) into v_items from chosen;
    if v_items is null or jsonb_array_length(v_items)=0 then return jsonb_build_object('ok',true,'status','nothing_queueable','queueable_count',v_queueable); end if;
    v_batch:=public.layer2_run_batch_create(p_profile_id,'manual',p_actor,v_items); v_req:=public.layer2_run_batch_dispatch(v_batch);
    return jsonb_build_object('ok',true,'status','started','batch_id',v_batch,'dispatch_request_id',v_req,'target_count',jsonb_array_length(v_items));
  end if;
  raise exception 'unsupported action' using errcode='22023';
end
$function$;
revoke all on function public.layer2_operator_sync_service(uuid,text,uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_operator_sync_service(uuid,text,uuid,integer) to service_role;