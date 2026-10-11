-- CF-247 (11 Oct 2026): fixes found in the live check of the on-demand scholarship tasks (migration 20261011009000).
--  B1: Read again now and Check scholarships for this course refuse, with a plain reason, when nothing in scope can be read
--      (an inactive scholarship, or a provider with no active scholarship pages), instead of starting an empty task.
--  B2: the task note says the credits figure is all scholarship scraper use for the provider while the task ran.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.scholarship_task_prepare_v1(text,jsonb)": "814855b565bee893d71854243ec39b6d", "security.admin_job_watch_v1(uuid)": "f166a3fba3b7cdaf9b4a00eb75e3cdc6"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.scholarship_task_prepare_v1(p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_prov uuid[]; v_sch uuid[]; v_course uuid; v_before uuid[] := '{}'; v_pages int := 0; v_cands int := 0; v_title text; v_scope text; v_missing text;
begin
  if p_kind = 'scholarship_provider_scan' then
    v_prov := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_prov), 0) = 0 then raise exception 'choose at least one provider'; end if;
    if cardinality(v_prov) > 50 then raise exception 'at most 50 providers in one task'; end if;
    select string_agg(coalesce(p.display_name, p.canonical_name), ', ') into v_missing from catalogue.providers p
     where p.id = any (v_prov) and coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) is null;
    if v_missing is not null then raise exception 'no website is known for %; add it on the provider first', v_missing; end if;
  elsif p_kind = 'scholarship_course_check' then
    v_course := (p_args->>'course_id')::uuid;
    select array[c.provider_id] into v_prov from catalogue.courses c where c.id = v_course;
    if v_prov is null then raise exception 'unknown course'; end if;
    v_before := array(select m.scholarship_id from scholarship.course_mappings m where m.course_id = v_course and m.mapping_state = 'mapped');
  elsif p_kind = 'scholarship_reread' then
    v_sch := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'scholarship_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_sch), 0) = 0 then raise exception 'choose a scholarship'; end if;
    v_prov := array(select distinct s.provider_id from scholarship.scholarships s where s.id = any (v_sch));
    if not exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = any (v_sch)) then raise exception 'this scholarship has no provider page to read'; end if;
  else
    raise exception 'unknown scholarship task';
  end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = any (v_prov)) then
    raise exception 'a chosen provider is unpublished or archived; publish or restore it first';
  end if;
  if p_kind = 'scholarship_provider_scan' then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status, attempts, updated_at)
    select p.id, coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')), 0, 'on_demand', 'pending', 0, now()
      from catalogue.providers p where p.id = any (v_prov)
    on conflict (provider_id) do update set status = 'pending', priority = 0, attempts = 0, leased_until = null, reason = 'on_demand', updated_at = now();
    update pipeline.scholarship_page_candidates c set next_read_at = now(), attempts = 0, leased_until = null, requested_at = now()
     where c.provider_id = any (v_prov) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register'
       and (c.read_status is null or c.read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed', 'scrape_failed', 'waiting_scraper', 'deferred'));
    get diagnostics v_cands = row_count;
  end if;
  update pipeline.scholarship_pages p set requested_at = now(), next_read_at = now(), attempts = 0, leased_until = null
    from scholarship.scholarships s
   where s.id = p.scholarship_id and s.lifecycle_status = 'active'
     and (case when v_sch is not null then s.id = any (v_sch) else s.provider_id = any (v_prov) end);
  get diagnostics v_pages = row_count;
  if v_pages = 0 and p_kind = 'scholarship_reread' then raise exception 'this scholarship is not active, so there is no page to read; restore it first'; end if;
  if v_pages = 0 and p_kind = 'scholarship_course_check' then raise exception 'this course''s provider has no active scholarship pages yet; use Find scholarships now on the provider'; end if;
  if v_sch is null then update pipeline.scholarship_listing_pages set next_read_at = now() where active and provider_id = any (v_prov); end if;
  v_title := case p_kind
    when 'scholarship_provider_scan' then 'Find scholarships now: ' || case when cardinality(v_prov) = 1 then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_prov[1]) else cardinality(v_prov) || ' providers' end
    when 'scholarship_course_check' then 'Check scholarships for ' || (select coalesce(c.display_title, c.canonical_title) || coalesce(' (' || c.course_code || ')', '') from catalogue.courses c where c.id = v_course)
    else 'Read again now: ' || case when cardinality(v_sch) = 1 then (select s.name from scholarship.scholarships s where s.id = v_sch[1]) else cardinality(v_sch) || ' scholarships' end end;
  v_scope := case p_kind
    when 'scholarship_provider_scan' then case when cardinality(v_prov) = 1 then v_prov[1]::text else 'providers:' || md5(array_to_string(array(select x::text from unnest(v_prov) x order by 1), ',')) end
    when 'scholarship_course_check' then v_course::text
    else case when cardinality(v_sch) = 1 then v_sch[1]::text else 'scholarships:' || md5(array_to_string(array(select x::text from unnest(v_sch) x order by 1), ',')) end end;
  return jsonb_build_object('providers', to_jsonb(v_prov), 'scholarship_ids', to_jsonb(coalesce(v_sch, '{}'::uuid[])), 'course_id', v_course, 'before', to_jsonb(v_before),
                            'pages', v_pages, 'candidates', v_cands, 'title', v_title, 'scope', v_scope);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_job_watch_v1(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_j pipeline.admin_jobs%rowtype; v_done int := 0; v_total int := 0; v_fin boolean := false; v_note text := null; v_phase text := null;
        v_n_map int := 0; v_n_cand int := 0; v_extra jsonb; v_sch uuid[]; v_before uuid[]; v_since timestamptz;
        v_last_done int; v_last_at timestamptz; v_stall interval; v_ids uuid[]; r record;
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
      v_note := v_done || ' scholarship page(s) read through the scraper' || coalesce(', ' || nullif((v_extra->>'new_scholarships')::int, 0) || ' new scholarship(s) found', '')
             || ', course links changed on ' || (v_extra->>'links_changed') || ', ' || (v_extra->>'credits') || ' scholarship scraper credit(s) used for ' || case when cardinality(v_ids) = 1 then 'this provider' else 'these providers' end || ' while the task ran'
             || case when v_j.kind = 'scholarship_course_check' then '; this course now has ' || (v_extra->>'linked_now') || ' scholarship(s) (' || jsonb_array_length(v_extra->'added') || ' added, ' || jsonb_array_length(v_extra->'removed') || ' removed)' else '' end;
    else
      perform security.scholarship_task_fire_v1(case when v_n_map > 0 then array['discover'] when v_n_cand > 0 then array['candidates'] else array['read'] end);
    end if;
  end if;
  if v_done <> v_last_done then v_last_done := v_done; v_last_at := now(); end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then
    v_fin := true; v_note := coalesce(v_note, v_done || ' of ' || v_total || ' done, nothing more for ' || extract(epoch from v_stall)::int / 60 || ' minutes: the rest wait their turn in the reader');
  end if;
  update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', v_last_done, 'last_change_at', v_last_at), progress = jsonb_build_object('done', v_done, 'total', v_total) || coalesce(jsonb_build_object('phase', v_phase), '{}'::jsonb), result = jsonb_build_object('done', v_done, 'total', v_total, 'errors', case when v_note like 'the request failed%' then 1 else 0 end) || coalesce(jsonb_build_object('note', v_note), '{}'::jsonb) || coalesce(v_extra, '{}'::jsonb), updated_at = now() where id = p_id;
  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;
end $function$;

do $post$
declare v_expected jsonb := '{"security.scholarship_task_prepare_v1(text,jsonb)": "747d4df851a35ef6c80184036ee6fee0", "security.admin_job_watch_v1(uuid)": "10dd1edb4da67f91480afa4d0adaccde"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
