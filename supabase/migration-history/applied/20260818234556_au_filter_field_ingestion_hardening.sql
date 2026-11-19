insert into ref.fields_of_study(code,name,path,depth,status)
values
('asced-01','Natural and Physical Sciences','asced/01',0,'active'),
('asced-02','Information Technology','asced/02',0,'active'),
('asced-03','Engineering and Related Technologies','asced/03',0,'active'),
('asced-04','Architecture and Building','asced/04',0,'active'),
('asced-05','Agriculture, Environmental and Related Studies','asced/05',0,'active'),
('asced-06','Health','asced/06',0,'active'),
('asced-07','Education','asced/07',0,'active'),
('asced-08','Management and Commerce','asced/08',0,'active'),
('asced-09','Society and Culture','asced/09',0,'active'),
('asced-10','Creative Arts','asced/10',0,'active'),
('asced-11','Food, Hospitality and Personal Services','asced/11',0,'active'),
('asced-12','Mixed Field Programmes','asced/12',0,'active')
on conflict (code) do update set name=excluded.name,path=excluded.path,status='active',updated_at=now();

create table if not exists catalogue.course_field_observations (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  field_id uuid not null references ref.fields_of_study(id) on delete restrict,
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  source_field_code text not null,
  source_field_name text not null,
  is_primary boolean not null default true,
  status text not null default 'current' check(status in ('current','superseded','withdrawn','review')),
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id,source_id,source_field_code)
);
create index if not exists course_field_observations_course_idx on catalogue.course_field_observations(course_id,status);
create index if not exists course_field_observations_field_idx on catalogue.course_field_observations(field_id,status);
create index if not exists course_field_observations_source_idx on catalogue.course_field_observations(source_id);
create index if not exists course_field_observations_evidence_idx on catalogue.course_field_observations(evidence_id);
alter table catalogue.course_field_observations enable row level security;
revoke all on catalogue.course_field_observations from public,anon,authenticated;
grant select,insert,update,delete on catalogue.course_field_observations to service_role;

