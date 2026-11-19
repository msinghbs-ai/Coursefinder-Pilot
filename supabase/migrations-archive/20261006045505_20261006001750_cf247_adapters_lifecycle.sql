-- CF-247 Decision 254 (6 Oct 2026, Platform Admin 15:25 to 15:39: "Adapters Lifecycle needs to managed in better UI
-- experience ... Try to combine then in a single UI experience", Adapters home "Under Layer2", "Both in one release").
-- The database side of the Layer 2 › Adapters screen:
--   pipeline.uni_adapters.read_cycle_days   how often a read course page of this university is read again (days).
--                                           Empty means the platform default (90 days, as before). 7 to 365.
--   public.svc_coverage_read_record         the re-read date of a read page uses the university's own cycle when set.
--                                           A page read again whose content hash is unchanged keeps its evidence, so
--                                           only a changed page produces new evidence for the adapter to read.
--   public.admin_adapters(action, args)     list: one row per university with an adapter or in the Firecrawl targets
--                                           (adapter state, admitted fields, latest Qualify, pages, next read).
--                                           detail: one university (coverage figures, central pages, schedule, the
--                                           Qualify results, its tasks and its log).
--                                           set_on: switch one or many adapters on or off (Platform Admin, logged).
--                                           set_cycle: set or clear one or many universities' read cycle (Platform
--                                           Admin, logged); the next read of each read page moves to last read + cycle.
--   public.admin_jobs 'start' admit_qualified  also takes provider_ids without a Qualify job: each adapter is admitted
--                                           from its own latest finished Qualify (stored as args.qual_jobs).
--   security.admin_job_slice_v1             the admit slice reads each adapter's own Qualify row from args.qual_jobs.
-- Switching an adapter off stops it being applied to pages read from now on (the general reader is used instead) and
-- stops what it reads being admitted. Values already admitted stay. Values entered or locked by hand are never changed.
-- Nothing is admitted by this migration and no adapter is switched. No table, row or function is removed. Snippet
-- patches are md5-guarded, each snippet found exactly once. No text value in this file contains a semicolon: {sc}
-- becomes chr(59).

alter table pipeline.uni_adapters add column if not exists read_cycle_days integer;
alter table pipeline.uni_adapters add constraint uni_adapters_read_cycle_days_range check (read_cycle_days is null or read_cycle_days between 7 and 365);
comment on column pipeline.uni_adapters.read_cycle_days is 'Days between reads of a read course page of this university. Empty: the platform default (90). Set in Layer 2 › Adapters.';

-- The read cycle used when a page is recorded as read
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure) is distinct from 'f186cfbfa0173ebf00a8236ecc215b92' then
    raise exception 'svc_coverage_read_record changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$when p_read_status in ('read','identity_mismatch') then now()+interval '90 days'$s$,
          $s$when p_read_status in ('read','identity_mismatch') then now()+make_interval(days => coalesce((select a.read_cycle_days from pipeline.uni_adapters a where a.provider_id=v_row.provider_id), 90))$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59)); v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

