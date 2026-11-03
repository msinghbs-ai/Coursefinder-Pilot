-- CF-247 Layer 4 Inbox performance (migration 20261104440000): the cases, on the production-scale seed after the migration. Scratch PostgreSQL only.
-- Budget for each first-load read of the screen (summary, universities, first page of a university or kind, the page's detail): 300 ms here.
create table fx.budget(ms numeric);
insert into fx.budget values (300);
select set_config('fx.uid', 'b0000000-0000-0000-0000-000000000006', false), set_config('fx.rank', '6', false);

-- F1 security.layer4_inbox_items_v1() returns exactly what it returned before (it now reads security.layer4_inbox_items_v2)
do $$
declare a bigint; b bigint;
begin
  a := (select count(*) from (select j from fx.v1_before except all select to_jsonb(i) from security.layer4_inbox_items_v1() i) x);
  b := (select count(*) from (select to_jsonb(i) from security.layer4_inbox_items_v1() i except all select j from fx.v1_before) x);
  if a <> 0 or b <> 0 then raise exception 'F1: items_v1 output changed (% missing, % new)', a, b; end if;
  if (select count(*) from fx.v1_before) < 4500 then raise exception 'F1: the seed is not at production scale'; end if;
  raise notice 'F1 ok: items_v1 returns the same % items, row for row', (select count(*) from fx.v1_before);
end $$;

-- F2 the screen's answers are the same as before (no hook functions exist yet)
do $$
declare r jsonb; o jsonb;
begin
  r := public.admin_layer4_inbox('summary', '{}'); o := (select x.r from fx.reply x where action = 'summary');
  if r - 'paging' - 'hooks_missing' - 'hooks_failed' <> o then raise exception 'F2: summary differs: % vs %', r - 'kinds', o - 'kinds'; end if;
  if r->'paging' <> '{"items": 25, "universities": 25, "detail_parallel": 3}'::jsonb then raise exception 'F2: paging settings %', r->'paging'; end if;
  if jsonb_array_length(r->'hooks_missing') <> 2 or r->'kinds' <> security.layer4_inbox_kinds_v1() then raise exception 'F2: missing hooks changed the kinds: %', r->'hooks_missing'; end if;
  r := public.admin_layer4_inbox('universities', '{"limit": 25, "offset": 0}'); o := (select x.r from fx.reply x where action = 'universities');
  if r <> o then raise exception 'F2: universities differ'; end if;
  r := public.admin_layer4_inbox('items', jsonb_build_object('provider_id', o->'items'->0->>'provider_id', 'limit', 25)); o := (select x.r from fx.reply x where action = 'items_first_university');
  if r->'items' <> o->'items' or r->'total' <> o->'total' or (r->>'before')::int <> 0 then raise exception 'F2: first university page differs'; end if;
  r := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "aer_review", "limit": 25}'); o := (select x.r from fx.reply x where action = 'items_aer_pill');
  if r->'items' <> o->'items' or r->'total' <> o->'total' then raise exception 'F2: AER pill page differs'; end if;
  r := public.admin_layer4_inbox('items', '{"kind": "course_link", "limit": 25}'); o := (select x.r from fx.reply x where action = 'items_kind_course_link');
  if r->'items' <> o->'items' or r->'total' <> o->'total' then raise exception 'F2: course link kind page differs'; end if;
  raise notice 'F2 ok: summary, universities and first pages (university, AER pill, kind) answer exactly as before; paging settings 25 items, 25 universities, 3 detail reads';
end $$;

-- F3 first-load reads under budget (each measured three times, the slowest kept)
do $$
declare t timestamptz; r jsonb; v_ms numeric; v_first jsonb; i int; v_page jsonb; v_b numeric := (select ms from fx.budget);
  v_calls text[][] := array[['summary', 'summary', '{}'], ['universities', 'universities', '{"limit": 25, "offset": 0}'],
                            ['items_aer_pill', 'items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "aer_review", "limit": 25}'],
                            ['items_kind_course_link', 'items', '{"kind": "course_link", "limit": 25}']]; c int;