create or replace function public.svc_layer1_apply_register_records(p_country_code text,p_source_id uuid,p_evidence_id uuid,p_registration_scheme text,p_records jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','pim','ref','pipeline'
as $$
declare
  r jsonb; v_country uuid; v_provider uuid; v_course uuid; v_family_provider uuid; v_family_course uuid; v_level uuid; v_subdivision uuid; v_field uuid; v_broad_field uuid;
  v_provider_created int:=0; v_provider_linked int:=0; v_provider_existing int:=0; v_course_created int:=0; v_course_linked int:=0; v_course_existing int:=0; v_conflicts int:=0; v_provider_unmapped_subdivision int:=0; v_field_mapped int:=0; v_field_unmapped int:=0;
  v_pcode text; v_ccode text; v_pname text; v_cname text; v_level_name text; v_weeks numeric; v_scheme text; v_website text; v_city text; v_state text; v_address1 text; v_address2 text; v_postcode text; v_provider_key text; v_course_key text; v_field_code text; v_field_name text; v_broad_code text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  v_scheme:=lower(nullif(trim(p_registration_scheme),'')); if v_scheme is null then raise exception 'registration scheme required'; end if;
  select id into v_country from ref.countries where upper(iso_alpha2::text)=upper(p_country_code);
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;
  select id into v_family_course from pim.attribute_families where entity_type='course' and status='active' order by case when code='course_default' then 0 else 1 end limit 1;
  if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;
  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_provider:=null; v_course:=null; v_level:=null; v_subdivision:=null; v_field:=null; v_broad_field:=null;
    v_pcode:=upper(nullif(trim(r->>'provider_code'),'')); v_ccode:=upper(nullif(trim(r->>'course_code'),'')); v_pname:=nullif(trim(r->>'provider_name'),''); v_cname:=nullif(trim(r->>'course_name'),'');
    v_level_name:=lower(coalesce(r->>'course_level','')); v_website:=nullif(trim(r->>'website'),''); v_city:=nullif(trim(r->>'city'),''); v_state:=nullif(trim(r->>'state'),''); v_address1:=nullif(trim(r->>'address_line1'),''); v_address2:=nullif(trim(r->>'address_line2'),''); v_postcode:=nullif(trim(r->>'postcode'),'');
    v_field_code:=nullif(trim(r->>'field_code'),''); v_field_name:=nullif(trim(r->>'field_name'),'');
    v_weeks:=case when (r->>'duration_weeks') ~ '^[0-9]+(\.[0-9]+)?$' then (r->>'duration_weeks')::numeric else null end;
    if v_pcode is null or v_pname is null then v_conflicts:=v_conflicts+1; continue; end if;
    if v_state is not null then v_subdivision:=ref.resolve_subdivision_exact(v_country,v_state); if v_subdivision is null then v_provider_unmapped_subdivision:=v_provider_unmapped_subdivision+1; end if; end if;
    v_provider_key := 'provider:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'));
    select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id where p.country_id=v_country and lower(pr.registration_scheme)=v_scheme and upper(pr.registration_code)=v_pcode order by pr.checked_at desc nulls last,pr.id limit 1;
    if v_provider is null then
      select p.id into v_provider from catalogue.providers p where p.country_id=v_country and p.stable_key=v_provider_key limit 1;
      if v_provider is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('provider',v_provider_key,v_family_provider) returning id into v_provider;
        insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,subdivision_id,website,primary_city,address_line1,address_line2,postcode,lifecycle_status,publication_status,canonical_source_id,last_verified_at)
        values(v_provider,v_provider_key,v_pname,v_pname,v_country,v_subdivision,v_website,v_city,v_address1,v_address2,v_postcode,'active','unpublished',p_source_id,now()); v_provider_created:=v_provider_created+1;
      else v_provider_linked:=v_provider_linked+1; end if;
      insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id) values(v_provider,p_source_id,v_scheme,v_pcode,'active',now(),p_evidence_id) on conflict do nothing;
    else v_provider_existing:=v_provider_existing+1; end if;
    update catalogue.provider_registrations set source_id=p_source_id,status='active',checked_at=now(),evidence_id=coalesce(p_evidence_id,evidence_id) where provider_id=v_provider and lower(registration_scheme)=v_scheme and upper(registration_code)=v_pcode;
    update catalogue.providers set canonical_source_id=p_source_id,last_verified_at=now(),website=coalesce(website,v_website),primary_city=coalesce(primary_city,v_city),subdivision_id=coalesce(v_subdivision,subdivision_id),address_line1=coalesce(address_line1,v_address1),address_line2=coalesce(address_line2,v_address2),postcode=coalesce(postcode,v_postcode),updated_at=now() where id=v_provider;
    if v_ccode is null or v_cname is null then continue; end if;
    v_course_key := 'course:'||v_scheme||':'||lower(regexp_replace(v_pcode,'[^a-zA-Z0-9]+','-','g'))||':'||lower(regexp_replace(v_ccode,'[^a-zA-Z0-9]+','-','g'));
    select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id where c.provider_id=v_provider and lower(cr.scheme)=v_scheme and upper(cr.registration_code)=v_ccode order by cr.id limit 1;
    if v_course is null then
      select c.id into v_course from catalogue.courses c where c.provider_id=v_provider and c.stable_key=v_course_key limit 1;
      if v_course is null then
        insert into pim.entity_registry(entity_type,stable_key,family_id) values('course',v_course_key,v_family_course) returning id into v_course;
        insert into catalogue.courses(id,stable_key,provider_id,canonical_title,display_title,course_code,duration_value,duration_unit,lifecycle_status,publication_status,canonical_source_id,last_verified_at) values(v_course,v_course_key,v_provider,v_cname,v_cname,v_ccode,v_weeks,case when v_weeks is not null then 'weeks' end,'active','unpublished',p_source_id,now()); v_course_created:=v_course_created+1;
      else v_course_linked:=v_course_linked+1; end if;
      insert into catalogue.course_registrations(course_id,scheme,registration_code,country_id,status,source_id,evidence_id) values(v_course,v_scheme,v_ccode,v_country,'active',p_source_id,p_evidence_id) on conflict do nothing;
    else v_course_existing:=v_course_existing+1; end if;
    select id into v_level from ref.study_levels where code=case when v_level_name like '%doctor%' or v_level_name like '%phd%' then 'doctorate' when v_level_name like '%master%' then 'masters' when v_level_name like '%graduate certificate%' then 'graduate_certificate' when v_level_name like '%graduate diploma%' then 'graduate_diploma' when v_level_name like '%bachelor%' then 'bachelor' when v_level_name like '%associate%' then 'associate_degree' when v_level_name like '%diploma%' then 'diploma' when v_level_name like '%certificate%' then 'certificate' when v_level_name like '%foundation%' then 'foundation' else null end;
    if v_field_code is not null and v_field_name is not null and v_field_code ~ '^[0-9]{4}$' then
      v_broad_code:=left(v_field_code,2);
      select id into v_broad_field from ref.fields_of_study where code='asced-'||v_broad_code;
      if v_broad_field is not null then
        insert into ref.fields_of_study(code,name,parent_id,path,depth,status) values('asced-'||v_field_code,v_field_name,v_broad_field,'asced/'||v_broad_code||'/'||v_field_code,1,'active') on conflict(code) do update set name=excluded.name,parent_id=excluded.parent_id,path=excluded.path,status='active',updated_at=now() returning id into v_field;
        insert into catalogue.course_field_observations(course_id,field_id,source_id,evidence_id,source_field_code,source_field_name,is_primary,status,observed_at,updated_at)
        values(v_course,v_field,p_source_id,p_evidence_id,v_field_code,v_field_name,true,'current',now(),now()) on conflict(course_id,source_id,source_field_code) do update set field_id=excluded.field_id,evidence_id=coalesce(excluded.evidence_id,catalogue.course_field_observations.evidence_id),source_field_name=excluded.source_field_name,status='current',observed_at=now(),updated_at=now();
        v_field_mapped:=v_field_mapped+1;
      else v_field_unmapped:=v_field_unmapped+1; end if;
    elsif v_field_code is not null or v_field_name is not null then v_field_unmapped:=v_field_unmapped+1; end if;
    update catalogue.courses set study_level_id=coalesce(v_level,study_level_id),primary_field_id=coalesce(v_field,primary_field_id),duration_value=coalesce(v_weeks,duration_value),duration_unit=case when v_weeks is not null then 'weeks' else duration_unit end,canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_course;
    update catalogue.course_registrations set source_id=p_source_id,status='active',evidence_id=coalesce(p_evidence_id,evidence_id) where course_id=v_course and lower(scheme)=v_scheme and upper(registration_code)=v_ccode;
  end loop;
  return jsonb_build_object('provider_created',v_provider_created,'provider_linked',v_provider_linked,'provider_existing',v_provider_existing,'course_created',v_course_created,'course_linked',v_course_linked,'course_existing',v_course_existing,'provider_unmapped_subdivision',v_provider_unmapped_subdivision,'field_mapped',v_field_mapped,'field_unmapped',v_field_unmapped,'conflicts',v_conflicts,'records',jsonb_array_length(coalesce(p_records,'[]'::jsonb)));
