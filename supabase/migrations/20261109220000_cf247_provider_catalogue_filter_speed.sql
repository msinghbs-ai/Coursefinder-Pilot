-- CF-247 Provider Catalogue: whole-set filters and sorts in under a second (P1 fix to 20261109200000, found on live 9 Nov 2026).
-- What was wrong: with a Description, Admission, Source tier, Website or Zoho filter (or one of their sorts) the Admin showed "The database took too long to answer"
-- (3 to 10 seconds against the 8 second statement limit). Cause, measured with read-only EXPLAIN (ANALYZE) on the live project: security.provider_catalogue_facts_v1 is
-- a SQL-language function, and SQL functions are planned once with their arguments unknown. For p_ids = null (every provider) the planner then expected about 25
-- providers instead of 3,103 and chose row-by-row nested loops that re-scanned the working set for every provider (6.1 s). With the actual arguments the same query
-- runs in about 0.15 s. The page path (50 ids) was not affected, which is why the default list stayed at about 0.14 s.
-- What changes (two function bodies; no table, column, setting, job, grant or consumer object):
--   1. security.provider_catalogue_facts_v1(uuid[], boolean): the same query, the same columns and the same results, now a plpgsql function set to
--      plan_cache_mode = force_custom_plan, so every call is planned with its own p_ids and p_feeds. (The body text and the language change; the signature does not.)
--   2. security.admin_providers_page_v3(jsonb): (a) the Description filter and the Description sort read catalogue.providers.description directly (btrim <> ''), the
--      very test the facts use for description_filled, and no longer start the facts at all; (b) the pipeline facts are worked out only for the providers that
--      already pass the filters on the provider's own columns (query, country, state, lifecycle, publication, group, type, Description), not for all 3,103; (c) the
--      two feed candidate scans still run only for a Website or Zoho filter or sort (or feeds=true from a visible feed column), as in 20261109200000.
--   Rows, order, fields, paging, totals, validation errors and the Unknown-not-zero behaviour are unchanged: the same request gives the same answer, only sooner.
-- Live definitions read 9 Nov 2026 (project fxcwkweaxjtknorudmwp; body md5 = pg_proc.prosrc):
--   security.provider_catalogue_facts_v1(uuid[], boolean)  body 4127aab7f07d3b97431191e58f07bfdb  (replaced here)
--   security.admin_providers_page_v3(jsonb)                body 70be6f7e4b3faac863d7011f5fcec832  (replaced here)
-- Both are guarded below: this migration stops if either live body is neither the one it replaces nor the one it writes.
-- Consumer API (G3): not touched. Nothing a consumer reads is created, altered or dropped; the feed candidate functions and feed tables are read only, as before.
-- Nothing is written to a catalogue, pipeline ledger or feed table. No job is added (G1). No operational number is written into code (G2).
-- Replaces: the bodies of security.provider_catalogue_facts_v1 and security.admin_providers_page_v3 from 20261109200000 (same functions, same signatures; the earlier text is kept in supabase/held/provider_catalogue_filter_speed_forward_recovery.sql)
-- Retires: nothing (no object has a caller removed; security.admin_providers_page_v2 stays retiring from 20261109200000)
-- Nothing dropped, deleted or renamed by this migration.

do $g$
declare v_f text; v_v text;
begin
  select md5(p.prosrc) into v_f from pg_proc p where p.oid = to_regprocedure('security.provider_catalogue_facts_v1(uuid[],boolean)');
  select md5(p.prosrc) into v_v from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)');
  if v_f is null or v_v is null then raise exception 'required Provider Catalogue functions (20261109200000) are missing'; end if;
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc); a second run finds the new text and rewrites it unchanged
  if v_f not in ('4127aab7f07d3b97431191e58f07bfdb', 'abc1345d4cdb341deba65bfd0a38277f') then raise exception 'live security.provider_catalogue_facts_v1 differs from the definition this change replaces (body md5 %)', v_f; end if;
  if v_v not in ('70be6f7e4b3faac863d7011f5fcec832', 'f3eb9fc6f8efa37566c36ac5ef2e8f0e') then raise exception 'live security.admin_providers_page_v3 differs from the definition this change replaces (body md5 %)', v_v; end if;
end $g$;

