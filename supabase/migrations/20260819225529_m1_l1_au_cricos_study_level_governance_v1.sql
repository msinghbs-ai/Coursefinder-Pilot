create table if not exists ref.study_level_source_mappings (
  id uuid primary key default extensions.gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  source_value text not null,
  study_level_id uuid references ref.study_levels(id) on delete restrict,
  mapping_status text not null default 'mapped' check (mapping_status in ('mapped','review_required','explicitly_excluded')),
  match_method text not null default 'exact_regulatory_value',
  confidence numeric(5,4) not null default 1.0000 check (confidence >= 0 and confidence <= 1),
  notes text,
  verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_id, source_value),
  check ((mapping_status = 'mapped' and study_level_id is not null) or (mapping_status <> 'mapped'))
);
alter table ref.study_level_source_mappings enable row level security;
revoke all on ref.study_level_source_mappings from anon, authenticated;
grant select, insert, update, delete on ref.study_level_source_mappings to service_role;
create index if not exists study_level_source_mappings_level_idx on ref.study_level_source_mappings(study_level_id);
create index if not exists study_level_source_mappings_source_idx on ref.study_level_source_mappings(source_id,mapping_status);

with parent as (select id,code from ref.study_levels)
insert into ref.study_levels(code,name,parent_id,sort_order,status)
values
 ('primary_school_studies','Primary School Studies',null,5,'active'),
 ('junior_secondary_studies','Junior Secondary Studies',null,6,'active'),
 ('senior_secondary_certificate','Senior Secondary Certificate of Education',null,15,'active'),
 ('certificate_i','Certificate I',(select id from parent where code='certificate'),21,'active'),
 ('certificate_ii','Certificate II',(select id from parent where code='certificate'),22,'active'),
 ('certificate_iii','Certificate III',(select id from parent where code='certificate'),23,'active'),
 ('certificate_iv','Certificate IV',(select id from parent where code='certificate'),24,'active'),
 ('vocational_short_course','Vocational Short Course',null,25,'active'),
 ('advanced_diploma','Advanced Diploma',(select id from parent where code='diploma'),31,'active'),
 ('bachelor_honours','Bachelor Honours Degree',(select id from parent where code='bachelor'),41,'active'),
 ('masters_coursework','Masters Degree (Coursework)',(select id from parent where code='masters'),71,'active'),
 ('masters_research','Masters Degree (Research)',(select id from parent where code='masters'),72,'active'),
 ('masters_extended','Masters Degree (Extended)',(select id from parent where code='masters'),73,'active'),
 ('non_aqf_award','Non AQF Award',null,90,'active')
on conflict(code) do update set name=excluded.name,parent_id=excluded.parent_id,sort_order=excluded.sort_order,status='active';

with src as (
  select id from pipeline.sources where metadata->>'dataset_slug'='cricos'
  order by case when metadata->>'coverage_role'='primary' then 0 else 1 end, created_at limit 1
), vals(source_value,level_code,notes) as (
 values
 ('Diploma','diploma','Exact current CRICOS Course Level vocabulary.'),
 ('Bachelor Degree','bachelor','Exact current CRICOS Course Level vocabulary; broad Bachelor canonical level.'),
 ('Masters Degree (Coursework)','masters_coursework','Exact current CRICOS Course Level vocabulary; child of Masters.'),
 ('Certificate III','certificate_iii','Exact current CRICOS Course Level vocabulary; child of Certificate.'),
 ('Certificate IV','certificate_iv','Exact current CRICOS Course Level vocabulary; child of Certificate.'),
 ('Non AQF Award','non_aqf_award','Exact current CRICOS non-AQF award vocabulary; intentionally not coerced to an AQF level.'),
 ('Advanced Diploma','advanced_diploma','Exact current CRICOS Course Level vocabulary; governed detailed Diploma-family level.'),
 ('Bachelor Honours Degree','bachelor_honours','Exact current CRICOS Course Level vocabulary; child of Bachelor.'),
 ('Graduate Diploma','graduate_diploma','Exact current CRICOS Course Level vocabulary.'),
 ('Graduate Certificate','graduate_certificate','Exact current CRICOS Course Level vocabulary.'),
 ('Doctoral Degree','doctorate','Exact current CRICOS Course Level vocabulary.'),
 ('Masters Degree (Research)','masters_research','Exact current CRICOS Course Level vocabulary; child of Masters.'),
 ('Senior Secondary Certificate of Education','senior_secondary_certificate','Exact current CRICOS school qualification vocabulary; not coerced to generic Certificate.'),
 ('Primary School Studies','primary_school_studies','Exact current CRICOS school-study vocabulary.'),
 ('Associate Degree','associate_degree','Exact current CRICOS Course Level vocabulary.'),
 ('Junior Secondary Studies','junior_secondary_studies','Exact current CRICOS school-study vocabulary.'),
 ('Certificate II','certificate_ii','Exact current CRICOS Course Level vocabulary; child of Certificate.'),
 ('Masters Degree (Extended)','masters_extended','Exact current CRICOS Course Level vocabulary; child of Masters.'),
 ('Vocational Short Course','vocational_short_course','Exact current CRICOS short-course vocabulary; not coerced to an AQF qualification.'),
 ('Certificate I','certificate_i','Exact current CRICOS Course Level vocabulary; child of Certificate.')
)
insert into ref.study_level_source_mappings(source_id,source_value,study_level_id,mapping_status,match_method,confidence,notes,verified_at)
select src.id,vals.source_value,sl.id,'mapped','exact_regulatory_value',1.0000,vals.notes,now()
from src cross join vals join ref.study_levels sl on sl.code=vals.level_code
on conflict(source_id,source_value) do update set study_level_id=excluded.study_level_id,mapping_status='mapped',match_method='exact_regulatory_value',confidence=1.0000,notes=excluded.notes,verified_at=now(),updated_at=now();

