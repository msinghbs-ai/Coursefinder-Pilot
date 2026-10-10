-- CF-247 (Decision 218, 2 Oct 2026). Platform Admin, 10:51: "flagged values should be covered by course fees automation,
-- can you reroute them to layer 3 course fees automation? Fix: error show in live activity".
--  1. Fee periods: a fee the Layer 3 fee check added as "per year" (period not recognised) is confirmed automatically when
--     the page wording it quoted says per year ("1st year indicative fee", "for 1 yr full-time", "annual" ...), or when the
--     course runs a year or less. Wording that names another period (semester, trimester, total, whole course) is never
--     confirmed; those stay in Flagged values for a person. Job fee-period-settle every 10 minutes.
--  2. Live activity: each worker error names the job that got it (scheduled calls note the function and mode they called),
--     and an operator can mark an error as seen; it shows again only if it happens again.
-- Function patches behind md5 guards.

-- 2a. which function each scheduled call went to (a ring of 50,000 slots; pg_net keeps replies a few hours)
create table if not exists pipeline.edge_request_log (
  slot int primary key,
  request_id bigint not null,
  function_name text not null,
  mode text,
  created_at timestamptz not null default now()
);
alter table pipeline.edge_request_log enable row level security;
revoke all on pipeline.edge_request_log from public, anon, authenticated;

create or replace function pipeline.edge_request_note(p_request_id bigint, p_function text, p_mode text) returns void
language sql security definer set search_path = '' as $fn$
  insert into pipeline.edge_request_log(slot, request_id, function_name, mode, created_at)
  values ((p_request_id % 50000)::int, p_request_id, p_function, nullif(p_mode, ''), now())
  on conflict (slot) do update set request_id = excluded.request_id, function_name = excluded.function_name, mode = excluded.mode, created_at = excluded.created_at;
$fn$;
revoke all on function pipeline.edge_request_note(bigint, text, text) from public, anon, authenticated;

-- 2b. errors an operator has marked as seen
create table if not exists pipeline.live_error_acks (
  function_name text not null,
  status_code int not null,
  message_md5 text not null,
  acked_at timestamptz not null default now(),
  acked_by uuid,
  note text,
  primary key (function_name, status_code, message_md5)
);
alter table pipeline.live_error_acks enable row level security;
revoke all on pipeline.live_error_acks from public, anon, authenticated;