begin
  v_first := (public.admin_layer4_inbox('universities', '{"limit": 25, "offset": 0}'))->'items'->0;
  v_calls := v_calls || array[['items_first_university', 'items', jsonb_build_object('provider_id', v_first->>'provider_id', 'limit', 25)::text]];
  for c in 1 .. array_length(v_calls, 1) loop
    v_ms := 0;
    for i in 1 .. 3 loop
      t := clock_timestamp(); r := public.admin_layer4_inbox(v_calls[c][2], v_calls[c][3]::jsonb);
      v_ms := greatest(v_ms, round(extract(epoch from clock_timestamp() - t) * 1000, 1));
    end loop;
    insert into fx.timing values ('after', v_calls[c][1], v_ms);
    if v_ms > v_b then raise exception 'F3: % took % ms (budget % ms)', v_calls[c][1], v_ms, v_b; end if;
  end loop;
  v_page := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "limit": 25}');
  t := clock_timestamp();
  r := public.admin_layer4_inbox('detail', jsonb_build_object('items', (select jsonb_agg(jsonb_build_object('kind', x->>'kind', 'ref', x->>'ref')) from jsonb_array_elements(v_page->'items') x), 'limit', 25));
  v_ms := round(extract(epoch from clock_timestamp() - t) * 1000, 1); insert into fx.timing values ('after', 'detail_page', v_ms);
  if v_ms > v_b then raise exception 'F3: detail of a page took % ms', v_ms; end if;
  if jsonb_array_length(r->'items') <> jsonb_array_length(v_page->'items') or exists (select 1 from jsonb_array_elements(r->'items') x where x->'detail' is null or x->'detail' = 'null'::jsonb) then
    raise exception 'F3: detail did not return every item of the page'; end if;
  raise notice 'F3 ok: before -> after (ms): %', (select jsonb_object_agg(a.action, coalesce(b.ms::text, '-') || ' -> ' || a.ms) from fx.timing a left join fx.timing b on b.action = a.action and b.at_stage = 'before' where a.at_stage = 'after');
end $$;

-- F4 every university's items, page by page, are every waiting item exactly once, oldest first within each kind
create table fx.seen(scope text, kind text, ref text, provider_id uuid);
do $$
declare u jsonb; v_off int := 0; v_us jsonb; r jsonb; cur jsonb; v_last jsonb; v_pages int := 0; v_n bigint; v_prev jsonb;
begin
  loop
    v_us := public.admin_layer4_inbox('universities', jsonb_build_object('limit', 100, 'offset', v_off));
    exit when jsonb_array_length(v_us->'items') = 0;
    for u in select x from jsonb_array_elements(v_us->'items') x where x->>'provider_id' is not null loop
      cur := '{}'; v_n := 0;
      loop
        r := public.admin_layer4_inbox('items', jsonb_build_object('provider_id', u->>'provider_id', 'limit', 25) || cur); v_pages := v_pages + 1;
        if (r->>'before')::bigint <> v_n then raise exception 'F4: % before % expected %', u->>'name', r->>'before', v_n; end if;
        if (r->>'total')::bigint <> (u->>'n')::bigint then raise exception 'F4: % total % but the list says %', u->>'name', r->>'total', u->>'n'; end if;
        insert into fx.seen select 'university', x->>'kind', x->>'ref', (x->>'provider_id')::uuid from jsonb_array_elements(r->'items') x;
        v_n := v_n + jsonb_array_length(r->'items');
        exit when not (r->>'more')::boolean;
        v_last := r->'items'->-1;
        cur := jsonb_build_object('after_o', v_last->'o', 'after_at', v_last->'created_at', 'after_kind', v_last->'kind', 'after_ref', v_last->'ref');
      end loop;
    end loop;
    v_off := v_off + 100;
  end loop;
  if exists (select 1 from fx.seen where scope = 'university' group by kind, ref having count(*) > 1) then raise exception 'F4: an item was shown twice'; end if;
  if exists (select j->>'kind', j->>'ref' from fx.v1_before where j->>'provider_id' is not null except select kind, ref from fx.seen where scope = 'university') then
    raise exception 'F4: % items were never shown', (select count(*) from (select j->>'kind', j->>'ref' from fx.v1_before where j->>'provider_id' is not null except select kind, ref from fx.seen) x); end if;
  raise notice 'F4 ok: % items over % universities in % pages, each exactly once, totals and positions right',
    (select count(*) from fx.seen), (select count(distinct provider_id) from fx.seen), v_pages;
