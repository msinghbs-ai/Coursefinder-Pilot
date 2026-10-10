-- Package 7 (Decision 146): evidence link index. Links are read once from STORED evidence
-- (Supabase Storage, bucket "evidence") by the evidence-link-index worker; no web fetching.
create table if not exists pipeline.evidence_links(
  id bigint generated always as identity primary key,
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete cascade,
  url text not null,
  host text not null,
  anchor_text text,
  same_site boolean not null,
  position int not null,
  unique(evidence_id, url)
);
create index if not exists evidence_links_host_idx on pipeline.evidence_links(host);
create table if not exists pipeline.evidence_link_index_state(
  evidence_id uuid primary key references pipeline.evidence_artifacts(id) on delete cascade,
  status text not null check (status in ('indexed','no_links','unsupported','error')),
  link_count int not null default 0,
  error text,
  indexed_at timestamptz not null default now()
);
alter table pipeline.evidence_links enable row level security;
alter table pipeline.evidence_link_index_state enable row level security;
revoke all on pipeline.evidence_links, pipeline.evidence_link_index_state from public, anon, authenticated;

-- Next artifacts to index: page-like evidence stored in the evidence bucket, not yet indexed
-- (errors retried after 6 hours).
create or replace function public.svc_evidence_link_index_next_v1(p_limit int default 60)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'path',e.storage_path,'mime',e.mime_type,'url',e.source_url,'type',e.evidence_type)),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type
        from pipeline.evidence_artifacts e
        left join pipeline.evidence_link_index_state st on st.evidence_id=e.id
        where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
          and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
          and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
          and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
        order by e.captured_at desc nulls last
        limit greatest(1,least(coalesce(p_limit,60),200))) e
$$;

-- Record one artifact's links (replaces any earlier result for that artifact).
create or replace function public.svc_evidence_link_index_record_v1(p_evidence_id uuid, p_status text, p_links jsonb, p_error text default null)
returns int language plpgsql security definer set search_path to 'pg_catalog','pipeline'
as $$
declare v_n int := 0;
begin
  delete from pipeline.evidence_links where evidence_id=p_evidence_id;
  if p_status='indexed' and jsonb_typeof(p_links)='array' then
    insert into pipeline.evidence_links(evidence_id,url,host,anchor_text,same_site,position)
    select p_evidence_id, left(l->>'url',2000), left(lower(l->>'host'),255), nullif(left(l->>'text',200),''), coalesce((l->>'same_site')::boolean,false), (ord-1)::int
    from jsonb_array_elements(p_links) with ordinality t(l,ord)
    where l->>'url' ~ '^https?://' and coalesce(l->>'host','')<>''
    on conflict (evidence_id,url) do nothing;
    get diagnostics v_n = row_count;
  end if;
  insert into pipeline.evidence_link_index_state(evidence_id,status,link_count,error,indexed_at)
  values (p_evidence_id, case when p_status='indexed' and v_n=0 then 'no_links' else p_status end, v_n, left(p_error,500), now())
  on conflict (evidence_id) do update set status=excluded.status, link_count=excluded.link_count, error=excluded.error, indexed_at=excluded.indexed_at;
  return v_n;
end $$;
revoke all on function public.svc_evidence_link_index_next_v1(int) from public, anon, authenticated;
revoke all on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.svc_evidence_link_index_next_v1(int) to service_role;
grant execute on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) to service_role;

-- Scheduled caller (same pattern as the other Layer 2 workers).
create or replace function pipeline.svc_invoke_evidence_link_index(p_limit int default 60)
returns bigint language plpgsql security definer set search_path to 'pipeline','vault','net','public'
as $$
declare v_key text; v_base text; v_id bigint;
begin
  if not exists (select 1 from public.svc_evidence_link_index_next_v1(1) x where jsonb_array_length(x)>0) then return null; end if;
  v_key := public.coursefinder_runtime_automation_key(); v_base := public.coursefinder_runtime_edge_base_url();
  if v_key is null or v_base is null then raise exception 'runtime automation secret or Edge base URL missing'; end if;
  select net.http_post(url:=rtrim(v_base,'/')||'/evidence-link-index',
    headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
    body:=jsonb_build_object('limit',p_limit), timeout_milliseconds:=120000) into v_id;
  return v_id;
end $$;
revoke all on function pipeline.svc_invoke_evidence_link_index(int) from public, anon, authenticated;

-- Schedule: every minute, up to 150 stored artifacts per run (backlog ~2.5 hours, then only new captures).
select cron.unschedule(jobid) from cron.job where jobname='evidence-link-index';
select cron.schedule('evidence-link-index','* * * * *',$c$select pipeline.svc_invoke_evidence_link_index(150);$c$);
