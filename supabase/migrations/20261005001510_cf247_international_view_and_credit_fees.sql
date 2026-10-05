-- CF-247 Decision 254 (5 Oct 2026). Two mechanisms asked for by the Platform Admin.
-- 1. International view of the course page (11:48, 13:02). Many course pages show the domestic view unless the address asks
--    for the international one (La Trobe "#/fees?location=BU&studentType=int&year=2027"). An adapter can now name its
--    university's international view (page_view: render true, suffix, wait_ms). Worker v0.17.4 reads those pages through
--    Firecrawl with the view applied. admin_uni_adapter_write('read_view') sends the university's pages back to be read
--    that way (pages read before the adapter was last saved, at most 600 a call). Page addresses are not changed.
-- 2. Fees charged per credit (12:12, Athabasca; 13:25 "Use 30 credits"). A Platform Admin records the university's
--    international rate, the credits it covers, and the credits in one full-time year, for a named list of courses, with
--    the page that prints the rate. The annual fee = rate / rate credits x credits per year. It is written as the course's
--    international annual tuition with that page as evidence and the formula in the notes, unless the fee was entered by
--    hand or excluded for the course. Scholarship savings for those courses are worked out again.
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon:
-- where a replacement needs a statement break it is written {sc} and turned into a semicolon with chr(59).

alter table pipeline.uni_adapters add column if not exists page_view jsonb not null default '{}'::jsonb;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_json(uuid)'::regprocedure) is distinct from 'fba7fabf30745cad12dec6b4c5447326' then
    raise exception 'uni_adapter_json changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_json(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('title_strip', a.title_strip, 'course_title_strip', a.course_title_strip, 'json_source', a.json_source, 'json_paths', a.json_paths,
                            'sections', a.sections, 'patterns', a.patterns, 'pick', a.pick, 'term_months', a.term_months, 'page_view', a.page_view,
                            'section_chars', a.section_chars, 'enabled', a.enabled, 'notes', a.notes, 'reason', a.reason, 'updated_at', a.updated_at)
  from pipeline.uni_adapters a where a.provider_id = p_provider
$f$;

