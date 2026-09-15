-- CF-CHG-20260915-245 — Gate E/F bounded field-level admission proof.
-- This does NOT auto-approve Layer 3. It admits only the already-qualified official URL
-- field when exact CRICOS identity, Evidence, source qualification and Search source gate agree.

create table if not exists pipeline.layer2_field_admissions(
  id uuid primary key default gen_random_uuid(),
  source_record_id uuid not null references pipeline.course_fact_source_records(id),
  course_id uuid not null references catalogue.courses(id),
  source_id uuid not null references pipeline.sources(id),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  field_key text not null,
  status text not null check(status in('admitted','unchanged','deferred','rejected')),
  reason_code text,
  candidate_payload jsonb not null default '{}'::jsonb,
  canonical_changed boolean not null default false,
  search_admission_eligible boolean not null default false,
  change_control_ref text not null default 'CF-CHG-20260915-245',
  decided_at timestamptz not null default now(),
  unique(source_record_id,field_key)
);
alter table pipeline.layer2_field_admissions enable row level security;
revoke all on pipeline.layer2_field_admissions from public,anon,authenticated;
grant select,insert,update on pipeline.layer2_field_admissions to service_role;
create index if not exists layer2_field_admissions_course_field_idx on pipeline.layer2_field_admissions(course_id,field_key,status,decided_at desc);
create index if not exists layer2_field_admissions_decided_idx on pipeline.layer2_field_admissions(decided_at desc);