end $$;

-- F5 by kind, the same
do $$
declare k text; r jsonb; cur jsonb; v_last jsonb; v_n bigint;
begin
  for k in select distinct j->>'kind' from fx.v1_before loop
    cur := '{}'; v_n := 0;
    loop
      r := public.admin_layer4_inbox('items', jsonb_build_object('kind', k, 'limit', 25) || cur);
      if (r->>'before')::bigint <> v_n then raise exception 'F5: % before % expected %', k, r->>'before', v_n; end if;
      insert into fx.seen select 'kind', x->>'kind', x->>'ref', (x->>'provider_id')::uuid from jsonb_array_elements(r->'items') x;
      v_n := v_n + jsonb_array_length(r->'items');
      exit when not (r->>'more')::boolean;
      v_last := r->'items'->-1;
      cur := jsonb_build_object('after_o', v_last->'o', 'after_at', v_last->'created_at', 'after_kind', v_last->'kind', 'after_ref', v_last->'ref');
    end loop;
    if v_n <> (r->>'total')::bigint then raise exception 'F5: % shown % of %', k, v_n, r->>'total'; end if;
  end loop;
  if exists (select 1 from fx.seen where scope = 'kind' group by kind, ref having count(*) > 1) then raise exception 'F5: an item was shown twice'; end if;
  if (select count(*) from (select j->>'kind', j->>'ref' from fx.v1_before except select kind, ref from fx.seen where scope = 'kind') x) <> 0 then raise exception 'F5: items never shown'; end if;
  raise notice 'F5 ok: every kind paged, % items each exactly once', (select count(*) from fx.seen where scope = 'kind');
end $$;

-- F6 the AER pill of a university: only its waiting AER items, the exact count (not its courses, not the rows)
do $$
declare r jsonb; v_n bigint := (select count(*) from fx.v1_before where j->>'kind' = 'aer_review' and j->>'provider_id' = '10000000-0000-0000-0000-000000000007');
begin
  r := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "aer_review", "limit": 25}');
  if (r->>'total')::bigint <> v_n or exists (select 1 from jsonb_array_elements(r->'items') x where x->>'kind' <> 'aer_review' or x->>'provider_id' <> '10000000-0000-0000-0000-000000000007') then
    raise exception 'F6: AER pill total % (expected %) or a foreign item', r->>'total', v_n; end if;
  if v_n < 303 then raise exception 'F6: the seed lost its AER-heavy university'; end if;
  raise notice 'F6 ok: the AER pill of the AER-heavy university says % waiting AER items, 25 on the first page', v_n;
end $$;

-- F7 a decision: the same audit row and effect; counts follow at once; ranks unchanged
do $$
declare s0 jsonb; s1 jsonb; it jsonb; r jsonb; e0 bigint := (select count(*) from pipeline.admin_control_events); u0 jsonb; u1 jsonb; v_other jsonb;
begin
  s0 := public.admin_layer4_inbox('summary', '{}');
  it := (public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "course_link", "limit": 2}'))->'items'->0;
  v_other := (public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "course_link", "limit": 2}'))->'items'->1;
  u0 := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "course_link", "limit": 1}');
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_link', 'ref', it->>'ref', 'choice', 'keep', 'reason', 'Fixture: the held page is right'));
  if not (r->>'ok')::boolean or (select count(*) from pipeline.admin_control_events where area = 'layer4' and action = 'inbox_decide') <> (select count(*) from pipeline.admin_control_events where area = 'layer4' and action = 'inbox_decide' and id <> (r->>'event_id')::bigint) + 1 then raise exception 'F7: decision %', r; end if;
  if not exists (select 1 from pipeline.admin_control_events where id = (r->>'event_id')::bigint and target = 'course_link:' || (it->>'ref') and detail->>'choice' = 'keep') then raise exception 'F7: audit row'; end if;
  if (select status from pipeline.layer4_review_items where id = (it->>'ref')::uuid) = 'pending' then raise exception 'F7: the item still waits'; end if;
  s1 := public.admin_layer4_inbox('summary', '{}');
  u1 := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "course_link", "limit": 1}');
  if (s1->>'total')::int <> (s0->>'total')::int - 1 or (u1->>'total')::int <> (u0->>'total')::int - 1
     or (s1->'by_kind'->'course_link'->>'n')::int <> (s0->'by_kind'->'course_link'->>'n')::int - 1 then raise exception 'F7: counts did not follow the decision'; end if;
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_link', 'ref', it->>'ref', 'choice', 'keep', 'reason', 'Fixture: again'));
    raise exception 'F7: a decided item was decided again';
  exception when others then if sqlerrm not like '%no longer waiting%' then raise; end if; end;
  perform set_config('fx.rank', '3', false);
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_link', 'ref', v_other->>'ref', 'choice', 'keep', 'reason', 'Fixture: curator'));
    raise exception 'F7: a Curator made a rank-4 choice';
  exception when others then if sqlerrm not like '%your role cannot make this choice%' then raise; end if; end;
  perform set_config('fx.rank', '2', false);
  begin perform public.admin_layer4_inbox('summary', '{}'); raise exception 'F7: rank 2 read the Inbox';
  exception when others then if sqlerrm not like '%Curator role or above required%' then raise; end if; end;
  perform set_config('fx.rank', '6', false);
  raise notice 'F7 ok: a decision writes its one audit row and closes the item, counts follow at once (summary, kind, university), a decided item is not decided again, ranks unchanged';
