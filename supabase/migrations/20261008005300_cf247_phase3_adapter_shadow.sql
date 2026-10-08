-- CF-247 Phase 3 of "Layers 1 to 4 on the Adapter Model": the merged reading step, run side by side with Layer 3.
-- Platform Admin decisions 9 Oct 2026 (multiple choice): shadow size "US$15/day, ~1,000 courses/day"; retire rule
-- "Match 95%+ and find as much".
--
-- The merged step reads a field the adapter's patterns did not read with the adapter's own model (the model chosen for
-- the adapter, else the builder default), on the adapter's section for that field (its JSON path or heading section),
-- under the same task contract as Layer 3 (prompt, schema and checks). In shadow mode it reads courses Layer 3 has
-- already finished, records its answer beside Layer 3's for the same course, field and stored page, and admits nothing.
--
-- A field (intakes, English) becomes eligible to retire from Layer 3 when, over at least min_compared compared courses:
--   agreement >= retire_match where both found a value, and the merged step finds a value at least as often as Layer 3.
-- Eligibility is reported only; retiring a field is a separate Platform Admin step (Phase 4), never automatic.
--
-- Limits: at most daily_usd_max US$ and daily_reads_max reads a day (split evenly between the two fields). Tuition stays
-- on Layer 3 for now (it runs through a different worker; it joins the shadow run in a later step).