create or replace function security.cf245_admit_official_url_record_v1(p_source_record_id uuid,p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','search'
as $$
declare
  r pipeline.course_fact_source_records%rowtype;
  v_provider uuid; v_course uuid; v_url text; v_existing boolean:=false; v_gate boolean:=false;
begin
  if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into r from pipeline.course_fact_source_records where id=p_source_record_id;
  if not found then return jsonb_build_object('ok',false,'eligible',false,'reason','source_record_not_found'); end if;
  if r.evidence_id is null then return jsonb_build_object('ok',true,'eligible',false,'reason','evidence_required'); end if;
  if coalesce((r.parsed_payload->>'identity_match')::boolean,false)=false then return jsonb_build_object('ok',true,'eligible',false,'reason','identity_mismatch'); end if;
  if coalesce((r.parsed_payload->>'regulatory_code_seen')::boolean,false)=false then return jsonb_build_object('ok',true,'eligible',false,'reason','regulatory_code_not_seen'); end if;
  v_url:=nullif(btrim(r.parsed_payload->>'official_course_url'),'');
  if v_url is null then return jsonb_build_object('ok',true,'eligible',false,'reason','official_url_not_resolved'); end if;
  if v_url is distinct from r.source_url then return jsonb_build_object('ok',true,'eligible',false,'reason','official_url_evidence_url_mismatch'); end if;
  if v_url !~ '^https?://' then return jsonb_build_object('ok',true,'eligible',false,'reason','official_url_invalid_scheme'); end if;

  select pr.provider_id into v_provider
  from catalogue.provider_registrations pr
  join catalogue.providers p on p.id=pr.provider_id
  join ref.countries c on c.id=p.country_id
  where trim(c.iso_alpha2)='AU' and lower(pr.registration_scheme)='cricos'
    and upper(btrim(pr.registration_code))=upper(btrim(r.provider_cricos))
    and coalesce(pr.status,'active') not in('inactive','cancelled','archived')
  order by pr.checked_at desc nulls last limit 1;
  if v_provider is null then return jsonb_build_object('ok',true,'eligible',false,'reason','provider_cricos_not_resolved'); end if;
  select cr.course_id into v_course
  from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id
  where c.provider_id=v_provider and lower(cr.scheme)='cricos'
    and upper(btrim(cr.registration_code))=upper(btrim(r.course_cricos)) limit 1;
  if v_course is null then return jsonb_build_object('ok',true,'eligible',false,'reason','course_cricos_not_resolved'); end if;
  if security.layer4_entity_or_parent_blocked('course',v_course,'operational') then return jsonb_build_object('ok',true,'eligible',false,'reason','layer4_operational_block'); end if;
  if not exists(select 1 from pipeline.course_fact_source_qualifications q where q.source_id=r.source_id and q.provider_cricos=upper(btrim(r.provider_cricos)) and q.qualification_status in('qualified','bounded') and 'official_course_url'=any(q.admitted_domains)) then
    return jsonb_build_object('ok',true,'eligible',false,'reason','source_not_qualified_for_official_url');
  end if;
  select exists(select 1 from search.enrichment_source_gates sg where sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=r.source_id and sg.gate_status='approved') into v_gate;
  if not v_gate then return jsonb_build_object('ok',true,'eligible',false,'reason','search_source_gate_not_approved'); end if;
  select exists(select 1 from catalogue.course_links l where l.course_id=v_course and l.link_type='official_course' and l.url=v_url and l.status='active') into v_existing;
  if not p_apply then return jsonb_build_object('ok',true,'eligible',true,'course_id',v_course,'url',v_url,'would_change',not v_existing,'search_admission_eligible',true); end if;

  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values(v_course,'official_course',v_url,'international','Official provider course page',false,'active',r.source_id,r.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set audience=excluded.audience,label=excluded.label,status='active',source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,last_verified_at=now(),updated_at=now();

  insert into pipeline.layer2_field_admissions(source_record_id,course_id,source_id,evidence_id,field_key,status,reason_code,candidate_payload,canonical_changed,search_admission_eligible)
  values(r.id,v_course,r.source_id,r.evidence_id,'official_course_url',case when v_existing then 'unchanged' else 'admitted' end,case when v_existing then 'already_active_same_url' else 'qualified_exact_cricos_evidence_match' end,jsonb_build_object('url',v_url),not v_existing,true)
  on conflict(source_record_id,field_key) do update set status=excluded.status,reason_code=excluded.reason_code,candidate_payload=excluded.candidate_payload,canonical_changed=excluded.canonical_changed,search_admission_eligible=excluded.search_admission_eligible,decided_at=now();
  return jsonb_build_object('ok',true,'eligible',true,'applied',true,'course_id',v_course,'url',v_url,'canonical_changed',not v_existing,'search_admission_eligible',true);
end $$;
revoke all on function security.cf245_admit_official_url_record_v1(uuid,boolean) from public,anon,authenticated;
grant execute on function security.cf245_admit_official_url_record_v1(uuid,boolean) to service_role;

create or replace function security.cf245_admit_official_url_wave_v1(p_batch_id uuid,p_limit integer default 25,p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','security','pipeline'
as $$
declare r record; v jsonb; v_checked int:=0; v_eligible int:=0; v_changed int:=0; v_reasons jsonb:='{}'::jsonb; v_reason text;
begin
  if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  for r in
    select distinct l.source_record_id
    from pipeline.layer2_enrichment_operational_ledger_v1 l
    where l.batch_id=p_batch_id and l.source_record_id is not null
      and not exists(select 1 from pipeline.layer2_field_admissions a where a.source_record_id=l.source_record_id and a.field_key='official_course_url' and a.status in('admitted','unchanged'))
    order by l.source_record_id
    limit greatest(1,least(coalesce(p_limit,25),100))
  loop
    v_checked:=v_checked+1;
    v:=security.cf245_admit_official_url_record_v1(r.source_record_id,p_apply);
    if coalesce((v->>'eligible')::boolean,false) then v_eligible:=v_eligible+1; end if;
    if coalesce((v->>'canonical_changed')::boolean,false) then v_changed:=v_changed+1; end if;
    v_reason:=coalesce(v->>'reason',case when coalesce((v->>'eligible')::boolean,false) then 'eligible' else 'unknown' end);
    v_reasons:=jsonb_set(v_reasons,array[v_reason],to_jsonb(coalesce((v_reasons->>v_reason)::int,0)+1),true);
  end loop;
  return jsonb_build_object('ok',true,'batch_id',p_batch_id,'apply',p_apply,'checked',v_checked,'eligible',v_eligible,'canonical_changed',v_changed,'reasons',v_reasons,'change_control_ref','CF-CHG-20260915-245');
end $$;
revoke all on function security.cf245_admit_official_url_wave_v1(uuid,integer,boolean) from public,anon,authenticated;
grant execute on function security.cf245_admit_official_url_wave_v1(uuid,integer,boolean) to service_role;
