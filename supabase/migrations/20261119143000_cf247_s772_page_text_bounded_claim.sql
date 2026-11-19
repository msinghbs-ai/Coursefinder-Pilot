-- CF-247 s772 (S2-Build; Platform Admin 19 Nov 2026 14:24, close IQ-00606): the page-text claim walks the bound pages in claim order and stops
-- at its limit.
--
-- What was read (19 Nov 2026 12:55-14:40 AEDT, rolled-back read-backs and plans through the dry-run workflow):
--   * Since 20261119104500 the duplicate-claim error is gone, but 14 of 55 coverage-sweep page_text runs failed with "svc_page_text_next_v1:
--     canceling statement due to statement timeout" (8 s gateway limit). The claim builds the whole candidate set (about 18,000 bound pages,
--     12,700 eligible) and sorts it to keep 40: 2.9 s by plan when quiet, more under load. A set-wise rewrite measured 1.1 to 2.3 s.
--   * pipeline.course_priority is empty, so the claim order is the country's Boost weight (AU 80, NZ 76, CA 72) and then the course id.
-- What it changes (CREATE OR REPLACE of the existing function, guarded by its live body md5; one partial index on a pipeline table; no new
-- table or function; the consumer API is not touched, G3 75/48):
--   * coverage_course_pages_bound_read_course_idx: the bound, read pages in course order with their stored page (index only).
--   * public.svc_page_text_next_v1 takes each country with active courses in weight order and walks its bound pages by course id, the
--     cheap checks first, stopping as soon as it has the limit: the work follows what is left to claim, not the size of the backlog. The claim
--     rows, the items returned and their order are as before. A call that finds another claim running returns no items instead of waiting.
-- Replaces: the whole-set sort of svc_page_text_next_v1 (20261119104500).
-- Retires: nothing.

do $g$ begin
  if md5((select prosrc from pg_proc where oid = 'public.svc_page_text_next_v1(integer)'::regprocedure)) <> '007c7250542efd4de3867223e5c9be2d'
     and position('20261119143000' in (select prosrc from pg_proc where oid = 'public.svc_page_text_next_v1(integer)'::regprocedure)) = 0 then
    raise exception 'live public.svc_page_text_next_v1 differs from the definition this change replaces';
  end if;
end $g$;

create index if not exists coverage_course_pages_bound_read_course_idx on pipeline.coverage_course_pages (course_id) include (evidence_id)
  where status = 'bound' and read_status = 'read';
comment on index pipeline.coverage_course_pages_bound_read_course_idx is
  'CF-247 s772 (20261119143000): bound, read course pages in course order with their stored page; walked by svc_page_text_next_v1.';

create or replace function public.svc_page_text_next_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v jsonb; v_lim int := least(greatest(coalesce(p_limit, 1), 1), 200);  -- fixed: bound on one call; the size is the setting batch.page_text
        v_c jsonb := '[]'::jsonb; v_part jsonb; v_n int; v_found int := 0; r record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  -- 20261119143000 (s772, IQ-00606): one claim at a time; a call that finds one running returns no items instead of waiting
  if not pg_try_advisory_xact_lock(hashtext('cf247:page_text_next')) then
    return jsonb_build_object('items', '[]'::jsonb, 'min_chars', security.pipeline_num_v1('page_text.min_chars', 200)::int, 'busy', true);
  end if;
  -- countries with active courses in Boost weight order; each country's bound pages walked by course id until the limit is found
  for r in
    select k.id country_id, k.iso_alpha2::text cc, mx.weight
      from (select m.country_code, max(m.weight) weight from security.boost_country_category_matrix_v1() m
             where m.enrichment_category in ('intakes_deadlines', 'course_basics') and m.weight > 0 group by 1) mx
      join ref.countries k on mx.country_code = coalesce((select split_part(a, '=', 2) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) a
                                                           where split_part(a, '=', 1) = k.iso_alpha2::text limit 1), k.iso_alpha2::text)
     where exists (select 1 from catalogue.providers p join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active' where p.country_id = k.id)
     order by mx.weight desc, k.iso_alpha2
  loop
    exit when v_found >= v_lim;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', z.course_id, 'evidence_id', z.evidence_id, 'country', r.cc, 'weight', r.weight)), '[]'::jsonb), count(*)
      into v_part, v_n
      from (select cp.course_id, cp.evidence_id
              from pipeline.coverage_course_pages cp
              join catalogue.courses c on c.id = cp.course_id and c.lifecycle_status = 'active'
              join catalogue.providers p on p.id = c.provider_id and p.country_id = r.country_id
             where cp.status = 'bound' and cp.read_status = 'read' and cp.evidence_id is not null
               and not exists (select 1 from pipeline.page_text_conversions x where x.source_evidence_id = cp.evidence_id
                                and (x.outcome in ('done', 'too_short')
                                     or (x.outcome = 'claimed' and x.claimed_at > now() - interval '10 minutes')  -- fixed: claim lease
                                     or (x.outcome = 'failed' and x.claimed_at > now() - interval '1 day')))  -- fixed: retry interval for a failed copy
               and (c.study_load is null or nullif(btrim(c.description), '') is null)
               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
               and exists (select 1 from pipeline.evidence_artifacts e where e.id = cp.evidence_id and e.evidence_type = 'source_snapshot' and e.storage_path is not null)
               and not exists (select 1 from pipeline.evidence_artifacts t where t.entity_id = cp.course_id and t.evidence_type = 'provider_course_page_text'
                                and t.metadata->>'derived_from_evidence_id' = cp.evidence_id::text)
             order by cp.course_id
             limit v_lim - v_found) z;
    v_c := v_c || v_part; v_found := v_found + v_n;
  end loop;
  with cand as (
    select x.course_id, x.evidence_id, e.storage_path, cp.url, x.country, x.weight, 1000000 csort
      from jsonb_to_recordset(v_c) as x(course_id uuid, evidence_id uuid, country text, weight numeric)
      join pipeline.evidence_artifacts e on e.id = x.evidence_id
      join pipeline.coverage_course_pages cp on cp.course_id = x.course_id),
  ins as (
    insert into pipeline.page_text_conversions as t (source_evidence_id, course_id, outcome, claimed_at)
    -- 20261119104500 (s720, IQ-00606): two courses can share one stored page; the page is claimed once (the items still list every course)
    select distinct on (evidence_id) evidence_id, course_id, 'claimed', now() from cand order by evidence_id, weight desc, csort
    on conflict (source_evidence_id) do update set outcome = 'claimed', claimed_at = now(), error = null
    returning t.source_evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path, 'url', c.url, 'country', c.country)
                  order by c.weight desc, c.csort), '[]'::jsonb)
    into v from cand c join ins i on i.source_evidence_id = c.evidence_id;
  return jsonb_build_object('items', v, 'min_chars', security.pipeline_num_v1('page_text.min_chars', 200)::int);
end $function$;

-- post-check: the function carries this change, the index exists, the consumer API is unchanged (the claim itself is not called here: a call
-- would lease live pages; it is timed in the rolled-back dry run)
do $c$
declare v_drift jsonb;
begin
  if position('20261119143000' in (select prosrc from pg_proc where oid = 'public.svc_page_text_next_v1(integer)'::regprocedure)) = 0 then
    raise exception 'svc_page_text_next_v1 was not replaced';
  end if;
  if not exists (select 1 from pg_indexes where schemaname = 'pipeline' and indexname = 'coverage_course_pages_bound_read_course_idx') then
    raise exception 'index coverage_course_pages_bound_read_course_idx missing';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift: %', v_drift->'drift'; end if;
end $c$;