create table if not exists catalogue.course_study_level_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  study_level_id uuid references ref.study_levels(id) on delete restrict,
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete restrict,
  scheme text not null,
  registration_code text not null,
  source_value text not null,
  mapping_status text not null check (mapping_status in ('mapped','review_required','explicitly_excluded')),
  source_snapshot_at timestamptz not null,
  content_hash text not null,
  status text not null default 'current' check (status in ('current','superseded','withdrawn')),
  valid_from timestamptz,
  valid_to timestamptz,
  observed_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_study_level_observations_snapshot_uq unique(course_id,source_id,scheme,registration_code,source_snapshot_at),
  constraint course_study_level_observations_valid_range_ck check(valid_to is null or valid_from is null or valid_to >= valid_from)
);
alter table catalogue.course_study_level_observations enable row level security;
revoke all on catalogue.course_study_level_observations from anon, authenticated;
grant select, insert, update, delete on catalogue.course_study_level_observations to service_role;
create index if not exists course_study_level_observations_course_idx on catalogue.course_study_level_observations(course_id,status);
create index if not exists course_study_level_observations_source_idx on catalogue.course_study_level_observations(source_id,source_snapshot_at,status);
create index if not exists course_study_level_observations_level_idx on catalogue.course_study_level_observations(study_level_id);

