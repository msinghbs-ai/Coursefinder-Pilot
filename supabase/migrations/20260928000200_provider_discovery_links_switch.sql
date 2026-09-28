-- CF-247 / R21 (option A, step 2): switch the link index to one row per provider link.
-- Proof before switching (28 Sep 2026): candidates from the per-provider table were identical to the
-- page-level index for all 648 providers (3,011 candidates; url, score and pages compared).
-- * the recorder writes provider_discovery_links (pages counted, longest link text kept);
-- * only evidence of providers still waiting for onboarding is indexed;
-- * layer2_catalogue_candidates_v1 reads the per-provider table (same scoring; v2 proof copy removed);
-- * the page-level index is emptied (447,678 rows, 188 MB); the table is kept empty for one release.
-- Consumer API: not touched (guard compared below).
do $switch$
declare v_before jsonb; v_after jsonb; v_diff jsonb; v_def text;
begin
  v_before:=security.consumer_api_snapshot_v1();

  if md5(pg_get_functiondef('public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text)'::regprocedure))<>'8696397371c09f648baadd532489ea18' then raise exception 'svc_evidence_link_index_record_v1 changed; aborting'; end if;
  if md5(pg_get_functiondef('public.svc_evidence_link_index_next_v1(integer)'::regprocedure))<>'7957741a50714e29bb7a0f0bd4766d9b' then raise exception 'svc_evidence_link_index_next_v1 changed; aborting'; end if;
  if md5(pg_get_functiondef('security.layer2_catalogue_candidates_v1(uuid,integer)'::regprocedure))<>'84970f30e61cd3ff7b0aabe786e9f571' then raise exception 'layer2_catalogue_candidates_v1 changed; aborting'; end if;

  execute $fn$
create or replace function public.svc_evidence_link_index_record_v1(p_evidence_id uuid, p_status text, p_links jsonb, p_error text default null)
returns integer language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_n int := 0; v_provider uuid;
begin
  select s.provider_id into v_provider from pipeline.evidence_artifacts e join pipeline.sources s on s.id=e.source_id where e.id=p_evidence_id;
  if p_status='indexed' and jsonb_typeof(p_links)='array' and v_provider is not null then
    insert into pipeline.provider_discovery_links as d(provider_id,url,anchor_text,pages,evidence_id,score_text,first_seen_at,last_seen_at)
    select v_provider, url, txt, 1, p_evidence_id, lower(coalesce(txt,'')), now(), now()
    from (select distinct on (left(l->>'url',1000)) left(l->>'url',1000) url, nullif(left(l->>'text',200),'') txt, ord
            from jsonb_array_elements(p_links) with ordinality t(l,ord)
           where l->>'url' ~ '^https?://' and coalesce(l->>'host','')<>'' and coalesce((l->>'same_site')::boolean,false)
             and (lower(l->>'url')||' '||lower(coalesce(l->>'text','')))
                 ~ '(study|course|degree|program|programme|handbook|undergrad|postgrad|find|search|explore|browse)'
             and lower(l->>'url') !~ '\.(pdf|jpg|jpeg|png|gif|svg|webp|mp4|docx?|xlsx?|zip)(\?|$)'
           order by left(l->>'url',1000), ord) x
    order by ord
    limit 200
    on conflict (provider_id,url) do update set
      pages=d.pages+1,
      anchor_text=case when length(coalesce(excluded.anchor_text,''))>length(coalesce(d.anchor_text,'')) then excluded.anchor_text else d.anchor_text end,
      score_text=greatest(d.score_text,excluded.score_text),
      last_seen_at=now();
    get diagnostics v_n = row_count;
  end if;
  insert into pipeline.evidence_link_index_state(evidence_id,status,link_count,error,indexed_at)
  values (p_evidence_id, case when p_status='indexed' and v_n=0 then 'no_links' else p_status end, v_n, left(p_error,500), now())
  on conflict (evidence_id) do update set status=excluded.status, link_count=excluded.link_count, error=excluded.error, indexed_at=excluded.indexed_at;
  return v_n;
end $f$;
$fn$;

  execute $fn$
create or replace function public.svc_evidence_link_index_next_v1(p_limit integer default 60)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type
        from pipeline.evidence_artifacts e
        left join pipeline.evidence_link_index_state st on st.evidence_id=e.id
        join pipeline.sources s on s.id=e.source_id
        join pipeline.layer2_onboarding_snapshot o on o.provider_id=s.provider_id
        where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
          and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
          and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
          and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
        order by o.rank_no, e.captured_at desc nulls last
        limit greatest(1,least(coalesce(p_limit,60),200))) x
$f$;
$fn$;

  v_def:=pg_get_functiondef('security.layer2_catalogue_candidates_v2(uuid,integer)'::regprocedure);
  execute replace(v_def,'security.layer2_catalogue_candidates_v2(','security.layer2_catalogue_candidates_v1(');
  drop function security.layer2_catalogue_candidates_v2(uuid,integer);

  truncate pipeline.evidence_links;

  v_after:=security.consumer_api_snapshot_v1();
  v_diff:=security.consumer_api_compare_v1(v_before,v_after);
  if jsonb_array_length(v_diff)>0 then raise exception 'consumer API output changed: %', v_diff; end if;
end $switch$;
revoke all on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.svc_evidence_link_index_next_v1(integer) from public, anon, authenticated;
grant execute on function public.svc_evidence_link_index_record_v1(uuid,text,jsonb,text) to service_role;
grant execute on function public.svc_evidence_link_index_next_v1(integer) to service_role;
revoke all on function security.layer2_catalogue_candidates_v1(uuid,integer) from public, anon, authenticated;
