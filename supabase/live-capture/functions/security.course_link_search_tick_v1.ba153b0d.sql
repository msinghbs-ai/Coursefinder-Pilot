CREATE OR REPLACE FUNCTION security.course_link_search_tick_v1(p_batch integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_urls text[]; v_c text[]; v_cap numeric; v_on boolean; v_used numeric; v_key text; v_dom text;
        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
begin
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;

  -- 1. Collect finished searches.
  for r in select s.*, h.status_code, h.content from pipeline.course_link_search s join net._http_response h on h.id = s.req_id
            where s.state = 'sent' loop
    n_harvest := n_harvest + 1;
    if r.status_code = 200 and left(r.content, 1) = '{' then
      perform public.svc_coverage_usage(2, 'course_link_search', r.provider_id, r.query);
      v_urls := array(select e->>'url' from jsonb_array_elements(coalesce((r.content::jsonb)->'data', '[]'::jsonb)) e);
      v_c := security.course_link_pick_v1(r.provider_id, v_urls);
      if cardinality(v_c) > 0 then
        update pipeline.course_link_search set state = 'found', results = to_jsonb(v_urls), candidates = to_jsonb(v_c), cand_idx = 1,
               bound_url = v_c[1], done_at = now() where course_id = r.course_id;
        perform security.course_link_bind_v1(r.course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
        n_found := n_found + 1;
      elsif r.stage = 'cricos' then
        update pipeline.course_link_search set stage = 'title', state = 'queued', results = to_jsonb(v_urls), attempts = 0 where course_id = r.course_id;
      else
        update pipeline.course_link_search set state = 'none', results = to_jsonb(v_urls), done_at = now() where course_id = r.course_id;
      end if;
    else
      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
  end loop;
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. Pages the reader could not confirm move to the next candidate, then to the title search.
  for r in select s.*, p.status pstatus, p.read_status, p.read_attempts from pipeline.course_link_search s
             join pipeline.coverage_course_pages p on p.course_id = s.course_id and p.url = s.bound_url
            where s.state = 'found' and (p.status = 'mismatch' or (p.read_status in ('fetch_failed','blocked','robots_disallowed') and (p.read_attempts >= 2 or p.http_status in (404, 410)))) loop
    if r.cand_idx < jsonb_array_length(r.candidates) then
      v_next := r.candidates->>r.cand_idx;
      update pipeline.course_link_search set cand_idx = cand_idx + 1, bound_url = v_next where course_id = r.course_id;
      perform security.course_link_bind_v1(r.course_id, r.provider_id, v_next, case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
    elsif r.stage = 'cricos' then
      update pipeline.course_link_search set stage = 'title', state = 'queued', attempts = 0, done_at = null where course_id = r.course_id;
    else
      update pipeline.course_link_search set state = 'none', done_at = now() where course_id = r.course_id;
    end if;
    n_moved := n_moved + 1;
  end loop;
  update pipeline.course_link_search s set state = 'verified' from pipeline.coverage_course_pages p
   where s.state = 'found' and p.course_id = s.course_id and p.url = s.bound_url and p.status = 'bound' and p.identity_basis is not null;

  -- 2b. Decision 217: courses without a CRICOS code whose earlier page was read again and is not theirs are searched by title.
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
  select p.course_id, p.provider_id, 'title', 'queued', now()
    from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
   where p.status = 'mismatch' and p.basis not in ('cricos_search', 'title_search')
     and coalesce(c.course_code, '') !~ '^[0-9]{6}[0-9A-Z]$'
     and exists (select 1 from pipeline.course_link_recipes rc where rc.provider_id = p.provider_id and rc.active)
     and not exists (select 1 from pipeline.course_link_search s where s.course_id = p.course_id)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p.course_id and k.field = 'official_url')
   limit 200
  on conflict (course_id) do nothing;

  -- 2c. Decision 252: pages from the Serper search pass, after the reader.
  perform security.search_pass_advance_v1();

  -- 3. Send the next batch, inside the monthly credit cap.
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if v_on and coalesce((select x.send_via from pipeline.course_link_search_settings x where x.id = 1), 'pg_net') = 'pg_net' and v_used + 2 * p_batch <= v_cap then
    v_key := public.svc_coverage_firecrawl()->>'secret';
    if v_key is not null then
      for r in select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
                 from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
                 join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
                 left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
                where s.state = 'queued' order by (s.stage <> 'cricos'), row_number() over (partition by s.provider_id order by md5(s.course_id::text)), coalesce(pp.rank, 100000)
                limit greatest(1, least(coalesce(p_batch, 40), 100)) loop
        v_dom := case r.stage when 'cricos' then '"' || r.course_code || '" site:' || r.search_domain
                                         else '"' || replace(regexp_replace(r.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || r.search_domain end;
        update pipeline.course_link_search set state = 'sent', sent_at = now(), query = v_dom,
               req_id = net.http_post(url := 'https://api.firecrawl.dev/v1/search',
                          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
                          body := jsonb_build_object('query', v_dom, 'limit', 5), timeout_milliseconds := 60000)
         where course_id = r.course_id;
        n_sent := n_sent + 1;
      end loop;
    end if;
  end if;
  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap);
end $function$
