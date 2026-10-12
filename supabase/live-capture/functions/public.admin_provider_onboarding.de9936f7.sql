CREATE OR REPLACE FUNCTION public.admin_provider_onboarding(p_action text DEFAULT 'read'::text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ids uuid[]; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  -- v2.15.255: one university's journey: steps, tasks, AI drafts, and the scholarships found with their state
  if p_action = 'journey' then
    return (select jsonb_build_object('id', o.id, 'status', o.status, 'stop_reason', o.stop_reason, 'started_at', o.started_at, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
      'qualify', o.result->'qualify', 'held', o.result->'held', 'ready', o.result->'ready', 'central_pages', o.result->'central_pages', 'scholarship_search', o.result->'scholarships',
      'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'status', e.status, 'stop_reason', e.stop_reason, 'note', e.note) order by e.at), '[]'::jsonb)
                   from pipeline.provider_onboarding_events e where e.onboarding_id = o.id),
      'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'title', j.title, 'state', j.state, 'created_at', j.created_at, 'finished_at', j.finished_at,
                   'note', left(coalesce(j.result->>'note', j.error, ''), 300)) order by j.created_at), '[]'::jsonb)
                  from pipeline.admin_jobs j where j.scope = o.provider_id::text and j.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'status', d.status, 'created_at', d.created_at, 'updated_at', d.updated_at, 'samples', jsonb_array_length(coalesce(d.samples, '[]'::jsonb)),
                   'proposals', jsonb_array_length(coalesce(d.proposals, '[]'::jsonb)), 'model', d.model, 'cost_usd', d.cost_usd, 'reason', d.reason) order by d.created_at), '[]'::jsonb)
                  from pipeline.uni_adapter_drafts d where d.provider_id = o.provider_id and d.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'scholarships', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
                   'created_at', s.created_at, 'url', s.source_url) order by s.created_at desc), '[]'::jsonb)
                  from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'ai_waiting', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
      'ai_read', (select coalesce(jsonb_object_agg(t.v, t.n), '{}'::jsonb) from (select coalesce(x.verdict, 'failed') v, count(*) n from pipeline.scholarship_ai_extractions x
                   where x.provider_id = o.provider_id and x.at >= coalesce(o.started_at, o.created_at) group by 1) t))
      from pipeline.provider_onboarding o where o.id = nullif(p_args->>'id', '')::uuid);
  end if;
  if p_action <> 'read' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'start' then
      v_ids := case when p_args->>'scope' = 'no_adapter' then array(
                 select pr.id from catalogue.providers pr
                  where pr.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
                    and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                    and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false)))
               else array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x) end;
      if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose universities'; end if;
      insert into pipeline.provider_onboarding(provider_id, source, requested_by, reason, priority)
      select i, case when p_args->>'scope' = 'no_adapter' then 'backfill' else 'manual' end, auth.uid(), v_reason,
             case when p_args->>'scope' = 'no_adapter' then (select least(count(*), 99999)::int from catalogue.courses c where c.provider_id = i and c.lifecycle_status = 'active') else 200000 end
        from unnest(v_ids) i
      on conflict do nothing;
      get diagnostics v_n = row_count;
    elsif p_action = 'stop' then
      update pipeline.provider_onboarding set status = 'cancelled', note = 'Stopped by a person: ' || v_reason, finished_at = now(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status not in ('done', 'cancelled');
      get diagnostics v_n = row_count;
    elsif p_action = 'retry' then
      update pipeline.provider_onboarding set status = case when stop_reason in ('capture_failed', 'proposal_failed') then 'course_pages' else 'website' end,
             stop_reason = null, attempts = 0, job_id = null, step_started_at = now(), note = 'Retried by a person: ' || v_reason, requested_by = auth.uid(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status = 'stopped';
      get diagnostics v_n = row_count;
    elsif p_action = 'settings' then
      update pipeline.provider_onboarding_settings set enabled = coalesce((p_args->>'enabled')::boolean, enabled), auto_start_new = coalesce((p_args->>'auto_start_new')::boolean, auto_start_new),
             max_active = coalesce((p_args->>'max_active')::int, max_active), run_as = case when (p_args->>'run_as_me')::boolean then auth.uid() else run_as end,
             changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
      v_n := 1;
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('onboarding', p_action, coalesce(p_args->>'scope', ''), p_args || jsonb_build_object('count', v_n), auth.uid());
  end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6,
    'settings', (select to_jsonb(s) - 'id' from pipeline.provider_onboarding_settings s where s.id = 1),
    'counts', (select coalesce(jsonb_object_agg(t.status, t.n), '{}'::jsonb) from (select status, count(*) n from pipeline.provider_onboarding group by 1) t),
    'stops', (select coalesce(jsonb_object_agg(t.r, t.n), '{}'::jsonb) from (select stop_reason r, count(*) n from pipeline.provider_onboarding where status = 'stopped' group by 1) t),
    'without_adapter', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                          and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                          and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))),
    'approvals_waiting', (select count(*) from pipeline.provider_fact_sources fs where fs.decision is null and fs.status = 'parsed' and fs.kind = 'fee_schedule')
                         + (select count(*) from pipeline.provider_policy_proposals pp where pp.status = 'proposed'),
    'rows', (select coalesce(jsonb_agg(x order by x->>'sort'), '[]'::jsonb) from (
       select jsonb_build_object('sort', lpad((case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end)::text, 2, '0') || to_char(o.updated_at, 'YYYYMMDDHH24MISS'),
              'id', o.id, 'provider_id', o.provider_id, 'name', coalesce(nullif(pr.display_name, ''), pr.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = pr.country_id),
              'website', pr.website, 'status', o.status, 'stop_reason', o.stop_reason, 'note', o.note, 'source', o.source, 'job_id', o.job_id,
              'ready', o.result->'ready', 'held', o.result->'held', 'central_pages', o.result->'central_pages', 'scholarships', o.result->'scholarships'->'new_scholarships', 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
              'scholarships_live', jsonb_build_object('found', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
                 'published', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute' and s.publication_status = 'published'),
                 'waiting_ai', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
                 'searched', o.result ? 'scholarships'),
              'courses', (select count(*) from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'),
              'pages_read', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read'),
              'started_at', o.started_at, 'step_started_at', o.step_started_at, 'updated_at', o.updated_at, 'finished_at', o.finished_at, 'created_at', o.created_at) x
         from pipeline.provider_onboarding o join catalogue.providers pr on pr.id = o.provider_id
        where (p_args->>'status' is null or o.status = p_args->>'status' or (p_args->>'status' = 'active' and o.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships')))
          and (p_args->>'q' is null or coalesce(pr.display_name, pr.canonical_name) ilike '%' || (p_args->>'q') || '%')
        order by case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end, o.updated_at desc
        limit least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500)) t));
end $function$