end $$;

-- F8 kind hooks: a registered kind (human input needed) and an AER extension plug in through the register
create table fx.interventions(id bigserial primary key, provider_id uuid, created_at timestamptz, subject text, missing_fact text, status text default 'open');
insert into fx.interventions(provider_id, created_at, subject, missing_fact)
select ('10000000-0000-0000-0000-' || lpad((1 + g % 50)::text, 12, '0'))::uuid, timestamptz '2026-11-03 00:00+00' + (g % 30) * interval '1 hour', 'Intervention ' || g, 'fee year'
  from generate_series(1, 300) g;
create table fx.recovery_calls(ref text, choice text, value text, reason text);
create function security.layer4_intervention_kind_v1() returns jsonb language sql stable as $f$
  select '{"label": "Human input needed", "order": 20, "choices": [{"key": "supply", "label": "Supply the fact", "input": "text", "returns": "The work resumes"},
           {"key": "close", "label": "Close", "rank": 5, "returns": "Closed"}]}'::jsonb $f$;
create function security.layer4_intervention_inbox_counts_v1() returns jsonb language sql stable as $f$
  select jsonb_build_object('kind', 'intervention', 'n', (select count(*) from fx.interventions where status = 'open'), 'oldest', (select min(created_at) from fx.interventions where status = 'open'),
         'late', 0, 'by_provider', (select jsonb_agg(jsonb_build_object('provider_id', provider_id, 'n', n, 'oldest', o)) from (select provider_id, count(*) n, min(created_at) o from fx.interventions where status = 'open' group by 1) x)) $f$;
create function security.layer4_intervention_inbox_page_v1(p_args jsonb) returns jsonb language sql stable as $f$
  with x as (select * from fx.interventions i where i.status = 'open' and (p_args->>'provider_id' is null or i.provider_id = (p_args->>'provider_id')::uuid))
  select jsonb_build_object('kind', 'intervention',
    'before', (select count(*) from x where p_args ? 'after_ref' and (x.created_at, x.id) <= ((p_args->>'after_at')::timestamptz, (p_args->>'after_ref')::bigint)),
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'intervention', 'ref', z.id::text, 'provider_id', z.provider_id, 'provider', null, 'subject', z.subject, 'why', 'Needs a fact',
             'suggestion', null, 'created_at', z.created_at, 'late', false, 'missing_fact', z.missing_fact) order by z.created_at, z.id)
      from (select * from x where not (p_args ? 'after_ref') or (x.created_at, x.id) > ((p_args->>'after_at')::timestamptz, (p_args->>'after_ref')::bigint)
             order by created_at, id limit (p_args->>'limit')::int) z), '[]'::jsonb)) $f$;
create function security.layer4_intervention_inbox_detail_v1(p_ref text) returns jsonb language sql stable as $f$
  select jsonb_build_object('sections', jsonb_build_array(jsonb_build_object('key', 'issue', 'title', 'Issue', 'body', 'Missing ' || i.missing_fact)),
         'actions', '[{"key": "supply", "allowed": true}, {"key": "close", "allowed": false}]'::jsonb) from fx.interventions i where i.id = p_ref::bigint $f$;