-- One row per university for the Adapters screen, and one university in full
create or replace function public.admin_adapters(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid; v_ids uuid[]; v_on boolean; v_days int; v_n int;
        v_pat text := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Operator or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object('as_at', now(), 'can_manage', v_rank >= 6, 'can_qualify', v_rank >= 5,
      'settings', jsonb_build_object('read_cycle_default', 90, 'read_cycle_min', 7, 'read_cycle_max', 365,
                                     'min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb), 'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)),
      'adapters', coalesce((
        with t as (select * from security.firecrawl_targets_fast()),
             ids as (select a.provider_id from pipeline.uni_adapters a union select t.provider_id from t where t.included),
             pg as (select g.provider_id, count(*) pages, count(*) filter (where g.read_status = 'read') pages_read, min(g.next_read_at) filter (where g.read_status in ('read', 'identity_mismatch')) next_read, max(g.read_at) last_read
                      from pipeline.coverage_course_pages g where g.provider_id in (select ids.provider_id from ids) group by g.provider_id),
             q as (select distinct on (x.provider_id) x.provider_id, x.job_id, x.measured_at, x.passing, x.pages_read
                     from pipeline.adapter_qualifications x join pipeline.admin_jobs j on j.id = x.job_id and j.kind = 'qualify_adapters' and j.state = 'done'
                    order by x.provider_id, x.measured_at desc)
        select jsonb_agg(jsonb_build_object(
                 'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'state', s.code,
                 'university', coalesce(p.display_name, p.canonical_name) ~* v_pat,
                 'adapter', case when a.provider_id is null then null else jsonb_build_object('state', case when not a.enabled then 'off' when a.admit then 'admitting' else 'testing' end,
                              'fields', case when a.admit then to_jsonb(coalesce(a.admit_fields, '{}')) else '[]'::jsonb end, 'read_cycle_days', a.read_cycle_days, 'updated_at', a.updated_at, 'admit_changed_at', a.admit_changed_at) end,
                 'target', case when t.provider_id is null then null else jsonb_build_object('included', t.included, 'rule_match', t.rule_match, 'override_reason', t.override_reason) end,
                 'pages', coalesce(pg.pages, 0), 'pages_read', coalesce(pg.pages_read, 0), 'next_read', pg.next_read, 'last_read', pg.last_read,
                 'qualify', case when q.provider_id is null then null else jsonb_build_object('job_id', q.job_id, 'at', q.measured_at, 'passing', to_jsonb(q.passing), 'pages_read', q.pages_read) end)
               order by coalesce(p.display_name, p.canonical_name))
          from ids join catalogue.providers p on p.id = ids.provider_id
          left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
          left join pipeline.uni_adapters a on a.provider_id = p.id left join t on t.provider_id = p.id
          left join pg on pg.provider_id = p.id left join q on q.provider_id = p.id), '[]'::jsonb));
  end if;
  if p_action = 'detail' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    return (select jsonb_build_object(
      'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'state', s.code, 'website', p.website,
      'can_manage', v_rank >= 6, 'can_qualify', v_rank >= 5,
      'english_policy', (select jsonb_build_object('status', pp.status, 'style', pp.style, 'url', pp.url, 'decided_at', pp.decided_at)
                         from pipeline.provider_policy_proposals pp where pp.provider_id = p.id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed', 'no_values')
                         order by (pp.status = 'approved') desc, (pp.status = 'proposed') desc, pp.updated_at desc limit 1),
      'calendar', (select jsonb_build_object('status', pp.status, 'style', pp.style, 'url', pp.url, 'decided_at', pp.decided_at)
                   from pipeline.provider_policy_proposals pp where pp.provider_id = p.id and pp.kind = 'intake_calendar' and pp.status in ('approved', 'proposed', 'no_values')
                   order by (pp.status = 'approved') desc, (pp.status = 'proposed') desc, pp.updated_at desc limit 1),
      'central_pages', (select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'url', x.url, 'status', x.status, 'read_at', x.read_at, 'evidence_id', x.evidence_id) order by x.kind, x.rank desc), '[]'::jsonb)
                        from pipeline.provider_fact_sources x where x.provider_id = p.id and x.found_via = 'manual' and x.kind in ('english_policy', 'intake_calendar')),
      'courses', m.courses, 'pages_read', m.pages_read,
      'intakes', jsonb_build_object('held', m.i_held, 'adapter', m.i_adapter, 'central', m.i_central, 'reader', m.i_reader, 'excluded', m.i_x),
      'english', jsonb_build_object('held', m.e_held, 'adapter', m.e_adapter, 'central', m.e_central, 'reader', m.e_reader, 'excluded', m.e_x),
      'fee', jsonb_build_object('held', m.f_held, 'adapter', m.f_adapter, 'reader', m.f_reader, 'excluded', m.f_x),
      'schedule', (select jsonb_build_object('read_cycle_days', (select a.read_cycle_days from pipeline.uni_adapters a where a.provider_id = p.id), 'read_cycle_default', 90,
                     'next_read', min(g.next_read_at) filter (where g.read_status in ('read', 'identity_mismatch')), 'last_read', max(g.read_at),
                     'due_7_days', count(*) filter (where g.next_read_at < now() + interval '7 days'), 'due_30_days', count(*) filter (where g.next_read_at < now() + interval '30 days'),
                     'by_status', (select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) from (select coalesce(g2.read_status, 'not_read') st, count(*) n from pipeline.coverage_course_pages g2 where g2.provider_id = p.id group by 1) z))
                   from pipeline.coverage_course_pages g where g.provider_id = p.id),
      'qualifications', (select coalesce(jsonb_agg(jsonb_build_object('job_id', x.job_id, 'title', j.title, 'at', x.measured_at, 'pages_read', x.pages_read, 'fields', x.fields, 'passing', to_jsonb(x.passing)) order by x.measured_at desc), '[]'::jsonb)
                         from (select * from pipeline.adapter_qualifications x where x.provider_id = p.id order by x.measured_at desc limit 5) x join pipeline.admin_jobs j on j.id = x.job_id),
      'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'state', j.state, 'title', j.title, 'created_at', j.created_at, 'finished_at', j.finished_at, 'result', j.result, 'error', j.error) order by j.created_at desc), '[]'::jsonb)
                from (select * from pipeline.admin_jobs j where j.scope = p.id::text or coalesce(j.args->'providers', '[]'::jsonb) ? p.id::text or coalesce(j.args->'provider_ids', '[]'::jsonb) ? p.id::text order by j.created_at desc limit 20) j),
      'log', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'area', e.area, 'action', e.action, 'detail', e.detail - 'courses', 'by', (select u.email from auth.users u where u.id = e.actor)) order by e.created_at desc), '[]'::jsonb)
              from (select * from pipeline.admin_control_events e where e.target = p.id::text order by e.created_at desc limit 30) e))
      from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
      cross join lateral (select count(*) courses, count(*) filter (where cf.read_status = 'read') pages_read,
                                 count(*) filter (where cf.intakes_src <> 'missing') i_held, count(*) filter (where cf.intakes_src = 'adapter') i_adapter,
                                 count(*) filter (where cf.intakes_src = 'central') i_central, count(*) filter (where cf.intakes_src = 'reader') i_reader, count(*) filter (where cf.intakes_x) i_x,
                                 count(*) filter (where cf.english_src <> 'missing') e_held, count(*) filter (where cf.english_src = 'adapter') e_adapter,
                                 count(*) filter (where cf.english_src = 'central') e_central, count(*) filter (where cf.english_src = 'reader') e_reader, count(*) filter (where cf.english_x) e_x,
                                 count(*) filter (where cf.fee_src <> 'missing') f_held, count(*) filter (where cf.fee_src = 'adapter') f_adapter,
                                 count(*) filter (where cf.fee_src = 'reader') f_reader, count(*) filter (where cf.fee_x) f_x
                          from security.university_course_fields_v1(p.id) cf) m
     where p.id = v_pid);
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids') = 'array' then p_args->'provider_ids' else '[]'::jsonb end) x);
  if cardinality(v_ids) = 0 then raise exception 'choose at least one adapter'; end if;
  if cardinality(v_ids) > 2000 then raise exception 'choose 2000 adapters or fewer at a time'; end if;
  if p_action = 'set_on' then
    v_on := (p_args->>'on')::boolean;
    if v_on is null then raise exception 'say on or off'; end if;
    v_ids := array(select a.provider_id from pipeline.uni_adapters a where a.provider_id = any (v_ids) and a.enabled is distinct from v_on);
    update pipeline.uni_adapters set enabled = v_on, updated_at = now(), updated_by = auth.uid() where provider_id = any (v_ids);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
      select 'toolsets', 'uni_adapter_switch', x::text, jsonb_build_object('on', v_on, 'reason', v_reason, 'together_with', cardinality(v_ids)), auth.uid() from unnest(v_ids) x;
    return jsonb_build_object('ok', true, 'changed', cardinality(v_ids), 'on', v_on);
  elsif p_action = 'set_cycle' then
    v_days := nullif(p_args->>'days', '')::int;
    if v_days is not null and (v_days < 7 or v_days > 365) then raise exception 'the read cycle is 7 to 365 days, or empty for the default'; end if;
    v_ids := array(select a.provider_id from pipeline.uni_adapters a where a.provider_id = any (v_ids));
    if cardinality(v_ids) = 0 then raise exception 'none of those universities has an adapter'; end if;
    update pipeline.uni_adapters set read_cycle_days = v_days, updated_at = now(), updated_by = auth.uid() where provider_id = any (v_ids);
    update pipeline.coverage_course_pages set next_read_at = read_at + make_interval(days => coalesce(v_days, 90)) where provider_id = any (v_ids) and read_status in ('read', 'identity_mismatch') and read_at is not null and leased_until is null;
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
      select 'toolsets', 'uni_adapter_read_cycle', x::text, jsonb_build_object('days', v_days, 'reason', v_reason, 'together_with', cardinality(v_ids)), auth.uid() from unnest(v_ids) x;
    return jsonb_build_object('ok', true, 'changed', cardinality(v_ids), 'pages_rescheduled', v_n, 'days', v_days);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_adapters(text, jsonb) from public, anon;
