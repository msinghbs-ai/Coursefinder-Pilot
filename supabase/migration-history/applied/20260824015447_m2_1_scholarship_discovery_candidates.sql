create table if not exists pipeline.layer2_scholarship_discovery_candidates(
 id uuid primary key default gen_random_uuid(),
 source_id uuid not null,
 evidence_id uuid not null references pipeline.evidence_artifacts(id),
 source_profile_version_id uuid references pipeline.layer2_source_profile_versions(id),
 scholarship_url text not null,
 observed_title text,
 status text not null default 'discovered' check(status in ('discovered','acquired','rejected','superseded')),
 created_at timestamptz not null default now(),
 unique(evidence_id,scholarship_url)
);
alter table pipeline.layer2_scholarship_discovery_candidates enable row level security;
revoke all on pipeline.layer2_scholarship_discovery_candidates from anon,authenticated;
grant select,insert,update on pipeline.layer2_scholarship_discovery_candidates to service_role;
create index if not exists layer2_scholarship_discovery_url_idx on pipeline.layer2_scholarship_discovery_candidates(scholarship_url,status);

create or replace function public.layer2_scholarship_discovery_record(p_evidence_id uuid,p_urls jsonb)
returns integer language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare e pipeline.evidence_artifacts%rowtype;x jsonb;n integer:=0;v_url text;v_title text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into e from pipeline.evidence_artifacts where id=p_evidence_id;if not found then raise exception 'evidence not found';end if;
 for x in select * from jsonb_array_elements(coalesce(p_urls,'[]'::jsonb)) loop
  v_url:=nullif(x->>'url','');v_title:=nullif(x->>'title','');if v_url is null then continue;end if;
  insert into pipeline.layer2_scholarship_discovery_candidates(source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title)
  values(e.source_id,e.id,e.source_profile_version_id,v_url,v_title) on conflict(evidence_id,scholarship_url) do nothing;
  if found then n:=n+1;end if;
 end loop;return n;
end $$;
revoke all on function public.layer2_scholarship_discovery_record(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_scholarship_discovery_record(uuid,jsonb) to service_role;
notify pgrst,'reload schema';
