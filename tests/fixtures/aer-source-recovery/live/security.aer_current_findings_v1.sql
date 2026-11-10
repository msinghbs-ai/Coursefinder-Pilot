CREATE OR REPLACE FUNCTION security.aer_current_findings_v1()
 RETURNS TABLE(fingerprint text, root_cause text, provider_id uuid, source_id uuid, scope_kind text, scope_key text, scope_label text, study_level text, evidence jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with el as (select * from security.aer_eligible_v1()),
  src as (
    select s.id, s.provider_id, s.title, s.url, s.status, s.error, s.read_at, s.content_hash,
           r.id run_id, r.state, r.error run_error, r.content_hash run_hash, r.result->'completeness'->>'status' cstatus,
           coalesce(r.result->'completeness'->>'heading', substring(r.error from '\("([^"]{1,120})')) heading,
           (select k.iso_alpha2::text from ref.countries k where k.iso_alpha2 ~ '^[A-Z]{2}$'
               and lower(replace(coalesce(s.title, ''), '-', ' ')) like '%' || lower(k.name) || '%' order by length(k.name) desc limit 1) title_country
      from pipeline.entry_matrix_sources s
      left join lateral (select r1.* from pipeline.entry_matrix_runs r1 where r1.source_id = s.id order by r1.created_at desc limit 1) r on true),
  src_f as (
    -- a source whose fetch failed, a read source never extracted, a read source whose latest run is held or incomplete, a stale source
    select s.*, c.cause from src s
     cross join lateral (values
       (case when s.status = 'failed' then 'source_unreadable' end),
       (case when s.status = 'read' and s.run_id is null then 'not_extracted' end),
       (case when s.status = 'read' then security.aer_run_cause_v1(s.state, s.run_error, s.cstatus) end),
       (case when s.status = 'read' and s.read_at < now() - make_interval(days => security.pipeline_num_v1('aer.stale_source_days', 90)::int) then 'stale_source' end)) c(cause)
     where c.cause is not null),
  src_rows as (
    select f.cause, f.provider_id, f.id source_id,
           case when f.cause = 'non_country_heading' then 'qualification' when f.title_country is not null then 'country' else 'source' end scope_kind,
           case when f.cause = 'non_country_heading' then btrim(regexp_replace(lower(coalesce(f.heading, f.title, '')), '[^a-z0-9]+', ' ', 'g'))
                when f.title_country is not null then f.title_country else f.id::text end scope_key,
           coalesce(case when f.cause = 'non_country_heading' then f.heading end, f.title, f.url) scope_label,
           jsonb_build_object('source_title', f.title, 'url', f.url, 'source_status', f.status, 'source_error', left(f.error, 200), 'read_at', f.read_at,
                              'run_id', f.run_id, 'run_state', f.state, 'run_error', left(f.run_error, 300), 'completeness', f.cstatus) evidence
      from src_f f),
  prov_rows as (
    -- an eligible provider with no source
    select 'no_source' cause, e.provider_id, null::uuid source_id, 'provider' scope_kind, null::text scope_key, e.country scope_label, null::text study_level,
           jsonb_build_object('country', e.country) evidence
      from el e where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)
    union all
    -- extracted requirements waiting for Layer 4
    select 'awaiting_layer4', w.provider_id, null, 'provider', null, null, null,
           jsonb_build_object('matrix_proposed', sum(w.m), 'course_proposed', sum(w.c))
      from (select m.provider_id, count(*) m, 0 c from catalogue.provider_entry_matrix m where m.status = 'proposed' group by 1
            union all
            select c.provider_id, 0, count(*) from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where x.status = 'proposed' group by 1) w
     group by w.provider_id
    union all
    -- course entry reads held whole (course outcome register), by study level
    select 'course_read_held', o.provider_id, null, 'study_level', coalesce(l.short_code, 'none'), coalesce(l.short_code, 'none'), coalesce(l.short_code, 'none'),
           jsonb_build_object('courses', count(*), 'sample', (array_agg(jsonb_build_object('course_id', o.course_id, 'reason', left(o.read_reason, 160)) order by o.course_id))[1:5])
      from pipeline.aer_course_outcomes o join catalogue.courses c on c.id = o.course_id left join ref.study_levels l on l.id = c.study_level_id
     where o.outcome = 'source_unreadable'
     group by o.provider_id, l.short_code
    union all
    -- a defect named on pending Layer 4 items: one finding per provider and root cause, linked to every item (mandate 16:33 §9)
    select z.root_cause, z.provider_id, null, 'review_items', z.readiness, z.readiness, null,
           jsonb_build_object('items', count(*), 'sample', (array_agg(z.review_item_id order by z.review_item_id))[1:20])
      from pipeline.aer_review_readiness z
     where z.settled_at is null and z.root_cause is not null and z.readiness in ('reader_correction_required', 'evidence_required', 'superseded_invalid')
     group by z.root_cause, z.provider_id, z.readiness
    union all
    -- P0: active (consumer-resolvable) rows without evidence or quote
    select 'consumer_unevidenced', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m where m.status = 'active' and (m.evidence_id is null or btrim(coalesce(m.quote, '')) = '')
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
             where x.status = 'active' and (x.evidence_id is null or btrim(coalesce(x.quote, '')) = '')) z
     group by z.provider_id
    union all
    -- P0: active AI-read rows whose Layer 4 item is not approved
    select 'consumer_unadmitted', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m
              left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.layer4_review_items li on li.id = r.review_item_id
             where m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
              left join pipeline.layer4_review_items li on li.id = nullif(x.provenance->>'review_item_id', '')::uuid
             where x.status = 'active' and coalesce(x.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')) z
     group by z.provider_id
    union all
    -- P0: active numeric minimum without its scale
    select 'consumer_number_without_scale', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m where m.status = 'active' and m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none'
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
             where x.status = 'active' and x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none') z
     group by z.provider_id),
  allr as (
    select cause, provider_id, source_id, scope_kind, scope_key, scope_label, null::text study_level, evidence from src_rows
    union all
    select cause, provider_id, source_id, scope_kind, scope_key, scope_label, study_level, evidence from prov_rows)
  select distinct on (1) security.aer_fingerprint_v1(a.provider_id, a.source_id, a.scope_kind, a.scope_key, a.study_level, a.cause),
         a.cause, a.provider_id, a.source_id, a.scope_kind, a.scope_key, a.scope_label, a.study_level, a.evidence
    from allr a
   order by 1
$function$
