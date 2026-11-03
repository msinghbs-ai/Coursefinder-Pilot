-- CF-247 AER rendered pilot: read-only measurement. Did the rendered read capture the country (UniSQ) or qualification x course (JCU) table?
-- Run in a load window (:x6-:x8) after the next entry-matrix-read runs. captured = rendered (read_via firecrawl), read done, and rows proposed for
-- at least 5 distinct countries (a measurement threshold, not a control) with none of them dropped as not on the page.
with p as (select s.* from pipeline.entry_matrix_sources s
            where lower(substring(s.url from '^https?://(?:www\.)?([^/:?#]+)')) in ('jcu.edu.au', 'unisq.edu.au')),
r as (select distinct on (x.source_id) x.* from pipeline.entry_matrix_runs x join p on p.id = x.source_id order by x.source_id, x.created_at desc),
m as (select x.source_id, count(*) n, count(distinct x.country_code) countries, array_agg(distinct x.country_code) codes
        from catalogue.provider_entry_matrix x join r on r.id = x.run_id group by 1),
u as (select x.url, sum(x.units) credits from pipeline.coverage_vendor_usage x join p on p.url = x.url
       where x.purpose = 'provider_facts_scrape' and x.at > (select max(at) from pipeline.admin_control_events where action = 'aer_render_pilot_start') group by 1)
select p.url, p.status, p.read_via, p.http_status, p.attempts, p.content_hash is not null stored, r.state run_state, left(r.error, 160) run_error,
       r.rows_admitted, r.rows_dropped, r.result->'completeness'->>'status' completeness, m.countries, m.codes,
       (select count(*) from jsonb_array_elements(coalesce(r.result->'dropped', '[]'::jsonb)) d where d->>'reason' = 'quote_not_on_page') dropped_not_on_page,
       coalesce(u.credits, 0) firecrawl_credits,
       p.read_via = 'firecrawl' and r.state = 'done' and coalesce(m.countries, 0) >= 5 captured
  from p left join r on r.source_id = p.id left join m on m.source_id = p.id left join u on u.url = p.url
 order by p.url;
