CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;
begin
  select * into v_j from pipeline.admin_jobs j where j.id = p_id for update;
  v_last_done := coalesce((v_j.cursor->>'last_done')::int, -1);
  v_last_at := coalesce((v_j.cursor->>'last_change_at')::timestamptz, v_j.started_at, v_j.created_at);
  if v_j.kind = 'reread_pages' then
    v_stall := interval '30 minutes';
    select * into r from pipeline.university_reread_requests q where q.id = (v_j.args->>'request_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the re-read request is gone';
    elsif r.status = 'cancelled' then v_fin := true; v_note := 'cancelled before every university was sent (' || cardinality(r.done_ids) || ' of ' || cardinality(r.provider_ids) || ' sent)';
    elsif r.status = 'failed' then v_fin := true; v_note := 'the request failed: ' || coalesce(r.last_error, 'no detail');
    elsif r.status in ('waiting', 'sending') then
      v_phase := 'sending'; v_done := cardinality(r.done_ids); v_total := cardinality(r.provider_ids);
    else
      v_phase := 'reading'; v_total := coalesce(r.pages, 0);
      v_ids := r.provider_ids;
      select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = any (v_ids) and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
      if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) sent back and read again'; end if;
    end if;
  elsif v_j.kind = 'firecrawl_run' then
    select * into r from pipeline.firecrawl_runs x where x.id = (v_j.args->>'run_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the run is gone';
    else
      v_done := coalesce(r.done, 0); v_total := coalesce(r.items, 0);
      if r.status <> 'running' then v_fin := true; v_note := 'run ' || r.status || ': ' || v_done || ' of ' || v_total || ' done, ' || coalesce(r.credits_used, 0) || ' credits'; end if;
    end if;
  elsif v_j.kind = 'adapter_apply' then
    v_stall := interval '20 minutes';
    v_total := coalesce((v_j.args->>'pages')::int, 0);
    select count(*) into v_done from pipeline.coverage_course_pages pg where pg.provider_id = (v_j.args->>'provider_id')::uuid and pg.read_at >= coalesce(v_j.started_at, v_j.created_at);
    if v_done >= v_total then v_fin := true; v_note := v_total || ' page(s) read again with the adapter'; end if;
  elsif v_j.kind = 'central_page_read' then
    v_stall := interval '30 minutes'; v_total := 1;
    select * into r from pipeline.provider_fact_sources s where s.id = (v_j.args->>'source_id')::uuid;
    if r.id is null then v_fin := true; v_note := 'the central page record is gone';
    elsif r.status in ('read', 'parsed', 'no_values', 'failed') and r.updated_at >= coalesce(v_j.started_at, v_j.created_at) - interval '1 minute' then
      v_done := 1; v_fin := true; v_note := 'page ' || r.status || coalesce(': ' || (r.parse_summary->>'error'), '');
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks. The pages in scope were queued first in line when the task
  -- started; each minute this checks progress, sends the scraper worker the next step (map the site, screen candidate pages, read
  -- scholarship pages) when none is already on its way, and finishes when nothing in scope is left to do.
  elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_stall := interval '30 minutes'; v_since := v_j.created_at;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x);
    v_sch := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x);
    select count(*) filter (where p.requested_at is null and p.read_at >= v_since), count(*) into v_done, v_total
      from pipeline.scholarship_pages p join scholarship.scholarships s on s.id = p.scholarship_id
     where s.lifecycle_status = 'active'
       and (case when v_j.kind = 'scholarship_reread' then s.id = any (v_sch) else s.provider_id = any (v_ids) end)
       and (p.requested_at is not null or p.read_at >= v_since or s.created_at >= v_since);
    if v_j.kind = 'scholarship_provider_scan' then
      select count(*) into v_n_map from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and d.status = 'pending' and d.attempts < 3;
      select count(*) into v_n_cand from pipeline.scholarship_page_candidates c
       where c.provider_id = any (v_ids) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.next_read_at <= now() and c.attempts < 3;
    end if;
    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    v_extra := jsonb_build_object('phase_detail', v_phase, 'providers_mapping', v_n_map, 'candidates_waiting', v_n_cand,
      'new_scholarships', (select count(*) from scholarship.scholarships s where s.provider_id = any (v_ids) and s.created_at >= v_since),
      'links_changed', (select count(*) from pipeline.scholarship_sweep_changes c join scholarship.scholarships s on s.id = c.scholarship_id
                         where s.provider_id = any (v_ids) and c.field = 'course_links' and c.changed_at >= v_since),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = any (v_ids) and u.purpose like 'sch\_%' and u.at >= v_since));
    if v_j.kind = 'scholarship_course_check' then
      v_before := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'before', '[]'::jsonb)) x);
      v_extra := v_extra || jsonb_build_object('course_id', v_j.args->>'course_id',
        'linked_now', (select count(*) from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped'),
        'added', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id
                   where m.course_id = (v_j.args->>'course_id')::uuid and m.mapping_state = 'mapped' and not (m.scholarship_id = any (v_before))),
        'removed', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name), '[]'::jsonb) from scholarship.scholarships s
                     where s.id = any (v_before) and not exists (select 1 from scholarship.course_mappings m where m.course_id = (v_j.args->>'course_id')::uuid and m.scholarship_id = s.id and m.mapping_state = 'mapped')));
    end if;
    if v_n_map = 0 and v_n_cand = 0 and v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' known scholarship page(s) read again through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' scholarship scraper credit(s) used for ' || case when cardinality(v_ids) = 1 then 'this provider' else 'these providers' end || ' while the task ran'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
    -- v2.15.248 (Platform Admin bugs 11/10-5, Feature 2): record what the task found and read, item by item, and count the new
    -- pages it checked in its progress and result
    perform security.scholarship_job_items_sync_v1(v_j.id);
    select v_extra || jsonb_build_object('candidates_found', count(*) filter (where i.kind = 'candidate'), 'became', count(*) filter (where i.outcome = 'became_scholarship'),
             'refused', count(*) filter (where i.outcome = 'refused'), 'too_thin', count(*) filter (where i.outcome = 'too_thin'), 'skipped', count(*) filter (where i.outcome = 'skipped'),
             'known_pages', count(*) filter (where i.kind = 'page')),
           v_done + count(*) filter (where i.kind = 'candidate' and i.outcome <> 'waiting'), v_total + count(*) filter (where i.kind = 'candidate')
      into v_extra, v_done, v_total from pipeline.admin_job_items i where i.job_id = v_j.id;
    if v_fin then
      v_done := v_total;
      v_note := coalesce(nullif((v_extra->>'candidates_found')::int, 0) || ' new page(s) checked (' || (v_extra->>'became') || ' became scholarships, ' || (v_extra->>'refused') || ' refused, '
                || (v_extra->>'too_thin') || ' too thin, ' || (v_extra->>'skipped') || ' skipped); ', 'no new pages found; ') || v_note;
    end if;
  -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website (website, then contacts, then central
  -- pages; each step sent to the worker when none is on its way) and Find course pages with Firecrawl (the chosen courses first in
  -- the course page search, finished when each has been searched).
  elsif v_j.kind = 'provider_fill' then
    v_stall := interval '30 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid; v_total := 3;
    select nullif(btrim(p.website), ''), (p.phone is not null and p.email is not null) into v_site, v_cok from catalogue.providers p where p.id = v_pid;
    select * into r from pipeline.coverage_provider_discovery d where d.provider_id = v_pid;
    if v_site is null and r.provider_id is not null and r.status = 'no_website' and (r.site_searched_at is null or r.site_searched_at < v_since) then
      v_phase := 'finding the website'; v_done := 0;
      perform security.provider_task_fire_v1('find_site');
    elsif v_site is null then
      v_fin := true; v_done := 3;
      v_note := 'no website could be verified by search' || coalesce(' (' || (r.site_evidence->>'note') || ')', '') || '; enter it by hand in the Adapter builder, step 1.1';
    else
      v_done := 1;
      if not coalesce(v_cok, false) and exists (select 1 from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active')
         and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = v_pid and k.kind = 'public_general' and k.checked_at >= v_since and k.outcome not in ('leased', 'requested')) then
        v_phase := 'reading contacts';
        perform security.provider_task_fire_v1('contact_page');
      else
        v_done := 2;
        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased')) then
          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');
        else
          v_done := 3; v_fin := true;
        end if;
      end if;
    end if;
    v_extra := jsonb_build_object('phase_detail', coalesce(v_phase, 'finishing'), 'website', v_site, 'website_basis', r.site_evidence->>'basis',
      'phone', (select p.phone from catalogue.providers p where p.id = v_pid), 'email', (select p.email from catalogue.providers p where p.id = v_pid),
      'central_found', (select coalesce(jsonb_array_length(s.found), 0) from pipeline.provider_central_search s where s.provider_id = v_pid),
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.at >= v_since));
    if v_fin and v_note is null then
      v_note := 'website ' || coalesce(v_site, 'not found') || '; phone ' || coalesce(v_extra->>'phone', 'not found') || ', email ' || coalesce(v_extra->>'email', 'not found')
             || '; ' || coalesce(v_extra->>'central_found', '0') || ' central page suggestion(s) to attach in the Adapter builder, step 1.3; ' || (v_extra->>'credits') || ' Firecrawl credit(s)';
    end if;
  -- v2.15.249 (bugs 11/10-6): qualifying the scholarship AI on the sample, or re-checking universities' pages with it
  elsif v_j.kind in ('scholarship_ai_qualify', 'scholarship_ai_backfill') then
    v_stall := interval '30 minutes';
    select count(*) filter (where q.state in ('done', 'failed')), count(*) into v_done, v_total from pipeline.scholarship_ai_queue q where q.job_id = v_j.id;
    v_phase := 'reading pages with AI';
    select jsonb_build_object('phase_detail', v_phase, 'scholarships', count(*) filter (where e.verdict = 'scholarship'), 'not_scholarships', count(*) filter (where e.verdict in ('not_scholarship', 'listing')),
             'unproven', count(*) filter (where e.verdict = 'unproven'), 'ai_errors', count(*) filter (where e.error is not null), 'admitted', count(*) filter (where coalesce((e.applied->>'admitted')::boolean, false)),
             'cost_usd', round(coalesce(sum(e.cost_usd), 0), 4))
      into v_extra from pipeline.scholarship_ai_extractions e where e.job_id = v_j.id;
    if v_done >= v_total then
      v_fin := true;
      v_note := v_done || ' page(s) read with AI: ' || (v_extra->>'scholarships') || ' scholarship(s), ' || (v_extra->>'not_scholarships') || ' not a scholarship, ' || (v_extra->>'unproven') || ' unproven, '
                || (v_extra->>'ai_errors') || ' error(s)' || case when v_j.kind = 'scholarship_ai_backfill' then ', ' || (v_extra->>'admitted') || ' admitted' else '' end || '; US$' || (v_extra->>'cost_usd');
    else
      perform security.scholarship_ai_fire_v1();
    end if;
  elsif v_j.kind = 'course_page_find' then
    v_stall := interval '45 minutes'; v_since := v_j.created_at; v_pid := (v_j.args->>'provider_id')::uuid;
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x);
    v_total := coalesce(cardinality(v_ids), 0);
    select count(*) filter (where s.state not in ('queued', 'sent') and s.queued_at >= v_since),
           count(*) filter (where s.state in ('verified', 'found') and s.queued_at >= v_since),
           count(*) filter (where s.state = 'none' and s.queued_at >= v_since)
      into v_done, v_c, v_c2 from pipeline.course_link_search s where s.course_id = any (v_ids);
    v_phase := 'searching course pages';
    v_extra := jsonb_build_object('phase_detail', v_phase, 'found', v_c, 'not_found', v_c2,
      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since));
    if v_done >= v_total then
      v_fin := true;
      v_note := v_c || ' of ' || v_total || ' course page(s) found on the provider''s site; ' || v_c2 || ' not found (enter those by hand in the Adapter builder, step 2.1)';
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$