end $$;

create or replace function public.ui_provider_filter_options(p_country_code text default null)
returns jsonb language plpgsql stable security definer set search_path='public','ref','catalogue','auth' as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return jsonb_build_object(
 'countries',(select coalesce(jsonb_agg(jsonb_build_object('code',c.iso_alpha2::text,'name',c.name) order by c.name),'[]'::jsonb) from ref.countries c where exists(select 1 from catalogue.providers p where p.country_id=c.id)),
 'subdivisions',(select coalesce(jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name),'[]'::jsonb) from (
   select distinct s.code,s.name,s.subdivision_type from ref.subdivisions s join ref.countries c on c.id=s.country_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code))) and (exists(select 1 from catalogue.providers p where p.subdivision_id=s.id) or exists(select 1 from catalogue.campuses cp where cp.subdivision_id=s.id))
 ) x));
end $$;

create or replace function public.ui_course_filter_options(p_country_code text default null,p_subdivision_code text default null)
returns jsonb language sql stable security definer set search_path='public','catalogue','ref','auth' as $$
select case when auth.uid() is null then null else jsonb_build_object(
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (select distinct co.iso_alpha2::text code,co.name from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id)x),'[]'::jsonb),
 'subdivisions',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name) from (select distinct s.code,s.name,s.subdivision_type from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id join ref.subdivisions s on s.id=p.subdivision_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))) union select distinct s.code,s.name,s.subdivision_type from catalogue.courses c join catalogue.course_campuses cc on cc.course_id=c.id join catalogue.campuses cp on cp.id=cc.campus_id join ref.countries co on co.id=cp.country_id join ref.subdivisions s on s.id=cp.subdivision_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))))x),'[]'::jsonb),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name) from (select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))) and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from ref.subdivisions s where s.id=p.subdivision_id and s.code=upper(trim(p_subdivision_code))) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code)))))x),'[]'::jsonb),
 'levels',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name) from (select distinct sl.code,sl.name,sl.sort_order from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))) and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from ref.subdivisions s where s.id=p.subdivision_id and s.code=upper(trim(p_subdivision_code))) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code)))))x),'[]'::jsonb),
 'fields',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name) from (select distinct fos.code,fos.name from catalogue.courses c join ref.fields_of_study fos on fos.id=c.primary_field_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))) and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or exists(select 1 from ref.subdivisions s where s.id=p.subdivision_id and s.code=upper(trim(p_subdivision_code))) or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id join ref.subdivisions cs on cs.id=cp.subdivision_id where cc.course_id=c.id and cs.code=upper(trim(p_subdivision_code)))))x),'[]'::jsonb),
 'delivery_modes',coalesce((select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code) from (select distinct c.delivery_mode code from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where c.delivery_mode is not null and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))) union select distinct cc.delivery_mode code from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where cc.delivery_mode is not null and (nullif(trim(coalesce(p_country_code,'')),'') is null or co.iso_alpha2::text=upper(trim(p_country_code))))x),'[]'::jsonb)
) end $$;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','net','public','extensions' as $$
declare v_nonce uuid:=extensions.gen_random_uuid();v_id bigint;begin
 if p_function not in ('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth') then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
 select net.http_post(url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id; return v_id;
end $$;
