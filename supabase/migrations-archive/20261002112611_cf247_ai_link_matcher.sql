-- CF-247 (2 Oct 2026). Platform Admin, 21:18: "Keep using firecrawl and ai models cascaded approach ... Outcome is maximum
-- data admitted till tomorrow morning for au, nz, Canada ... Get started on new model asap." (plan: CourseFinder discovery
-- and admission control plan, section 5).
-- Map-first AI link matcher. For a course with no verified page (no page found, or the page found failed the identity
-- check), the 25 closest addresses from its university's stored site map (pipeline.coverage_provider_urls; no Firecrawl
-- credit) are prepared here; coverage-sweep mode ai_match asks one pinned model (Qwen3 30B 2507, OpenRouter) to pick the
-- course's own page or none. The chosen address must be one of the prepared candidates. It is then read like any other
-- bound page and accepted only under the unchanged identity rule (course code on the page, or the exact title / NZQA
-- title and level as the heading); a page that fails goes back here for the next candidate (at most 3 attempts).
-- Nothing is admitted by the model; pages entered by hand are never replaced.

create table if not exists pipeline.coverage_ai_match (
  id bigint generated always as identity primary key,
  course_id uuid not null,
  provider_id uuid not null,
  attempt int not null default 1,
  state text not null default 'ready' check (state in ('ready', 'leased', 'chosen', 'none', 'no_candidates', 'error')),
  candidates jsonb not null default '[]'::jsonb,
  chosen_url text,
  answer jsonb,
  model text,
  cost_usd numeric,
  leased_until timestamptz,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists coverage_ai_match_state on pipeline.coverage_ai_match(state, id);
create index if not exists coverage_ai_match_course on pipeline.coverage_ai_match(course_id);
alter table pipeline.coverage_ai_match enable row level security;
revoke all on pipeline.coverage_ai_match from public, anon, authenticated;

-- 1. prepare candidates for the next universities (set-based, like coverage_bind_v2; runs from cron as postgres)
create or replace function security.coverage_ai_match_prepare_v1(p_providers int default 4, p_courses int default 300)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare r record; v jsonb := '[]'::jsonb; v_n int;
begin
  for r in
    with missing as (
      select co.provider_id, count(*) n
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.lifecycle_status = 'active'
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < 3
       group by 1)
    select m.provider_id, m.n from missing m
     where exists (select 1 from pipeline.coverage_provider_urls u where u.provider_id = m.provider_id)
     order by coalesce((select pp.rank from pipeline.provider_priority pp where pp.provider_id = m.provider_id), 100000), m.n desc
     limit greatest(1, least(p_providers, 20))
  loop
    insert into pipeline.coverage_ai_match(course_id, provider_id, attempt, state, candidates)
    with c as (
      select co.id course_id, lower(coalesce(co.course_code, '')) code,
             security.coverage_text_tokens(regexp_replace(co.canonical_title, '\(\s*level\s+\d+\s*\)', '', 'i')) tok,
             (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) prev
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.provider_id = r.provider_id and co.lifecycle_status = 'active'
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < 3
       order by coalesce(co.open_to_international, false) desc, co.id
       limit greatest(1, least(p_courses, 1000))),
    tried as (
      select p.course_id, p.url from pipeline.coverage_course_pages p join c using (course_id)
      union select q.course_id, q.chosen_url from pipeline.coverage_ai_match q join c using (course_id) where q.chosen_url is not null),
    u as (
      select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
        from pipeline.coverage_provider_urls where provider_id = r.provider_id
         and url !~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|contact|faqs?)(/|$)'
         and url !~* '\.(pdf|jpe?g|png|gif|svg|docx?|xlsx?|zip)(\?|$)'),
    ct as (select course_id, cardinality(tok) nc, t from c, unnest(tok) t),
    ut as (select url, ns n, t from u, unnest(tokens) t union all select url, nt, t from u, unnest(title_tokens) t),
    m as (select ct.course_id, ut.url, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1, 2),
    s as (select m.course_id, m.url, max(2.0 * hits / nullif(nc + nu, 0)) sc from m group by 1, 2
          union all
          select c.course_id, u.url, 2.0 from c join u on length(c.code) >= 6 and position(c.code in lower(u.url)) > 0),
    best as (select s.course_id, s.url, max(s.sc) sc from s where not exists (select 1 from tried t where t.course_id = s.course_id and t.url = s.url) group by 1, 2),
    rk as (select b.*, row_number() over (partition by b.course_id order by b.sc desc, length(b.url)) n from best b)
    select c.course_id, r.provider_id, c.prev + 1,
           case when count(rk.url) = 0 then 'no_candidates' else 'ready' end,
           coalesce(jsonb_agg(jsonb_build_object('url', rk.url, 'title', left(coalesce(u.title, ''), 160)) order by rk.n) filter (where rk.url is not null), '[]'::jsonb)
      from c left join rk on rk.course_id = c.course_id and rk.n <= 25
      left join u on u.url = rk.url
     group by c.course_id, c.prev;
    get diagnostics v_n = row_count;
    v := v || jsonb_build_object('provider_id', r.provider_id, 'prepared', v_n);
  end loop;
  return v;