grant execute on function public.admin_adapters(text, jsonb) to authenticated;

-- Admit from each adapter's own latest Qualify, and show those Qualify rows on the admit task
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_jobs(text,jsonb)'::regprocedure) is distinct from '128fcc8c475f93ada292060c785846ec' then
    raise exception 'admin_jobs changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_jobs(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$where q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid)$s$,
          $s$where (q.job_id = coalesce(j.args->>'qualification_job_id', j.id::text)::uuid or q.job_id::text = j.args->'qual_jobs'->>q.provider_id::text))$s$],
    array[$s$    elsif v_kind = 'admit_qualified' then$s$,
          $s$    elsif v_kind = 'admit_qualified' and not (coalesce(p_args->'args', '{}'::jsonb) ? 'qualification_job_id') then
      -- 6 Oct (Layer 2 › Adapters): admit the ticked adapters, each from its own latest finished Qualify
      if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'{sc} end if{sc}
      v_fields := case when p_args->'args' ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'args'->'fields') x where x in ('intakes', 'english', 'fee', 'delivery')) else array['intakes', 'english', 'fee', 'delivery'] end{sc}
      select coalesce(jsonb_object_agg(z.provider_id, z.job_id), '{}'::jsonb), coalesce(array_agg(z.provider_id order by z.provider_id), '{}') into v_res, v_ids
        from (select distinct on (x.provider_id) x.provider_id, x.job_id, x.passing from pipeline.adapter_qualifications x join pipeline.admin_jobs qj on qj.id = x.job_id and qj.kind = 'qualify_adapters' and qj.state = 'done'
               where x.provider_id = any (array(select (y)::uuid from jsonb_array_elements_text(coalesce(p_args->'args'->'provider_ids', '[]'::jsonb)) y))
               order by x.provider_id, x.measured_at desc) z
       where z.passing && v_fields and exists (select 1 from pipeline.uni_adapters u where u.provider_id = z.provider_id and u.enabled){sc}
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'no ticked adapter passed for those fields in its latest Qualify (or it is switched off)'{sc} end if{sc}
      v_title := 'Admit the passing fields of ' || case when array_length(v_ids, 1) = 1 then coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_ids[1]), '1 adapter') else array_length(v_ids, 1) || ' adapters' end || ' (latest Qualify of each)'{sc}
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
        values (v_kind, 'adapters', v_title, jsonb_build_object('qual_jobs', v_res, 'fields', to_jsonb(v_fields), 'providers', to_jsonb(v_ids)), jsonb_build_object('done', 0, 'total', array_length(v_ids, 1)), auth.uid(), v_reason,
                coalesce(nullif(p_args->'args'->>'scope', ''), case when array_length(v_ids, 1) = 1 then v_ids[1]::text else 'adapters' end))
        returning * into v_j{sc}
      v_res := null{sc}
    elsif v_kind = 'admit_qualified' then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59)); v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_job_slice_v1(uuid,integer)'::regprocedure) is distinct from '68bf25c2ac72ad26a09aad0219e62367' then
    raise exception 'admin_job_slice_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.admin_job_slice_v1(uuid,integer)'::regprocedure);
  v_pairs := array[
    array[$s$where q.job_id = (v_j.args->>'qualification_job_id')::uuid and q.provider_id = v_pid$s$,
          $s$where q.job_id = coalesce((v_j.args->'qual_jobs'->>v_pid::text)::uuid, (v_j.args->>'qualification_job_id')::uuid) and q.provider_id = v_pid$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    v_pair[1] := replace(v_pair[1], '{sc}', chr(59)); v_pair[2] := replace(v_pair[2], '{sc}', chr(59));
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