create or replace function security.uni_adapter_view_requeue_v1(p_provider_id uuid, p_reason text, p_limit int default 600) returns integer
language plpgsql security definer set search_path = '' as $f$
declare n int; v_ids uuid[];
begin
  if not exists (select 1 from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and coalesce(u.page_view->>'render', 'false') = 'true') then
    raise exception 'the adapter names no international view to read'; end if;
  v_ids := array(select pg.course_id from pipeline.coverage_course_pages pg join pipeline.uni_adapters u on u.provider_id = pg.provider_id
                  join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
                  where pg.provider_id = p_provider_id and pg.url is not null
                    and pg.read_status in ('read', 'identity_mismatch', 'needs_render', 'fetch_failed', 'blocked')
                    and (pg.read_at is null or pg.read_at < u.updated_at)
                  order by pg.course_id limit greatest(1, least(coalesce(p_limit, 600), 600)));
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, 'university adapter: international view read (' || left(p_reason, 300) || ')'
    from pipeline.coverage_course_pages pg where pg.course_id = any (v_ids);
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', next_read_at = now(), leased_until = null where pg.course_id = any (v_ids);
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_view_requeue_v1(uuid, text, int) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from '576a1545bdfe9abd23bf6e1e94324425' then
    raise exception 'admin_uni_adapter_write changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_write(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'$s$,
          $s$if jsonb_typeof(coalesce(v_a->'page_view', '{}'::jsonb)) <> 'object' or coalesce(v_a->'page_view'->>'suffix', '') !~ '^([#?&][^ <>]{1,250})?$'
       or coalesce(v_a->'page_view'->>'wait_ms', '0') !~ '^[0-9]{1,4}$' or coalesce((v_a->'page_view'->>'wait_ms')::int, 0) > 8000
       or coalesce(v_a->'page_view'->>'render', 'false') not in ('true', 'false') then
      raise exception 'page_view must hold render (true or false), suffix (starting with # ? or &) and wait_ms (0 to 8000)'{sc}
    end if{sc}
    if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'$s$],
    array[$s$pick, term_months, section_chars, notes, reason, updated_by, updated_at)$s$,
          $s$pick, term_months, page_view, section_chars, notes, reason, updated_by, updated_at)$s$],
    array[$s$coalesce(v_a->'term_months', '{}'::jsonb), greatest($s$,
          $s$coalesce(v_a->'term_months', '{}'::jsonb), coalesce(v_a->'page_view', '{}'::jsonb), greatest($s$],
    array[$s$term_months = excluded.term_months,$s$,
          $s$term_months = excluded.term_months, page_view = excluded.page_view,$s$],
    array[$s$elsif p_action = 'apply' then$s$,
          $s$elsif p_action = 'read_view' then
    v_n := security.uni_adapter_view_requeue_v1(v_pid, v_reason, coalesce((p_args->>'limit')::int, 600)){sc}
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_read_view', v_pid::text, jsonb_build_object('page_view', security.uni_adapter_json(v_pid)->'page_view', 'pages_read_again', v_n, 'reason', v_reason), auth.uid()){sc}
    return jsonb_build_object('ok', true, 'pages_read_again', v_n){sc}
  elsif p_action = 'apply' then$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

create table if not exists pipeline.provider_credit_fees (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  label text not null,
  course_ids uuid[] not null,
  rate numeric(12,2) not null check (rate > 0),
  rate_credits numeric(6,2) not null check (rate_credits > 0),
  annual_credits numeric(6,2) not null check (annual_credits > 0),
  fee_year int not null check (fee_year between 2024 and 2035),
  currency_code text not null check (currency_code in ('AUD', 'NZD', 'CAD')),
  source_url text not null,
  fact_source_id uuid references pipeline.provider_fact_sources(id),
  active boolean not null default true,
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now(),
  applied_at timestamptz,
  last_result jsonb
);
alter table pipeline.provider_credit_fees enable row level security;
revoke all on table pipeline.provider_credit_fees from anon, authenticated;

create or replace function security.provider_credit_fee_apply_v1(p_rule_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r pipeline.provider_credit_fees%rowtype; v_ev uuid; v_hash text; v_src uuid; v_fee numeric; c uuid; v_cur numeric;
        v_done int := 0; v_same int := 0; v_skip int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}';
begin
  select * into r from pipeline.provider_credit_fees where id = p_rule_id;
  if r.id is null then raise exception 'unknown credit fee rule'; end if;
  if not r.active then return jsonb_build_object('ok', false, 'note', 'the rule is switched off'); end if;
  select s.evidence_id into v_ev from pipeline.provider_fact_sources s where s.id = r.fact_source_id;
  if v_ev is null then raise exception 'the rate page has not been read yet (no evidence)'; end if;
  select e.content_hash into v_hash from pipeline.evidence_artifacts e where e.id = v_ev;
  v_fee := round(r.rate / r.rate_credits * r.annual_credits, 2);
  if v_fee not between 1000 and 500000 then raise exception 'the annual fee % is outside 1,000 to 500,000', v_fee; end if;
  v_src := security.coverage_sweep_source(r.provider_id);
  insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'provider_current_tuition', v_src, 'approved', 'CF-CHG-20260915-247, Decision 254, Platform Admin 5 Oct 2026 13:25 (fees per credit)', now(), now(), now()
    where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = v_src);
  foreach c in array r.course_ids loop
    if not exists (select 1 from catalogue.courses co where co.id = c and co.provider_id = r.provider_id and co.lifecycle_status = 'active')
       or security.uni_adapter_excluded(c, 'fee')
       or exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c and k.field in ('tuition', 'fee', 'fees')) then
      v_skip := v_skip + 1;
      continue;
    end if;
    select f.amount into v_cur from catalogue.course_fees f where f.course_id = c and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = r.fee_year order by f.updated_at desc nulls last limit 1;
    if v_cur = v_fee then v_same := v_same + 1; continue; end if;
    begin
      update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = c and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = r.fee_year and amount <> v_fee;
      perform security.coverage_apply_course_v1(c, v_src, v_ev, r.source_url, v_hash, jsonb_build_object('fee_amount', v_fee, 'fee_year', r.fee_year, 'currency_code', r.currency_code, 'fee_basis', 'annual', 'audience', 'international',
                 'fee_notes', 'Per-credit rate x credits in a full-time year: ' || r.rate || ' per ' || r.rate_credits || ' credits x ' || r.annual_credits || ' credits (' || r.label || ')',
                 'fee_key', 'credit-fee:' || r.id || ':' || c || ':' || r.fee_year));
      insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
        values (c, r.provider_id, 'fee', to_jsonb(v_cur), jsonb_build_object('amount', v_fee, 'year', r.fee_year, 'currency', r.currency_code, 'formula', jsonb_build_object('rate', r.rate, 'rate_credits', r.rate_credits, 'annual_credits', r.annual_credits), 'rule_id', r.id), v_ev, r.source_url);
      v_done := v_done + 1; v_courses := v_courses || c;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    foreach c in array v_courses loop perform scholarship.refresh_course_financial_calculations(c, null); end loop;
  end if;
  update pipeline.provider_credit_fees set applied_at = now(), last_result = jsonb_build_object('fee', v_fee, 'written', v_done, 'same', v_same, 'skipped', v_skip, 'errors', v_err, 'last_error', v_last) where id = r.id;
  return jsonb_build_object('fee', v_fee, 'written', v_done, 'same', v_same, 'skipped', v_skip, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.provider_credit_fee_apply_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_provider_credit_fee(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid; v_id uuid; v_ids uuid[]; v_src uuid; v_res jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'read' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'course_ids' || jsonb_build_object('courses', cardinality(x.course_ids)) order by x.set_at desc) from pipeline.provider_credit_fees x where x.provider_id = (p_args->>'provider_id')::uuid), '[]'::jsonb);
  elsif p_action = 'add' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if jsonb_typeof(p_args->'course_ids') <> 'array' or jsonb_array_length(p_args->'course_ids') = 0 then raise exception 'give the courses the rate applies to'; end if;
    v_ids := array(select distinct x::uuid from jsonb_array_elements_text(p_args->'course_ids') x);
    if exists (select 1 from unnest(v_ids) x where not exists (select 1 from catalogue.courses co where co.id = x and co.provider_id = v_pid)) then raise exception 'every course must belong to this university'; end if;
    if coalesce(p_args->>'source_url', '') !~ '^https?://[^ ]+$' then raise exception 'give the page that prints the rate'; end if;
    select s.id into v_src from pipeline.provider_fact_sources s where s.provider_id = v_pid and s.url = btrim(p_args->>'source_url') order by s.updated_at desc limit 1;
    if v_src is null then raise exception 'attach the rate page as a central page first so it is read with evidence'; end if;
    insert into pipeline.provider_credit_fees(provider_id, label, course_ids, rate, rate_credits, annual_credits, fee_year, currency_code, source_url, fact_source_id, reason, set_by)
      values (v_pid, btrim(coalesce(p_args->>'label', 'per-credit rate')), v_ids, (p_args->>'rate')::numeric, (p_args->>'rate_credits')::numeric, (p_args->>'annual_credits')::numeric,
              (p_args->>'fee_year')::int, upper(btrim(p_args->>'currency_code')), btrim(p_args->>'source_url'), v_src, v_reason, auth.uid())
      returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'credit_fee_add', v_pid::text, jsonb_build_object('rule_id', v_id, 'args', p_args - 'course_ids', 'courses', cardinality(v_ids), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_id, 'annual_fee', round((p_args->>'rate')::numeric / (p_args->>'rate_credits')::numeric * (p_args->>'annual_credits')::numeric, 2));
  elsif p_action = 'apply' then
    v_id := (p_args->>'id')::uuid;
    v_res := security.provider_credit_fee_apply_v1(v_id);
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'credit_fee_apply', v_id::text, jsonb_build_object('result', v_res, 'reason', v_reason), auth.uid());
    return v_res;
  elsif p_action = 'off' then
    v_id := (p_args->>'id')::uuid;
    update pipeline.provider_credit_fees set active = false, reason = v_reason, set_by = auth.uid(), set_at = now() where id = v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'credit_fee_off', v_id::text, jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_provider_credit_fee(text, jsonb) from public, anon;
grant execute on function public.admin_provider_credit_fee(text, jsonb) to authenticated;
