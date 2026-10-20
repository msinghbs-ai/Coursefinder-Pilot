CREATE OR REPLACE FUNCTION public.layer2_scale_scope_service(p_actor uuid, p_action text, p_country_code text, p_scope_type text DEFAULT 'country'::text, p_scope_id uuid DEFAULT NULL::uuid, p_wave_size integer DEFAULT 0, p_sample_size integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_rank integer:=0;
  v_country_id uuid;
  v_scope text:=lower(coalesce(nullif(trim(p_scope_type),''),'country'));
  v_policy pipeline.layer2_execution_policy%rowtype;
  v_wave integer;
  v_sample integer;
  v_retry_hours integer;
  v_run uuid;
  v_provider_count integer:=0;
  v_course_count integer:=0;
  v_payload jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if v_scope not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default' and enabled;
 if not found then raise exception 'Layer 2 execution policy missing' using errcode='55000'; end if;
 v_wave:=least(greatest(coalesce(nullif(p_wave_size,0),v_policy.qualification_provider_wave_size),1),v_policy.qualification_provider_wave_max);
 v_sample:=least(greatest(coalesce(nullif(p_sample_size,0),v_policy.qualification_sample_size),1),50);
 v_retry_hours:=v_policy.qualification_retry_hours;

 select id into v_country_id from ref.countries where upper(iso_alpha2::text)=upper(trim(p_country_code)) limit 1;
 if v_country_id is null then raise exception 'country not found' using errcode='22023'; end if;

 if p_action='preview' then
   with providers as (
     select p.id
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
   ), status as (
     select p.id,
       exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       ) qualified,
       (select count(*) from catalogue.courses c where c.provider_id=p.id)::integer courses
     from providers p
   )
   select jsonb_build_object(
     'ok',true,'scope_source','layer1_catalogue','country_code',upper(trim(p_country_code)),
     'scope_type',v_scope,'scope_id',p_scope_id,
     'university_count',count(*)::integer,
     'catalogue_count',coalesce(sum(courses),0)::integer,
     'qualified_provider_count',count(*) filter(where qualified)::integer,
     'qualification_required_count',count(*) filter(where not qualified)::integer,
     'executable_course_count',coalesce(sum(courses) filter(where qualified),0)::integer,
     'qualification_course_count',coalesce(sum(courses) filter(where not qualified),0)::integer,
     'queueable_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and (
         nullif(c.course_url,'') is not null
         or exists(
           select 1 from pipeline.layer2_course_discovery_candidates dc
           join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
           join pipeline.sources s2 on s2.id=lp2.source_id
           where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
         )
       )
     ),
     'needs_discovery_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and nullif(c.course_url,'') is null
       and not exists(
         select 1 from pipeline.layer2_course_discovery_candidates dc
         join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
         join pipeline.sources s2 on s2.id=lp2.source_id
         where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
       )
     ),
     'active_run_count',(
       select count(*)::integer from pipeline.layer2_run_batches b
       join pipeline.layer2_source_profiles lp on lp.id=b.profile_id
       join pipeline.sources s on s.id=lp.source_id
       where b.status in ('queued','running')
         and s.provider_id in (select id from providers)
     ),
     'recommended_action',case when count(*) filter(where not qualified)>0 then 'qualify_wave' else 'sync' end,
     'wave_size',v_wave,'sample_size',v_sample
   ) into v_payload
   from status;
   return v_payload;
 end if;

 if p_action='qualify_wave' then
   insert into pipeline.layer2_scale_qualification_runs(
     country_id,scope_type,scope_id,requested_by,wave_size,sample_size,status,change_control_ref
   ) values(v_country_id,v_scope,p_scope_id,p_actor,v_wave,v_sample,'planned','CF-CHG-20260830-048')
   returning id into v_run;

   with eligible as (
     select p.id,p.canonical_name,(select count(*) from catalogue.courses c where c.provider_id=p.id) course_count
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
       and not exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi
         join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
         where qi.provider_id=p.id
           and qr.status in ('planned','running')
       )
       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi2
         join pipeline.layer2_scale_qualification_runs qr2 on qr2.id=qi2.run_id
         where qi2.provider_id=p.id
           and qi2.status in ('source_pattern_candidate','source_limited','blocked','layer3_required','layer4_required')
           and qr2.created_at > now()-make_interval(hours=>v_retry_hours)
       )
     order by course_count desc,p.canonical_name,p.id
     limit v_wave
   ), samples as (
     select e.id provider_id,c.id course_id,
            row_number() over(partition by e.id order by
              case when nullif(c.course_url,'') is null then 0 else 1 end,
              c.stable_key,c.id
            )::integer sample_rank
     from eligible e
     join catalogue.courses c on c.provider_id=e.id
   )
   insert into pipeline.layer2_scale_qualification_items(run_id,provider_id,course_id,sample_rank,selection_reason)
   select v_run,provider_id,course_id,sample_rank,
          case when sample_rank<=greatest(1,least(2,v_sample)) then 'gap_first_control_mix' else 'layer1_gap_sample' end
   from samples where sample_rank<=v_sample
   order by provider_id,sample_rank;

   select count(distinct provider_id),count(*) into v_provider_count,v_course_count
   from pipeline.layer2_scale_qualification_items where run_id=v_run;

   if v_provider_count=0 then
     update pipeline.layer2_scale_qualification_runs
     set status='completed',completed_at=now(),result_summary=jsonb_build_object('outcome','nothing_to_qualify','background_scheduler_authorized',true,'auto_progress_scope',true,'qualification_identity_sample_only',true,'route_mode',v_policy.route_mode,'production_target_wave_size',v_policy.production_target_wave_size)
     where id=v_run;
   else
     update pipeline.layer2_scale_qualification_runs
     set provider_count=v_provider_count,course_sample_count=v_course_count,
         result_summary=jsonb_build_object(
           'outcome','sample_selected',
           'next_step','deterministic_source_qualification',
           'identity_safety_required',true,
           'background_scheduler_authorized',true,
           'auto_progress_scope',true,
           'qualification_identity_sample_only',true,
           'route_mode',v_policy.route_mode,
           'production_target_wave_size',v_policy.production_target_wave_size,
           'canonical_mutation_authorised',false,
           'search_mutation_authorised',false,
           'publication_mutation_authorised',false
         )
     where id=v_run;
   end if;

   return jsonb_build_object(
     'ok',true,'status',case when v_provider_count=0 then 'nothing_to_qualify' else 'qualification_wave_planned' end,
     'qualification_run_id',v_run,'provider_count',v_provider_count,'course_sample_count',v_course_count,
     'wave_size',v_wave,'sample_size',v_sample,'background_scheduled',true,'identity_sample_only',true,
     'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
   );
 end if;

 raise exception 'unsupported action' using errcode='22023';
end $function$
