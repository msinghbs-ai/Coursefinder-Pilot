CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_context(p_run_id uuid, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'public'
AS $function$
  select jsonb_build_object(
    'run_id',r.id,
    'country_code',co.iso_alpha2::text,
    'providers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'provider_id',x.provider_id,
        'provider_name',x.canonical_name,
        'website',x.website,
        'profile_id',x.profile_id,
        'items',x.items
      ) order by x.canonical_name)
      from (
        select p.id provider_id,p.canonical_name,p.website,lp.id profile_id,
          jsonb_agg(jsonb_build_object(
            'item_id',qi.id,'course_id',qi.course_id,'sample_rank',qi.sample_rank,
            'course_title',c.canonical_title,'course_code',c.course_code
          ) order by qi.sample_rank) items
        from pipeline.layer2_scale_qualification_items qi
        join catalogue.providers p on p.id=qi.provider_id
        join catalogue.courses c on c.id=qi.course_id
        join pipeline.sources s on s.provider_id=p.id
        join pipeline.layer2_source_profiles lp on lp.source_id=s.id
          and lp.authority_class='qualification_candidate'
          and lp.domain='course_facts'
          and lp.enabled and not lp.paused
        where qi.run_id=r.id and qi.status='qualifying'
        group by p.id,p.canonical_name,p.website,lp.id
        order by p.canonical_name
        limit least(greatest(coalesce(p_limit,5),1),10)
      ) x
    ),'[]'::jsonb)
  )
  from pipeline.layer2_scale_qualification_runs r
  join ref.countries co on co.id=r.country_id
  where r.id=p_run_id
$function$
