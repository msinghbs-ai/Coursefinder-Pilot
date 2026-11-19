insert into integration.systems(code,name,system_type,base_url,status,config)
values('au_rmit_course_pages','RMIT University official course pages','provider_website','https://www.rmit.edu.au','active',jsonb_build_object('country','AU','provider_cricos','00122A','authority','first_party_provider'))
on conflict(code) do update set name=excluded.name,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now();

insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'provider_course_page',sys.id,p.id,c.id,'https://www.rmit.edu.au/study-with-us','RMIT University official course pages',95,'active',jsonb_build_object('provider_cricos','00122A','course_identity','exact_cricos_course_code','facts',jsonb_build_array('course_link','international_fee'))
from integration.systems sys
join catalogue.provider_registrations pr on lower(pr.registration_scheme)='cricos' and pr.registration_code='00122A'
join catalogue.providers p on p.id=pr.provider_id
join ref.countries c on c.id=p.country_id and c.iso_alpha2='AU'
where sys.code='au_rmit_course_pages'
and not exists(select 1 from pipeline.sources s where s.system_id=sys.id and s.provider_id=p.id);

create table if not exists pipeline.course_fact_source_records(
 id uuid primary key default gen_random_uuid(),
 source_id uuid not null references pipeline.sources(id) on delete cascade,
 source_record_id text not null,
 source_url text not null,
 provider_cricos text not null,
 course_cricos text not null,
 content_hash text not null,
 evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
 parsed_payload jsonb not null default '{}'::jsonb,
 status text not null default 'observed' check(status in ('observed','applied','rejected','error')),
 observed_at timestamptz not null default now(),
 applied_at timestamptz,
 error_text text,
 unique(source_id,source_record_id,content_hash)
);
create index if not exists course_fact_source_records_course_idx on pipeline.course_fact_source_records(course_cricos,observed_at desc);
create index if not exists course_fact_source_records_evidence_idx on pipeline.course_fact_source_records(evidence_id);
alter table pipeline.course_fact_source_records enable row level security;
revoke all on pipeline.course_fact_source_records from public,anon,authenticated;
grant select,insert,update,delete on pipeline.course_fact_source_records to service_role;

create or replace function public.svc_coursefacts_resolve_source(p_system_code text,p_provider_cricos text)
returns jsonb language sql stable security definer set search_path='public','pipeline','integration','catalogue','ref' as $$
 select case when current_user='postgres' or coalesce(auth.role(),'')='service_role' then (
  select jsonb_build_object('source_id',s.id,'provider_id',s.provider_id,'system_code',sys.code,'country_code',c.iso_alpha2::text)
  from pipeline.sources s join integration.systems sys on sys.id=s.system_id join catalogue.providers p on p.id=s.provider_id join ref.countries c on c.id=p.country_id
  where sys.code=p_system_code and exists(select 1 from catalogue.provider_registrations pr where pr.provider_id=p.id and lower(pr.registration_scheme)='cricos' and pr.registration_code=upper(trim(p_provider_cricos))) and s.status='active' limit 1
 ) else null end $$;
revoke all on function public.svc_coursefacts_resolve_source(text,text) from public,anon,authenticated;
grant execute on function public.svc_coursefacts_resolve_source(text,text) to service_role;

create or replace function public.svc_coursefacts_register_evidence(p_source_id uuid,p_source_url text,p_storage_path text,p_content_hash text,p_mime_type text,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path='public','pipeline' as $$
declare v_id uuid;begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata)
 values(p_source_id,'source_snapshot',p_source_url,p_storage_path,p_content_hash,p_mime_type,coalesce(p_metadata,'{}'::jsonb)) returning id into v_id;
 return v_id;end $$;
