revoke all on function public.ui_course_field_states(uuid) from authenticated,anon,public;
grant execute on function public.ui_course_field_states(uuid) to service_role;
revoke all on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) from authenticated,anon,public;
grant execute on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) to service_role;

create or replace function security.layer4_course_scalar_resolve_impl(p_actor uuid,p_course_id uuid,p_field_code text,p_value jsonb,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','catalogue','pipeline','auth'
as $$
declare
  v_rank int:=0; v_prior jsonb; v_new jsonb:=p_value; v_prev_id uuid; v_resolution_id uuid; v_text text; v_duration numeric; v_unit text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<3 then raise exception 'curator role required for Layer 4 resolution' using errcode='42501'; end if;
  if not exists(select 1 from catalogue.courses where id=p_course_id) then raise exception 'course not found' using errcode='22023'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or length(trim(p_reason))<5 then raise exception 'resolution reason is required' using errcode='22023'; end if;
  if p_field_code not in ('course_description','official_course_url','delivery_mode','duration') then raise exception 'field is not enabled for scalar Layer 4 editing' using errcode='22023'; end if;
  select id into v_prev_id from pipeline.layer4_course_field_resolutions where course_id=p_course_id and field_code=p_field_code and status='applied' order by created_at desc limit 1;
  if p_field_code='course_description' then
    select to_jsonb(c.description) into v_prior from catalogue.courses c where c.id=p_course_id; v_text:=p_value #>> '{}';
    if nullif(trim(v_text),'') is null then raise exception 'description cannot be empty' using errcode='22023'; end if;
    update catalogue.courses set description=v_text,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='delivery_mode' then
    select to_jsonb(c.delivery_mode) into v_prior from catalogue.courses c where c.id=p_course_id; v_text:=p_value #>> '{}';
    if nullif(trim(v_text),'') is null then raise exception 'delivery mode cannot be empty' using errcode='22023'; end if;
    update catalogue.courses set delivery_mode=v_text,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='duration' then
    select jsonb_build_object('value',c.duration_value,'unit',c.duration_unit) into v_prior from catalogue.courses c where c.id=p_course_id;
    v_duration:=nullif(p_value->>'value','')::numeric; v_unit:=nullif(trim(p_value->>'unit'),'');
    if v_duration is null or v_duration<=0 or v_unit is null then raise exception 'duration requires positive value and unit' using errcode='22023'; end if;
    update catalogue.courses set duration_value=v_duration,duration_unit=v_unit,updated_at=now(),last_verified_at=now() where id=p_course_id;
  elsif p_field_code='official_course_url' then
    select to_jsonb(cl.url) into v_prior from catalogue.course_links cl where cl.course_id=p_course_id and cl.link_type='official_course' and coalesce(cl.status,'active')='active' order by (cl.audience='international') desc,cl.last_verified_at desc nulls last,cl.created_at desc limit 1;
    v_text:=p_value #>> '{}'; if v_text !~* '^https?://[^[:space:]]+$' then raise exception 'official Course URL must be http/https' using errcode='22023'; end if;
    update catalogue.course_links set status='superseded',valid_to=current_date,updated_at=now() where course_id=p_course_id and link_type='official_course' and coalesce(status,'active')='active';
    insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,valid_from,confidence,last_verified_at) values(p_course_id,'official_course',v_text,'international','Layer 4 human resolution',true,'active',current_date,1,now());
  end if;
  if v_prev_id is not null then update pipeline.layer4_course_field_resolutions set status='superseded' where id=v_prev_id; end if;
  insert into pipeline.layer4_course_field_resolutions(course_id,field_code,prior_value,resolved_value,resolution_reason,actor_id,supersedes_id) values(p_course_id,p_field_code,v_prior,v_new,trim(p_reason),p_actor,v_prev_id) returning id into v_resolution_id;
  return jsonb_build_object('ok',true,'resolution_id',v_resolution_id,'course_id',p_course_id,'field_code',p_field_code,'resolved_value',v_new,'layer',4,'publication_changed',false,'search_changed',false);
end$$;
revoke all on function security.layer4_course_scalar_resolve_impl(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function security.layer4_course_scalar_resolve_impl(uuid,uuid,text,jsonb,text) to service_role;

create or replace function public.layer4_course_scalar_resolve_service(p_actor uuid,p_course_id uuid,p_field_code text,p_value jsonb,p_reason text)
returns jsonb
language sql
security definer
set search_path='pg_catalog','security'
as $$ select security.layer4_course_scalar_resolve_impl(p_actor,p_course_id,p_field_code,p_value,p_reason) $$;
revoke all on function public.layer4_course_scalar_resolve_service(uuid,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.layer4_course_scalar_resolve_service(uuid,uuid,text,jsonb,text) to service_role;
