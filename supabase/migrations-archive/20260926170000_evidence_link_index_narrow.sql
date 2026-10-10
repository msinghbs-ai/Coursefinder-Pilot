-- Decision 146 (refined 26 Sep 2026): the evidence link index is a NARROW derived index.
-- Storing every link (1.75 million rows, 672 MB in a few hours) overloaded the pilot database and
-- made Auth time out. Only same-site, discovery-relevant links are kept (max 200 per page); the
-- complete link lists remain in the stored evidence. Batch selection uses the onboarding snapshot;
-- the index runs every 5 minutes (60 files) and the snapshot every 30 minutes (top 100).
create or replace function public.svc_evidence_link_index_record_v1(p_evidence_id uuid, p_status text, p_links jsonb, p_error text default null)
returns int language plpgsql security definer set search_path to 'pg_catalog','pipeline'
as $$
declare v_n int := 0;
begin
  delete from pipeline.evidence_links where evidence_id=p_evidence_id;
  if p_status='indexed' and jsonb_typeof(p_links)='array' then
    insert into pipeline.evidence_links(evidence_id,url,host,anchor_text,same_site,position)
    select p_evidence_id, left(l->>'url',1000), left(lower(l->>'host'),255), nullif(left(l->>'text',200),''), true, (ord-1)::int
    from jsonb_array_elements(p_links) with ordinality t(l,ord)
    where l->>'url' ~ '^https?://' and coalesce(l->>'host','')<>'' and coalesce((l->>'same_site')::boolean,false)
      and (lower(l->>'url')||' '||lower(coalesce(l->>'text','')))
          ~ '(study|course|degree|program|programme|handbook|undergrad|postgrad|find|search|explore|browse)'
      and lower(l->>'url') !~ '\.(pdf|jpg|jpeg|png|gif|svg|webp|mp4|docx?|xlsx?|zip)(\?|$)'
    order by ord
    limit 200
    on conflict (evidence_id,url) do nothing;
    get diagnostics v_n = row_count;
  end if;
  insert into pipeline.evidence_link_index_state(evidence_id,status,link_count,error,indexed_at)
  values (p_evidence_id, case when p_status='indexed' and v_n=0 then 'no_links' else p_status end, v_n, left(p_error,500), now())
  on conflict (evidence_id) do update set status=excluded.status, link_count=excluded.link_count, error=excluded.error, indexed_at=excluded.indexed_at;
  return v_n;
end $$;
revoke all on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) to service_role;

create or replace function public.svc_evidence_link_index_next_v1(p_limit int default 60)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type
        from pipeline.evidence_artifacts e
        left join pipeline.evidence_link_index_state st on st.evidence_id=e.id
        left join pipeline.sources s on s.id=e.source_id
        left join pipeline.layer2_onboarding_snapshot o on o.provider_id=s.provider_id
        where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
          and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
          and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
          and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
        order by coalesce(o.rank_no, 1000000), e.captured_at desc nulls last
        limit greatest(1,least(coalesce(p_limit,60),200))) x
$$;
revoke all on function public.svc_evidence_link_index_next_v1(int) from public, anon, authenticated;
grant execute on function public.svc_evidence_link_index_next_v1(int) to service_role;

-- The caller no longer runs the batch query just to check for work; the worker returns quickly when idle.
create or replace function pipeline.svc_invoke_evidence_link_index(p_limit int default 60)
returns bigint language plpgsql security definer set search_path to 'pipeline','vault','net','public'
as $$
declare v_key text; v_base text; v_id bigint;
begin
  v_key := public.coursefinder_runtime_automation_key(); v_base := public.coursefinder_runtime_edge_base_url();
  if v_key is null or v_base is null then raise exception 'runtime automation secret or Edge base URL missing'; end if;
  select net.http_post(url:=rtrim(v_base,'/')||'/evidence-link-index',
    headers:=jsonb_build_object('content-type','application/json','x-cf-pilot-key',v_key),
    body:=jsonb_build_object('limit',p_limit), timeout_milliseconds:=120000) into v_id;
  return v_id;
end $$;
revoke all on function pipeline.svc_invoke_evidence_link_index(int) from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname in ('evidence-link-index','layer2-onboarding-snapshot');
select cron.schedule('evidence-link-index','*/5 * * * *',$c$select pipeline.svc_invoke_evidence_link_index(60);$c$);
select cron.schedule('layer2-onboarding-snapshot','23,53 * * * *',$c$select security.layer2_onboarding_snapshot_refresh_v1(100);$c$);