revoke all on function public.svc_coursefacts_register_evidence(uuid,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.svc_coursefacts_register_evidence(uuid,text,text,text,text,jsonb) to service_role;

create or replace function public.svc_coursefacts_apply_record(p_source_id uuid,p_evidence_id uuid,p_provider_cricos text,p_course_cricos text,p_source_record_id text,p_source_url text,p_content_hash text,p_payload jsonb,p_apply boolean default false)
returns jsonb language plpgsql security definer set search_path='public','pipeline','catalogue','ref' as $$
declare v_provider uuid;v_course uuid;v_existing_record uuid;v_link_created int:=0;v_fee_created int:=0;v_fee_year int;v_amount numeric;v_currency text;v_basis text;v_fee_key text;v_audience text;begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU' and lower(pr.registration_scheme)='cricos' and pr.registration_code=upper(trim(p_provider_cricos)) limit 1;
 if v_provider is null then raise exception 'provider CRICOS not resolved';end if;
 select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id where c.provider_id=v_provider and lower(cr.scheme)='cricos' and cr.registration_code=upper(trim(p_course_cricos)) limit 1;
 if v_course is null then raise exception 'course CRICOS not resolved';end if;
 if coalesce(trim(p_source_record_id),'')='' or coalesce(trim(p_source_url),'')='' or coalesce(trim(p_content_hash),'')='' then raise exception 'source identity/evidence fields required';end if;
 if not p_apply then return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'would_apply_link',coalesce((p_payload->>'course_url')<>'',false),'would_apply_fee',p_payload ? 'fee_amount');end if;
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at)
 values(p_source_id,p_source_record_id,p_source_url,upper(trim(p_provider_cricos)),upper(trim(p_course_cricos)),p_content_hash,p_evidence_id,p_payload,'observed',now())
 on conflict(source_id,source_record_id,content_hash) do update set evidence_id=coalesce(excluded.evidence_id,pipeline.course_fact_source_records.evidence_id),parsed_payload=excluded.parsed_payload,observed_at=now()
 returning id into v_existing_record;
 if nullif(trim(p_payload->>'course_url'),'') is not null then
   insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
   values(v_course,coalesce(nullif(trim(p_payload->>'link_type'),''),'official_course'),trim(p_payload->>'course_url'),coalesce(nullif(trim(p_payload->>'audience'),''),'international'),'Official course page',true,'active',p_source_id,p_evidence_id,1,now(),now())
   on conflict(course_id,link_type,url) do update set audience=excluded.audience,label=excluded.label,is_primary=true,status='active',source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,last_verified_at=now(),updated_at=now();
   v_link_created:=1;
   update catalogue.courses set course_url=coalesce(course_url,trim(p_payload->>'course_url')),updated_at=now() where id=v_course;
 end if;
 if p_payload ? 'fee_amount' then
   v_fee_year:=nullif(p_payload->>'fee_year','')::int;v_amount:=nullif(p_payload->>'fee_amount','')::numeric;v_currency:=coalesce(nullif(trim(p_payload->>'currency_code'),''),'AUD');v_basis:=nullif(trim(p_payload->>'fee_basis'),'');v_audience:=coalesce(nullif(trim(p_payload->>'audience'),''),'international');v_fee_key:=coalesce(nullif(trim(p_payload->>'fee_key'),''),lower(upper(trim(p_course_cricos))||':'||v_audience||':'||coalesce(v_fee_year::text,'current')||':'||coalesce(v_basis,'tuition')));
   if v_amount is null or v_amount<=0 then raise exception 'positive fee amount required';end if;
   if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;
   insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,updated_at)
   values(v_course,v_fee_year,v_audience,'tuition',v_amount,v_currency,v_basis,p_payload->>'fee_notes',p_source_id,p_evidence_id,1,null,v_fee_key,'active',now(),now())
   on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do update set fee_year=excluded.fee_year,audience=excluded.audience,fee_type=excluded.fee_type,amount=excluded.amount,currency_code=excluded.currency_code,basis=excluded.basis,notes=excluded.notes,evidence_id=excluded.evidence_id,confidence=1,status='active',last_verified_at=now(),updated_at=now();
   v_fee_created:=1;
 end if;
 update pipeline.course_fact_source_records set status='applied',applied_at=now() where id=v_existing_record;
 return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'link_applied',v_link_created,'fee_applied',v_fee_created,'source_record_id',v_existing_record);
end $$;
revoke all on function public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean) to service_role;

create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path='pipeline','net','public','extensions' as $$
declare v_nonce uuid:=extensions.gen_random_uuid();v_id bigint;begin
 if p_function not in ('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness','coursefacts-au-rmit') then raise exception 'one-time Pilot Edge function is not allowlisted'; end if;
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,p_function,now()+interval '2 minutes');
 select net.http_post(url:='https://fxcwkweaxjtknorudmwp.supabase.co/functions/v1/'||p_function,headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=120000) into v_id;return v_id;end $$;
