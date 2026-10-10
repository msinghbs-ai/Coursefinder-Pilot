CREATE OR REPLACE FUNCTION security.course_link_reverse_tick_v1(p_batch integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; n_done int := 0; n_bound int := 0; n_sent int := 0;
begin
  -- 1. Store the CRICOS codes printed on each page read.
  for r in select x.url, h.status_code, h.content from pipeline.course_link_reverse x join net._http_response h on h.id = x.req_id where x.state = 'sent' loop
    n_done := n_done + 1;
    if r.status_code = 200 and r.content is not null then
      update pipeline.course_link_reverse set state = 'done', done_at = now(),
             codes = array(select distinct m[1] from regexp_matches(upper(r.content), '(?:^|[^0-9A-Z])([0-9]{6}[0-9A-Z])(?![0-9A-Z])', 'g') m)
       where url = r.url;
    else
      update pipeline.course_link_reverse set state = 'error', done_at = now() where url = r.url;
    end if;
  end loop;
  update pipeline.course_link_reverse set state = 'queued'
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. For universities whose pages are all read: bind a course still being searched for when its code is on exactly
  --    one page, and that page shows no more than three of the university's codes.
  for r in with done_prov as (select provider_id from pipeline.course_link_reverse group by provider_id
                               having bool_and(state in ('done','error')) and bool_or(state = 'done')),
                pc as (select x.provider_id, x.url, co.id course_id, co.course_code
                         from pipeline.course_link_reverse x join done_prov using (provider_id)
                         join catalogue.courses co on co.provider_id = x.provider_id and co.lifecycle_status = 'active' and co.course_code = any(x.codes)
                        where x.state = 'done'),
                per_page as (select url, count(*) n from pc group by url),
                per_code as (select course_id, count(distinct url) n from pc group by course_id)
           select pc.provider_id, pc.url, pc.course_id from pc join per_page pp using (url) join per_code pk using (course_id)
             join pipeline.course_link_search s on s.course_id = pc.course_id and s.state in ('queued','none','error')
            where pp.n <= 3 and pk.n = 1 loop
    update pipeline.course_link_search set state = 'found', candidates = to_jsonb(array[r.url]), cand_idx = 1, bound_url = r.url, done_at = now()
     where course_id = r.course_id;
    perform security.course_link_bind_v1(r.course_id, r.provider_id, r.url, 'cricos_search');
    update pipeline.course_link_reverse set bound = bound + 1 where url = r.url;
    n_bound := n_bound + 1;
  end loop;

  -- 3. Read the next pages, universities in turn.
  for r in select x.url from pipeline.course_link_reverse x where x.state = 'queued'
            order by row_number() over (partition by x.provider_id order by x.url) limit greatest(1, least(coalesce(p_batch, 30), 60)) loop
    update pipeline.course_link_reverse set state = 'sent', sent_at = now(),
           req_id = net.http_get(r.url, headers := jsonb_build_object('user-agent', 'Mozilla/5.0 (compatible; CourseFinderBot/1.0)'), timeout_milliseconds := 30000)
     where url = r.url;
    n_sent := n_sent + 1;
  end loop;
  return jsonb_build_object('read', n_done, 'bound', n_bound, 'sent', n_sent);
end $function$
