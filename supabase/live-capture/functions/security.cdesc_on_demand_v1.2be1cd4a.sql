CREATE OR REPLACE FUNCTION security.cdesc_on_demand_v1(p_action text, p_args jsonb, p_rank integer, p_uid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a jsonb := coalesce(p_args, '{}'::jsonb);
  v_mode text := lower(btrim(coalesce(a->>'mode', '')));
  v_ids uuid[] := array(select distinct x::uuid from jsonb_array_elements_text(case when jsonb_typeof(a->'course_ids') = 'array' then a->'course_ids' else '[]'::jsonb end) x);
  v_pids uuid[] := array(select distinct x::uuid from jsonb_array_elements_text(case when jsonb_typeof(a->'provider_ids') = 'array' then a->'provider_ids' else '[]'::jsonb end) x);
  v_max int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
  v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int;
  v_vmax constant int := 10; -- fixed: the read-back calls public.website_v2_course for each course (about 255 ms each), so ten stay inside the 8 second request limit
  v_used int; v_room int; v_scope text; v_limit int; v_reason text; v_key text; v_given boolean; v_job uuid; v_n int; v_total int; v_elig int;
  v_blocks jsonb; v_sel uuid[]; v_providers uuid[]; v_flags bigint[]; f bigint; v_title text; v_usd numeric; v_rows jsonb; v_missing uuid[]; v_ex pipeline.admin_jobs%rowtype; v_ptitle text; v_zoho jsonb;
  r record; v_web jsonb; v_wst text; v_zst text; v_wnote text; v_znote text;
begin
  if p_action = 'verify' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    if cardinality(v_ids) = 0 then raise exception 'choose the courses to check'; end if;
    if cardinality(v_ids) > v_vmax then raise exception 'check at most % courses at a time', v_vmax; end if;
    v_zoho := coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb); -- fixed: the Zoho feed's own default country (security.zoho_sync_item_v1)
    v_rows := '[]'::jsonb;
    for r in select co.id, nullif(btrim(co.description), '') descr, k.iso_alpha2::text cc, d.course_stable_key sk
               from catalogue.courses co join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
               left join lateral (select d0.course_stable_key from search.course_documents d0 where d0.course_id = co.id limit 1) d on true
              where co.id = any (v_ids) order by co.id loop
      v_wst := null; v_zst := null; v_wnote := null; v_znote := null;
      if r.descr is null then
        v_wst := 'not_applicable'; v_wnote := 'The catalogue holds no description, so there is nothing to carry.';
        v_zst := 'not_applicable'; v_znote := v_wnote;
      else
        if r.sk is null then v_wst := 'pending'; v_wnote := 'The course is not in the published search set yet.';
        else
          begin
            v_web := public.website_v2_course(r.sk);
            v_wst := case when v_web->'item'->>'description' is null then 'missing' when v_web->'item'->>'description' = r.descr then 'matched' else 'differs' end;
            v_wnote := case v_wst when 'matched' then 'The Website API returns the same words as the catalogue.' when 'missing' then 'The Website API returns no description for this course.' else 'The Website API returns different words from the catalogue.' end;
          exception when others then
            v_wst := 'unknown'; v_wnote := 'The read-back failed: ' || left(sqlerrm, 160); -- fixed: the length of an error shown to a person
          end;
        end if;
        if not (v_zoho ? r.cc) then v_zst := 'not_applicable'; v_znote := 'The country is not synced to Zoho (zoho.sync_countries).';
        elsif r.sk is null then v_zst := 'pending'; v_znote := 'The course is not in the published search set yet.';
        else
          select case when z.item_key is null then 'pending' when z.item ? 'description' then (case when z.item->>'description' = r.descr then 'matched' else 'differs' end) else 'not_carried' end
            into v_zst from (select 1) one left join pipeline.zoho_sync_items z on z.entity = 'course' and z.item_key = r.sk and z.removed_at is null;
          v_znote := case v_zst when 'pending' then 'The course is not in the Zoho course feed yet.' when 'matched' then 'The Zoho course item holds the same words.'
                                when 'differs' then 'The Zoho course item holds different words.' else 'The Zoho course item has no description field, so Zoho does not receive it from this feed.' end;
        end if;
      end if;
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('course_id', r.id, 'stable_key', r.sk, 'country', r.cc,
        'catalogue', jsonb_build_object('state', case when r.descr is null then 'missing' else 'present' end, 'chars', length(r.descr)),
        'website', jsonb_build_object('state', v_wst, 'note', v_wnote), 'zoho', jsonb_build_object('state', v_zst, 'note', v_znote),
        'http', jsonb_build_object('state', 'not_checked', 'note', 'The database cannot call the website. The release check reads the Website API over HTTP; until it has, this is not checked, neither passed nor failed.')));
    end loop;
    return jsonb_build_object('verified_at', now(), 'courses', v_rows, 'missing', to_jsonb(array(select x from unnest(v_ids) x where x not in (select (e->>'course_id')::uuid from jsonb_array_elements(v_rows) e))),
      'summary', jsonb_build_object(
        'website', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select e->'website'->>'state' s, count(*) n from jsonb_array_elements(v_rows) e group by 1) z),
        'zoho', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select e->'zoho'->>'state' s, count(*) n from jsonb_array_elements(v_rows) e group by 1) z)));
  end if;

  if p_action = 'description_tasks' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    -- the saved record of the on-demand tasks (newest first; one screen's list), so the person finds the task and its outcome after closing the browser; optionally only the tasks that held one course
    return jsonb_build_object('tasks', coalesce((select jsonb_agg(t.x order by t.created_at desc) from (
      select j.created_at, jsonb_build_object('id', j.id, 'title', j.title, 'state', j.state, 'progress', j.progress, 'reason', j.reason, 'created_at', j.created_at, 'finished_at', j.finished_at,
               'mode', j.args->>'mode', 'scope', j.args->>'scope', 'requested_by', j.requested_by,
               'by_state', (select coalesce(jsonb_object_agg(z.s, z.n), '{}'::jsonb) from (select e.state s, count(*) n from pipeline.field_enrich_items e where e.job_id = j.id group by 1) z),
               'described_now', (select count(*) from pipeline.field_enrich_items e join catalogue.courses c on c.id = e.course_id where e.job_id = j.id and nullif(btrim(c.description), '') is not null)) x
        from pipeline.admin_jobs j
       where j.kind = 'enrich_fields' and j.args->>'on_demand' = 'true'
         and (cardinality(v_ids) = 0 or exists (select 1 from pipeline.field_enrich_items e where e.job_id = j.id and e.course_id = any (v_ids)))
       order by j.created_at desc limit 10) t), '[]'::jsonb)); -- fixed: one screen's list of tasks
  end if;

  -- preview and start
  if p_action not in ('preview', 'start') then raise exception 'unknown action %', p_action using errcode = '22023'; end if;
  if v_mode not in ('fill', 'recheck') then raise exception 'choose Fill description or Recheck description'; end if;
  if cardinality(v_ids) > 0 and cardinality(v_pids) > 0 then raise exception 'choose courses or one university, not both'; end if;
  if cardinality(v_ids) > 0 then
    v_scope := 'courses';
    if cardinality(v_ids) > v_max then raise exception 'choose at most % courses at a time (Pipeline settings > Run now: most courses in a cohort)', v_max; end if;
  elsif cardinality(v_pids) = 1 then
    v_scope := 'university';
  else
    raise exception 'choose up to % courses, or one university', v_max;
  end if;

  if p_action = 'start' then
    if coalesce(p_rank, 0) < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(a->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the task)'; end if;
    v_given := nullif(btrim(coalesce(a->>'idempotency_key', '')), '') is not null;
    v_key := left(coalesce(nullif(btrim(coalesce(a->>'idempotency_key', '')), ''),
                'cdesc:' || v_mode || ':' || md5(coalesce((select string_agg(x::text, ',' order by x) from unnest(case when v_scope = 'courses' then v_ids else v_pids end) x), ''))), 120); -- fixed: a key's length
    -- Locks come BEFORE the selection, so what is chosen is what is true when the items are written. A request for one university takes that university's lock exclusively; a request for chosen
    -- courses takes each course's lock exclusively and each of their universities' locks shared (so two course requests in one university run side by side, but a university request waits for
    -- them and they wait for it). Always taken providers first, then courses, in sorted order, so two requests can never wait on each other. The standing queue takes no lock: see the header.
    perform pg_advisory_xact_lock(hashtextextended('cdesc_on_demand:' || v_key, 0));
    if v_scope = 'university' then
      perform pg_advisory_xact_lock(hashtextextended('cdesc_provider:' || v_pids[1]::text, 0));
    else
      for r in select distinct co.provider_id pid from catalogue.courses co where co.id = any (v_ids) order by 1 loop
        perform pg_advisory_xact_lock_shared(hashtextextended('cdesc_provider:' || r.pid::text, 0));
      end loop;
      for r in select x from unnest(v_ids) x order by 1 loop
        perform pg_advisory_xact_lock(hashtextextended('cdesc_course:' || r.x::text, 0));
      end loop;
    end if;
    select * into v_ex from pipeline.admin_jobs j where j.kind = 'enrich_fields' and j.args->>'idempotency_key' = v_key and (v_given or j.state in ('queued', 'running')) order by j.created_at desc limit 1;
    if v_ex.id is not null then
      if v_ex.args->>'mode' is distinct from v_mode or v_ex.args->>'scope' is distinct from v_scope then
        raise exception 'this idempotency key was already used for a different request (% / %); use a new key', v_ex.args->>'mode', v_ex.args->>'scope';
      end if;
      return jsonb_build_object('job_id', v_ex.id, 'items', (select count(*) from pipeline.field_enrich_items e where e.job_id = v_ex.id), 'repeat', true, 'mode', v_mode, 'scope', v_scope, 'idempotency_key', v_key);
    end if;
  end if;

  -- the day's room under the standing queue's own ceiling (items already made today for the description, by any route)
  select v_cap - count(*) into v_used from pipeline.field_enrich_items e where e.field = 'description' and e.created_at > now() - interval '1 day'; -- fixed: the cap is a day's
  v_room := greatest(v_used, 0); -- v_used is what is left of the day's ceiling
  v_limit := case when v_scope = 'courses' then least(v_max, v_room) else v_room end; -- an on-demand request never takes more readings than the day's ceiling leaves

  create temporary table if not exists pg_temp.cdesc_sel (course_id uuid, provider_id uuid, block text, ord int, flags bigint[], payload jsonb) on commit drop;
  truncate pg_temp.cdesc_sel;
  insert into pg_temp.cdesc_sel(course_id, provider_id, block, ord, flags, payload)
  select s.course_id, s.provider_id, case v_mode when 'fill' then s.fill_block else s.recheck_block end,
         row_number() over (order by (s.last_item_id is not null), s.last_attempt_at nulls first, s.course_id),
         s.release_flag_ids,
         to_jsonb(s) || jsonb_build_object('fill_info', security.cdesc_block_info_v1(s.fill_block), 'recheck_info', security.cdesc_block_info_v1(s.recheck_block))
    from security.cdesc_state_v1(case when v_scope = 'courses' then v_ids end, case when v_scope = 'university' then v_pids[1] end) s;

  v_total := (select count(*) from pg_temp.cdesc_sel);
  -- back-pressure as the standing queue has it (enrich.course_description_pending_global_max, 0 = off): no new readings while that many descriptions already wait for a person in Layer 4
  if coalesce(security.pipeline_num_v1('enrich.course_description_pending_global_max', 0), 0) > 0
     and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending')
         >= security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) then
    update pg_temp.cdesc_sel set block = 'review_backlog' where block is null;
  end if;
  v_elig := (select count(*) from pg_temp.cdesc_sel where block is null);
  v_missing := array(select x from unnest(v_ids) x where x not in (select course_id from pg_temp.cdesc_sel));
  -- a request queues the first v_limit eligible courses (never-tried first, then the oldest attempt); the rest wait for the next request
  update pg_temp.cdesc_sel set block = 'daily_capacity' where block is null and ord > 0
     and (select count(*) from pg_temp.cdesc_sel x where x.block is null and x.ord <= pg_temp.cdesc_sel.ord) > v_limit;
  v_blocks := (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select block k, count(*) n from pg_temp.cdesc_sel where block is not null group by 1) z);
  v_n := (select count(*) from pg_temp.cdesc_sel where block is null);
  v_usd := nullif((security.enrich_unit_costs_v1()->>'enrich_usd_per_item')::numeric, 0);

  if p_action = 'preview' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    return jsonb_build_object('mode', v_mode, 'scope', v_scope, 'selected', case when v_scope = 'courses' then cardinality(v_ids) end, 'missing', to_jsonb(v_missing),
      'total', v_total, 'eligible', v_elig, 'to_queue', v_n, 'left_for_later', v_elig - v_n, 'blocked', v_blocks,
      'blocked_info', (select coalesce(jsonb_object_agg(k, security.cdesc_block_info_v1(k)), '{}'::jsonb) from jsonb_object_keys(v_blocks) k),
      'limit', jsonb_build_object('courses_per_request', v_max, 'room_today', v_room, 'items_per_day', v_cap),
      'estimate', jsonb_build_object('items', v_n, 'usd_per_item', v_usd, 'usd', case when v_usd is null then null else round(v_n * v_usd, 4) end, 'scraper_credits', 0),
      'courses', case when v_scope = 'courses' then (select coalesce(jsonb_agg(z.payload || jsonb_build_object('block', z.block, 'block_info', security.cdesc_block_info_v1(z.block), 'will_queue', z.block is null) order by z.ord), '[]'::jsonb) from pg_temp.cdesc_sel z)
                     else (select coalesce(jsonb_agg(z.payload || jsonb_build_object('block', z.block, 'block_info', security.cdesc_block_info_v1(z.block), 'will_queue', z.block is null) order by z.ord), '[]'::jsonb)
                             from (select * from pg_temp.cdesc_sel order by (block is not null), ord limit v_max) z) end);
  end if;

  -- start (rank, reason, key, locks and the repeat check were done before the selection)
  if v_n = 0 then
    raise exception 'nothing to queue: %', coalesce((select string_agg(coalesce(security.cdesc_block_info_v1(k)->>'label', k) || ' (' || n || ')', '; ' order by n desc) from (select block k, count(*) n from pg_temp.cdesc_sel where block is not null group by 1) z), 'no course found');
  end if;
  v_sel := array(select course_id from pg_temp.cdesc_sel where block is null order by ord);
  v_providers := array(select distinct provider_id from pg_temp.cdesc_sel where block is null);
  v_ptitle := case when v_scope = 'university' then (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = v_pids[1]) end;
  v_title := left((case v_mode when 'fill' then 'Fill description' else 'Recheck description' end) || ' · ' || case when v_scope = 'university' then coalesce(v_ptitle, 'university') || ' · ' || v_n || ' course(s)'
                                                                                                                     else v_n || ' course(s)' end, 200); -- fixed: the title column's length (as Enrich fields)
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', v_title,
          jsonb_build_object('countries', '[]'::jsonb, 'provider_ids', to_jsonb(v_providers), 'fields', jsonb_build_array('description'), 'ai', true, 'scraper', false,
                             'on_demand', true, 'mode', v_mode, 'scope', v_scope, 'course_ids', case when v_scope = 'courses' then to_jsonb(v_sel) else '[]'::jsonb end,
                             'idempotency_key', v_key, 'requested_courses', case when v_scope = 'courses' then cardinality(v_ids) else v_total end),
          jsonb_build_object('done', 0, 'total', 0), p_uid, v_reason, case when v_scope = 'university' then coalesce(v_ptitle, '1 university') else v_n || ' courses' end)
  returning id into v_job;
  -- recheck: the counting flag (the standing queue's wait) of each chosen course's description is released as a person's release, in the flag history, so the engine's own gate lets the item in
  if v_mode = 'recheck' then
    for f in select unnest(flags) from pg_temp.cdesc_sel where block is null and flags is not null loop
      perform security.flag_release_v1(f, p_uid::text, 'person', 'Recheck description requested: ' || v_reason, jsonb_build_object('job_id', v_job), false);
    end loop;
  end if;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
  select v_job, s.provider_id, s.course_id, 'description' from pg_temp.cdesc_sel s where s.block is null order by s.ord on conflict do nothing;
  select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
  if v_n = 0 then raise exception 'nothing was queued (the engine''s own gate holds every chosen course); nothing was changed'; end if;
  update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, v_n || ' item(s) to settle', jsonb_build_object('mode', v_mode, 'scope', v_scope, 'reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('enrich_fields', 'on_demand_' || v_mode, v_job::text, jsonb_build_object('job_id', v_job, 'items', v_n, 'scope', v_scope, 'reason', v_reason, 'blocked', v_blocks, 'idempotency_key', v_key), p_uid);
  return jsonb_build_object('job_id', v_job, 'items', v_n, 'repeat', false, 'mode', v_mode, 'scope', v_scope, 'blocked', v_blocks, 'left_for_later', v_elig - v_n, 'idempotency_key', v_key);
end $function$