-- 1. the pipeline facts: the same query, planned with the actual arguments on every call
CREATE OR REPLACE FUNCTION security.provider_catalogue_facts_v1(p_ids uuid[] DEFAULT NULL, p_feeds boolean DEFAULT true)
 RETURNS TABLE(provider_id uuid, description_filled boolean, admission_state text, source_tier text, evidence_id uuid, source_url text,
               admitted_at timestamptz, admitted_by text, reader_state text, reader_rule text, reader_via text, reader_tries integer,
               reader_updated_at timestamptz, last_read_ok_at timestamptz, hold_reason text, hold_rule text, next_retry_at timestamptz,
               l4_status text, l4_at timestamptz, l4_actor text, canonical_status text, website_state text, zoho_state text, mismatch text,
               readback_at timestamptz, readback_website boolean, readback_zoho boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 -- fixed: a plan setting, not an operational value; the SQL-function planning described above is what this replaces
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
#variable_conflict use_column
  -- p_ids null = every provider; an empty array = none. p_feeds false skips the two feed candidate scans (they read every provider) and leaves
  -- website_state, zoho_state and mismatch null: the page asks for them only when a column, filter or sort needs them. Reads only; nothing is written. A provider is attributed an admission only when its
  -- catalogue description is the very text that was admitted (a later hand edit leaves it "unrecorded", never credited to the pipeline).
begin
  -- Planned with the actual p_ids and p_feeds on every call (the function is set to force_custom_plan). As a SQL function it was planned once with the arguments
  -- unknown: the planner then expected a handful of providers and chose row-by-row nested loops that took seconds when p_ids is null (every provider).
  return query
  with pv as (
    select p.id, p.stable_key, p.lifecycle_status, p.publication_status, nullif(btrim(p.description), '') descr
      from catalogue.providers p where p_ids is null or p.id = any(p_ids)
  ), lr as (
    select distinct on (r.provider_id) r.provider_id, r.id read_id, r.state, r.rule, r.reason, r.read_via, r.tries, r.next_try_at, r.evidence_id, r.source_url,
           r.review_item_id, r.created_at, r.updated_at, r.consumer_checked_at, r.consumer_checks
      from pipeline.provider_description_reads r join pv on pv.id = r.provider_id
     order by r.provider_id, r.created_at desc, r.id desc
  ), ar as (
    select distinct on (r.provider_id) r.provider_id, r.read_via, r.evidence_id, r.source_url, r.review_item_id, coalesce(r.last_verified_at, r.updated_at) at,
           r.consumer_checked_at, r.consumer_checks
      from pipeline.provider_description_reads r join pv on pv.id = r.provider_id
     where r.state in ('admitted', 'verified') and nullif(btrim(r.proposal ->> 'description'), '') = pv.descr
     order by r.provider_id, coalesce(r.last_verified_at, r.updated_at) desc, r.id desc
  ), la as (
    select a.provider_id, a.tier, a.created_at, a.evidence_id, a.source_url
      from pipeline.provider_description_machine_admissions a join pv on pv.id = a.provider_id
     where a.outcome = 'admitted' and a.withdrawn_at is null and nullif(btrim(a.after_description), '') = pv.descr
  ), ld as (
    select distinct on (a.provider_id) a.provider_id, a.tier, a.reason, a.review_item_id
      from pipeline.provider_description_machine_admissions a join pv on pv.id = a.provider_id
     where a.outcome = 'declined'
     order by a.provider_id, a.created_at desc, a.id desc
  ), okr as (
    -- a successful read is a page captured as evidence by a page read (stored, direct or Firecrawl); register-fact profiles read no page
    select r.provider_id, max(coalesce(r.source_captured_at, r.last_verified_at)) at
      from pipeline.provider_description_reads r join pv on pv.id = r.provider_id
     where r.evidence_id is not null and r.read_via is not null
     group by r.provider_id
  ), l4 as (
    select x.provider_id, ri.status, ri.decided_at,
           (select d.layer2_state ->> 'actor_kind' from pipeline.layer4_decisions d where d.review_item_id = ri.id order by d.created_at desc limit 1) actor_kind
      from (select pv.id provider_id, coalesce(lr.review_item_id, ar.review_item_id) rid from pv left join lr on lr.provider_id = pv.id left join ar on ar.provider_id = pv.id) x
      join pipeline.layer4_review_items ri on ri.id = x.rid
  ), wf as (
    select i.item_key, i.removed_at, nullif(btrim(i.item ->> 'description'), '') d from pipeline.website_sync_items i join pv on pv.stable_key = i.item_key where i.entity = 'provider'
  ), zf as (
    select i.item_key, i.removed_at, nullif(btrim(i.item ->> 'description'), '') d from pipeline.zoho_sync_items i join pv on pv.stable_key = i.item_key where i.entity = 'provider'
  ), wc as (select c.ref_id from security.website_sync_candidates_v1('provider') c where p_feeds and c.ref_id is not null),
     zc as (select c.ref_id from security.zoho_sync_candidates_v1('provider') c where p_feeds and c.ref_id is not null),
  base as (
    select pv.id provider_id, pv.descr, pv.lifecycle_status, pv.publication_status,
           lr.state lr_state, lr.rule lr_rule, lr.reason lr_reason, lr.read_via lr_via, lr.tries lr_tries, lr.next_try_at, lr.updated_at lr_updated,
           lr.evidence_id lr_evidence, lr.source_url lr_url, lr.review_item_id lr_item, lr.consumer_checked_at lr_checked, lr.consumer_checks lr_checks,
           la.tier la_tier, la.created_at la_at, la.evidence_id la_evidence, la.source_url la_url,
           ar.read_via ar_via, ar.at ar_at, ar.evidence_id ar_evidence, ar.source_url ar_url, ar.consumer_checked_at ar_checked, ar.consumer_checks ar_checks,
           ld.tier ld_tier, ld.reason ld_reason, ld.review_item_id ld_item,
           okr.at ok_at, l4.status l4_status, l4.decided_at l4_at, l4.actor_kind l4_actor,
           (la.provider_id is not null or ar.provider_id is not null) has_admission,
           (select ri2.decided_at from pipeline.layer4_review_items ri2 where ri2.id = ar.review_item_id) ar_decided,
           (wf.item_key is not null and wf.removed_at is null) w_live, wf.d w_d, (wc.ref_id is not null) w_cand,
           (zf.item_key is not null and zf.removed_at is null) z_live, zf.d z_d, (zc.ref_id is not null) z_cand
      from pv
      left join lr on lr.provider_id = pv.id
      left join ar on ar.provider_id = pv.id
      left join la on la.provider_id = pv.id
      left join ld on ld.provider_id = pv.id
      left join okr on okr.provider_id = pv.id
      left join l4 on l4.provider_id = pv.id
      left join wf on wf.item_key = pv.stable_key
      left join zf on zf.item_key = pv.stable_key
      left join wc on wc.ref_id = pv.id
      left join zc on zc.ref_id = pv.id
  ), st as (
    select b.*,
      case when b.descr is not null and b.has_admission then 'admitted'
           when b.descr is not null then 'unrecorded'
           -- a proposal waiting for its Layer 4 decision is pending, whatever the machine rule said about it: declined is a decision already taken
           when b.lr_state in ('proposed', 'queued', 'reading') and b.l4_status = 'pending' then 'pending'
           when b.lr_state = 'rejected' or b.lr_rule like 'machine\_declined%' or (b.lr_item is not null and b.lr_item = b.ld_item) then 'declined'
           when b.lr_state in ('held', 'dead_letter') then 'held'
           when b.lr_state in ('queued', 'reading', 'proposed') then 'pending'
           else 'none' end admission_state,
      -- Website feed: matched = the feed item holds the same text; pending = the feed item holds other text (the existing feed scan refreshes it);
      -- missing = the scan serves this provider but holds no item for it; not applicable = not a provider the feed serves, or nothing to publish
      case when b.descr is null then (case when b.w_live and b.w_d is not null then 'pending' else 'not_applicable' end)
           when b.w_live and b.w_d = b.descr then 'matched'
           when b.w_live then 'pending'
           when b.w_cand then 'missing'
           else 'not_applicable' end website_state,
      case when b.descr is null then (case when b.z_live and b.z_d is not null then 'pending' else 'not_applicable' end)
           when b.z_live and b.z_d = b.descr then 'matched'
           when b.z_live then 'pending'
           when b.z_cand then 'missing'
           else 'not_applicable' end zoho_state
      from base b
  )
  select s.provider_id, (s.descr is not null), s.admission_state,
         case when s.descr is not null then coalesce(s.la_tier, s.ar_via, 'unknown')
              else coalesce(s.lr_via, case when s.lr_rule in ('registry_factual', 'insufficient_verified_facts') then 'registry_factual' end, s.ld_tier) end,
         coalesce(s.la_evidence, s.ar_evidence, s.lr_evidence), coalesce(s.la_url, s.ar_url, s.lr_url),
         case when s.descr is not null then coalesce(s.la_at, s.ar_decided, s.ar_at) end,
         case when s.descr is null then null when s.la_at is not null then 'machine' when s.has_admission then 'layer4' end,
         s.lr_state, s.lr_rule, s.lr_via, s.lr_tries, s.lr_updated, s.ok_at,
         case when s.admission_state in ('held', 'declined') then coalesce(nullif(s.lr_reason, ''), s.ld_reason, s.lr_rule) end,
         case when s.admission_state in ('held', 'declined') then s.lr_rule end,
         case when s.lr_state in ('queued', 'held') then s.next_try_at end,
         s.l4_status, s.l4_at, s.l4_actor,
         case when s.descr is null then 'none' when s.lifecycle_status = 'active' and s.publication_status = 'published' then 'published' else 'unpublished' end,
         case when p_feeds then s.website_state end, case when p_feeds then s.zoho_state end,
         case when not p_feeds then null
              when s.website_state in ('pending', 'missing') and s.zoho_state in ('pending', 'missing') then 'both'
              when s.website_state in ('pending', 'missing') then 'website'
              when s.zoho_state in ('pending', 'missing') then 'zoho' else 'none' end,
         case when s.ar_checked is not null then s.ar_checked else s.lr_checked end,
         case when (case when s.ar_checked is not null then s.ar_checks else s.lr_checks end ->> 'website_verified') in ('true', 'false')
              then (case when s.ar_checked is not null then s.ar_checks else s.lr_checks end ->> 'website_verified')::boolean end,
         case when (case when s.ar_checked is not null then s.ar_checks else s.lr_checks end ->> 'zoho_verified') in ('true', 'false')
              then (case when s.ar_checked is not null then s.ar_checks else s.lr_checks end ->> 'zoho_verified')::boolean end
    from st s;
end
$function$;
comment on function security.provider_catalogue_facts_v1(uuid[], boolean) is 'CF-247 Provider Catalogue columns (directive 9 Nov 2026): per provider, read only and set-based, the description pipeline and its two consumers: populated, admission state (admitted, declined, held, pending, none, unrecorded), source tier (stored, direct, firecrawl, registry_factual, unknown), evidence and source address, when and how it was admitted, the reader''s state, last successful page read, hold reason and next retry, the Layer 4 decision state, the catalogue description''s state, and, separately, the Website feed and Zoho feed states (matched, pending, missing, not applicable) read from pipeline.website_sync_items and pipeline.zoho_sync_items for the providers the existing scans serve, with a mismatch summary. p_ids null = every provider. Presence in catalogue.providers.description is never read as consumer publication.';

-- 2. providers_page, version 3: Description read directly; the facts only for the providers that pass the cheap filters
CREATE OR REPLACE FUNCTION security.admin_providers_page_v3(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
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
comment on function security.admin_providers_page_v3(jsonb) is 'CF-247 Provider Catalogue columns (directive 9 Nov 2026): providers_page. Every request security.admin_providers_page_v2 accepted gives the same rows, order, fields, paging and total; each item also carries registration, scholarships (all rows, and published), entry_coverage (pipeline.aer_provider_coverage) and pdesc (security.provider_catalogue_facts_v1 plus the description text). New filters over the whole filtered set: description (filled, missing), admission (pending, held, declined, admitted), source_tier, website and zoho (matched, pending, missing, not_applicable), provider_type; new sort keys for the new columns. Any assigned role (rank 1 and above), as v2.';

revoke all on function security.provider_catalogue_facts_v1(uuid[], boolean), security.admin_providers_page_v3(jsonb) from public, anon, authenticated;

-- 3. the component register: the same two functions, with a note of this change
update pipeline.component_register
   set note = coalesce(note || '; ', '') || 'filter speed fix 20261109220000 (body replaced; same signature)'
 where kind = 'function' and name in ('security.provider_catalogue_facts_v1', 'security.admin_providers_page_v3')
   and coalesce(note, '') not like '%20261109220000%';

-- post-check
do $$
declare v_f text; v_v text;
begin
  select md5(p.prosrc) into v_f from pg_proc p where p.oid = to_regprocedure('security.provider_catalogue_facts_v1(uuid[],boolean)');
  select md5(p.prosrc) into v_v from pg_proc p where p.oid = to_regprocedure('security.admin_providers_page_v3(jsonb)');
  if v_f <> 'abc1345d4cdb341deba65bfd0a38277f' then raise exception 'Provider Catalogue filter speed post-check: facts body md5 % is not the text this change writes', v_f; end if;
  if v_v <> 'f3eb9fc6f8efa37566c36ac5ef2e8f0e' then raise exception 'Provider Catalogue filter speed post-check: page body md5 % is not the text this change writes', v_v; end if;
  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('security.provider_catalogue_facts_v1(uuid[],boolean)') and p.proconfig @> array['plan_cache_mode=force_custom_plan']) then raise exception 'Provider Catalogue filter speed post-check: the facts function is not set to custom plans'; end if;
  if has_function_privilege('authenticated', 'security.admin_providers_page_v3(jsonb)', 'execute') or has_function_privilege('anon', 'security.provider_catalogue_facts_v1(uuid[], boolean)', 'execute') then raise exception 'Provider Catalogue filter speed post-check: a function is callable by a user directly'; end if;
  if position('security.admin_providers_page_v3(p_args)' in pg_get_functiondef('security.admin_catalogue_page(text,jsonb)'::regprocedure)) = 0 then raise exception 'Provider Catalogue filter speed post-check: providers_page no longer routes to v3'; end if;
end $$;
