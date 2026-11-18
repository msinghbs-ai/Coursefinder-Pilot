-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-4): "on demand run for scholarship never runs, it ask for reason which is not
-- required and nothing happened afterwards". Starting a task no longer needs a reason (Platform Admin decision: every Start);
-- it is logged as "Started from <screen>". Admit the passing fields (writes data in bulk), pause, resume and cancel still need a
-- reason. Scholarships › Coverage rows carry the provider's CRICOS code, so two providers with one name (Victoria University,
-- 00124K and 02475D) can be told apart. Nothing is dropped or deleted. Each replaced function is checked against its live
-- definition first.
do $guard$
declare v_expected jsonb := '{"public.admin_jobs(text,jsonb)": "43e1caadcc5c59ac0fd1a369006aed3b", "public.admin_scholarship_coverage_read(text,text,integer,integer)": "20be9198c28640a041efeaebd0743391"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.admin_jobs(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_id uuid; v_kind text; v_ids uuid[]; v_j pipeline.admin_jobs%rowtype;
        v_q pipeline.admin_jobs%rowtype; v_fields text[]; v_title text; v_n int; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'jobs', coalesce((select jsonb_agg(to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0), 'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)
                         from (select * from pipeline.admin_jobs where state in ('queued', 'running', 'paused') or (p_args->>'all')::boolean order by created_at desc limit greatest(1, least(coalesce((p_args->>'limit')::int, 50), 200))) j), '[]'::jsonb),
      'match', case when p_args ? 'kind' then (select to_jsonb(j) - 'args' || jsonb_build_object('providers', coalesce(jsonb_array_length(j.args->'providers'), 0)) from pipeline.admin_jobs j
                      where j.kind = p_args->>'kind' and j.scope is not distinct from nullif(p_args->>'scope', '') and j.state in ('queued', 'running', 'paused') order by j.created_at desc limit 1) end,
      'job', case when p_args ? 'id' then (select to_jsonb(j) - 'args' || jsonb_build_object('args', j.args - 'providers', 'providers', coalesce(jsonb_array_length(j.args->'providers'), 0),
                    'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by),
                    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'note', e.note, 'detail', e.detail) order by e.id desc) from (select * from pipeline.admin_job_events e where e.job_id = j.id order by e.id desc limit 200) e), '[]'::jsonb),
                    'qualifications', coalesce((select jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(p.id), 'pages_read', q.pages_read, 'fields', q.fields, 'passing', q.passing, 'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = q.provider_id), 'admitted', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.admit)) order by coalesce(p.display_name, p.canonical_name))
                                       from pipeline.adapter_qualifications q join catalogue.providers p on p.id = q.provider_id where (q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid or q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text)), '[]'::jsonb))
                  from pipeline.admin_jobs j where j.id = (p_args->>'id')::uuid) end,
      'settings', jsonb_build_object('min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'countries', coalesce((select jsonb_agg(jsonb_build_object('code', k.iso_alpha2, 'name', k.name, 'adapters', n.n) order by k.name) from ref.countries k join (select p.country_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.country_id) n on n.country_id = k.id), '[]'::jsonb),
      'states', coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'country', k.iso_alpha2, 'adapters', n.n) order by s.code) from ref.subdivisions s join ref.countries k on k.id = s.country_id join (select p.subdivision_id, count(*) n from pipeline.uni_adapters u join catalogue.providers p on p.id = u.provider_id group by p.subdivision_id) n on n.subdivision_id = s.id), '[]'::jsonb),
      'can_admit', v_rank >= 6,
      -- 11 Oct 2026: job kinds from the registry, and (Task manager) everything using resources right now
      'kinds', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object('label', k.label, 'can_pause', k.can_pause)), '{}'::jsonb) from pipeline.admin_job_kinds k),
      'running_now', case when coalesce((p_args->>'running')::boolean, false) then security.admin_running_now_v1() end);
  end if;
  -- v2.15.247 (bugs 11/10-4): starting a task needs no reason; it is logged as started from the screen named in p_args.from.
  -- Admit the passing fields (writes data in bulk), pause, resume and cancel still need one.
  if length(v_reason) < 4 then
    if p_action = 'start' and coalesce(p_args->>'kind', '') <> 'admit_qualified' then
      v_reason := 'Started from ' || coalesce(nullif(btrim(p_args->>'from'), ''), 'the app');
    else
      raise exception 'give a reason (kept in the log)';
    end if;
  end if;
  if p_action = 'start' then
    v_kind := p_args->>'kind';
    if v_kind = 'qualify_adapters' then
      if v_rank < 5 then raise exception 'Operator (adapters) or above required' using errcode = '42501'; end if;
      v_ids := security.admin_jobs_resolve_adapters_v1(coalesce(p_args->'args', '{}'::jsonb));
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapters match that choice'; end if;
      v_title := 'Qualify ' || array_length(v_ids, 1) || ' adapter(s)' || coalesce(' in ' || nullif(btrim(coalesce(p_args->'args'->>'state', p_args->'args'->>'country', '')), ''), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), nullif(p_args->'args'->>'state', ''), nullif(p_args->'args'->>'country', '')))
        returning * into v_j;
    elsif v_kind = 'admit_qualified' and not (coalesce(p_args->'args', '{}'::jsonb) ? 'qualification_job_id') then
      -- 6 Oct (Layer 2 › Adapters): admit the ticked adapters, each from its own latest finished Qualify
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      select coalesce(jsonb_object_agg(z.provider_id, z.job_id), '{}'::jsonb), coalesce(array_agg(z.provider_id order by z.provider_id), '{}') into v_res, v_ids
        from (select distinct on (x.provider_id) x.provider_id, x.job_id, x.passing from pipeline.adapter_qualifications x join pipeline.admin_jobs qj on qj.id = x.job_id and qj.kind = 'qualify_adapters' and qj.state = 'done'
               where x.provider_id = any (array(select (y)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) y))
               order by x.provider_id, x.measured_at desc) z
       where z.passing && v_fields and exists (select 1 from pipeline.uni_adapters u where u.provider_id = z.provider_id and u.enabled);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no ticked adapter passed for those fields in its latest Qualify (or it is switched off)'; end if;
      v_title := 'Admit the passing fields of ' || case when array_length(v_ids, 1) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 adapter') else array_length(v_ids, 1) || ' adapters' end || ' (latest Qualify of each)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qual_jobs', v_res, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), case when array_length(v_ids, 1) = 1 then v_ids[1]::text else 'adapters' end))
        returning * into v_j;
      v_res := null;
    elsif v_kind = 'admit_qualified' then
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
      select * into v_q from pipeline.admin_jobs q where q.id = (p_args->'args'->>'qualification_job_id')::uuid;
      if v_q.id is null or v_q.kind <> 'qualify_adapters' or v_q.state <> 'done' then raise exception 'choose a finished Qualify job'; end if;
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end;
      v_ids := array(select q.provider_id from pipeline.adapter_qualifications q where q.job_id = v_q.id and q.passing && v_fields
                      and exists (select 1 from pipeline.uni_adapters u where u.provider_id = q.provider_id and u.enabled)
                      order by q.provider_id);
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no adapter passed for those fields'; end if;
      v_title := 'Admit the passing fields of ' || array_length(v_ids, 1) || ' adapter(s) (from ' || v_q.title || ')';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qualification_job_id', v_q.id, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason, v_q.id::text)
        returning * into v_j;
    elsif v_kind = 'reread_pages' then
      v_res := public.admin_university_reread('queue', coalesce(p_args->'args', '{}'::jsonb) || jsonb_build_object('reason', v_reason));
      v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) x);
      v_title := 'Read pages again: ' || case when cardinality(v_ids) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 university') else cardinality(v_ids) || ' universities' end
                 || case when coalesce(p_args->'args'->>'which', 'all') = 'not_confirmed' then ' (pages not confirmed)' else '' end || case when coalesce((p_args->'args'->>'central')::boolean, false) then ' with central pages' else '' end;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('request_id', v_res->>'request_id', 'provider_ids', to_jsonb(v_ids), 'which', coalesce(p_args->'args'->>'which', 'all'), 'central', coalesce((p_args->'args'->>'central')::boolean, false)),
                jsonb_build_object('done', 0, 'total', cardinality(v_ids), 'phase', 'sending'), auth.uid(), v_reason, case when cardinality(v_ids) = 1 then v_ids[1]::text else coalesce(nullif(p_args->'args'->>'scope', ''), 'universities') end)
        returning * into v_j;
    elsif v_kind = 'firecrawl_run' then
      v_res := public.admin_firecrawl_write('start', jsonb_build_object('use_case', p_args->'args'->>'use_case', 'reason', v_reason));
      v_title := 'Firecrawl run: ' || replace(coalesce(p_args->'args'->>'use_case', ''), '_', ' ') || ' (' || coalesce(v_res->>'items', '0') || ' pages, cap ' || coalesce(v_res->>'credits_cap', '-') || ' credits)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'firecrawl', v_title, jsonb_build_object('run_id', v_res->>'run_id', 'use_case', p_args->'args'->>'use_case', 'items', (v_res->>'items')::int), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'items')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'use_case')
        returning * into v_j;
      v_ids := '{}';
    elsif v_kind = 'adapter_apply' then
      v_res := public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'reason', v_reason));
      v_title := 'Apply the adapter: ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '') || ' (' || coalesce(v_res->>'pages_read_again', '0') || ' pages)';
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'pages', coalesce((v_res->>'pages_read_again')::int, 0), 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages_read_again')::int, 0)), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    elsif v_kind = 'central_page_read' then
      v_res := public.admin_provider_central_page(coalesce(nullif(p_args->'args'->>'action', ''), 'add'), jsonb_build_object('provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'title', p_args->'args'->>'title', 'reason', v_reason));
      v_title := 'Read a central page: ' || replace(coalesce(p_args->'args'->>'kind', ''), '_', ' ') || ' for ' || coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = (p_args->'args'->>'provider_id')::uuid), '');
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'reads', v_title, jsonb_build_object('source_id', v_res->>'source_id', 'provider_id', p_args->'args'->>'provider_id', 'kind', p_args->'args'->>'kind', 'url', p_args->'args'->>'url', 'providers', jsonb_build_array(p_args->'args'->>'provider_id')), jsonb_build_object('done', 0, 'total', 1), auth.uid(), v_reason, p_args->'args'->>'provider_id')
        returning * into v_j;
      v_ids := array[(p_args->'args'->>'provider_id')::uuid];
    -- 11 Oct 2026 (CF-247, Platform Admin): on-demand scholarship tasks (provider, several providers, course, scholarship)
    elsif v_kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      v_res := security.scholarship_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this check is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'scholarships:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope', jsonb_build_object('done', 0, 'total', coalesce((v_res->>'pages')::int, 0)), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array(select x::uuid from jsonb_array_elements_text(v_res->'providers') x);
      perform security.scholarship_task_fire_v1(case when v_kind = 'scholarship_provider_scan' then array['discover', 'read'] else array['read'] end);
    -- 11 Oct 2026 (CF-247, Platform Admin bugs 11/10-2): Fill in a provider from its website; Find course pages with Firecrawl
    elsif v_kind in ('provider_fill', 'course_page_find') then
      v_res := security.provider_task_prepare_v1(v_kind, coalesce(p_args->'args', '{}'::jsonb));
      if exists (select 1 from pipeline.admin_jobs j where j.kind = v_kind and j.scope is not distinct from (v_res->>'scope') and j.state in ('queued', 'running', 'paused')) then
        raise exception 'this task is already running; see Scheduled jobs › Task manager';
      end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'providers:' || v_kind || ':' || coalesce(v_res->>'scope', ''), v_res->>'title', v_res - 'title' - 'scope',
                jsonb_build_object('done', 0, 'total', case when v_kind = 'provider_fill' then 3 else jsonb_array_length(v_res->'course_ids') end), auth.uid(), v_reason, v_res->>'scope')
        returning * into v_j;
      v_ids := array[(v_res->>'provider_id')::uuid];
      if v_kind = 'provider_fill' then
        perform security.provider_task_fire_v1(case when coalesce((v_res->>'had_website')::boolean, false) then 'contact_page' else 'find_site' end);
      end if;
    else
      raise exception 'unknown job kind';
    end if;
    insert into pipeline.admin_job_events(job_id, note, detail) values (v_j.id, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_start', v_j.id::text, jsonb_build_object('kind', v_kind, 'title', v_j.title, 'providers', array_length(v_ids, 1), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_j.id, 'title', v_j.title, 'providers', array_length(v_ids, 1));
  end if;
  v_id := (p_args->>'id')::uuid;
  select * into v_j from pipeline.admin_jobs j where j.id = v_id;
  if v_j.id is null then raise exception 'unknown job'; end if;
  if v_rank < 5 and v_j.requested_by <> auth.uid() then raise exception 'only the person who started it, or an Operator, may change this job' using errcode = '42501'; end if;
  if p_action = 'cancel' then
    if v_j.state in ('done', 'failed', 'cancelled') then raise exception 'the job has already finished'; end if;
    if v_j.kind = 'reread_pages' then
      update pipeline.university_reread_requests set status = 'cancelled', finished_at = now() where id = (v_j.args->>'request_id')::uuid and status in ('waiting', 'sending');
    elsif v_j.kind = 'firecrawl_run' then
      perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason));
    elsif v_j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
      -- the pages lose their place at the front of the queue; they are read again in their normal turn
      update pipeline.scholarship_pages p set requested_at = null from scholarship.scholarships s
       where s.id = p.scholarship_id and p.requested_at is not null
         and (s.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x))
              or s.id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'scholarship_ids', '[]'::jsonb)) x)));
      update pipeline.scholarship_page_candidates c set requested_at = null
       where c.requested_at is not null and c.provider_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'providers', '[]'::jsonb)) x));
    elsif v_j.kind = 'course_page_find' then
      -- the courses lose their place at the front of the course page search; they are searched in their normal turn
      update pipeline.course_link_search set requested_at = null
       where requested_at is not null and course_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(v_j.args->'course_ids', '[]'::jsonb)) x));
    elsif v_j.kind = 'provider_fill' then
      update pipeline.coverage_provider_discovery set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
      update pipeline.provider_central_search set requested_at = null where provider_id = (v_j.args->>'provider_id')::uuid and requested_at is not null;
    end if;
    if v_j.state in ('queued', 'paused') then
      update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), updated_at = now(), cancel_requested = true where id = v_id;
      perform security.admin_job_close_v1(v_id);
    else
      update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'pause' then
    if v_j.state not in ('queued', 'running') then raise exception 'only a queued or running job can be paused'; end if;
    if not coalesce((select k.can_pause from pipeline.admin_job_kinds k where k.kind = v_j.kind), false) then raise exception 'this task cannot be paused, only cancelled'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('stop', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    if v_j.state = 'queued' then
      update pipeline.admin_jobs set state = 'paused', updated_at = now() where id = v_id;
    else
      update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = v_id;
    end if;
  elsif p_action = 'resume' then
    if v_j.state <> 'paused' then raise exception 'only a paused job can be resumed'; end if;
    if v_j.kind = 'firecrawl_run' then perform public.admin_firecrawl_write('continue', jsonb_build_object('run_id', v_j.args->>'run_id', 'reason', v_reason)); end if;
    update pipeline.admin_jobs set state = 'queued', pause_requested = false, updated_at = now() where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_id, p_action || ' requested by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text), jsonb_build_object('reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('jobs', 'job_' || p_action, v_id::text, jsonb_build_object('title', v_j.title, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_coverage_read(p_scope text DEFAULT 'watch'::text, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_rows jsonb; v_total int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  with ids as (
    select p.id, coalesce(p.display_name, p.canonical_name) n, upper(substring(p.stable_key from '^provider:cricos:(.+)$')) code from catalogue.providers p
     where p.lifecycle_status = 'active'
       and (case when coalesce(p_scope, 'watch') = 'watch' then exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active)
                 else exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')
                   or exists (select 1 from pipeline.scholarship_listing_pages l where l.provider_id = p.id and l.active)
                   or exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active) end)
       and (v_q is null or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
  select (select count(*) from ids), coalesce(jsonb_agg(security.scholarship_coverage_row_v1(x.id) || jsonb_build_object('code', x.code) order by x.n, x.code), '[]'::jsonb)
    into v_total, v_rows from (select * from ids order by n limit greatest(1, least(coalesce(p_limit, 100), 300)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('scope', coalesce(p_scope, 'watch'), 'total', v_total, 'rows', v_rows, 'can_manage', v_rank >= 6, 'can_watch', v_rank >= 5,
    'auto_publish', jsonb_build_object('on', security.scholarship_setting('auto_publish', 0) >= 1,
      'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name), 'at', b.created_at,
                    'status', s.publication_status, 'value', s.award_value_text, 'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'))
                    order by b.created_at desc, s.name), '[]'::jsonb)
                   from pipeline.scholarship_publication_batches b cross join lateral unnest(b.scholarship_ids) sid
                   join scholarship.scholarships s on s.id = sid join catalogue.providers p on p.id = s.provider_id
                  where b.kind = 'publish' and b.approval_ref like 'auto-publish%' and b.created_at > now() - interval '3 days')),
    'totals', jsonb_build_object(
      'watch', (select count(*) from pipeline.scholarship_watch w where w.active),
      'with_listing', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.active and l.source <> 'suggested'),
      'suggested', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.source = 'suggested' and not exists (select 1 from pipeline.scholarship_listing_pages a where a.provider_id = l.provider_id and a.active and a.source <> 'suggested')),
      'checked', (select count(*) from pipeline.scholarship_coverage_checks),
      'active', (select count(*) from scholarship.scholarships where lifecycle_status = 'active'),
      'published', (select count(*) from scholarship.scholarships where lifecycle_status = 'active' and publication_status = 'published')));
end $function$;

do $post$
declare v_expected jsonb := '{"public.admin_jobs(text,jsonb)": "e5aa7642d610954253f18ceeaf0390de", "public.admin_scholarship_coverage_read(text,text,integer,integer)": "1c27d8194e2da7c6e8e9ced614caed6e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception '20261011010100 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