create function security.layer4_intervention_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb language plpgsql as $f$
declare v bigint;
begin
  if p_choice = 'supply' and coalesce(p_value, '') = '' then return jsonb_build_object('ok', false, 'request', 'Enter the fee year as printed on the page'); end if;
  update fx.interventions set status = 'resolved' where id = p_ref::bigint;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('layer4', 'inbox_decide', 'intervention:' || p_ref, jsonb_build_object('kind', 'intervention', 'choice', p_choice), auth.uid()) returning id into v;
  return jsonb_build_object('ok', true, 'returns', 'The work resumes', 'result', jsonb_build_object('resumed', true), 'event_id', v);
end $f$;
create function security.layer4_aer_recovery_kind_v1() returns jsonb language sql stable as $f$
  select '{"choices": [{"key": "reread_stored", "label": "Re-read from stored evidence", "returns": "Read again from the stored copy"},
     {"key": "request_evidence", "label": "Request official evidence", "input": "text", "returns": "Asked"}, {"key": "ai_analyse", "label": "Ask AI to analyse the failure", "returns": "Analysed"},
     {"key": "open_intervention", "label": "Open human input", "input": "text", "returns": "Opened"}, {"key": "approve", "label": "Approve anyway", "returns": "must never show"}]}'::jsonb $f$;
create function security.layer4_aer_recovery_detail_v1(p_ref text) returns jsonb language sql stable as $f$
  select jsonb_build_object('sections', jsonb_build_array(jsonb_build_object('key', 'recovery', 'title', 'Recovery', 'body', jsonb_build_object('Owner', 'reader', 'Next attempt', 'tonight'))),
         'actions', '[{"key": "reread_stored", "allowed": true}, {"key": "ai_analyse", "allowed": false}]'::jsonb) $f$;
create function security.layer4_aer_recovery_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb language plpgsql as $f$
declare v bigint;
begin
  insert into fx.recovery_calls values (p_ref, p_choice, p_value, p_reason);
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('layer4', 'inbox_decide', 'aer_review:' || p_ref, jsonb_build_object('kind', 'aer_review', 'choice', p_choice), auth.uid()) returning id into v;
  return jsonb_build_object('ok', true, 'returns', 'Queued', 'event_id', v);
end $f$;

