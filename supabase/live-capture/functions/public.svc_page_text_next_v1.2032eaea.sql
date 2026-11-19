CREATE OR REPLACE FUNCTION public.svc_page_text_next_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_lim int := least(greatest(coalesce(p_limit, 1), 1), 200);  -- fixed: bound on one call; the size is the setting batch.page_text
        v_c jsonb := '[]'::jsonb; v_part jsonb; v_n int; v_found int := 0; r record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  -- 20261119150000 (s772, IQ-00606): one claim at a time; a call that finds one running returns no items instead of waiting
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
end $function$