do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('pipeline','svc_pilot_submit_nonce','812983b8ec7ea2faaf2eff3f197c6f05',
      array[$o$into v_id; return v_id; end$o$],
      array[$n$into v_id; perform pipeline.edge_request_note(v_id, p_function, p_body->>'mode'); return v_id; end$n$]),
    ('pipeline','svc_pilot_invoke_edge','7967f53602b31a5dedc0a2dbf062bcc4',
      array[$o$into v_id; return v_id; end$o$],
      array[$n$into v_id; perform pipeline.edge_request_note(v_id, p_function, p_body->>'mode'); return v_id; end$n$]),
    ('pipeline','svc_pilot_invoke_layer2','d5f848a2e817aa70e4c3189891d7e7d4',
      array[E'into v_id;\n return v_id;'],
      array[E'into v_id;\n perform pipeline.edge_request_note(v_id, p_function, p_body->>''mode'');\n return v_id;']),
    ('public','layer2_run_batch_dispatch','2dd337996dfc2ca35aa42e058dfee5da',
      array[E'into v_req;\n return v_req;'],
      array[E'into v_req;\n perform pipeline.edge_request_note(v_req, ''layer2-batch-runner'', null);\n return v_req;']),
    ('security','admin_live_activity_v1','9a8705ecbc8162af37b3bad6b3ccf8aa',
      array[$o$'worker_errors', (select coalesce(jsonb_agg(jsonb_build_object('status', x.status_code, 'timed_out', x.timed_out, 'message', x.message, 'count', x.n, 'last', x.last) order by x.last desc), '[]'::jsonb)
                        from (select h.status_code, h.timed_out, left(coalesce(h.error_msg, h.content), 200) message, count(*) n, max(h.created) last
                                from net._http_response h where h.status_code >= 400 or h.status_code is null
                               group by 1, 2, 3 order by max(h.created) desc limit 10) x)$o$],
      array[$n$'worker_errors', (select coalesce(jsonb_agg(jsonb_build_object('function', x.fn, 'job', x.job, 'status', x.status_code, 'timed_out', x.timed_out, 'message', x.message, 'count', x.n, 'last', x.last) order by x.last desc), '[]'::jsonb)
                        from (select e.*, (select a.label from pipeline.automation_catalogue a join cron.job j on j.jobname = a.jobname
                                            where e.fn <> '' and j.command like '%''' || e.fn || '''%' and (e.mode is null or j.command like '%"mode":"' || e.mode || '"%')
                                            order by a.sort limit 1) job
                                from (select coalesce(l.function_name, '') fn, l.mode, h.status_code, h.timed_out, left(coalesce(h.error_msg, h.content), 200) message, count(*) n, max(h.created) last
                                        from net._http_response h left join pipeline.edge_request_log l on l.slot = (h.id % 50000)::int and l.request_id = h.id
                                       where h.status_code >= 400 or h.status_code is null
                                       group by 1, 2, 3, 4, 5) e
                               where not exists (select 1 from pipeline.live_error_acks k where k.function_name = e.fn and k.status_code = coalesce(e.status_code, -1)
                                                    and k.message_md5 = md5(e.message) and k.acked_at >= e.last)
                               order by e.last desc limit 10) x)$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;

-- 2c. mark an error as seen (Pipeline Operator and above); returns the refreshed live activity
create or replace function public.admin_live_error_ack(p_function text, p_status int, p_message text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline operator or admin role required' using errcode = '42501'; end if;
  insert into pipeline.live_error_acks(function_name, status_code, message_md5, acked_at, acked_by)
  values (coalesce(p_function, ''), coalesce(p_status, -1), md5(coalesce(p_message, '')), now(), auth.uid())
  on conflict (function_name, status_code, message_md5) do update set acked_at = now(), acked_by = auth.uid(), note = null;
  return security.admin_live_activity_v1();
end $fn$;
revoke all on function public.admin_live_error_ack(text, int, text) from public, anon;
grant execute on function public.admin_live_error_ack(text, int, text) to authenticated;

-- the errors on the screen now are understood and resolved: old automation key (Decisions 215-216), deliberate test calls
-- after the run-pass change, and two compute-limit replies from evidence indexing (made lighter in this release)
insert into pipeline.live_error_acks(function_name, status_code, message_md5, acked_at, note)
select distinct '', coalesce(h.status_code, -1), md5(left(coalesce(h.error_msg, h.content), 200)), now(),
       'Decision 218: resolved before job names were recorded (old automation key; run-pass test calls; evidence indexing compute limit)'
  from net._http_response h where h.status_code >= 400 or h.status_code is null
on conflict (function_name, status_code, message_md5) do update set acked_at = now(), note = excluded.note;

-- 1. settle fee periods from the page wording or a short course
create or replace function security.fee_period_settle_v1(p_limit int default 500) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare r record; v_rule text; v_quote text; v_wording int := 0; v_short int := 0; v_left int := 0; v_ids uuid[] := '{}';
  yr constant text := '(per\s+(year|annum|academic\s+year)|a\s+year\M|\mannual(ly)?\M|\myearly\M|\m1\s*(yr|year)\M|\mone\s+year\M|\m(first|1st)[- ]year\M|\mp\.?a\.?\M|/\s*(year|yr)\M|each\s+year|full[- ]time\s+year)';
  other constant text := '(per\s+(semester|trimester|term|unit|subject|credit|study\s+period|session)|\m(semester|trimester)s?\M|\mtotal\M|\m(whole|entire|full)\s+(course|program|programme|degree)\M)';
begin
  if current_user not in ('postgres', 'service_role') and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required' using errcode = '42501'; end if;
  for r in select fl.id, fl.entity_id, fl.record_id, coalesce(fl.detail->>'quotes', '') q, c.duration_value dv, lower(coalesce(c.duration_unit, '')) du
             from pipeline.data_flags fl join catalogue.courses c on c.id = fl.entity_id
             join catalogue.course_fees fe on fe.id = fl.record_id and fe.status = 'active'
            where fl.status = 'open' and fl.flag_code = 'tuition_period_assumed_annual'
            order by fl.created_at limit greatest(1, least(coalesce(p_limit, 500), 2000))
            for update of fl skip locked loop
    v_rule := null; v_quote := null;
    if r.q ~* other then v_left := v_left + 1; continue; end if;
    if r.q ~* yr then v_rule := 'per_year_wording'; v_quote := substring(r.q from '(?i)([^"]{0,80}' || yr || '[^"]{0,40})');
    elsif (r.du in ('week', 'weeks') and r.dv <= 52) or (r.du in ('month', 'months') and r.dv <= 12) or (r.du in ('year', 'years') and r.dv <= 1) then
      v_rule := 'course_one_year_or_less';
    end if;
    if v_rule is null then v_left := v_left + 1; continue; end if;
    update catalogue.course_fees set last_verified_at = now(), updated_at = now(),
           notes = coalesce(notes, '') || case v_rule when 'per_year_wording' then ' | period confirmed per year from the page wording (automatic check, Decision 218)'
                                                 else ' | course runs a year or less, so per year equals the whole course (automatic check, Decision 218)' end
     where id = r.record_id;
    update pipeline.data_flags set status = 'confirmed', resolved_at = now(), resolved_by = null,
           resolution = jsonb_build_object('action', 'confirm', 'by', 'automatic period check', 'rule', v_rule, 'quote', v_quote,
                                           'duration', case when v_rule = 'course_one_year_or_less' then r.dv || ' ' || r.du end, 'decision', 'Decision 218')
     where id = r.id;
    if v_rule = 'per_year_wording' then v_wording := v_wording + 1; else v_short := v_short + 1; end if;
    v_ids := v_ids || r.entity_id;
  end loop;
  if cardinality(v_ids) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_ids, true); end if;
  return jsonb_build_object('confirmed_by_wording', v_wording, 'confirmed_short_course', v_short, 'left_for_a_person', v_left);
end $fn$;
revoke all on function security.fee_period_settle_v1(int) from public, anon, authenticated;

select cron.schedule('fee-period-settle', '5-59/10 * * * *', $c$select security.fee_period_settle_v1(500)$c$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
  ('fee-period-settle', 'Layer 3 AI', 45, 'Settle fee periods from page wording',
   'Confirms a fee added as per year when the page wording it quoted says per year, or the course runs a year or less. Anything naming another period stays in Flagged values for a person.', 5, false)
on conflict (jobname) do nothing;
