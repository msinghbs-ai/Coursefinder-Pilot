-- CF-247 F-SCH: per-provider scholarship coverage in the existing Scholarships › Coverage view, and an applicant-nationality country filter in the
-- Scholarships Catalogue (Platform Admin S2-Scholarship directive 13 Nov 2026 16:01 §5, §6; Developer Requirements v2.26 F-SCH.11, F-SCH.13).
-- Why (live, 13 Nov 2026 05:30 UTC):
--   1. Coverage lists only providers on the watch list or with scholarships; providers with none (87 of 143 classified universities at the audit,
--      73 Canadian ones never searched) cannot be found, filtered by country or seen with their source, read state, disposition and next action.
--      The same per-provider reading exists only as the read-only evidence export (Pilot #1122), which takes over a minute: the university test
--      alone is 13.7 s across all providers, too slow for a screen.
--   2. The Catalogue's nationality filter is by rule only (restricted / any / under review / not stated). It cannot answer "which scholarships
--      can a student from India apply for", and the four rule values were reported as not reconciling (155 + 1,050 against 1,202). Re-measured
--      on distinct published IDs at 05:20 UTC: 158 restricted + 1,061 not stated = 1,219 published, mutually exclusive by construction; the
--      earlier figures were taken minutes apart while publication changed.
-- Change:
--   1. pipeline.scholarship_provider_coverage: a snapshot, one row per provider in the scholarship population (every classified university plus
--      every provider with discovery, candidates, listings or scholarships), the same columns, disposition and next action as the evidence
--      export. Refreshed at the end of each full scholarship-coverage-classify run (hourly :29). Read by public.admin_scholarship_provider_coverage
--      (Curator and above): filters country, universities only, disposition, with/without published scholarships, discovery status, search;
--      sorts; a provider funnel and disposition counts for the filtered population.
--   2. security.admin_scholarships_page takes nationality_country (ISO code): scholarships whose proven rule names that country, or that are
--      proven open to every nationality, never those that exclude it; not-stated rules are returned only with nationality_unknown_too and stay
--      labelled "Not stated". Each row carries its nationality_codes; the result lists the countries present (nationality_countries).
--   Admission, publication, Layer 4 and the consumer APIs are unchanged (admin read paths only, G3).
-- Settings: none new.
-- Replaces: security.admin_scholarships_page(jsonb), security.scholarship_coverage_classify_v1(uuid[]) (same names and signatures; md5-guarded
--   edits of the live text).
-- Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

create table if not exists pipeline.scholarship_provider_coverage (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  provider text, country text, classified_university boolean, provider_type text, website text, provider_publication text,
  discovery_status text, discovery_method text, map_urls integer, kept_pages integer, discovered_at timestamptz, next_discover_at timestamptz,
  discovery_error text, search_off boolean, search_eligible boolean,
  candidates integer, candidates_read integer, candidates_unread integer, candidates_admitted integer, candidates_rejected integer, reject_reasons text,
  n_domestic integer, n_intl_unknown integer, listing_pages integer, listing_complete integer, listing_failed integer,
  scholarships_active integer, scholarships_published integer, scholarships_unpublished integer, sample_published_sources text,
  coverage_states text, layer4_open integer, layer4_facts text, ai_reviews_pending integer, firecrawl_credits_30d numeric, next_retry timestamptz,
  disposition text not null, next_action text, refreshed_at timestamptz not null default now());
comment on table pipeline.scholarship_provider_coverage is 'F-SCH per-provider scholarship coverage snapshot (Platform Admin 13 Nov 2026 §5/§6, F-SCH.11): one row per provider in the scholarship population with its source, read, admission, publication, Layer 4 state, disposition and next action. Rebuilt by security.scholarship_provider_coverage_refresh_v1 after each full scholarship-coverage-classify run; read by public.admin_scholarship_provider_coverage. Derived; not a task list.';
create index if not exists scholarship_provider_coverage_country_idx on pipeline.scholarship_provider_coverage (country, disposition);
alter table pipeline.scholarship_provider_coverage enable row level security;

create or replace function security.scholarship_provider_coverage_refresh_v1() returns integer
language plpgsql security definer set search_path to '' as $function$
-- CF-247 F-SCH (13 Nov 2026): the same reading as scripts/export/sch-provider-coverage-evidence.sql, kept as a snapshot for the Coverage screen
-- (the university test runs once per provider; about 70 s for all providers, hourly, after classification)
declare v_n int;
begin
  delete from pipeline.scholarship_provider_coverage;
  insert into pipeline.scholarship_provider_coverage (provider_id, provider, country, classified_university, provider_type, website, provider_publication,
         discovery_status, discovery_method, map_urls, kept_pages, discovered_at, next_discover_at, discovery_error, search_off, search_eligible,
         candidates, candidates_read, candidates_unread, candidates_admitted, candidates_rejected, reject_reasons, n_domestic, n_intl_unknown,
         listing_pages, listing_complete, listing_failed, scholarships_active, scholarships_published, scholarships_unpublished, sample_published_sources,
         coverage_states, layer4_open, layer4_facts, ai_reviews_pending, firecrawl_credits_30d, next_retry, disposition, next_action)
  select provider_id, provider, country, classified_university, provider_type, website, provider_publication,
         discovery_status, discovery_method, map_urls, kept_pages, discovered_at, next_discover_at, discovery_error, search_off, search_eligible,
         candidates, candidates_read, candidates_unread, candidates_admitted, candidates_rejected, reject_reasons, n_domestic, n_intl_unknown,
         listing_pages, listing_complete, listing_failed, scholarships_active, scholarships_published, scholarships_unpublished, sample_published_sources,
         coverage_states, layer4_open, layer4_facts, ai_reviews_pending, firecrawl_credits_30d, next_retry, disposition, next_action
    from (
with univ as materialized (select p.id from catalogue.providers p where security.scholarship_university(p.id)),
pop as (
  select id from univ
  union select provider_id from pipeline.scholarship_discovery_providers
  union select provider_id from pipeline.scholarship_page_candidates
  union select provider_id from pipeline.scholarship_listing_pages
  union select provider_id from scholarship.scholarships where provider_id is not null),
cand as (
  select k.provider_id, count(*) n,
         count(*) filter (where k.read_status in ('read', 'too_thin')) n_read,
         count(*) filter (where k.read_status is null or k.read_status in ('pending', 'queued', 'waiting_scraper', 'failed')) n_unread,
         count(*) filter (where k.admit_status = 'admitted') n_admitted,
         count(*) filter (where k.admit_status = 'rejected') n_rejected,
         min(k.next_read_at) filter (where k.read_status is distinct from 'read') next_read
    from pipeline.scholarship_page_candidates k group by 1),
rej as (
  select provider_id, string_agg(r || ' ' || n, '; ' order by n desc) reasons,
         sum(n) filter (where r in ('domestic_only', 'eligibility_domestic')) n_domestic,
         sum(n) filter (where r in ('international_not_stated')) n_intl_unknown
    from (select provider_id, r, count(*) n from pipeline.scholarship_page_candidates, unnest(admit_reasons) r where admit_status = 'rejected' group by 1, 2) x
   group by 1),
lst as (
  select provider_id, count(*) n, count(*) filter (where completed_at is not null) n_complete, count(*) filter (where status = 'failed') n_failed
    from pipeline.scholarship_listing_pages group by 1),
sch as (
  select provider_id, count(*) filter (where lifecycle_status = 'active') n_active,
         count(*) filter (where lifecycle_status = 'active' and publication_status = 'published') n_published,
         count(*) filter (where lifecycle_status = 'active' and publication_status <> 'published') n_held,
         (array_agg(source_url order by updated_at desc) filter (where lifecycle_status = 'active' and publication_status = 'published'))[1:3] sample_published
    from scholarship.scholarships group by 1),
cov as (
  select provider_id, string_agg(state || ' ' || n, '; ' order by n desc) states, min(next_recovery_at) next_recovery
    from (select provider_id, state, count(*) n, min(next_recovery_at) next_recovery_at from pipeline.scholarship_coverage_items where present group by 1, 2) y group by 1),
l4 as (
  select split_part(entity, '|', 1)::uuid provider_id, count(*) n, string_agg(distinct missing_fact, ', ') facts
    from pipeline.layer4_interventions where lane like 'sch%' and status = 'awaiting_input' group by 1),
rv as (select provider_id, count(*) n from pipeline.scholarship_ai_reviews where status = 'pending' group by 1),
fc as (select provider_id, sum(units) units from pipeline.coverage_vendor_usage where purpose like 'sch%' and at > now() - interval '30 days' group by 1),
base as (
  select p.id provider_id, coalesce(p.display_name, p.canonical_name) provider, c.iso_alpha2 country, (p.id in (select u.id from univ u)) classified_university,
         t.code provider_type, p.website, p.publication_status provider_publication,
         d.status discovery_status, d.method discovery_method, d.url_count map_urls, d.kept_count kept_pages, d.discovered_at, d.next_discover_at,
         left(d.last_error, 160) discovery_error, security.provider_sch_search_off_v1(p.id) search_off, security.fc_sch_eligible_v1(p.id) search_eligible,
         coalesce(k.n, 0) candidates, coalesce(k.n_read, 0) candidates_read, coalesce(k.n_unread, 0) candidates_unread,
         coalesce(k.n_admitted, 0) candidates_admitted, coalesce(k.n_rejected, 0) candidates_rejected, r.reasons reject_reasons,
         coalesce(r.n_domestic, 0) n_domestic, coalesce(r.n_intl_unknown, 0) n_intl_unknown,
         coalesce(l.n, 0) listing_pages, coalesce(l.n_complete, 0) listing_complete, coalesce(l.n_failed, 0) listing_failed,
         coalesce(s.n_active, 0) scholarships_active, coalesce(s.n_published, 0) scholarships_published, coalesce(s.n_held, 0) scholarships_unpublished,
         array_to_string(s.sample_published, ' ') sample_published_sources,
         cv.states coverage_states, coalesce(i.n, 0) layer4_open, i.facts layer4_facts, coalesce(v.n, 0) ai_reviews_pending,
         coalesce(f.units, 0) firecrawl_credits_30d,
         least(d.next_discover_at, k.next_read, cv.next_recovery) next_retry
    from pop join catalogue.providers p on p.id = pop.id join ref.countries c on c.id = p.country_id
    left join ref.provider_types t on t.id = p.provider_type_id
    left join pipeline.scholarship_discovery_providers d on d.provider_id = p.id
    left join cand k on k.provider_id = p.id left join rej r on r.provider_id = p.id left join lst l on l.provider_id = p.id
    left join sch s on s.provider_id = p.id left join cov cv on cv.provider_id = p.id left join l4 i on i.provider_id = p.id
    left join rv v on v.provider_id = p.id left join fc f on f.provider_id = p.id)
select b.*,
       case when scholarships_published > 0 then 'published'
            when scholarships_active > 0 then 'admitted_not_published'
            when layer4_open > 0 or ai_reviews_pending > 0 then 'protected_hold'
            when candidates_unread > 0 or listing_failed > 0 or (listing_pages > listing_complete) then 'source_found_unprocessed'
            when candidates > 0 and n_domestic > 0 and n_domestic >= n_intl_unknown then 'current_awards_ineligible_or_domestic'
            when candidates > 0 then 'evidence_insufficient'
            when nullif(btrim(coalesce(website, '')), '') is null then 'website_unknown'
            when discovery_status in ('mapped', 'empty') then 'searched_none_evidenced'
            else 'not_yet_attempted_or_vendor_failure' end disposition,
       case when scholarships_published > 0 then 'keep re-reading on the cadence; complete fields'
            when scholarships_active > 0 then 'complete the publishing checks (value, audience, round) from the stored page'
            when layer4_open > 0 or ai_reviews_pending > 0 then 'Layer 4: ' || coalesce(layer4_facts, 'AI review question') || ' (reviewer)'
            when candidates_unread > 0 then 'read the unread candidate pages'
            when listing_failed > 0 or listing_pages > listing_complete then 'traverse the listing pages'
            when candidates > 0 and n_domestic > 0 and n_domestic >= n_intl_unknown then 'none needed while the current awards are domestic-only; re-map on the cadence'
            when candidates > 0 then 'eligibility reader on the award pages; re-map the official scholarship section'
            when nullif(btrim(coalesce(website, '')), '') is null then 'find the official website'
            when discovery_status in ('mapped', 'empty') then 're-map on the cadence; site search for the scholarship section'
            when not search_eligible then 'not eligible for scholarship search under the current rule'
            else 'map the official website' end next_action
  from base b
    ) z;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- the snapshot after each full classification run (a failure leaves the previous snapshot and is reported as a warning, never stops the run)
select pg_temp.edit_n('security.scholarship_coverage_classify_v1(uuid[])', 'e305eb1354ba06dc5922d0d7b7f3ed19', array[
  array[$o$  return jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items,$o$,
        $n$  -- CF-247 F-SCH (13 Nov 2026): the per-provider coverage snapshot (Coverage › All providers), on the full run only
  if p_providers is null then
    begin perform security.scholarship_provider_coverage_refresh_v1();
    exception when others then raise warning 'scholarship_provider_coverage_refresh_v1: %', sqlerrm; end;
  end if;
  return jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items,$n$]
], array[1]);

create or replace function public.admin_scholarship_provider_coverage(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
-- CF-247 F-SCH (Platform Admin 13 Nov 2026 §5/§6): Scholarships › Coverage › All providers. Filters: country, universities, disposition,
-- published (yes/no), discovery status, provider search. The funnel and disposition counts are for the filtered population before paging.
declare v_rank int := coalesce(security.current_role_rank(), 0); v_q text := nullif(btrim(coalesce(p_args->>'query', '')), '');
        v_limit int := least(greatest(coalesce(nullif(p_args->>'limit', '')::int, 100), 1), 500);  -- fixed: page size bounds of one screen
        v_offset int := greatest(coalesce(nullif(p_args->>'offset', '')::int, 0), 0);
        v_sort text := lower(coalesce(nullif(p_args->>'sort', ''), 'provider')); v_desc boolean := lower(coalesce(p_args->>'direction', 'asc')) = 'desc';
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (
    with f as (
      select c.* from pipeline.scholarship_provider_coverage c
       where (nullif(p_args->>'country', '') is null or c.country = upper(p_args->>'country'))
         and (nullif(p_args->>'universities', '') is null or c.classified_university = (p_args->>'universities')::boolean)
         and (v_q is null or c.provider ilike '%' || v_q || '%' or coalesce(c.website, '') ilike '%' || v_q || '%')),
    g as (
      select f.* from f
       where (nullif(p_args->>'disposition', '') is null or f.disposition = p_args->>'disposition')
         and (nullif(p_args->>'has_published', '') is null or (f.scholarships_published > 0) = (p_args->>'has_published')::boolean)
         and (nullif(p_args->>'discovery', '') is null or coalesce(f.discovery_status, 'never') = p_args->>'discovery')),
    pg as (
      select g.* from g order by
        case when v_sort = 'provider' and not v_desc then lower(g.provider) end asc, case when v_sort = 'provider' and v_desc then lower(g.provider) end desc,
        case when v_sort = 'country' and not v_desc then g.country end asc, case when v_sort = 'country' and v_desc then g.country end desc,
        case when v_sort = 'published' and not v_desc then g.scholarships_published end asc, case when v_sort = 'published' and v_desc then g.scholarships_published end desc,
        case when v_sort = 'candidates' and not v_desc then g.candidates end asc, case when v_sort = 'candidates' and v_desc then g.candidates end desc,
        case when v_sort = 'discovered' and not v_desc then g.discovered_at end asc nulls first, case when v_sort = 'discovered' and v_desc then g.discovered_at end desc nulls last,
        case when v_sort = 'retry' and not v_desc then g.next_retry end asc nulls last, case when v_sort = 'retry' and v_desc then g.next_retry end desc nulls last,
        lower(g.provider), g.provider_id
       limit v_limit offset v_offset)
    select jsonb_build_object(
      'refreshed_at', (select max(refreshed_at) from pipeline.scholarship_provider_coverage),
      'total', (select count(*) from g), 'limit', v_limit, 'offset', v_offset,
      'rows', coalesce((select jsonb_agg(to_jsonb(pg) - 'refreshed_at') from pg), '[]'::jsonb),
      -- one funnel for the population the country, university and search filters select
      'funnel', (select jsonb_build_object(
          'providers', count(*),
          'searched', count(*) filter (where f.discovery_status in ('mapped', 'empty') or f.candidates > 0 or f.listing_pages > 0),
          'official_source', count(*) filter (where f.candidates > 0 or f.listing_pages > 0),
          'candidate_pages', coalesce(sum(f.candidates), 0), 'pages_read', coalesce(sum(f.candidates_read), 0),
          'candidates_admitted', coalesce(sum(f.candidates_admitted), 0),
          'scholarships_active', coalesce(sum(f.scholarships_active), 0), 'scholarships_published', coalesce(sum(f.scholarships_published), 0),
          'providers_published', count(*) filter (where f.scholarships_published > 0),
          'providers_searched_none', count(*) filter (where f.disposition = 'searched_none_evidenced'),
          'layer4_open', coalesce(sum(f.layer4_open), 0), 'ai_reviews_pending', coalesce(sum(f.ai_reviews_pending), 0),
          'firecrawl_credits_30d', coalesce(sum(f.firecrawl_credits_30d), 0)) from f),
      'dispositions', (select coalesce(jsonb_object_agg(x.disposition, x.n), '{}'::jsonb) from (select f.disposition, count(*) n from f group by 1) x),
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', y.country, 'n', y.n) order by y.n desc), '[]'::jsonb)
                      from (select c.country, count(*) n from pipeline.scholarship_provider_coverage c group by 1) y))
  );
end $f$;
revoke all on function public.admin_scholarship_provider_coverage(jsonb) from public, anon;
grant execute on function public.admin_scholarship_provider_coverage(jsonb) to authenticated;

-- applicant nationality (proven rules only; not stated is never eligible and is returned only when asked)
select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', '4ab6f36b1da99f3a19b55552332c5bc6', array[
  array[$o$             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end nationality_status,
$o$, $n$             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end nationality_status,
        coalesce(nr.codes, '{}'::text[]) nationality_codes,
$n$],
  array[$o$             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end) = p_args->>'nationality_status')
