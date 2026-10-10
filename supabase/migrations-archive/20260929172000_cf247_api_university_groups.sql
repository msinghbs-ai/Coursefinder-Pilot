-- CF-247 Decision 166: university groups in the consumer API (additive; consumer snapshots before and after).
--  * course search: filter university_groups (codes go8, atn, iru, run; 'au_' prefix accepted); provider.university_groups on items;
--  * scholarship search: same filter and provider.university_groups; new filter published_only (true = only scholarships
--    cleared for display under Decision 139);
--  * reference bundle: university_groups vocabulary (code, name, official page, member providers, course count) and
--    university_groups on each provider.
do $patch$
declare v text; v_before jsonb; v_after jsonb;
begin
  v_before:=security.consumer_api_snapshot_v1();

  if (select md5(prosrc) from pg_proc where oid='public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure)<>'11ca4c7aed8d9998db7e4b6f8aac1d6a' then
    raise exception 'website_edge_course_search_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.website_edge_course_search_v1(jsonb,int,int)'::regprocedure);
  if position($o$  v_providers text[] := api.website_text_array(f->'provider_ids');$o$ in v)=0
     or position($o$and (v_providers is null or d.provider_stable_key = any(v_providers))$o$ in v)=0
     or position($o$'legal_name',p.provider_name)$o$ in v)=0 then raise exception 'course search anchors not found'; end if;
  v:=replace(v,$o$  v_providers text[] := api.website_text_array(f->'provider_ids');$o$,
               $n$  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);$n$);
  v:=replace(v,$o$and (v_providers is null or d.provider_stable_key = any(v_providers))$o$,
               $n$and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=d.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))$n$);
  v:=replace(v,$o$'legal_name',p.provider_name)$o$,$n$'legal_name',p.provider_name,'university_groups',security.provider_university_groups(p.provider_id))$n$);
  execute v;

  if (select md5(prosrc) from pg_proc where oid='public.website_edge_scholarship_search_v1(jsonb,int,int)'::regprocedure)<>'d0342eabc45c3caba89ab7d07d1287be' then
    raise exception 'website_edge_scholarship_search_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('public.website_edge_scholarship_search_v1(jsonb,int,int)'::regprocedure);
  if position($o$  v_open boolean := coalesce((f->>'open_only')::boolean,false);$o$ in v)=0
     or position($o$      and (v_providers is null or pr.stable_key = any(v_providers))$o$ in v)=0
     or position($o$'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name)$o$ in v)=0 then raise exception 'scholarship anchors not found'; end if;
  v:=replace(v,$o$  v_open boolean := coalesce((f->>'open_only')::boolean,false);$o$,
               $n$  v_open boolean := coalesce((f->>'open_only')::boolean,false);
  v_published boolean := coalesce((f->>'published_only')::boolean,false);
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);$n$);
  v:=replace(v,$o$      and (v_providers is null or pr.stable_key = any(v_providers))$o$,
               $n$      and (v_providers is null or pr.stable_key = any(v_providers))
      and (not v_published or s.publication_status='published')
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=s.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))$n$);
  v:=replace(v,$o$'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name)$o$,
               $n$'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name,'university_groups',security.provider_university_groups(p.provider_id))$n$);
  execute v;

  if (select md5(prosrc) from pg_proc where oid='security.zoho_reference_bundle_live_v1()'::regprocedure)<>'33e7052d3bbdd0ba93fcb4a27c4953cc' then
    raise exception 'zoho_reference_bundle_live_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.zoho_reference_bundle_live_v1()'::regprocedure);
  if (length(v)-length(replace(v,$o$'display_name', security.provider_presentable_name(p.display_name),$o$,'')))/length($o$'display_name', security.provider_presentable_name(p.display_name),$o$)<>1
     or position($o$'top_study_areas',coalesce((select items from top_fields),'[]'::jsonb)
  )
);$o$ in v)=0 then raise exception 'bundle anchors not found'; end if;
  v:=replace(v,$o$'display_name', security.provider_presentable_name(p.display_name),$o$,
               $n$'display_name', security.provider_presentable_name(p.display_name),
      'university_groups', security.provider_university_groups(p.id),$n$);
  v:=replace(v,$o$'top_study_areas',coalesce((select items from top_fields),'[]'::jsonb)
  )
);$o$,$n$'top_study_areas',coalesce((select items from top_fields),'[]'::jsonb)
  )
) || jsonb_build_object('university_groups', coalesce((
  select jsonb_agg(jsonb_build_object(
           'code', replace(ic.code,'au_',''), 'name', ic.name, 'official_url', ic.official_url, 'country_code', 'AU',
           'providers', (select jsonb_agg(jsonb_build_object('provider_id', pv.stable_key, 'name', security.provider_presentable_name(coalesce(pv.display_name,pv.canonical_name))) order by pv.canonical_name)
                           from catalogue.provider_collection_memberships m join catalogue.providers pv on pv.id=m.provider_id
                          where m.collection_id=ic.id and m.status='active' and (m.valid_to is null or m.valid_to>=current_date)),
           'course_count', (select count(*) from search.course_documents d join catalogue.provider_collection_memberships m on m.provider_id=d.provider_id
                             where m.collection_id=ic.id and m.status='active' and (m.valid_to is null or m.valid_to>=current_date)))
         order by ic.name)
    from ref.institution_collections ic where ic.collection_type='university_group' and ic.status='active'), '[]'::jsonb));$n$);
  execute v;
  perform security.refresh_reference_bundle_cache_v1();

  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before university groups in the consumer API (Decision 166)',v_before),
    ('after university groups in the consumer API (Decision 166)',v_after);
end $patch$;