create or replace function public.svc_layer1_apply_course_study_levels(p_country_code text,p_source_id uuid,p_evidence_id uuid,p_registration_scheme text,p_source_snapshot_at timestamptz,p_records jsonb,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='public','catalogue','ref','pipeline','extensions','pg_temp' as $$
declare
 v_country uuid; v_scheme text; v_records int:=0; v_matched int:=0; v_course_missing int:=0; v_source_absent int:=0; v_mapped int:=0; v_review int:=0; v_unmapped int:=0; v_observation_created int:=0; v_observation_updated int:=0; v_observation_unchanged int:=0; v_observation_superseded int:=0; v_course_level_changed int:=0;
begin
 if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
 v_scheme:=lower(nullif(trim(p_registration_scheme),'')); if v_scheme is null then raise exception 'registration scheme required'; end if;
 if p_source_id is null or p_evidence_id is null or p_source_snapshot_at is null then raise exception 'source/evidence/snapshot required'; end if;
 select id into v_country from ref.countries where upper(trim(iso_alpha2::text))=upper(trim(p_country_code)) limit 1; if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;
 if not exists(select 1 from pipeline.sources where id=p_source_id) then raise exception 'source missing: %',p_source_id; end if;
 if not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id and source_id=p_source_id) then raise exception 'evidence/source mismatch'; end if;
 drop table if exists pg_temp.cf_level_raw; drop table if exists pg_temp.cf_level_resolved;
 create temp table cf_level_raw on commit drop as
 select ord::int ord,upper(nullif(trim(value->>'provider_code'),'')) provider_code,upper(nullif(trim(value->>'course_code'),'')) course_code,nullif(trim(value->>'course_level_raw'),'') source_value
 from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) with ordinality x(value,ord);
 create temp table cf_level_resolved on commit drop as
 select i.*,p.id provider_id,c.id course_id,m.study_level_id,m.mapping_status,sl.code study_level_code,
 encode(extensions.digest(jsonb_build_object('source_value',i.source_value,'study_level_code',sl.code,'mapping_status',coalesce(m.mapping_status,case when i.source_value is null then 'source_absent' else 'review_required' end))::text,'sha256'),'hex') content_hash
 from cf_level_raw i
 left join catalogue.provider_registrations pr on lower(pr.registration_scheme)=v_scheme and upper(pr.registration_code)=i.provider_code
 left join catalogue.providers p on p.id=pr.provider_id and p.country_id=v_country
 left join catalogue.course_registrations cr on lower(cr.scheme)=v_scheme and upper(cr.registration_code)=i.course_code and (cr.country_id is null or cr.country_id=v_country)
 left join catalogue.courses c on c.id=cr.course_id and c.provider_id=p.id
 left join ref.study_level_source_mappings m on m.source_id=p_source_id and m.source_value=i.source_value
 left join ref.study_levels sl on sl.id=m.study_level_id;
 select count(*),count(*) filter(where course_id is not null),count(*) filter(where course_id is null),count(*) filter(where source_value is null),count(*) filter(where source_value is not null and mapping_status='mapped' and study_level_id is not null),count(*) filter(where source_value is not null and mapping_status='review_required'),count(*) filter(where source_value is not null and mapping_status is null)
 into v_records,v_matched,v_course_missing,v_source_absent,v_mapped,v_review,v_unmapped from cf_level_resolved;
 select count(*) filter(where o.id is null),count(*) filter(where o.id is not null and (o.study_level_id is distinct from r.study_level_id or o.source_value is distinct from r.source_value or o.mapping_status is distinct from coalesce(r.mapping_status,'review_required') or o.content_hash is distinct from r.content_hash or o.status<>'current')),count(*) filter(where o.id is not null and o.study_level_id is not distinct from r.study_level_id and o.source_value is not distinct from r.source_value and o.mapping_status is not distinct from coalesce(r.mapping_status,'review_required') and o.content_hash is not distinct from r.content_hash and o.status='current')
 into v_observation_created,v_observation_updated,v_observation_unchanged
 from cf_level_resolved r left join catalogue.course_study_level_observations o on o.course_id=r.course_id and o.source_id=p_source_id and o.scheme=v_scheme and o.registration_code=r.course_code and o.source_snapshot_at=p_source_snapshot_at
 where r.course_id is not null and r.source_value is not null;
 select count(*) into v_observation_superseded from catalogue.course_study_level_observations o join cf_level_resolved r on r.course_id=o.course_id and r.course_code=o.registration_code where r.course_id is not null and o.source_id=p_source_id and o.scheme=v_scheme and o.source_snapshot_at<>p_source_snapshot_at and o.status='current';
 select count(*) into v_course_level_changed from cf_level_resolved r join catalogue.courses c on c.id=r.course_id where r.mapping_status='mapped' and r.study_level_id is not null and c.study_level_id is distinct from r.study_level_id;
 if p_apply then
  update catalogue.course_study_level_observations o set status='superseded',valid_to=p_source_snapshot_at,updated_at=now() from cf_level_resolved r where r.course_id=o.course_id and r.course_code=o.registration_code and r.course_id is not null and o.source_id=p_source_id and o.scheme=v_scheme and o.source_snapshot_at<>p_source_snapshot_at and o.status='current';
  insert into catalogue.course_study_level_observations(course_id,study_level_id,source_id,evidence_id,scheme,registration_code,source_value,mapping_status,source_snapshot_at,content_hash,status,valid_from,valid_to,observed_at,last_verified_at)
  select r.course_id,r.study_level_id,p_source_id,p_evidence_id,v_scheme,r.course_code,r.source_value,coalesce(r.mapping_status,'review_required'),p_source_snapshot_at,r.content_hash,'current',p_source_snapshot_at,null,now(),now() from cf_level_resolved r where r.course_id is not null and r.source_value is not null
  on conflict on constraint course_study_level_observations_snapshot_uq do update set study_level_id=excluded.study_level_id,evidence_id=excluded.evidence_id,source_value=excluded.source_value,mapping_status=excluded.mapping_status,content_hash=excluded.content_hash,status='current',valid_from=excluded.valid_from,valid_to=null,observed_at=now(),last_verified_at=now(),updated_at=now();
  update catalogue.courses c set study_level_id=r.study_level_id,last_verified_at=now(),updated_at=now() from cf_level_resolved r where c.id=r.course_id and r.mapping_status='mapped' and r.study_level_id is not null and c.study_level_id is distinct from r.study_level_id;
 end if;
 return jsonb_build_object('apply',p_apply,'records',v_records,'matched',v_matched,'course_missing',v_course_missing,'source_absent',v_source_absent,'mapped',v_mapped,'review_required',v_review,'unmapped',v_unmapped,'observation_created',v_observation_created,'observation_updated',v_observation_updated,'observation_unchanged',v_observation_unchanged,'observation_superseded',v_observation_superseded,'course_level_changed',v_course_level_changed,'source_snapshot_at',p_source_snapshot_at);
end $$;
revoke all on function public.svc_layer1_apply_course_study_levels(text,uuid,uuid,text,timestamptz,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.svc_layer1_apply_course_study_levels(text,uuid,uuid,text,timestamptz,jsonb,boolean) to service_role;
