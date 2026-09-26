-- Package 8.5 (Decision 152, lifecycle approved 26 Sep 2026): admission lifecycle policy.
-- Check cheaply for change and acquire only when there is something new. Layer 2 profile freshness
-- is brought into line through the official versioning path (layer2_create_profile_version), in
-- batches; Layer 1 cadences are set directly. Re-running is safe: matching profiles are skipped.
create table if not exists pipeline.admission_lifecycle_policy(
  data_type text primary key,
  label text not null,
  layer text not null,
  cycle_days int not null check (cycle_days between 1 and 730),
  check_days int check (check_days between 1 and 730),
  window_months int[],
  on_demand boolean not null default true,
  rationale text not null,
  updated_by uuid, updated_at timestamptz not null default now());
insert into pipeline.admission_lifecycle_policy(data_type,label,layer,cycle_days,check_days,window_months,on_demand,rationale) values
 ('regulatory_register','CRICOS and NZQA registers','L1',7,7,null,true,'Check weekly for a change; ingest only when the register changed'),
 ('course_facts','Provider course facts (tuition, intakes, English, links, description)','L2',365,null,array[8,9,10,11],true,'Changes about once a year when providers publish next year''s details; refresh annually in the Aug–Nov publishing window, or on demand'),
 ('scholarships','Scholarships','L2',90,null,null,true,'Application windows and amounts change a few times a year'),
 ('provider_assets','Provider assets (logos, contacts)','L2',365,null,null,true,'Rarely change'),
 ('qilt','QILT surveys','L1',365,182,null,false,'Published annually; check twice a year for a new edition'),
 ('prisms','PRISMS student flow','L1',30,30,null,false,'Periodic releases; check monthly, ingest only on a new release'),
 ('rankings','QS and THE rankings','L1',365,365,null,false,'Annual licensed files, uploaded when published')
on conflict (data_type) do nothing;
alter table pipeline.admission_lifecycle_policy enable row level security;
revoke all on pipeline.admission_lifecycle_policy from public, anon, authenticated;

-- Bring Layer 2 profile freshness into line with the policy, in batches, through the official path.
create or replace function security.admission_lifecycle_apply_l2_v1(p_actor uuid, p_limit int default 300)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
declare r record; v_done int := 0; v_err int := 0; v_left int; t0 timestamptz := clock_timestamp();
begin
  for r in
    select sp.id, v.configuration cfg, (pol.cycle_days*24) target_h
    from pipeline.layer2_source_profiles sp
    join pipeline.layer2_source_profile_versions v on v.id=sp.current_version_id
    join pipeline.admission_lifecycle_policy pol on pol.data_type = case sp.domain when 'course_facts' then 'course_facts' when 'scholarship' then 'scholarships' when 'provider_asset' then 'provider_assets' end
    where sp.enabled and coalesce(sp.freshness_sla_hours,-1) <> pol.cycle_days*24
    order by sp.id limit greatest(1,least(coalesce(p_limit,300),1000))
  loop
    begin
      perform public.layer2_create_profile_version(p_actor, r.id, jsonb_set(r.cfg,'{freshness_sla_hours}',to_jsonb(r.target_h)), 'CF-CHG-20260915-247', 'Decision-152-admission-lifecycle');
      v_done := v_done+1;
    exception when others then v_err := v_err+1;
    end;
  end loop;
  select count(*) into v_left from pipeline.layer2_source_profiles sp join pipeline.admission_lifecycle_policy pol
    on pol.data_type = case sp.domain when 'course_facts' then 'course_facts' when 'scholarship' then 'scholarships' when 'provider_asset' then 'provider_assets' end
   where sp.enabled and coalesce(sp.freshness_sla_hours,-1) <> pol.cycle_days*24;
  return jsonb_build_object('versioned',v_done,'errors',v_err,'remaining',v_left,'ms',round(extract(epoch from clock_timestamp()-t0)*1000));
end $$;
revoke all on function security.admission_lifecycle_apply_l2_v1(uuid,int) from public, anon, authenticated;

-- Layer 1 cadences from the policy.
update pipeline.layer1_source_operations o set verification_cadence_days=7, ingestion_cadence_days=7
 from pipeline.sources s where s.id=o.source_id and (s.label ilike 'CRICOS%' or s.label ilike 'NZQA%')
 and (o.verification_cadence_days is distinct from 7 or o.ingestion_cadence_days is distinct from 7);
update pipeline.layer1_source_operations o set verification_cadence_days=182, ingestion_cadence_days=365
 from pipeline.sources s where s.id=o.source_id and s.label ilike 'QILT%'
 and (o.verification_cadence_days is distinct from 182 or o.ingestion_cadence_days is distinct from 365);
update pipeline.layer1_source_operations o set verification_cadence_days=30, ingestion_cadence_days=30
 from pipeline.sources s where s.id=o.source_id and s.label ilike '%PRISMS%'
 and (o.verification_cadence_days is distinct from 30 or o.ingestion_cadence_days is distinct from 30);

-- Lifecycle read for the Resources view.
create or replace function public.admin_admission_lifecycle_read_v1()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','public'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 5 then raise exception 'PIM Admin role is required' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'data_type',p.data_type,'label',p.label,'layer',p.layer,'cycle_days',p.cycle_days,'check_days',p.check_days,
    'window_months',p.window_months,'on_demand',p.on_demand,'rationale',p.rationale,
    'profiles', case when p.layer='L2' then (select count(*) from pipeline.layer2_source_profiles sp where sp.enabled
        and sp.domain = case p.data_type when 'course_facts' then 'course_facts' when 'scholarships' then 'scholarship' when 'provider_assets' then 'provider_asset' end) end,
    'aligned', case when p.layer='L2' then (select count(*) from pipeline.layer2_source_profiles sp where sp.enabled and sp.freshness_sla_hours=p.cycle_days*24
        and sp.domain = case p.data_type when 'course_facts' then 'course_facts' when 'scholarships' then 'scholarship' when 'provider_asset' then 'provider_asset' end) end,
    'next_due', case when p.layer='L1' then (select min(o.next_ingestion_at) from pipeline.layer1_source_operations o join pipeline.sources s on s.id=o.source_id
        where (p.data_type='regulatory_register' and (s.label ilike 'CRICOS%' or s.label ilike 'NZQA%')) or (p.data_type='qilt' and s.label ilike 'QILT%')
           or (p.data_type='prisms' and s.label ilike '%PRISMS%') or (p.data_type='rankings' and (s.label ilike 'QS %' or s.label ilike 'Times Higher%'))) end
  ) order by p.layer, p.data_type),'[]'::jsonb) from pipeline.admission_lifecycle_policy p);
end $$;
revoke all on function public.admin_admission_lifecycle_read_v1() from public, anon;
grant execute on function public.admin_admission_lifecycle_read_v1() to authenticated, service_role;
