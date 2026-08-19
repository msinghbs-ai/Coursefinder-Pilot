alter table catalogue.course_intakes add column if not exists source_intake_key text;
create unique index if not exists course_intakes_source_identity_uidx on catalogue.course_intakes(course_id,source_id,source_intake_key) where source_id is not null and source_intake_key is not null;

alter table catalogue.course_english_requirements add column if not exists source_requirement_key text;
alter table catalogue.course_english_requirements add column if not exists status text not null default 'active';
alter table catalogue.course_english_requirements add column if not exists valid_from date;
alter table catalogue.course_english_requirements add column if not exists valid_to date;
alter table catalogue.course_english_requirements add column if not exists last_verified_at timestamptz;

create table if not exists pipeline.course_fact_source_qualifications (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references ref.countries(id),
 source_id uuid not null references pipeline.sources(id) on delete cascade,
 source_key text not null unique,
 authority_name text not null,
 source_class text not null,
 provider_cricos text not null,
 mapping_strategy text not null,
 evidence_strategy text not null,
 qualification_status text not null check (qualification_status in ('qualified','bounded','deferred','rejected')),
 admitted_domains text[] not null default array['official_course_url','international_fee','intake','english_requirement']::text[],
 notes text,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table pipeline.course_fact_source_qualifications enable row level security;
revoke all on pipeline.course_fact_source_qualifications from public,anon,authenticated;
grant select,insert,update,delete on pipeline.course_fact_source_qualifications to service_role;

create or replace function public.svc_coursefacts_apply_record(
 p_source_id uuid,p_evidence_id uuid,p_provider_cricos text,p_course_cricos text,p_source_record_id text,p_source_url text,p_content_hash text,p_payload jsonb,p_apply boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_provider uuid;v_course uuid;v_record uuid;v_test uuid;r jsonb;
 v_fee_year int;v_amount numeric;v_currency text;v_basis text;v_fee_key text;v_audience text;
 v_links int:=0;v_fees int:=0;v_intakes int:=0;v_english int:=0;
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU' and lower(pr.registration_scheme)='cricos' and upper(btrim(pr.registration_code))=upper(btrim(p_provider_cricos)) and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1;
 if v_provider is null then raise exception 'provider CRICOS not resolved';end if;
 select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id where c.provider_id=v_provider and lower(cr.scheme)='cricos' and upper(btrim(cr.registration_code))=upper(btrim(p_course_cricos)) limit 1;
 if v_course is null then raise exception 'course CRICOS not resolved';end if;
 if coalesce(btrim(p_source_record_id),'')='' or coalesce(btrim(p_source_url),'')='' or coalesce(btrim(p_content_hash),'')='' then raise exception 'source identity/evidence fields required';end if;
 if not exists(select 1 from pipeline.course_fact_source_qualifications q where q.source_id=p_source_id and q.provider_cricos=upper(btrim(p_provider_cricos)) and q.qualification_status in ('qualified','bounded')) then raise exception 'source not qualified for AU course facts';end if;
 if not p_apply then return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'would_apply_link',nullif(btrim(p_payload->>'course_url'),'') is not null,'would_apply_fee',p_payload ? 'fee_amount','would_apply_intakes',coalesce(jsonb_array_length(coalesce(p_payload->'intakes','[]'::jsonb)),0),'would_apply_english',coalesce(jsonb_array_length(coalesce(p_payload->'english_requirements','[]'::jsonb)),0));end if;
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at)
 values(p_source_id,p_source_record_id,p_source_url,upper(btrim(p_provider_cricos)),upper(btrim(p_course_cricos)),p_content_hash,p_evidence_id,p_payload,'observed',now())
 on conflict(source_id,source_record_id,content_hash) do update set evidence_id=coalesce(excluded.evidence_id,pipeline.course_fact_source_records.evidence_id),parsed_payload=excluded.parsed_payload,observed_at=now(),error_text=null returning id into v_record;
 if nullif(btrim(p_payload->>'course_url'),'') is not null then
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values(v_course,coalesce(nullif(btrim(p_payload->>'link_type'),''),'official_course'),btrim(p_payload->>'course_url'),coalesce(nullif(btrim(p_payload->>'audience'),''),'international'),'Official provider course page',false,'active',p_source_id,p_evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set audience=excluded.audience,label=excluded.label,status='active',source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,last_verified_at=now(),updated_at=now(); v_links:=1;
 end if;
 if p_payload ? 'fee_amount' then
  v_fee_year:=nullif(p_payload->>'fee_year','')::int;v_amount:=nullif(p_payload->>'fee_amount','')::numeric;v_currency:=coalesce(nullif(btrim(p_payload->>'currency_code'),''),'AUD');v_basis:=nullif(btrim(p_payload->>'fee_basis'),'');v_audience:=coalesce(nullif(btrim(p_payload->>'audience'),''),'international');v_fee_key:=coalesce(nullif(btrim(p_payload->>'fee_key'),''),lower(upper(btrim(p_course_cricos))||':'||v_audience||':'||coalesce(v_fee_year::text,'current')||':'||coalesce(v_basis,'tuition')));
  if v_amount is null or v_amount<=0 then raise exception 'positive fee amount required';end if;
  if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;
  insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
  values(v_course,v_fee_year,v_audience,'provider_current_tuition',v_amount,v_currency,v_basis,p_payload->>'fee_notes',p_source_id,p_evidence_id,1,null,v_fee_key,'active',now(),now(),now())
  on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do update set fee_year=excluded.fee_year,audience=excluded.audience,fee_type=excluded.fee_type,amount=excluded.amount,currency_code=excluded.currency_code,basis=excluded.basis,notes=excluded.notes,evidence_id=excluded.evidence_id,confidence=1,status='active',last_verified_at=now(),source_snapshot_at=now(),updated_at=now(); v_fees:=1;
 end if;
 for r in select value from jsonb_array_elements(coalesce(p_payload->'intakes','[]'::jsonb)) loop
  if nullif(btrim(r->>'intake_label'),'') is null then raise exception 'intake_label required';end if;
  insert into catalogue.course_intakes(course_id,intake_year,intake_label,start_date,application_deadline,campus_id,status,source_id,evidence_id,confidence,source_intake_key)
  values(v_course,nullif(r->>'intake_year','')::int,r->>'intake_label',nullif(r->>'start_date','')::date,nullif(r->>'application_deadline','')::date,null,coalesce(nullif(r->>'status',''),'active'),p_source_id,p_evidence_id,1,coalesce(nullif(r->>'source_intake_key',''),lower(upper(btrim(p_course_cricos))||':'||coalesce((r->>'intake_year'),'current')||':'||(r->>'intake_label'))))
  on conflict(course_id,source_id,source_intake_key) where source_id is not null and source_intake_key is not null do update set intake_year=excluded.intake_year,intake_label=excluded.intake_label,start_date=excluded.start_date,application_deadline=excluded.application_deadline,status=excluded.status,evidence_id=excluded.evidence_id,confidence=1; v_intakes:=v_intakes+1;
 end loop;
 for r in select value from jsonb_array_elements(coalesce(p_payload->'english_requirements','[]'::jsonb)) loop
  select id into v_test from ref.english_tests where code=upper(btrim(r->>'test_code')) limit 1;
  if v_test is null then raise exception 'english test not seeded: %',r->>'test_code';end if;
  insert into catalogue.course_english_requirements(course_id,english_test_id,overall_score,component_scores,notes,source_id,evidence_id,confidence,source_requirement_key,status,valid_from,valid_to,last_verified_at)
  values(v_course,v_test,nullif(r->>'overall_score','')::numeric,coalesce(r->'component_scores','{}'::jsonb),r->>'notes',p_source_id,p_evidence_id,1,coalesce(nullif(r->>'source_requirement_key',''),lower(upper(btrim(p_course_cricos))||':'||upper(btrim(r->>'test_code')))),coalesce(nullif(r->>'status',''),'active'),nullif(r->>'valid_from','')::date,nullif(r->>'valid_to','')::date,now())
  on conflict(course_id,english_test_id) do update set overall_score=excluded.overall_score,component_scores=excluded.component_scores,notes=excluded.notes,source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,source_requirement_key=excluded.source_requirement_key,status=excluded.status,valid_from=excluded.valid_from,valid_to=excluded.valid_to,last_verified_at=now(); v_english:=v_english+1;
 end loop;
 update pipeline.course_fact_source_records set status='applied',applied_at=now() where id=v_record;
 return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'links_applied',v_links,'fees_applied',v_fees,'intakes_applied',v_intakes,'english_applied',v_english,'source_record_id',v_record);
end $$;
revoke all on function public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean) to service_role;