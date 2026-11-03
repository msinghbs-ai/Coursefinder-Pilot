CREATE OR REPLACE FUNCTION security.aer_course_outcomes_build_v1(p_source text DEFAULT 'job'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_t timestamptz := clock_timestamp(); v_n int; v_by jsonb;
begin
  -- single flight: an overlapping run does not build a second time
  if not pg_try_advisory_xact_lock(hashtextextended('cf247.aer.outcome_register', 0)) then return jsonb_build_object('state', 'busy'); end if;
  delete from pipeline.aer_course_outcomes;
  insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_name, provider_published, course_title, course_code, outcome, detail,
                                           course_url, page_status, identity_basis, read_state, read_reason, review_item_id, built_at)
  with scope as (select (e.v)::uuid pid from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) e(v)),
  c as (
    select c.id, c.provider_id, k.iso_alpha2 cc, coalesce(p.display_name, p.canonical_name) pname, p.publication_status = 'published' pub,
           coalesce(c.display_title, c.canonical_title) title, c.course_code, g.status gs, g.url, g.identity_basis,
           (e.storage_path is not null) stored,
           (g.status = 'bound' and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')) id_ok,
           exists (select 1 from scope s where s.pid = c.provider_id) in_scope
      from catalogue.courses c
      join catalogue.providers p on p.id = c.provider_id
      join ref.countries k on k.id = p.country_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.evidence_artifacts e on e.id = g.evidence_id
     where c.lifecycle_status = 'active'
       and coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb) ? k.iso_alpha2),
  li as (select distinct on (f.course_id) f.course_id, f.state, f.reason from pipeline.field_enrich_items f
          where f.field = 'entry_requirements' order by f.course_id, f.updated_at desc),
  cpend as (select distinct on (i.entity_id) i.entity_id course_id, i.id from pipeline.layer4_review_items i
             where i.status = 'pending' and i.field_code = 'course_entry_first_read' order by i.entity_id, i.created_at),
  ppend as (select i.entity_id provider_id, count(*) n, (array_agg(i.id order by i.created_at))[1] first_id from pipeline.layer4_review_items i
             where i.status = 'pending' and i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') group by i.entity_id),
  mact as (select m.provider_id, count(*) n from catalogue.provider_entry_matrix m where m.status = 'active' group by 1),
  cact as (select r.course_id, count(*) n from catalogue.course_entry_requirements r where r.status = 'active' group by 1)
  select c.id, c.provider_id, c.cc, c.pname, coalesce(c.pub, false), c.title, c.course_code, o.outcome, o.detail,
         c.url, c.gs, c.identity_basis, li.state, li.reason,
         case when o.outcome = 'awaiting_review' then coalesce(cp.id, pp.first_id) when cp.id is not null then cp.id end, now()
    from c
    left join li on li.course_id = c.id
    left join cpend cp on cp.course_id = c.id
    left join ppend pp on pp.provider_id = c.provider_id
    left join mact ma on ma.provider_id = c.provider_id
    left join cact ca on ca.course_id = c.id
    cross join lateral (select case
        when ca.n is not null then 'admitted_course'
        when ma.n is not null then 'admitted_provider'
        when cp.id is not null then 'awaiting_review'
        when li.state = 'skipped' then 'no_requirement_published'
        when pp.n is not null then 'awaiting_review'
        when c.gs is null then 'no_course_url'
        when c.gs <> 'bound' or not c.id_ok then 'identity_unresolved'
        when li.state = 'failed' or not c.stored then 'source_unreadable'
        else 'excluded' end outcome) oc
    cross join lateral (select oc.outcome, case oc.outcome
        when 'admitted_course' then ca.n || ' active course-level row(s)'
        when 'admitted_provider' then 'provider table active (' || ma.n || ' rows): the resolver answers by country'
             || case when cp.id is not null then '; the course''s own read also waits in Layer 4' else '' end
        when 'awaiting_review' then case when cp.id is not null then 'the course''s read waits in Layer 4 (course entry first read)'
             else 'the provider''s table waits in Layer 4 (' || pp.n || ' item(s))' end
        when 'no_requirement_published' then 'read finished, nothing kept: ' || coalesce(li.reason, 'no reason recorded')
             || case when pp.n is not null then '; the provider''s table waits in Layer 4' else '' end
        when 'no_course_url' then 'no official course page found'
        when 'identity_unresolved' then case when c.gs <> 'bound' then 'course page ' || c.gs
             else 'identity basis ' || coalesce(c.identity_basis, 'none') || ' is not accepted for entry requirements' end
        when 'source_unreadable' then case when li.state = 'failed' then 'read held or failed: ' || coalesce(li.reason, 'no reason recorded')
             else 'the bound course page has no stored copy' end
        else case when not c.in_scope then 'provider outside the entry-read scope (setting entry.course_read_providers)'
             else 'eligible, not read: course reads are held (AER production-closure mandate, 30 Oct 2026)' end end detail) o;
  get diagnostics v_n = row_count;
  select coalesce(jsonb_object_agg(x.outcome, x.n), '{}'::jsonb) into v_by from (select a.outcome, count(*) n from pipeline.aer_course_outcomes a group by 1) x;
  insert into pipeline.aer_course_outcome_builds(built_at, finished_at, took_ms, courses, by_outcome, source)
  values (v_t, clock_timestamp(), round(extract(epoch from clock_timestamp() - v_t) * 1000)::int, v_n, v_by, p_source);
  return jsonb_build_object('state', 'built', 'courses', v_n, 'took_ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)::int);
end $function$
