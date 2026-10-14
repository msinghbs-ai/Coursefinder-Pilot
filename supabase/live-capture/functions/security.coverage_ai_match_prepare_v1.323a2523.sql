CREATE OR REPLACE FUNCTION security.coverage_ai_match_prepare_v1(p_providers integer DEFAULT 4, p_courses integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare r record; v jsonb := '[]'::jsonb; v_n int;
begin
  for r in
    with missing as (
      select co.provider_id, count(*) n
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.lifecycle_status = 'active'
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < 3
       group by 1)
    select m.provider_id, m.n from missing m
     where exists (select 1 from pipeline.coverage_provider_urls u where u.provider_id = m.provider_id)
     order by coalesce((select pp.rank from pipeline.provider_priority pp where pp.provider_id = m.provider_id), 100000), m.n desc
     limit greatest(1, least(p_providers, 500))
  loop
    insert into pipeline.coverage_ai_match(course_id, provider_id, attempt, state, candidates)
    with c as (
      select co.id course_id, lower(coalesce(co.course_code, '')) code,
             security.coverage_text_tokens(regexp_replace(co.canonical_title, '\(\s*level\s+\d+\s*\)', '', 'i')) tok,
             (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) prev
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.provider_id = r.provider_id and co.lifecycle_status = 'active'
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < 3
       order by coalesce(co.open_to_international, false) desc, co.id
       limit greatest(1, least(p_courses, 1000))),
    tried as (
      select p.course_id, p.url from pipeline.coverage_course_pages p join c using (course_id)
      union select q.course_id, q.chosen_url from pipeline.coverage_ai_match q join c using (course_id) where q.chosen_url is not null),
    u as (
      select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
        from pipeline.coverage_provider_urls where provider_id = r.provider_id
         and url !~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|contact|faqs?)(/|$)'
         and url !~* '\.(pdf|jpe?g|png|gif|svg|docx?|xlsx?|zip)(\?|$)'),
    ct as (select course_id, cardinality(tok) nc, t from c, unnest(tok) t),
    ut as (select url, ns n, t from u, unnest(tokens) t union all select url, nt, t from u, unnest(title_tokens) t),
    m as (select ct.course_id, ut.url, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1, 2),
    s as (select m.course_id, m.url, max(2.0 * hits / nullif(nc + nu, 0)) sc from m group by 1, 2
          union all
          select c.course_id, u.url, 2.0 from c join u on length(c.code) >= 6 and position(c.code in lower(u.url)) > 0),
    best as (select s.course_id, s.url, max(s.sc) sc from s where not exists (select 1 from tried t where t.course_id = s.course_id and t.url = s.url) group by 1, 2),
    rk as (select b.*, row_number() over (partition by b.course_id order by b.sc desc, length(b.url)) n from best b)
    select c.course_id, r.provider_id, c.prev + 1,
           case when count(rk.url) = 0 then 'no_candidates' else 'ready' end,
           coalesce(jsonb_agg(jsonb_build_object('url', rk.url, 'title', left(coalesce(u.title, ''), 160)) order by rk.n) filter (where rk.url is not null), '[]'::jsonb)
      from c left join rk on rk.course_id = c.course_id and rk.n <= 25
      left join u on u.url = rk.url
     group by c.course_id, c.prev;
    get diagnostics v_n = row_count;
    v := v || jsonb_build_object('provider_id', r.provider_id, 'prepared', v_n);
  end loop;
  return v;
end $function$
