-- HELD, NOT A MIGRATION (do not move into supabase/migrations/ unless the Fill fields change must be backed out).
-- CF-247 Fill fields: forward recovery for migration 20261110030000.
-- It writes the two edited function bodies back, byte for byte, to the text they had before that migration (the text in migration 20261109220000 for the Provider
-- Catalogue page and in 20261106200000 for the Run & Validate service). Each is guarded by body md5: the live body must be the one 20261110030000 wrote
-- (2c906a2b1f7c346522ef7742d74039f1 for the page, fc036b02c22bf9128a80897635f784cb for the service) or already the earlier one, and the result must be the earlier body md5
-- (f3eb9fc6f8efa37566c36ac5ef2e8f0e for the page, b397cf320a689b6e981aa6747e7156b8 for the service), or the whole script stops.
-- It is a forward change, written as a new migration if it is ever used; it drops and deletes nothing. The new table pipeline.provider_description_quality, the new
-- functions and the two registry rows can stay (nothing calls them once the service and the page are back); the screen then needs the previous build, because the
-- Fill fields panel calls actions the earlier service does not have.
-- Replaces: the Fill fields bodies of security.admin_providers_page_v3 and public.admin_provider_description_run_v1
-- Retires: pipeline.provider_description_quality and the security.provider_description_quality_* , _fill_status_v1, _publication_read_v1, _cohort_cap_v1, _selection_multi_v1 functions (marked retiring; dropped later by a paste file, never by a migration)

do $g$
declare v_page text; v_run text;
begin
  select md5(p.prosrc) into v_page from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)');
  select md5(p.prosrc) into v_run from pg_proc p where p.oid = to_regprocedure('public.admin_provider_description_run_v1(text,jsonb)');
  if v_page not in ('2c906a2b1f7c346522ef7742d74039f1', 'f3eb9fc6f8efa37566c36ac5ef2e8f0e') then raise exception 'live security.admin_providers_page_v3 is neither the Fill fields text nor the earlier one (body md5 %)', v_page; end if;
  if v_run not in ('fc036b02c22bf9128a80897635f784cb', 'b397cf320a689b6e981aa6747e7156b8') then raise exception 'live public.admin_provider_description_run_v1 is neither the Fill fields text nor the earlier one (body md5 %)', v_run; end if;
end $g$;