$o$, $n$             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end) = p_args->>'nationality_status')
        -- 2026111335: applicant nationality - the proven rule names the country or is proven open to all, and does not exclude it
        and (nullif(p_args->>'nationality_country', '') is null
             or (l4.entity_id is null
                 and (upper(p_args->>'nationality_country') = any (coalesce(nr.codes, '{}'::text[])) or coalesce(nr.phrases ? 'ANY', false))
                 and not exists (select 1 from scholarship.criteria cx where cx.scholarship_id = s.id and cx.criterion_type = 'nationality'
                                    and coalesce(cx.status, 'active') not in ('rejected', 'superseded', 'withdrawn')
                                    and coalesce(cx.value_json->'excluded', '[]'::jsonb) ? upper(p_args->>'nationality_country')))
             or (coalesce((p_args->>'nationality_unknown_too')::boolean, false) and l4.entity_id is null
                 and cardinality(coalesce(nr.codes, '{}'::text[])) = 0 and not coalesce(nc.excl_or_regions, false) and not coalesce(nr.phrases ? 'ANY', false)))
$n$],
  array[$o$'status_counts',(select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select b.status, count(*) n from base b group by 1) z))$o$,
        $n$'status_counts',(select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select b.status, count(*) n from base b group by 1) z),
        'nationality_countries',(select coalesce(jsonb_agg(jsonb_build_object('code', z.cc, 'name', (select c.name from ref.countries c where c.iso_alpha2 = z.cc limit 1), 'n', z.n) order by z.n desc, z.cc), '[]'::jsonb)
                                   from (select x.cc, count(distinct s2.id) n from scholarship.scholarships s2 join scholarship.nationality_readings nr2 on nr2.scholarship_id = s2.id
                                           cross join lateral unnest(nr2.codes) x(cc) where s2.lifecycle_status = 'active' and s2.publication_status = 'published' group by 1) z))$n$]
], array[1, 1, 1]);

-- the first snapshot is built by the next full classification run (hourly :29)