end $f$;
revoke all on function security.coverage_ai_match_prepare_v1(int, int) from public, anon, authenticated;

-- 2. lease prepared items to the worker (service role only)
create or replace function public.svc_coverage_ai_match_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select id from pipeline.coverage_ai_match
     where state = 'ready' or (state = 'leased' and leased_until < now())
     order by (state = 'leased'), id limit greatest(1, least(coalesce(p_limit, 20), 80)) for update skip locked),
  upd as (update pipeline.coverage_ai_match q set state = 'leased', leased_until = now() + interval '10 minutes' from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'course_id', u.course_id, 'provider_id', u.provider_id, 'title', co.canonical_title,
           'code', case when co.course_code ~ '^[0-9a-f]{8}-' then null else co.course_code end,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id),
           'provider', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(u.provider_id),
           'candidates', u.candidates)), '[]'::jsonb)
    into v from upd u join catalogue.courses co on co.id = u.course_id join catalogue.providers pr on pr.id = u.provider_id;
  return v;
end $f$;
revoke all on function public.svc_coverage_ai_match_next(int) from public, anon, authenticated;
grant execute on function public.svc_coverage_ai_match_next(int) to service_role;

-- 3. record the model's choice; a chosen page must be one of the candidates and is bound for reading
create or replace function public.svc_coverage_ai_match_record(p_id bigint, p_url text, p_answer jsonb, p_model text, p_cost numeric, p_error text)
returns text language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare q pipeline.coverage_ai_match%rowtype; v_state text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.coverage_ai_match where id = p_id for update;
  if q.id is null or q.state <> 'leased' then return 'not_leased'; end if;
  if p_error is not null then
    v_state := 'error';
  elsif p_url is null then
    v_state := 'none';
  elsif not exists (select 1 from jsonb_array_elements(q.candidates) x where x->>'url' = p_url) then
    v_state := 'error'; p_answer := coalesce(p_answer, '{}'::jsonb) || jsonb_build_object('refused', 'chosen address is not one of the candidates');
  else
    v_state := 'chosen';
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, score, runner_up, basis, status, bound_at, next_read_at, read_attempts)
    values (q.course_id, q.provider_id, p_url, null, null, 'ai_match', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, score = null, runner_up = null, basis = 'ai_match', status = 'bound', bound_at = now(),
           next_read_at = now(), read_attempts = 0, read_status = null, identity_basis = null, leased_until = null
     where (pipeline.coverage_course_pages.status = 'mismatch' or pipeline.coverage_course_pages.basis = 'ai_match')
       and coalesce(pipeline.coverage_course_pages.basis, '') <> 'manual';
  end if;
  update pipeline.coverage_ai_match set state = v_state, chosen_url = case when v_state = 'chosen' then p_url end, answer = coalesce(p_answer, '{}'::jsonb) || case when p_error is not null then jsonb_build_object('error', left(p_error, 300)) else '{}'::jsonb end,
         model = p_model, cost_usd = p_cost, decided_at = now(), leased_until = null
   where id = p_id;
  return v_state;
end $f$;
revoke all on function public.svc_coverage_ai_match_record(bigint, text, jsonb, text, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_coverage_ai_match_record(bigint, text, jsonb, text, numeric, text) to service_role;

-- 4. the site-map binder leaves AI-matched pages alone (as it does pages found by search or entered by hand)
do $p$
declare v_src text;
begin
  select prosrc into v_src from pg_proc where oid = 'security.coverage_bind_v2(uuid)'::regprocedure;
  if md5(v_src) <> '312eb36ec442aff182a0c613b1c36578' then raise exception 'coverage_bind_v2 changed since it was read (md5 %)', md5(v_src); end if;
  if (length(v_src) - length(replace(v_src, $q$not in ('cricos_search','title_search','manual')$q$, ''))) / length($q$not in ('cricos_search','title_search','manual')$q$) <> 2 then
    raise exception 'coverage_bind_v2: expected two basis lists';
  end if;
  execute replace(pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure),
                  $q$not in ('cricos_search','title_search','manual')$q$, $q$not in ('cricos_search','title_search','manual','ai_match')$q$);
end $p$;

-- 5. schedule: candidates are prepared every 2 minutes (the worker's schedule is added once the worker is deployed)
select cron.schedule('coverage-ai-match-prepare', '*/2 * * * *', $$select security.coverage_ai_match_prepare_v1(4, 300)$$);
