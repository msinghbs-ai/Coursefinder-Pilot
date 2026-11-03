CREATE OR REPLACE FUNCTION security.field_stalled_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (select security.pipeline_num_v1('stall.days', 7)::int d, security.pipeline_num_v1('stall.min_points', 1) mp, security.pipeline_num_v1('stall.country_gap_points', 30) gp),
  today as (select max(snapshot_date) t from pipeline.field_coverage_daily),
  cur as (select x.country_code cc, x.field, x.total, x.filled, round(100.0 * x.filled / nullif(x.total, 0), 1) pct
            from pipeline.field_coverage_daily x, today where x.snapshot_date = today.t and x.total > 0),
  ago as (select distinct on (x.country_code, x.field) x.country_code cc, x.field, x.snapshot_date, round(100.0 * x.filled / nullif(x.total, 0), 1) pct
            from pipeline.field_coverage_daily x, today, s where x.snapshot_date <= today.t - s.d and x.total > 0
           order by x.country_code, x.field, x.snapshot_date desc),
  best as (select field, max(pct) pct, (array_agg(cc order by pct desc))[1] cc from cur group by field),
  cause as (select z.country_code cc, z.attribute field, jsonb_object_agg(z.c, z.n) counts, (array_agg(z.c order by z.n desc))[1] main
              from (select a.country_code, a.attribute,
                           case when a.state = 'not_on_page' then 'not_stated' when a.state = 'in_queue' then 'in_queue'
                                when a.state in ('in_review', 'candidate', 'awaiting_l3') then 'in_review' when a.state in ('page_found', 'blocked') then 'not_read'
                                when a.state in ('site_known', 'no_website') then 'no_page' when a.state = 'missing_l1' then 'register' when a.state = 'no_reader' then 'no_reader' end c,
                           count(*) n
                      from pipeline.course_attribute_coverage a where a.state <> 'admitted' group by 1, 2, 3) z
             group by 1, 2),
  rows as (
    select c.cc, c.field, r.label, r.reader, r.level, c.total, c.filled, c.pct, r.target_pct target, g.pct pct_ago, g.snapshot_date ago_date,
           round(c.pct - g.pct, 1) moved, b.cc best_cc, b.pct best_pct,
           case when r.reader = 'none' then 'no_reader'
                when g.pct is not null and c.pct - g.pct < s.mp then 'flat'
                when b.pct - c.pct >= s.gp then 'behind' end reason,
           case when r.reader = 'none' then 'no_reader' when r.level = 'provider' then 'provider' else coalesce(k.main, 'not_read') end main_cause,
           k.counts
      from cur c join pipeline.field_register r on r.field = c.field and r.active and r.target_pct > 0
      cross join s left join ago g on g.cc = c.cc and g.field = c.field left join best b on b.field = c.field
      left join cause k on k.cc = c.cc and k.field = c.field
     where c.pct < r.target_pct)
  select coalesce(jsonb_agg(jsonb_build_object(
           'country', r.cc, 'field', r.field, 'label', r.label, 'reader', r.reader, 'level', r.level, 'total', r.total, 'filled', r.filled, 'pct', r.pct,
           'target', r.target, 'pct_ago', r.pct_ago, 'ago_date', r.ago_date, 'moved', r.moved, 'days', (select d from s), 'best_country', r.best_cc, 'best_pct', r.best_pct,
           'reason', r.reason, 'cause', r.main_cause, 'causes', r.counts,
           'can_fill', r.field in ('level', 'field_of_study', 'duration', 'delivery', 'campus', 'campus_city', 'international', 'p_address'),
           'action', case
              when r.reason = 'no_reader' then 'Nothing reads this field yet: a reader is a build task. Set the target to 0 until it exists, so the field is not raised.'
              when r.main_cause = 'in_queue' then 'Being filled now by Fill the gaps or an Enrich fields task: check again after the run.'
              when r.main_cause = 'in_review' then 'Waiting for a person: Layer 4 › Inbox, and For review in the Enrich fields task results.'
              when r.main_cause = 'register' then 'The register does not give it: check the register run on Layer 1 Register.'
              when r.main_cause = 'not_stated' and r.reader = 'enrich' then 'The course pages read do not state it. Add a central page or an adapter rule for the universities below (Layer 2/3 › Universities › Builder), then Release holds and fill; or lower the target if the universities do not publish it.'
              when r.main_cause = 'not_stated' then 'The course pages read do not state it. Add a central page or an adapter rule for the universities below (Layer 2/3 › Universities › Builder); or lower the target if the universities do not publish it.'
              when r.main_cause in ('not_read', 'no_page') and r.reader = 'enrich' then 'Pages not read for this field yet: Fill now starts an Enrich fields task for it in this country (AI on, new page reads within the daily limits).'
              when r.main_cause in ('not_read', 'no_page') then 'Course pages not found or not read: check course-page search for the universities below on Layer 2/3 › Operations and Universities.'
              when r.field = 'p_address' then 'Fill now reads each provider''s contact or home page for its street address.'
              else 'Provider field: open the providers missing it on Providers and add it, or lower the target.' end,
           'top_providers', case when r.level = 'course' then (
              select coalesce(jsonb_agg(jsonb_build_object('id', t.provider_id, 'name', t.name, 'missing', t.n) order by t.n desc), '[]'::jsonb) from (
                select a.provider_id, max(coalesce(p.display_name, p.canonical_name)) name, count(*) n from pipeline.course_attribute_coverage a join catalogue.providers p on p.id = a.provider_id
                 where a.country_code = r.cc and a.attribute = r.field and a.state <> 'admitted' group by 1 order by 3 desc limit 5) t) end)
         order by r.cc, case r.reason when 'flat' then 1 when 'behind' then 2 when 'no_reader' then 3 else 4 end, r.target - r.pct desc), '[]'::jsonb)
    from rows r
$function$
