-- M2.4.2 A11 — expose full Layer 1 catalogue to Layer 2 and introduce bounded qualification waves.
-- Deployed as migration m2_4_2_a11_layer1_catalogue_scale_scope.
-- No canonical, Search or Publication mutation is authorised by qualification-wave creation.

begin;

create table if not exists pipeline.layer2_scale_qualification_runs (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references ref.countries(id),
  scope_type text not null check (scope_type in ('country','state','university')),
  scope_id uuid,
  requested_by uuid,
  wave_size integer not null check (wave_size between 1 and 10),
  sample_size integer not null check (sample_size between 1 and 20),
  status text not null default 'planned' check (status in ('planned','running','completed','partial','blocked','cancelled')),
  provider_count integer not null default 0,
  course_sample_count integer not null default 0,
  result_summary jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260827-044',
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists pipeline.layer2_scale_qualification_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references pipeline.layer2_scale_qualification_runs(id) on delete cascade,
  provider_id uuid not null references catalogue.providers(id),
  course_id uuid not null references catalogue.courses(id),
  sample_rank integer not null,
  selection_reason text not null default 'layer1_gap_sample',
  status text not null default 'selected' check (status in ('selected','qualifying','qualified_l2','layer3_required','layer4_required','source_limited','blocked')),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  outcome jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(run_id,provider_id,course_id),
  unique(run_id,provider_id,sample_rank)
);

create index if not exists layer2_scale_qualification_runs_scope_idx
  on pipeline.layer2_scale_qualification_runs(country_id,scope_type,scope_id,created_at desc);
create index if not exists layer2_scale_qualification_items_run_idx
  on pipeline.layer2_scale_qualification_items(run_id,provider_id,status,sample_rank);

alter table pipeline.layer2_scale_qualification_runs enable row level security;
alter table pipeline.layer2_scale_qualification_items enable row level security;
revoke all on pipeline.layer2_scale_qualification_runs,pipeline.layer2_scale_qualification_items from public,anon,authenticated;

create or replace function public.layer2_scope_countries_service(p_actor uuid)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','catalogue','ref','security'
as $$
declare v_rank integer:=0; v_items jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

 select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'providers',x.providers,'courses',x.courses) order by x.name),'[]'::jsonb)
 into v_items
 from (
   select co.iso_alpha2::text code,co.name,count(distinct p.id)::integer providers,count(distinct c.id)::integer courses
   from catalogue.providers p
   join catalogue.courses c on c.provider_id=p.id
   join ref.countries co on co.id=p.country_id
   group by co.iso_alpha2,co.name
 ) x;
 return jsonb_build_object('countries',v_items,'scope_source','layer1_catalogue');
end $$;