-- the Provider Catalogue page, earlier text
CREATE OR REPLACE FUNCTION security.admin_providers_page_v3(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
 -- fixed: a plan setting, not an operational value. Without it the page statement is planned once with its filters unknown after five calls on a connection
 -- (measured: 0.3 s becomes 4 to 10 s for the Admission, Website and Zoho filters), the same defect as in the facts function.
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'provider'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_query text:=nullif(trim(coalesce(p_args->>'query','')),'');
  v_country text:=nullif(trim(coalesce(p_args->>'country_code','')),'');
  v_subdivision text:=nullif(trim(coalesce(p_args->>'subdivision_code','')),'');
  v_lifecycle text:=nullif(trim(coalesce(p_args->>'lifecycle_status','')),'');
  v_publication text:=nullif(trim(coalesce(p_args->>'publication_status','')),'');
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_adapter text:=nullif(trim(coalesce(p_args->>'adapter','')),'');
  v_desc text:=nullif(lower(trim(coalesce(p_args->>'description',''))),'');
  v_adm text:=nullif(lower(trim(coalesce(p_args->>'admission',''))),'');
  v_tier text:=nullif(lower(trim(coalesce(p_args->>'source_tier',''))),'');
  v_web text:=nullif(lower(trim(coalesce(p_args->>'website',''))),'');
  v_zoho text:=nullif(lower(trim(coalesce(p_args->>'zoho',''))),'');
  v_type text:=nullif(trim(coalesce(p_args->>'provider_type','')),'');
  v_need_facts boolean;
  v_scan_feeds boolean;
  v_page_feeds boolean;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_desc is not null and v_desc not in ('filled','missing') then raise exception 'unsupported description filter: %',v_desc using errcode='22023'; end if;
  if v_adm is not null and v_adm not in ('pending','held','declined','admitted') then raise exception 'unsupported admission filter: %',v_adm using errcode='22023'; end if;
  if v_tier is not null and v_tier not in ('stored','direct','firecrawl','registry_factual','unknown') then raise exception 'unsupported source tier filter: %',v_tier using errcode='22023'; end if;
  if v_web is not null and v_web not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported website filter: %',v_web using errcode='22023'; end if;
  if v_zoho is not null and v_zoho not in ('matched','pending','missing','not_applicable') then raise exception 'unsupported zoho filter: %',v_zoho using errcode='22023'; end if;
  if v_type is not null and v_type<>'unclassified' and not exists (select 1 from ref.provider_types pt where pt.code=v_type) then raise exception 'unsupported provider type filter: %',v_type using errcode='22023'; end if;
  -- the description facts are worked out for every provider only when a filter or a sort needs them
  -- Description (filled, missing) and the Description sort read the provider's own description column, so they need no facts. The pipeline facts are worked out
  -- only for a filter or sort that needs them, and only for the providers that already pass the filters on the provider's own columns.
  v_need_facts:=coalesce(v_adm,v_tier,v_web,v_zoho) is not null
    or v_sort in ('admission','source','desc_admitted','reader','last_read','next_retry','layer4','canonical','website','zoho','mismatch');

  -- The two feed candidate scans read every provider, so they run only when a Website or Zoho filter or sort needs them across the whole set, or when the
  -- screen shows a feed column (it then sends feeds=true) for the rows of the page. Otherwise those three fields come back null.
  v_scan_feeds:=coalesce(v_web,v_zoho) is not null or v_sort in ('website','zoho','mismatch');
  v_page_feeds:=v_scan_feeds or lower(coalesce(p_args->>'feeds',''))='true';

  return (
    -- Same design as v2 (CF-247 W34): the page is chosen first on the light columns; the per-provider counts, the adapter status, the evidence count and
    -- the new columns are worked out for the rows of the page only. The adapter status is worked out for every matching provider only when the Adapter
    -- filter or sort needs it, the course count only for the Courses sort, the registration, scholarship and coverage values only for their own sort.
    with cand as (
      -- the providers that pass the filters on the provider's own columns (query, country, state, lifecycle, publication, group, type, Description)
      select p.id
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        left join ref.subdivisions ps on ps.id=p.subdivision_id
       where
        (
          v_query is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||v_query||'%'
          or coalesce(p.stable_key,'') ilike '%'||v_query||'%'
          or coalesce(p.primary_city,'') ilike '%'||v_query||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||v_query||'%'
          or coalesce(c.name,'') ilike '%'||v_query||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||v_query||'%'
          or coalesce(ps.code,'') ilike '%'||v_query||'%'
          or coalesce(ps.name,'') ilike '%'||v_query||'%'
        )
        and (v_country is null or c.iso_alpha2::text=upper(v_country))
        and (v_subdivision is null or ps.code=upper(v_subdivision))
        and (v_lifecycle is null or p.lifecycle_status=v_lifecycle)
        and (v_publication is null or p.publication_status=v_publication)
        and (v_group is null or p.id in (select security.university_group_provider_ids(v_group)))
        and (v_type is null or (v_type='unclassified' and p.provider_type_id is null) or p.provider_type_id=(select pt.id from ref.provider_types pt where pt.code=v_type))
        and (v_desc is null or (v_desc='filled')=(nullif(btrim(p.description),'') is not null))
    ), facts as materialized (
      select * from security.provider_catalogue_facts_v1(array(select x.id from cand x), v_scan_feeds) where v_need_facts
    ), base as (
      select
        p.id,p.display_name,p.canonical_name,c.iso_alpha2::text country_code,c.default_currency_code::text currency_code,
        ps.name subdivision_name,p.primary_city city,p.last_verified_at,p.provider_type_id,p.lifecycle_status,p.publication_status,p.updated_at,
        case when v_adapter is not null or v_sort='adapter' then security.provider_adapter_status_v1(p.id) end adapter_status,
        case when v_sort='courses' then (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) end course_count,
        case when v_sort='scholarships' then (select count(*)::bigint from scholarship.scholarships sc where sc.provider_id=p.id) end scholarship_count,
        case when v_sort='registration' then (select lower(pr.registration_scheme||' '||pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=p.id order by pr.checked_at desc nulls last,pr.id limit 1) end registration_key,
        case when v_sort='coverage' then (select ac.disposition from pipeline.aer_provider_coverage ac where ac.provider_id=p.id) end coverage_key,
        (nullif(btrim(p.description),'') is not null) description_filled,f.admission_state,f.source_tier,f.admitted_at,f.reader_state,f.last_read_ok_at,f.next_retry_at,f.l4_status,f.canonical_status,f.website_state,f.zoho_state,f.mismatch
      from cand x
      join catalogue.providers p on p.id=x.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      left join facts f on f.provider_id=p.id
      where
        (v_adm is null or f.admission_state=v_adm)
        and (v_tier is null or f.source_tier=v_tier)
        and (v_web is null or f.website_state=v_web)
        and (v_zoho is null or f.zoho_state=v_zoho)
    ), filtered as (
      select * from base
       where v_adapter is null
          or (v_adapter = 'any' and adapter_status not in ('none', 'no_courses'))
          or adapter_status = v_adapter
    ), numbered as (
      select f.id,count(*) over()::bigint total_count,row_number() over (order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(f.display_name,f.canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(f.display_name,f.canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then f.country_code end asc,
        case when v_sort='country' and v_dir='desc' then f.country_code end desc,
        case when v_sort='currency' and v_dir='asc' then f.currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then f.currency_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(f.subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(f.subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(f.city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(f.city,'')) end desc,
        case when v_sort='type' and v_dir='asc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'~') end asc,
        case when v_sort='type' and v_dir='desc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'') end desc,
        case when v_sort='courses' and v_dir='asc' then f.course_count end asc,
        case when v_sort='courses' and v_dir='desc' then f.course_count end desc,
        case when v_sort='adapter' and v_dir='asc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end asc,
        case when v_sort='adapter' and v_dir='desc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end desc,
        case when v_sort='verified' and v_dir='asc' then f.last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then f.last_verified_at end desc nulls last,
        -- the new sorts. Unknown (no value held) is last in both directions, as on the Course catalogue's time sorts.
        case when v_sort='registration' and v_dir='asc' then f.registration_key end asc nulls last,
        case when v_sort='registration' and v_dir='desc' then f.registration_key end desc nulls last,
        case when v_sort='scholarships' and v_dir='asc' then f.scholarship_count end asc,
        case when v_sort='scholarships' and v_dir='desc' then f.scholarship_count end desc,
        case when v_sort='coverage' and v_dir='asc' then f.coverage_key end asc nulls last,
        case when v_sort='coverage' and v_dir='desc' then f.coverage_key end desc nulls last,
        case when v_sort='lifecycle' and v_dir='asc' then f.lifecycle_status end asc,
        case when v_sort='lifecycle' and v_dir='desc' then f.lifecycle_status end desc,
        case when v_sort='publication' and v_dir='asc' then f.publication_status end asc,
        case when v_sort='publication' and v_dir='desc' then f.publication_status end desc,
        case when v_sort='modified' and v_dir='asc' then f.updated_at end asc nulls last,
        case when v_sort='modified' and v_dir='desc' then f.updated_at end desc nulls last,
        case when v_sort='description' and v_dir='asc' then f.description_filled::int end asc,
        case when v_sort='description' and v_dir='desc' then f.description_filled::int end desc,
        case when v_sort='admission' and v_dir='asc' then f.admission_state end asc nulls last,
        case when v_sort='admission' and v_dir='desc' then f.admission_state end desc nulls last,
        case when v_sort='source' and v_dir='asc' then f.source_tier end asc nulls last,
        case when v_sort='source' and v_dir='desc' then f.source_tier end desc nulls last,
        case when v_sort='desc_admitted' and v_dir='asc' then f.admitted_at end asc nulls last,
        case when v_sort='desc_admitted' and v_dir='desc' then f.admitted_at end desc nulls last,
        case when v_sort='reader' and v_dir='asc' then f.reader_state end asc nulls last,
        case when v_sort='reader' and v_dir='desc' then f.reader_state end desc nulls last,
        case when v_sort='last_read' and v_dir='asc' then f.last_read_ok_at end asc nulls last,
        case when v_sort='last_read' and v_dir='desc' then f.last_read_ok_at end desc nulls last,
        case when v_sort='next_retry' and v_dir='asc' then f.next_retry_at end asc nulls last,
        case when v_sort='next_retry' and v_dir='desc' then f.next_retry_at end desc nulls last,
        case when v_sort='layer4' and v_dir='asc' then f.l4_status end asc nulls last,
        case when v_sort='layer4' and v_dir='desc' then f.l4_status end desc nulls last,
        case when v_sort='canonical' and v_dir='asc' then f.canonical_status end asc nulls last,
        case when v_sort='canonical' and v_dir='desc' then f.canonical_status end desc nulls last,
        case when v_sort='website' and v_dir='asc' then f.website_state end asc nulls last,
        case when v_sort='website' and v_dir='desc' then f.website_state end desc nulls last,
        case when v_sort='zoho' and v_dir='asc' then f.zoho_state end asc nulls last,
        case when v_sort='zoho' and v_dir='desc' then f.zoho_state end desc nulls last,
        case when v_sort='mismatch' and v_dir='asc' then f.mismatch end asc nulls last,
        case when v_sort='mismatch' and v_dir='desc' then f.mismatch end desc nulls last,
        lower(coalesce(f.display_name,f.canonical_name)),f.id) ord
      from filtered f
    ), keys as (
      select n.id,n.total_count,n.ord from numbered n where n.ord>v_offset and n.ord<=v_offset+v_limit
    ), pfacts as (
      -- the page's rows only: array(...) is an empty array, never null, when the page is empty (null would mean every provider)
      select * from security.provider_catalogue_facts_v1(array(select k.id from keys k), v_page_feeds)
    ), reg as (
      select distinct on (pr.provider_id) pr.provider_id,jsonb_build_object('scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'checked_at',pr.checked_at) j
        from catalogue.provider_registrations pr where pr.provider_id in (select k.id from keys k)
       order by pr.provider_id,pr.checked_at desc nulls last,pr.id
    ), sch as (
      select s.provider_id,jsonb_build_object('total',count(*),'published',count(*) filter (where s.publication_status='published' and s.lifecycle_status='active')) j
        from scholarship.scholarships s where s.provider_id in (select k.id from keys k) group by s.provider_id
    ), cov as (
      select ac.provider_id,jsonb_build_object('disposition',ac.disposition,'discovery',ac.discovery_state,'extraction',ac.extraction_state,'admission',ac.admission_state,
               'matrix_active',ac.matrix_active,'course_requirements_active',ac.course_req_active,'as_at',ac.updated_at) j
        from pipeline.aer_provider_coverage ac where ac.provider_id in (select k.id from keys k)
    ), page as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select pt.code from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_code,
        (select pt.name from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_name,
        p.provider_type_basis,
        exists (select 1 from pipeline.manual_locks ml where ml.entity='provider' and ml.entity_id=p.id and ml.field='provider_type_id') provider_type_locked,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        security.provider_adapter_status_v1(p.id) adapter_status,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count,
        p.description description_text,
        k.ord
      from keys k
      join catalogue.providers p on p.id=k.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
    )
    select jsonb_build_object(
      'items',coalesce((select jsonb_agg((to_jsonb(o)-'ord'-'description_text')||jsonb_build_object(
                'university_groups',security.provider_university_groups(o.id),
                'registration',(select r.j from reg r where r.provider_id=o.id),
                'scholarships',coalesce((select s.j from sch s where s.provider_id=o.id),jsonb_build_object('total',0,'published',0)),
                'entry_coverage',(select cv.j from cov cv where cv.provider_id=o.id),
                'pdesc',coalesce((select to_jsonb(pf)-'provider_id' from pfacts pf where pf.provider_id=o.id),'{}'::jsonb)||jsonb_build_object('text',o.description_text)) order by o.ord) from page o),'[]'::jsonb),
      'total',coalesce((select max(total_count) from keys),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir,
      'columns_profile','provider_columns_v1'
    )
  );
end
$function$;

-- the Run & Validate service, earlier text
create or replace function public.admin_provider_description_run_v1(p_action text,p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid:=auth.uid(); v_rank int:=security.current_role_rank(); c pipeline.provider_description_cohorts%rowtype;
 v_res jsonb; v_preview jsonb; v_fresh jsonb; x jsonb; v_id uuid; v_reason text:=btrim(coalesce(p_args->>'reason','')); v_n int:=0; v_run uuid; v_why text;
 v_mode text; v_history jsonb; v_rule text; v_diagnosis jsonb; v_context jsonb; v_issue bigint; v_ai_request bigint; v_ai_model text; v_ai_why text; v_job pipeline.automation_catalogue%rowtype; v_dispatch_error text; v_dispatch_sqlstate text;
begin
 if v_actor is null or v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_job from pipeline.automation_catalogue where jobname='provider-description-read';
 if p_action='verify' and v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
 if p_action='capabilities' then
 return jsonb_build_object('contract','provider-description-run-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
 'can_explain',v_rank>=coalesce(v_job.control_rank,6),'can_diagnose',security.pipeline_num_v1('ops.ai_diagnosis_on',0)>=1 and security.ai_use_allowed_v1('ops_diagnose') and nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','') is not null,'ai_diagnosis_reason','AI assistance requires the existing approved Operations diagnosis switch, model and spending guards plus an existing open issue linked to this exact provider and evidence. Explain evidence always uses stored checks.',
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',k.iso_alpha2,'label',coalesce(to_jsonb(k)->>'name',to_jsonb(k)->>'country_name',k.iso_alpha2::text),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.countries'),'[]')?k.iso_alpha2::text)) from ref.countries k where k.iso_alpha2 in ('AU','NZ','CA')),'[]'),
 'provider_types',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'label',coalesce(to_jsonb(t)->>'label',to_jsonb(t)->>'name',t.code),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.provider_types'),'[]')?t.code)) from ref.provider_types t),'[]'),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.id,'name',coalesce(p.display_name,p.canonical_name),'country',k.iso_alpha2,'type',t.code) order by coalesce(p.display_name,p.canonical_name)) from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id where security.provider_description_scope_v1(p.id)),'[]'),
 'min_size',1,'max_size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,'default_size',security.pipeline_num_v1('batch.provider_description',3)::int,
 'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
 'model',(select model_identifier from pipeline.central_ai_settings where id=1),'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,
 'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
 'policy',jsonb_build_object('countries',security.toolset_setting('pipeline','pdesc.countries'),'types',security.toolset_setting('pipeline','pdesc.provider_types'),'provider_keys',security.toolset_setting('pipeline','pdesc.provider_keys'),'ai_usd_max',security.pipeline_num_v1('pdesc.ai_usd_max',1),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'reserved_usd',(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads),'remaining_usd',greatest(0,security.pipeline_num_v1('pdesc.ai_usd_max',1)-(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')-(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads)),'actual_ai_calls',(select coalesce(sum(ai_calls),0) from pipeline.provider_description_reads),'recorded_billable_calls',(select coalesce(sum(calls),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'recorded_cost_usd',(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'ai_call_counter_scope','reported model calls since provider-description-autonomy instrumentation; ledger calls are separate recorded billable calls','budget_period','lifetime pilot','required_approval','Individual human Layer 4 decision'));
 elsif p_action='preview' then
 v_res:=security.provider_description_selection_v1(p_args);
 insert into pipeline.provider_description_cohorts(requested_by,selection,snapshot,expires_at)
 values(v_actor,p_args||jsonb_build_object('mode',coalesce(nullif(p_args->>'mode',''),'stored')),v_res,now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int)) returning id into v_id;
 return v_res||jsonb_build_object('token',v_id,'preview_token',v_id,'expires_at',now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int));
 elsif p_action='prepare' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason is shorter than the governed minimum' using errcode='22023'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'preview_token','')::uuid and requested_by=v_actor for update;
 if c.id is null then raise exception 'unknown owned preview' using errcode='42501'; end if;
 if c.state in ('prepared','started') then return security.provider_description_run_result_v1(c.id); end if;
 if c.expires_at<now() then raise exception 'preview expired; preview again' using errcode='22023'; end if;
 v_fresh:=security.provider_description_selection_v1(c.selection);
 for x in select * from jsonb_array_elements(c.snapshot->'providers') where (value->>'eligible')::boolean loop
  if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where f->>'provider_id'=x->>'provider_id' and (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description' and f->>'last_read_id' is not distinct from x->>'last_read_id') then raise exception 'preview changed; preview again' using errcode='22023'; end if;
  v_n:=v_n+1;
  insert into pipeline.provider_description_cohort_members(cohort_id,provider_id,evidence_id,pick,snapshot) values(c.id,(x->>'provider_id')::uuid,(x->>'evidence_id')::uuid,v_n,x);
 end loop;
 if v_n=0 then raise exception 'no eligible provider with approved evidence in this preview' using errcode='22023'; end if;
 update pipeline.provider_description_cohorts set state='prepared',reason=v_reason,prepared_at=now() where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','cohort_prepare',c.id::text,jsonb_build_object('selected',v_n,'reason',v_reason,'selection',c.selection),v_actor);
 return security.provider_description_run_result_v1(c.id);
 elsif p_action='run' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot start this job' using errcode='42501'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'cohort_id','')::uuid and requested_by=v_actor for update;
 if c.id is null or c.state='preview' then raise exception 'unknown owned fixed cohort' using errcode='42501'; end if;
 if c.run_id is not null then return security.provider_description_run_result_v1(c.id)||jsonb_build_object('repeat',true); end if;
 if (select count(*) from pipeline.provider_description_cohort_members where cohort_id=c.id)>least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int then
   raise exception 'current_cap_changed: the fixed cohort exceeds the current governed cap; prepare a new cohort' using errcode='22023';
 end if;
 -- Same task kind, catalogue permission, pause/spend/review rules and provider-description job. Never a second scheduler.
 v_why:=case when not coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read' then 'job_not_allowlisted'
 when v_job.jobname is null then 'job_not_catalogued'
 when not exists(select 1 from cron.job where jobname='provider-description-read' and active) then 'job_paused'
 when security.pipeline_num_v1('pdesc.enabled',0)<1 then 'reader_off'
 when not security.ai_use_allowed_v1('provider_description') then 'ai_refused'
 when (select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')>=security.pipeline_num_v1('pdesc.ai_usd_max',1) then 'ai_ceiling'
 when (select count(*) from pipeline.layer4_review_items where field_code='provider_description' and status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then 'review_full' end;
 -- Policy/capacity holds are durable: the fixed cohort stays recoverable and the existing scheduled job resumes it.
 for x in select m.snapshot from pipeline.provider_description_cohort_members m where m.cohort_id=c.id order by m.pick loop
   v_fresh:=security.provider_description_selection_v1(c.selection||jsonb_build_object('provider_id',x->>'provider_id','size',1));
   if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description') then
     update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('eligibility_reason','selection_changed_before_run','eligible',false) where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid; continue;
   end if;
   insert into pipeline.provider_description_reads(provider_id) values((x->>'provider_id')::uuid) on conflict do nothing returning id into v_id;
   if v_id is null then select id into v_id from pipeline.provider_description_reads where provider_id=(x->>'provider_id')::uuid and state in ('queued','reading','proposed') order by created_at desc limit 1; end if;
   update pipeline.provider_description_cohort_members set read_id=v_id where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid;
   v_n:=v_n+1; v_id:=null;
 end loop;
 update pipeline.provider_description_cohorts set state='started' where id=c.id;
 if v_why is null and v_n>0 then
   perform set_config('cf.pdesc_run_now',c.id::text,true);
   begin
     v_res:=security.provider_description_fire_v1();
   exception when others then
     -- OTHERS deliberately excludes query cancellation: the caller's statement/lock limits remain authoritative.
     get stacked diagnostics v_dispatch_error=message_text,v_dispatch_sqlstate=returned_sqlstate;
     v_res:=jsonb_build_object('sent',0,'parked',true,'reason','reader_dispatch_failed','error',v_dispatch_error,'sqlstate',v_dispatch_sqlstate,'retry_strategy','existing provider-description-read schedule resumes this saved queued cohort');
   end;
 else v_res:=jsonb_build_object('sent',0,'parked',true,'reason',coalesce(v_why,'selection_changed_before_run')); end if;
 insert into pipeline.admin_jobs(kind,lane,state,title,args,result,error,requested_by,reason,started_at,finished_at,scope,outcome)
 values('job_run_now','run_now',case when v_dispatch_error is not null then 'failed' when v_why is null then 'done' else 'cancelled' end,'Provider descriptions: bounded Run Now',jsonb_build_object('job','provider-description-read','cohort_id',c.id,'idempotency_key',c.request_key),v_res||jsonb_build_object('selected',v_n,'admitted',0,'publication_measured_separately',true),v_dispatch_error,v_actor,c.reason,now(),clock_timestamp(),'cohort:'||c.id,case when v_dispatch_error is not null then 'failed_retryable' when v_why is not null then 'blocked_policy' else 'succeeded_no_movement' end) returning id into v_run;
 update pipeline.provider_description_cohorts set run_id=v_run where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','run_now','provider-description-read',jsonb_build_object('cohort_id',c.id,'run_id',v_run,'dispatch',v_res,'reason',c.reason),v_actor);
 return security.provider_description_run_result_v1(c.id)||jsonb_build_object('dispatch',v_res);
 elsif p_action in ('saved','verify','diagnose') then
 if p_action='diagnose' and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor;
 elsif nullif(p_args->>'cohort_id','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'cohort_id')::uuid and requested_by=v_actor;
 else select * into c from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc,id desc limit 1; end if;
 if p_action='diagnose' then
   if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot diagnose this job' using errcode='42501'; end if;
   if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason required'; end if;
   if c.id is null and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor; end if;
   if c.id is null then raise exception 'owned saved evidence required' using errcode='42501'; end if;
   select coalesce(r.rule,m.snapshot->>'eligibility_reason'),coalesce(r.reason,m.snapshot->>'reason') into v_rule,v_why from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid;
   if v_rule is null then select x->>'eligibility_reason',x->>'reason' into v_rule,v_why from jsonb_array_elements(c.snapshot->'providers') x where x->>'provider_id'=p_args->>'provider_id'; end if;
   if v_rule is null then raise exception 'provider is not in owned saved evidence' using errcode='42501'; end if;
   v_diagnosis:=jsonb_build_object('method','stored_checks','rule',v_rule,'explanation',coalesce(v_why,case v_rule when 'no_verified_stored_source' then 'A current official About/Overview page stored against this exact provider is needed.' when 'unchanged_unsuitable_evidence' then 'The same evidence previously failed or was rejected. A changed approved source is needed before another AI read.' when 'review_full' then 'The validated proposal is parked until Layer 4 capacity becomes available; no further AI read is needed.' else 'Inspect the official source, identity references and validation checks. Only the existing human Layer 4 decision can authorise admission.' end),'ai_used',false,'cost_usd',0,'ai_reason','Provider-description AI diagnostics have no approved existing route.','at',now());
   -- AI is advice through the existing Operations lane only, bound to an already recorded issue and the exact stored source.
   select coalesce((select m.snapshot||jsonb_build_object('evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'checks',r.checks,'sentences',r.proposal->'sentences') from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid),
     (select z from jsonb_array_elements(c.snapshot->'providers') z where z->>'provider_id'=p_args->>'provider_id')) into v_context;
   v_ai_model:=nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','');
   v_ai_why:=case when security.pipeline_num_v1('ops.ai_diagnosis_on',0)<1 then 'ops.ai_diagnosis_on is 0'
      when v_ai_model is null then 'no approved Operations diagnosis model'
      when not security.ai_use_allowed_v1('ops_diagnose') then 'existing Operations AI spending guard refuses assistance'
      when nullif(v_context->>'evidence_id','') is null then 'no exact stored evidence reference for an existing issue' end;
   if v_ai_why is null then
    select i.id into v_issue from pipeline.integration_issues i where i.status not in ('closed','superseded') and (p_args->>'provider_id')::uuid=any(i.provider_ids)
      and jsonb_path_exists(i.evidence,'$.**.evidence_id ? (@ == $id)',jsonb_build_object('id',v_context->>'evidence_id')) order by i.id desc limit 1;
    if v_issue is null then v_ai_why:='no existing open integration issue links this exact provider and stored evidence'; end if;
   end if;
   if v_ai_why is null then
    perform pg_advisory_xact_lock(hashtext('cf247 pdesc diagnosis '||v_issue::text)); -- fixed: duplicate request suppression for the existing issue/evidence.
    select q.id into v_ai_request from pipeline.ops_ai_diagnosis_requests q where q.issue_id=v_issue and q.context->>'provider_description_evidence_id'=v_context->>'evidence_id' and q.state in ('queued','leased','answered','refused') order by q.id desc limit 1;
    if v_ai_request is null then
     insert into pipeline.ops_ai_diagnosis_requests(issue_id,context,model,note)
     values(v_issue,jsonb_build_object('issue',v_issue,'provider_id',p_args->>'provider_id','provider_description_evidence_id',v_context->>'evidence_id','evidence',v_context,'question','Explain why this official source or claim is unsuitable and which evidence is missing. Advice only; do not authorise a description or change any setting.',
       'deterministic',v_diagnosis,'root_causes',(select jsonb_agg(jsonb_build_object('code',rc.code,'class',rc.class,'title',rc.title,'description',rc.description)) from pipeline.ops_root_causes rc)),v_ai_model,'Provider description evidence explanation; advice through existing Operations diagnosis') returning id into v_ai_request;
    end if;
    v_diagnosis:=v_diagnosis||jsonb_build_object('request_id',v_ai_request,'request_status','queued','integration_issue_id',v_issue,'model',v_ai_model,'ai_reason','Queued through the existing Operations diagnosis worker; no approval or settings authority.');
   else v_diagnosis:=v_diagnosis||jsonb_build_object('ai_reason',v_ai_why); end if;
   update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('diagnosis',v_diagnosis) where cohort_id=c.id and provider_id=(p_args->>'provider_id')::uuid;
   update pipeline.provider_description_cohorts set snapshot=jsonb_set(snapshot,'{providers}',(select jsonb_agg(case when z->>'provider_id'=p_args->>'provider_id' then z||jsonb_build_object('diagnosis',v_diagnosis) else z end) from jsonb_array_elements(snapshot->'providers') z)) where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','explain_evidence',c.id::text,jsonb_build_object('provider_id',p_args->>'provider_id','reason',v_reason,'diagnosis',v_diagnosis),v_actor);
   return v_diagnosis;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('cohort_id',h.id,'state',h.state,'created_at',h.created_at,'reason',h.reason,'run_id',h.run_id) order by h.created_at desc),'[]') into v_history from (select * from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int) h;
 if c.state='preview' then
   v_preview:=jsonb_set(c.snapshot,'{providers}',coalesce((select jsonb_agg(z||case when z->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(z->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',z->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(z->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end) from jsonb_array_elements(c.snapshot->'providers') z),'[]'::jsonb));
   return jsonb_build_object('preview',v_preview||jsonb_build_object('token',c.id,'expires_at',c.expires_at),'scope',c.selection,'history',v_history);
 end if;
 if c.id is null then return jsonb_build_object('history',v_history,'providers','[]'::jsonb,'runs','[]'::jsonb); end if;
 v_res:=security.provider_description_run_result_v1(c.id);
 if p_action='verify' then
   update pipeline.provider_description_cohorts set verified_at=now(),verification=v_res-'last_verification' where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify',c.id::text,jsonb_build_object('totals',v_res->'totals','as_at',now(),'reason','Operator requested actual catalogue and consumer read-back'),v_actor);
 end if;
 return v_res||jsonb_build_object('history',v_history);
 end if;
 raise exception 'unknown provider-description action %',p_action using errcode='22023';
end $function$;

do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)')) <> 'f3eb9fc6f8efa37566c36ac5ef2e8f0e' then raise exception 'recovery post-check: the page body is not the earlier text'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.admin_provider_description_run_v1(text,jsonb)')) <> 'b397cf320a689b6e981aa6747e7156b8' then raise exception 'recovery post-check: the service body is not the earlier text'; end if;
end $c$;