do $$
declare s jsonb; r jsonb; cur jsonb; v_last jsonb; v_n bigint; v_keys text[] := '{}'; e0 bigint; aer jsonb; v_ref text; v_prov text := '10000000-0000-0000-0000-000000000007'; v_exp bigint;
begin
  s := public.admin_layer4_inbox('summary', '{}');
  if s->'kinds'->'intervention'->>'label' <> 'Human input needed' or (s->'by_kind'->'intervention'->>'n')::int <> 300 then raise exception 'F8: intervention kind or count %', s->'by_kind'->'intervention'; end if;
  if (s->>'total')::bigint <> (select count(*) from security.layer4_inbox_items_v1()) + 300 then raise exception 'F8: total does not add the hook count'; end if;
  aer := s->'kinds'->'aer_review'->'choices';
  if (select array_agg(c->>'key' order by o) from jsonb_array_elements(aer) with ordinality x(c, o)) <> array['approve', 'approve_except', 'reject', 'reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention']
     or (select c->>'label' from jsonb_array_elements(aer) c where c->>'key' = 'approve') <> 'Approve all rows' then raise exception 'F8: AER choices %', aer; end if;
  if jsonb_array_length(s->'hooks_missing') <> 0 then raise exception 'F8: hooks missing %', s->'hooks_missing'; end if;
  -- a university with built-in and hook items: every item once, the hook kind after the built-in ones (order 20)
  cur := '{}'; v_n := 0; v_exp := (select count(*) from security.layer4_inbox_items_v1() i where i.provider_id = v_prov::uuid) + (select count(*) from fx.interventions where provider_id = v_prov::uuid and status = 'open');
  loop
    r := public.admin_layer4_inbox('items', jsonb_build_object('provider_id', v_prov, 'limit', 25) || cur);
    if (r->>'before')::bigint <> v_n or (r->>'total')::bigint <> v_exp then raise exception 'F8: before %/% total %/%', r->>'before', v_n, r->>'total', v_exp; end if;
    v_keys := v_keys || array(select x->>'kind' || ':' || (x->>'ref') from jsonb_array_elements(r->'items') x);
    v_n := v_n + jsonb_array_length(r->'items');
    exit when not (r->>'more')::boolean;
    v_last := r->'items'->-1; cur := jsonb_build_object('after_o', v_last->'o', 'after_at', v_last->'created_at', 'after_kind', v_last->'kind', 'after_ref', v_last->'ref');
  end loop;
  if v_n <> v_exp or (select count(distinct k) from unnest(v_keys) k) <> v_n then raise exception 'F8: university pages % of % (distinct %)', v_n, v_exp, (select count(distinct k) from unnest(v_keys) k); end if;
  if v_keys[array_length(v_keys, 1)] not like 'intervention:%' then raise exception 'F8: hook items are not last in kind order'; end if;
  -- the university list counts the hook kind with the rest
  r := public.admin_layer4_inbox('universities', '{"kind": "intervention", "limit": 100}');
  if (r->>'total')::int <> 50 or (select sum((x->>'n')::int) from jsonb_array_elements(r->'items') x) <> 300 then raise exception 'F8: universities by hook kind %', r->>'total'; end if;
  -- by kind: every intervention exactly once
  cur := '{}'; v_n := 0; v_keys := '{}';
  loop
    r := public.admin_layer4_inbox('items', jsonb_build_object('kind', 'intervention', 'limit', 25) || cur);
    v_keys := v_keys || array(select x->>'ref' from jsonb_array_elements(r->'items') x); v_n := v_n + jsonb_array_length(r->'items');
    exit when not (r->>'more')::boolean;
    v_last := r->'items'->-1; cur := jsonb_build_object('after_o', v_last->'o', 'after_at', v_last->'created_at', 'after_kind', v_last->'kind', 'after_ref', v_last->'ref');
  end loop;
  if v_n <> 300 or (select count(distinct k) from unnest(v_keys) k) <> 300 then raise exception 'F8: intervention kind pages %', v_n; end if;
  -- lazy detail: the hook's sections and allowed actions; an AER item gets its recovery detail and its stored-copy facts
  v_ref := (select id::text from fx.interventions where provider_id = v_prov::uuid order by id limit 1);
  aer := (public.admin_layer4_inbox('items', jsonb_build_object('provider_id', v_prov, 'kind', 'aer_review', 'limit', 1)))->'items'->0;
  r := public.admin_layer4_inbox('detail', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('kind', 'intervention', 'ref', v_ref), jsonb_build_object('kind', 'aer_review', 'ref', aer->>'ref'))));
  if (select x->'hook_detail'->'sections'->0->>'title' from jsonb_array_elements(r->'items') x where x->>'kind' = 'intervention') <> 'Issue'
     or (select x->'hook_detail'->'sections'->0->>'title' from jsonb_array_elements(r->'items') x where x->>'kind' = 'aer_review') <> 'Recovery'
     or (select x->'detail'->>'field_code' from jsonb_array_elements(r->'items') x where x->>'kind' = 'aer_review') <> 'course_entry_first_read' then raise exception 'F8: detail %', r; end if;
  -- decisions: the hook decides and audits itself (one row), ok false comes back as a request; a recovery choice goes to the recovery hook
  e0 := (select count(*) from pipeline.admin_control_events);
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'intervention', 'ref', v_ref, 'choice', 'supply', 'reason', 'Fixture'));
  if (r->>'ok')::boolean or r->>'request' <> 'Enter the fee year as printed on the page' or (select count(*) from pipeline.admin_control_events) <> e0 then raise exception 'F8: ok false %', r; end if;
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'intervention', 'ref', v_ref, 'choice', 'supply', 'value', '2026', 'reason', 'Fixture: the page prints 2026'));
  if not (r->>'ok')::boolean or (select count(*) from pipeline.admin_control_events) <> e0 + 1 then raise exception 'F8: hook decision % wrote % rows', r, (select count(*) from pipeline.admin_control_events) - e0; end if;
  perform set_config('fx.rank', '4', false);
  begin perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'intervention', 'ref', v_ref, 'choice', 'close', 'reason', 'Fixture')); raise exception 'F8: rank 4 closed';
  exception when others then if sqlerrm not like '%your role cannot make this choice%' then raise; end if; end;
  perform set_config('fx.rank', '6', false);
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'aer_review', 'ref', aer->>'ref', 'choice', 'reread_stored', 'reason', 'Fixture: dropped rows'));
  if not (r->>'ok')::boolean or not exists (select 1 from fx.recovery_calls where ref = aer->>'ref' and choice = 'reread_stored') then raise exception 'F8: recovery decision %', r; end if;
  -- the built-in approve never reaches the recovery hook (its colliding "approve" choice was left out)
  begin perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'aer_review', 'ref', aer->>'ref', 'choice', 'approve', 'reason', 'Fixture: approve')); exception when others then null; end;
  if exists (select 1 from fx.recovery_calls where choice = 'approve') then raise exception 'F8: approve reached the recovery hook'; end if;
  raise notice 'F8 ok: a registered kind counts, pages (each of 300 once, after the built-in kinds), shows lazy detail and decides through its own function (one audit row); AER recovery choices are added after the built-in ones and go to their hook';