create table if not exists pipeline.adapter_shadow_settings (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default true,
  daily_usd_max numeric not null default 15 check (daily_usd_max between 0 and 50),
  daily_reads_max int not null default 1000 check (daily_reads_max between 0 and 5000),
  retire_match numeric not null default 0.95 check (retire_match between 0.5 and 1),
  min_compared int not null default 300 check (min_compared >= 50),
  reason text not null default 'Platform Admin 9 Oct 2026: US$15/day, ~1,000 courses/day; retire at 95%+ agreement and at least as many found',
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into pipeline.adapter_shadow_settings(id) values (1) on conflict (id) do nothing;
alter table pipeline.adapter_shadow_settings enable row level security;

create table if not exists pipeline.adapter_shadow_reads (
  id uuid primary key default gen_random_uuid(),
  task text not null check (task in ('intake','english')),
  work_item_id uuid not null unique references pipeline.layer3_work_items(id),
  course_id uuid not null,
  provider_id uuid not null,
  evidence_id uuid not null,
  profile_code text not null,
  model text not null,
  status text not null default 'claimed' check (status in ('claimed','done','error')),
  input_basis text,                -- 'adapter_json' | 'adapter_section' | 'page' (the adapter names nothing for this field)
  input_chars int,
  shadow_status text,              -- the contract's status: months | not_stated | stated | ...
  shadow_valid boolean,
  shadow_value jsonb,              -- the checked value: {"months":[...]} or {"tests":[...]}, null when none
  shadow_found boolean,
  layer3_status text,              -- the Layer 3 work item status when the shadow read was claimed
  layer3_value jsonb,
  layer3_found boolean,
  layer3_cost_usd numeric,
  agree boolean,                   -- only when both found a value
  cost_usd numeric not null default 0,
  input_tokens int,
  output_tokens int,
  latency_ms int,
  errors jsonb,
  worker_version text,
  claimed_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists adapter_shadow_reads_day on pipeline.adapter_shadow_reads(claimed_at);
create index if not exists adapter_shadow_reads_provider on pipeline.adapter_shadow_reads(provider_id, task);
alter table pipeline.adapter_shadow_reads enable row level security;

-- the same comparison the Layer 3 cascade uses (cf247-cascade.ts sameAnswer): intake months as a set; English tests and
-- overall scores as a set (6.5 and 6.50 are the same score)
create or replace function security.adapter_shadow_same_v1(p_task text, a jsonb, b jsonb)
returns boolean language sql immutable set search_path to '' as $$
  select case
    when a is null or b is null then null
    when p_task = 'intake' then
      coalesce((select array_agg(distinct (m)::int order by (m)::int) from jsonb_array_elements_text(a->'months') m), '{}')
      = coalesce((select array_agg(distinct (m)::int order by (m)::int) from jsonb_array_elements_text(b->'months') m), '{}')
    else
      coalesce((select array_agg(distinct (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text order by (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text) from jsonb_array_elements(a->'tests') t), '{}')
      = coalesce((select array_agg(distinct (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text order by (t->>'test') || ':' || trim_scale((t->>'overall')::numeric)::text) from jsonb_array_elements(b->'tests') t), '{}')
  end
$$;

create or replace function security.adapter_shadow_found_v1(p_task text, v jsonb)
returns boolean language sql immutable set search_path to '' as $$
  select case when v is null then false
              when p_task = 'intake' then jsonb_typeof(v->'months') = 'array' and jsonb_array_length(v->'months') > 0
              else jsonb_typeof(v->'tests') = 'array' and jsonb_array_length(v->'tests') > 0 end
$$;

create or replace function public.svc_adapter_shadow_claim(p_task text, p_limit int, p_worker text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare s pipeline.adapter_shadow_settings; v_spent numeric; v_reads int; v_task_reads int; v_cap int; v_limit int;
        v_class text; v_items jsonb := '[]'::jsonb; r record; v_prof jsonb; v_id uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_task not in ('intake','english') then raise exception 'task must be intake or english'; end if;
  v_class := case p_task when 'intake' then 'provider_intake_validation' else 'provider_english_validation' end;
  select * into s from pipeline.adapter_shadow_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('items', v_items, 'reason', 'shadow run switched off'); end if;
  perform pg_advisory_xact_lock(hashtext('adapter-shadow-claim'));
  -- a claim left by a lost worker is closed as an error after 30 minutes
  update pipeline.adapter_shadow_reads set status = 'error', errors = '["stale claim released"]'::jsonb, completed_at = now()
   where status = 'claimed' and claimed_at < now() - interval '30 minutes';
  select coalesce(sum(cost_usd), 0), count(*), count(*) filter (where task = p_task) into v_spent, v_reads, v_task_reads
    from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  if v_spent >= s.daily_usd_max then return jsonb_build_object('items', v_items, 'reason', format('daily spend limit: %s of %s USD', round(v_spent, 4), s.daily_usd_max)); end if;
  v_cap := s.daily_reads_max / 2;
  if v_task_reads >= v_cap or v_reads >= s.daily_reads_max then return jsonb_build_object('items', v_items, 'reason', format('daily read limit: %s of %s for %s', v_task_reads, v_cap, p_task)); end if;
  v_limit := greatest(1, least(coalesce(p_limit, 3), 10, v_cap - v_task_reads));
  for r in
    select w.id work_item_id, w.status l3_status, co.id course_id, co.provider_id, i.evidence_id, e.storage_path,
           i.candidate_value, i.status i_status, i.estimated_cost_usd, to_jsonb(ua) adapter
      from pipeline.layer3_work_items w
      join pipeline.layer3_interpretations i on i.id = w.interpretation_id
      join pipeline.evidence_artifacts e on e.id = i.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = w.entity_id
      join pipeline.uni_adapters ua on ua.provider_id = co.provider_id and ua.enabled
     where w.task_class = v_class and w.entity_type = 'course'
       and w.status in ('admitted','no_candidate','layer4_required','validated')
       and w.completed_at > now() - interval '14 days'
       and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id)
     order by w.completed_at desc
     limit v_limit
  loop
    v_prof := (select to_jsonb(p) - 'prompt_system' - 'structured_output_schema' - 'deterministic_validators' - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                 from pipeline.layer3_model_profiles p
                where p.code = security.adapter_builder_model_for_v1(r.provider_id)->>'code'
                  and p.enabled and not p.paused and p.retired_at is null);
    if v_prof is null then continue; end if;
    insert into pipeline.adapter_shadow_reads(task, work_item_id, course_id, provider_id, evidence_id, profile_code, model, layer3_status,
           layer3_value, layer3_found, layer3_cost_usd)
    values (p_task, r.work_item_id, r.course_id, r.provider_id, r.evidence_id, v_prof->>'code', v_prof->>'model_identifier', r.l3_status,
           case when r.i_status = 'validated' then r.candidate_value end,
           r.i_status = 'validated' and security.adapter_shadow_found_v1(p_task, r.candidate_value), r.estimated_cost_usd)
    returning id into v_id;
    v_items := v_items || jsonb_build_object('shadow_id', v_id, 'course_id', r.course_id, 'provider_id', r.provider_id,
      'storage_path', r.storage_path, 'adapter', r.adapter - 'notes' - 'reason' - 'updated_by' - 'admit_reason', 'profile', v_prof);
  end loop;
  return jsonb_build_object('items', v_items, 'spent_today_usd', v_spent, 'reads_today', v_reads, 'worker', p_worker);
end $$;

create or replace function public.svc_adapter_shadow_complete(p_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v pipeline.adapter_shadow_reads; v_found boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v from pipeline.adapter_shadow_reads where id = p_id for update;
  if v.id is null or v.status <> 'claimed' then return jsonb_build_object('ok', false, 'reason', 'not an open shadow claim'); end if;
  v_found := coalesce((p_result->>'valid')::boolean, false) and security.adapter_shadow_found_v1(v.task, p_result->'admitted');
  update pipeline.adapter_shadow_reads set
    status = case when p_result ? 'worker_error' then 'error' else 'done' end,
    input_basis = p_result->>'input_basis', input_chars = (p_result->>'input_chars')::int,
    shadow_status = p_result->>'status', shadow_valid = (p_result->>'valid')::boolean,
    shadow_value = case when v_found then p_result->'admitted' end, shadow_found = v_found,
    agree = case when v_found and v.layer3_found then security.adapter_shadow_same_v1(v.task, p_result->'admitted', v.layer3_value) end,
    cost_usd = coalesce((p_result->>'cost_usd')::numeric, 0), input_tokens = (p_result->>'input_tokens')::int,
    output_tokens = (p_result->>'output_tokens')::int, latency_ms = (p_result->>'latency_ms')::int,
    errors = p_result->'errors', worker_version = p_result->>'worker_version', completed_at = now()
  where id = p_id returning * into v;
  return jsonb_build_object('ok', true, 'status', v.status, 'shadow_found', v.shadow_found, 'layer3_found', v.layer3_found, 'agree', v.agree);
end $$;

-- per field: compared reads, agreement where both found, how often each finds a value, cost; and the retire test
create or replace function security.adapter_shadow_summary_v1()
returns jsonb language sql stable set search_path to '' as $$
  with s as (select * from pipeline.adapter_shadow_settings where id = 1),
  d as (select * from pipeline.adapter_shadow_reads where status = 'done'),
  t as (
    select d.task, count(*) compared,
           count(*) filter (where d.shadow_found and d.layer3_found) both_found,
           count(*) filter (where d.agree) agree_n,
           count(*) filter (where d.shadow_found) shadow_found_n,
           count(*) filter (where d.layer3_found) layer3_found_n,
           count(*) filter (where d.shadow_found and not d.layer3_found) shadow_only,
           count(*) filter (where d.layer3_found and not d.shadow_found) layer3_only,
           round(sum(d.cost_usd), 4) shadow_cost_usd, round(sum(d.layer3_cost_usd), 4) layer3_cost_usd,
           round(avg(d.input_chars)) avg_input_chars,
           count(*) filter (where d.input_basis <> 'page') adapter_input_n
      from d group by d.task)
  select jsonb_build_object(
    'settings', (select to_jsonb(s) from s),
    'today', (select jsonb_build_object('reads', count(*), 'cost_usd', round(coalesce(sum(cost_usd), 0), 4), 'errors', count(*) filter (where status = 'error'))
                from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),
    'fields', coalesce((select jsonb_agg(jsonb_build_object(
        'task', t.task, 'compared', t.compared, 'both_found', t.both_found, 'agree_n', t.agree_n,
        'agreement', case when t.both_found > 0 then round(t.agree_n::numeric / t.both_found, 4) end,
        'shadow_found_rate', round(t.shadow_found_n::numeric / nullif(t.compared, 0), 4),
        'layer3_found_rate', round(t.layer3_found_n::numeric / nullif(t.compared, 0), 4),
        'shadow_only', t.shadow_only, 'layer3_only', t.layer3_only,
        'shadow_cost_usd', t.shadow_cost_usd, 'layer3_cost_usd', t.layer3_cost_usd,
        'avg_input_chars', t.avg_input_chars, 'adapter_input_n', t.adapter_input_n,
        'eligible_to_retire', t.compared >= s.min_compared and t.both_found > 0
            and t.agree_n::numeric / t.both_found >= s.retire_match and t.shadow_found_n >= t.layer3_found_n) order by t.task)
      from t, s), '[]'::jsonb))
$$;

create or replace function public.admin_adapter_shadow(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_before jsonb; v_after jsonb; v_reason text := btrim(coalesce(p_args->>'reason', ''));
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'summary' then return security.adapter_shadow_summary_v1(); end if;
  if p_action = 'providers' then
    return coalesce((select jsonb_agg(x order by x->>'agreement' nulls last) from (
      select jsonb_build_object('provider_id', d.provider_id, 'provider', pr.name, 'task', d.task, 'compared', count(*),
             'both_found', count(*) filter (where d.shadow_found and d.layer3_found),
             'agreement', round(count(*) filter (where d.agree)::numeric / nullif(count(*) filter (where d.shadow_found and d.layer3_found), 0), 4),
             'shadow_found', count(*) filter (where d.shadow_found), 'layer3_found', count(*) filter (where d.layer3_found)) x
        from pipeline.adapter_shadow_reads d left join catalogue.providers pr on pr.id = d.provider_id
       where d.status = 'done' and (p_args->>'task' is null or d.task = p_args->>'task')
       group by d.provider_id, pr.name, d.task having count(*) >= 5) q), '[]'::jsonb);
  end if;
  if p_action = 'settings' then
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    select to_jsonb(s) into v_before from pipeline.adapter_shadow_settings s where id = 1;
    update pipeline.adapter_shadow_settings set
      enabled = coalesce((p_args->>'enabled')::boolean, enabled),
      daily_usd_max = coalesce((p_args->>'daily_usd_max')::numeric, daily_usd_max),
      daily_reads_max = coalesce((p_args->>'daily_reads_max')::int, daily_reads_max),
      reason = v_reason, updated_by = auth.uid(), updated_at = now()
    where id = 1 returning to_jsonb(adapter_shadow_settings) into v_after;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('adapter_shadow', 'settings', 'phase3', jsonb_build_object('before', v_before, 'after', v_after, 'reason', v_reason), auth.uid());
    return v_after;
  end if;
  raise exception 'action must be summary, providers or settings';
end $$;

revoke all on function public.svc_adapter_shadow_claim(text, int, text) from public, anon, authenticated;
revoke all on function public.svc_adapter_shadow_complete(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_shadow_claim(text, int, text) to service_role;
grant execute on function public.svc_adapter_shadow_complete(uuid, jsonb) to service_role;
revoke all on function public.admin_adapter_shadow(text, jsonb) from public, anon;
grant execute on function public.admin_adapter_shadow(text, jsonb) to authenticated, service_role;
revoke all on function security.adapter_shadow_summary_v1() from public, anon, authenticated;

-- two jobs, one per field, through the Layer 3 worker's shadow mode (one-time run tokens; nothing admitted)
select cron.schedule('adapter-shadow-intake', '*/2 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"shadow","task":"intake","limit":3}'::jsonb)$c$);
select cron.schedule('adapter-shadow-english', '1-59/2 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"shadow","task":"english","limit":3}'::jsonb)$c$);