create or replace function public.layer2_scope_options_page_service(
  p_actor uuid,p_country_code text,p_kind text,p_state_id uuid default null,p_query text default null,p_limit integer default 10,p_offset integer default 0
) returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','security'
as $$
declare
  v_rank integer:=0;
  v_kind text:=lower(coalesce(nullif(trim(p_kind),''),''));
  v_country text:=upper(coalesce(nullif(trim(p_country_code),''),''));
  v_query text:=lower(nullif(trim(coalesce(p_query,'')),''));
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if v_country='' then raise exception 'country required' using errcode='22023'; end if;

 if v_kind='state' then
   with q as (
     select sd.id::text value,sd.name label,sd.code meta
     from ref.subdivisions sd
     join ref.countries co on co.id=sd.country_id
     where upper(co.iso_alpha2::text)=v_country
       and (v_query is null or lower(sd.name||' '||coalesce(sd.code,'')) like '%'||v_query||'%')
       and exists (
         select 1
         from catalogue.providers p
         join catalogue.courses c on c.provider_id=p.id
         where p.country_id=co.id
           and (
             p.subdivision_id=sd.id
             or exists (
               select 1 from catalogue.course_campuses cc
               join catalogue.campuses cam on cam.id=cc.campus_id
               where cc.course_id=c.id and cam.subdivision_id=sd.id
             )
           )
       )
   ), n as (select count(*) total from q),
   page as (select * from q order by lower(label),value limit v_limit offset v_offset)
   select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
          coalesce((select total from n),0)
   into v_items,v_total;
 elsif v_kind='university' then
   with q as (
     select p.id::text value,p.canonical_name label,
       case when exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         left join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       ) then 'Qualified for Layer 2' else 'Needs Layer 2 qualification' end meta
     from catalogue.providers p
     join ref.countries co on co.id=p.country_id
     where upper(co.iso_alpha2::text)=v_country
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         p_state_id is null or p.subdivision_id=p_state_id
         or exists(
           select 1 from catalogue.courses c
           join catalogue.course_campuses cc on cc.course_id=c.id
           join catalogue.campuses cam on cam.id=cc.campus_id
           where c.provider_id=p.id and cam.subdivision_id=p_state_id
         )
       )
       and (v_query is null or lower(coalesce(p.canonical_name,'')||' '||coalesce(p.display_name,'')) like '%'||v_query||'%')
   ), n as (select count(*) total from q),
   page as (select * from q order by lower(label),value limit v_limit offset v_offset)
   select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
          coalesce((select total from n),0)
   into v_items,v_total;
 else
   raise exception 'unsupported scope option kind' using errcode='22023';
 end if;

 return jsonb_build_object('items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,'has_more',(v_offset+jsonb_array_length(v_items))<v_total,'scope_source','layer1_catalogue');
end $$;

create or replace function public.layer2_scale_scope_service(
  p_actor uuid,p_action text,p_country_code text,p_scope_type text default 'country',p_scope_id uuid default null,p_wave_size integer default 5,p_sample_size integer default 10
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref','security'
as $$
declare
  v_rank integer:=0;
  v_country_id uuid;
  v_scope text:=lower(coalesce(nullif(trim(p_scope_type),''),'country'));
  v_wave integer:=least(greatest(coalesce(p_wave_size,5),1),10);
  v_sample integer:=least(greatest(coalesce(p_sample_size,10),1),20);
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
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       ) qualified,
       (select count(*) from catalogue.courses c where c.provider_id=p.id)::integer courses
     from providers p
   )
   select jsonb_build_object(
     'ok',true,'scope_source','layer1_catalogue','country_code',upper(trim(p_country_code)),
     'scope_type',v_scope,'scope_id',p_scope_id,'university_count',count(*)::integer,
     'catalogue_count',coalesce(sum(courses),0)::integer,
     'qualified_provider_count',count(*) filter(where qualified)::integer,
     'qualification_required_count',count(*) filter(where not qualified)::integer,
     'executable_course_count',coalesce(sum(courses) filter(where qualified),0)::integer,
     'qualification_course_count',coalesce(sum(courses) filter(where not qualified),0)::integer,
     'queueable_count',(
       select count(distinct c.id)::integer from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts' and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and (nullif(c.course_url,'') is not null or exists(
         select 1 from pipeline.layer2_course_discovery_candidates dc
         join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
         join pipeline.sources s2 on s2.id=lp2.source_id
         where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
       ))
     ),
     'needs_discovery_count',(
       select count(distinct c.id)::integer from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts' and lp.enabled and not lp.paused and pv.validation_status='valid'
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
       where b.status in ('queued','running') and s.provider_id in (select id from providers)
     ),
     'recommended_action',case when count(*) filter(where not qualified)>0 then 'qualify_wave' else 'sync' end,
     'wave_size',v_wave,'sample_size',v_sample
   ) into v_payload from status;
   return v_payload;
 end if;

 if p_action='qualify_wave' then
   insert into pipeline.layer2_scale_qualification_runs(country_id,scope_type,scope_id,requested_by,wave_size,sample_size,status,change_control_ref)
   values(v_country_id,v_scope,p_scope_id,p_actor,v_wave,v_sample,'planned','CF-CHG-20260827-044') returning id into v_run;

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
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
     order by course_count desc,p.canonical_name,p.id
     limit v_wave
   ), samples as (
     select e.id provider_id,c.id course_id,
       row_number() over(partition by e.id order by case when nullif(c.course_url,'') is null then 0 else 1 end,c.stable_key,c.id)::integer sample_rank
     from eligible e join catalogue.courses c on c.provider_id=e.id
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
     set status='completed',completed_at=now(),result_summary=jsonb_build_object('outcome','nothing_to_qualify')
     where id=v_run;
   else
     update pipeline.layer2_scale_qualification_runs
     set provider_count=v_provider_count,course_sample_count=v_course_count,
       result_summary=jsonb_build_object(
         'outcome','sample_selected','next_step','deterministic_source_qualification',
         'identity_safety_required',true,'canonical_mutation_authorised',false,
         'search_mutation_authorised',false,'publication_mutation_authorised',false
       )
     where id=v_run;
   end if;

   return jsonb_build_object(
     'ok',true,'status',case when v_provider_count=0 then 'nothing_to_qualify' else 'qualification_wave_planned' end,
     'qualification_run_id',v_run,'provider_count',v_provider_count,'course_sample_count',v_course_count,
     'wave_size',v_wave,'sample_size',v_sample,'canonical_mutation_authorised',false,
     'search_mutation_authorised',false,'publication_mutation_authorised',false
   );
 end if;

 raise exception 'unsupported action' using errcode='22023';
end $$;

revoke all on function public.layer2_scope_countries_service(uuid) from public,anon,authenticated;
revoke all on function public.layer2_scope_options_page_service(uuid,text,text,uuid,text,integer,integer) from public,anon,authenticated;
revoke all on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.layer2_scope_countries_service(uuid) to service_role;
grant execute on function public.layer2_scope_options_page_service(uuid,text,text,uuid,text,integer,integer) to service_role;
grant execute on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) to service_role;

commit;