end $$;

-- F9 a hook that fails or is switched off never breaks the Inbox
create function security.fx_broken_kind_v1() returns jsonb language sql as $f$ select '{"label": "Broken", "order": 21, "choices": [{"key": "x", "label": "X"}]}'::jsonb $f$;
create function security.fx_broken_counts_v1() returns jsonb language plpgsql as $f$ begin raise exception 'broken counts'; end $f$;
create function security.fx_broken_page_v1(jsonb) returns jsonb language plpgsql as $f$ begin raise exception 'broken page'; end $f$;
create function security.fx_broken_decide_v1(text, text, text, text) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create function public.fx_outside_kind_v1() returns jsonb language sql as $f$ select '{"label": "Outside", "order": 22, "choices": []}'::jsonb $f$;
insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, decide_fn) values
 ('broken', 'kind', 'security.fx_broken_kind_v1()', 'security.fx_broken_counts_v1()', 'security.fx_broken_page_v1(jsonb)', 'security.fx_broken_decide_v1(text,text,text,text)'),
 ('outside', 'kind', 'public.fx_outside_kind_v1()', 'public.fx_outside_kind_v1()', 'public.fx_outside_kind_v1()', 'public.fx_outside_kind_v1()'),
 ('course_link', 'kind', 'security.fx_broken_kind_v1()', 'security.fx_broken_counts_v1()', 'security.fx_broken_page_v1(jsonb)', 'security.fx_broken_decide_v1(text,text,text,text)');
do $$
declare s jsonb; r jsonb;
begin
  s := public.admin_layer4_inbox('summary', '{}');
  if not exists (select 1 from jsonb_array_elements(s->'hooks_failed') x where x->>'id' = 'broken:kind' and x->>'error' = 'broken counts') then raise exception 'F9: broken counts not named %', s->'hooks_failed'; end if;
  if not exists (select 1 from jsonb_array_elements(s->'hooks_failed') x where x->>'id' = 'course_link:kind') or s->'kinds'->'course_link' <> security.layer4_inbox_kinds_v1()->'course_link' then raise exception 'F9: a hook replaced a built-in kind'; end if;
  if s->'kinds' ? 'outside' or not exists (select 1 from jsonb_array_elements(s->'hooks_missing') x where x->>'id' = 'outside:kind') then raise exception 'F9: a function outside schema security was used'; end if;
  r := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "limit": 25}');
  if jsonb_array_length(r->'items') <> 25 then raise exception 'F9: a failing page broke the items'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'layer4.inbox_hooks_on';
  s := public.admin_layer4_inbox('summary', '{}');
  if s->'kinds' <> security.layer4_inbox_kinds_v1() or s->'by_kind' ? 'intervention' then raise exception 'F9: hooks off still shows hooks'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'layer4.inbox_hooks_on';
  raise notice 'F9 ok: a failing hook is named and left out, a hook cannot replace a built-in kind or use a function outside schema security, the switch turns hooks off';
end $$;

select 'timings' x, jsonb_object_agg(at_stage || ':' || action, ms) from fx.timing;
