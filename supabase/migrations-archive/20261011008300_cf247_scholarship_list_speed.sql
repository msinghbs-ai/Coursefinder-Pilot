-- CF-247 bug (Platform Admin, 11 Oct 2026 10:57, screenshot): Scholarships list "canceling statement due to statement timeout" when
-- returning to the screen. The list worked out publishability for every scholarship (about 3.6 s) and several counts per row before
-- choosing the 25 on the page (5.5 to 5.8 s; past 8 s while pages are being read). Publishability is now worked out only when
-- unpublished scholarships are listed, and counts and the value label only for the rows on the page. Same columns.
-- md5-checked before and after; nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.admin_scholarships_page(jsonb)": "1e0e5ca08c099dcc4f14e3515997b76b"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.admin_scholarships_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'scholarship'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  return (
    -- 11 Oct 2026: publishability (about 3.6 s for every scholarship) is worked out only when unpublished ones are listed;
    -- counts and the value label are built for the rows on the page only. The list of published scholarships needs neither.
    with pub as materialized (select scholarship_id, publishable, missing from security.scholarship_publishability_v1()
                               where coalesce(p_args->>'status', '') <> 'published'),
    mapped as (select m.scholarship_id, count(*)::int n from scholarship.course_mappings m where m.mapping_state = 'mapped' group by 1),
    base as (
      select s.id,s.stable_key,s.name,s.scholarship_type,s.description,s.audience,s.nationalities,
        case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce(pb.publishable, false) then 'ready' else 'held' end status,
        coalesce(pb.missing, '{}'::text[]) held_reasons,s.award_value_text,s.award_value_type,s.award_percentage,s.award_amount,s.award_currency_code,s.academic_year,s.application_required,s.application_open_date,s.application_close_date,s.lifecycle_status,s.publication_status,s.source_url,s.created_at,s.updated_at,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
        s.evidence_id,coalesce(mp.n,0) mapped_course_count
      from scholarship.scholarships s
      left join catalogue.providers p on p.id=s.provider_id
      left join ref.countries co on co.id=p.country_id
      left join pub pb on pb.scholarship_id=s.id
      left join mapped mp on mp.scholarship_id=s.id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null
          or s.name ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.description,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.award_value_text,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.scholarship_type,'') ilike '%'||trim(p_args->>'query')||'%'
          or coalesce(s.academic_year::text,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (v_provider_id is null or s.provider_id=v_provider_id)
        and (nullif(p_args->>'lifecycle_status','') is null or s.lifecycle_status=p_args->>'lifecycle_status')
        and (nullif(p_args->>'publication_status','') is null or s.publication_status=p_args->>'publication_status')
        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')
        and (nullif(trim(coalesce(p_args->>'course','')),'') is null or exists (
              select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
               where cm.scholarship_id=s.id and cm.mapping_state='mapped'
                 and (c.canonical_title ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'course')||'%' or coalesce(c.course_code,'') ilike trim(p_args->>'course')||'%')))
    ), numbered as (
      select *,count(*) over() total_count from base
       where case when coalesce(p_args->>'status','') = '' then status <> 'inactive' else status = p_args->>'status' end
    ), ordered as (
      select *, row_number() over () rn from (select * from numbered order by
        case when v_sort='scholarship' and v_dir='asc' then lower(name) end asc,
        case when v_sort='scholarship' and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(provider_name,'')) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(provider_name,'')) end desc,
        case when v_sort='type' and v_dir='asc' then lower(coalesce(scholarship_type,'')) end asc,
        case when v_sort='type' and v_dir='desc' then lower(coalesce(scholarship_type,'')) end desc,
        case when v_sort='audience' and v_dir='asc' then lower(coalesce(audience::text,'')) end asc,
        case when v_sort='audience' and v_dir='desc' then lower(coalesce(audience::text,'')) end desc,
        case when v_sort='award' and v_dir='asc' then coalesce(award_percentage,award_amount) end asc nulls last,
        case when v_sort='award' and v_dir='desc' then coalesce(award_percentage,award_amount) end desc nulls last,
        case when v_sort='year' and v_dir='asc' then academic_year end asc nulls last,
        case when v_sort='year' and v_dir='desc' then academic_year end desc nulls last,
        case when v_sort='close' and v_dir='asc' then application_close_date end asc nulls last,
        case when v_sort='close' and v_dir='desc' then application_close_date end desc nulls last,
        case when v_sort='courses' and v_dir='asc' then mapped_course_count end asc,
        case when v_sort='courses' and v_dir='desc' then mapped_course_count end desc,
        case when v_sort='publication' and v_dir='asc' then lower(coalesce(publication_status,'')) end asc,
        case when v_sort='publication' and v_dir='desc' then lower(coalesce(publication_status,'')) end desc,
        case when v_sort='updated' and v_dir='asc' then updated_at end asc,
        case when v_sort='updated' and v_dir='desc' then updated_at end desc,
        lower(name),id
      limit v_limit offset v_offset) q
    )
    select jsonb_build_object('items',coalesce(jsonb_agg((to_jsonb(o)-'total_count'-'evidence_id'-'rn')||jsonb_build_object(
        'value_label',scholarship.value_label(o.id),
        'cycle_count',(select count(*)::int from scholarship.offering_cycles oc where oc.scholarship_id=o.id),
        'window_count',(select count(*)::int from scholarship.application_windows aw where aw.scholarship_id=o.id),
        'evidence_count',(select count(*)::int from pipeline.evidence_artifacts e where e.entity_id=o.id)+case when o.evidence_id is not null then 1 else 0 end,
        'review_course_count',(select count(*)::int from scholarship.course_mapping_candidates mc where mc.scholarship_id=o.id and mc.status='needs_review'),
        'description_excerpt',left(regexp_replace(coalesce(o.description,''),'\s+',' ','g'),220)) order by o.rn),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,'status_counts',(select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select b.status, count(*) n from base b group by 1) z))
    from ordered o
  );
end
$function$;

do $post$
declare v_expected jsonb := '{"security.admin_scholarships_page(jsonb)": "a27526afafe6d7fbc501224024e0f26f"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
