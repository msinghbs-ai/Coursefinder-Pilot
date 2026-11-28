-- CF-247 s1363 (S2-RM-Design; Platform Admin 28 Nov 2026 22:03 AEDT: "take ownership of the binding performance fix ... validate per-provider
-- transaction isolation and reuse of existing page checks before implementation"; PC-20261128-2121-BIND-EXECUTION-RECOVERY; DR-19).
-- Incident: coverage-bind (cron job 47) failed every run from 28 Nov 14:25 AEDT (statement timeout, 120 s); 37 universities re-mapped at 14:21
-- to 14:34 AEDT waited, and the same oldest 30 were retried every 5 minutes because one timeout rolled back the whole tick.
-- Cause (measured live, read-only): security.coverage_bind_v2 wrote with INSERT ... ON CONFLICT (course_id) DO UPDATE. PostgreSQL fires BEFORE
-- INSERT row triggers for every proposed row before the conflict is found, and the E16 guard (coverage_page_refused_host, 2 Nov 2026) treats an
-- INSERT as new evidence, so security.course_page_check_v1 ran on every proposed row, about 0.3 s each: university 9d22a19e alone proposes 507
-- rows. The 29 Oct cycle predates the guard, so 28 Nov was the first to meet it; one timeout rolled back every university, so no run progressed.
-- The same check also ran on rows the ON CONFLICT WHERE never updates (a protected basis, a code-proven read page, or a null result of the W31
-- clause), and when it refused, binding_refusal_route_v1 wrote a rejection and could raise a Layer 4 item for a course whose row was not changed.
-- Fix (no timeout change, no new job, queue, schedule, table or function; every identity check that decides a written row still runs):
--  1. coverage_bind_v2 sorts the rows it would write, using the same SET and the same ON CONFLICT WHERE as before:
--     a. 'skip': a row the ON CONFLICT WHERE would not update (a no-op before); it is not proposed, so only its spurious check is removed;
--     b. 'same': a course whose page is unchanged and was already written in this mapping cycle (bound_at at or after the university's mapped_at),
--        so it passed the identity check this cycle; that check is reused and the row is updated by UPDATE (no new check);
--     c. 'write': everything else, including an unchanged page not yet re-checked this cycle, a changed page and a new course, goes through the
--        original INSERT ... ON CONFLICT DO UPDATE, unchanged, so the E16 check, the CRICOS guard and the refusal route run exactly as before;
--        written in chunks of binding.bind_chunk_rows.
--     When the run's time budget is spent between chunks, the chunks written are kept, and the release of old bindings and bound_at wait for the
--     next run, which resumes where it stopped (rows written are now 'same'). Each page is checked once per mapping cycle, not once per retry.
--  2. coverage_bind_tick_v1 isolates each university: one subtransaction each (an error parks that university, recorded in the result and the
--     log, and the others continue), and no university starts once binding.tick_budget_seconds has passed.
-- G1: no job. G2: binding.tick_budget_seconds and binding.bind_chunk_rows are settings. G3: not the consumer API (75/48 asserted). Locks and
-- cron asserted. Both live definitions are checked by md5 before they are replaced. Nothing dropped.
-- Replaces: the single INSERT ... ON CONFLICT write of security.coverage_bind_v2, and the all-or-nothing loop of security.coverage_bind_tick_v1.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'binding.tick_budget_seconds', 'Course-page binding: time budget per run',
  'The site-map binder (coverage-bind) starts no further university, and writes no further chunk of pages, once a run has used this many seconds; the rest continue in the next run. Keep it well under the database statement time-out so a run always finishes and keeps its work.',
  'number', '50'::jsonb, 10, 90, 'seconds', 191, 'Job sizes', 'security.coverage_bind_tick_v1, security.coverage_bind_v2 (s1363)', 'CF-247 s1363 binding performance fix (job 47)'),
 ('pipeline', 'binding.bind_chunk_rows', 'Course-page binding: pages written at a time',
  'Course pages the binder re-checks are written in chunks of this size, so it can stop between chunks when its time budget is spent and keep what it wrote; the next run resumes where it stopped. Each page is identity-checked when written, once per mapping cycle.',
  'number', '15'::jsonb, 1, 200, 'pages', 192, 'Job sizes', 'security.coverage_bind_v2 (s1363)', 'CF-247 s1363 binding performance fix (job 47)')
on conflict (toolset_key, key) do nothing;

do $e$
declare
  v jsonb := security.consumer_api_check_v1();
  v_locks bigint := (select count(*) from pipeline.manual_locks); v_jobs bigint := (select count(*) from cron.job where active);
  v_bind text := md5(pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure));
  v_tick text := md5(pg_get_functiondef('security.coverage_bind_tick_v1(integer)'::regprocedure));
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  -- the definitions this change was written against (live 28 Nov 2026 22:20 AEDT); a rerun after it applied is allowed
  if v_bind <> '56168ae1c9f753ed7dde4092d0c5e16c' and position('s1363' in pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure)) = 0 then
    raise exception 'guard: security.coverage_bind_v2 changed since it was read (md5 %)', v_bind;
  end if;
  if v_tick <> 'cb0496b37152c2b819918f1949738c2a' and position('s1363' in pg_get_functiondef('security.coverage_bind_tick_v1(integer)'::regprocedure)) = 0 then
    raise exception 'guard: security.coverage_bind_tick_v1 changed since it was read (md5 %)', v_tick;
  end if;
  perform set_config('cf.s1363_locks', v_locks::text, false);  -- read by the post-check below (separate statement)
  perform set_config('cf.s1363_jobs', v_jobs::text, false);
end $e$;

create or replace function security.coverage_bind_v2(p_provider_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security'
as $function$
declare v_bound int; v_amb int; v_ids uuid[]; v_partial boolean := false; v_same int := 0; v_changed int := 0;
        -- s1363: this mapping cycle; a row written since then has passed the identity check in this cycle
        v_mapped timestamptz := (select d.mapped_at from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id);
        -- s1363: the run's time budget, set by coverage_bind_tick_v1 for this transaction (none when called on its own)
        v_deadline timestamptz := nullif(current_setting('cf.coverage_bind_deadline', true), '')::timestamptz;
        v_chunk int := greatest(1, security.pipeline_num_v1('binding.bind_chunk_rows', 15)::int);
        v_code_basis text := case security.coverage_country(p_provider_id) when 'AU' then 'cricos_code' when 'NZ' then 'nzqa_code' else 'adapter_code' end;
begin
  drop table if exists _cb_c, _cb_u, _cb_s, _cb_best, _cb_w;
  create temp table _cb_c on commit drop as
    select co.id course_id, lower(co.course_code) code, security.coverage_text_tokens(co.canonical_title) tok
      from catalogue.courses co where co.provider_id=p_provider_id and co.lifecycle_status='active';
  create temp table _cb_u on commit drop as
    select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
      from pipeline.coverage_provider_urls where provider_id=p_provider_id
       and security.site_host_v1(url) not in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id)  -- s1196: the site-map binder never binds a retired host
       and url !~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|pathways?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|research|contact|faqs?)(/|$)';
  create temp table _cb_s on commit drop as
    with ct as (select course_id, cardinality(tok) nc, t from _cb_c, unnest(tok) t),
         ut as (select url, 's' k, ns n, t from _cb_u, unnest(tokens) t union all select url, 't', nt, t from _cb_u, unnest(title_tokens) t),
         m as (select ct.course_id, ut.url, ut.k, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1,2,3)
    select course_id, url, max(2.0*hits/nullif(nc+nu,0)) sc, false by_code from m group by 1,2
    union all
    select c.course_id, u.url, 1.0, true from _cb_c c join _cb_u u
      on c.code is not null and length(c.code)>=6 and (position(c.code in lower(u.url))>0 or position(c.code in lower(coalesce(u.title,'')))>0);
  create temp table _cb_best on commit drop as
    with s as (select course_id, url, max(sc) sc, bool_or(by_code) by_code from _cb_s group by 1,2),
         rc as (select *, row_number() over (partition by course_id order by sc desc, length(url)) rk_c,
                          lead(sc) over (partition by course_id order by sc desc, length(url)) nxt_c,
                          row_number() over (partition by url order by sc desc) rk_u,
                          lead(sc) over (partition by url order by sc desc) nxt_u from s)
    select course_id, url, sc, coalesce(nxt_c,0) nxt, by_code,
           by_code or (sc>=0.8 and sc-coalesce(nxt_c,0)>=0.1 and rk_u=1 and sc-coalesce(nxt_u,0)>=0.1) or (sc>=0.999 and coalesce(nxt_c,0)<0.999 and rk_u=1 and coalesce(nxt_u,0)<0.999) mutual
      from rc where rk_c=1 and sc>=0.6;
  -- s1363: the rows to write (refused pages skipped as before: S1), each with the row the course already has.
  --   kind 'skip'    a row the ON CONFLICT WHERE would not update (a no-op before; only its spurious BEFORE INSERT check is removed);
  --   kind 'same'    the same page, bound or ambiguous, already written in this mapping cycle: its check is reused, written by UPDATE;
  --   kind 'write'   everything else (also an unchanged page not yet re-checked this cycle): the original INSERT ... ON CONFLICT, in chunks.
  create temp table _cb_w on commit drop as
    select b.course_id, b.url, round(b.sc,3) score, round(b.nxt,3) runner_up,
           case when b.by_code then v_code_basis else 'title_match' end basis,
           case when b.mutual then 'bound' else 'ambiguous' end status,
           case
             when p.course_id is null then 'write'
             -- exactly the ON CONFLICT WHERE below; a null there means no update, so it is a skip here too
             when not coalesce((p.status not in ('mismatch') or p.url is distinct from b.url)
                       and coalesce(p.basis,'') not in ('cricos_search','title_search','manual','ai_match')
                       and not (p.read_status = 'read'
                                and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')
                                and not security.page_refused_v1(p.course_id, p.url)), false) then 'skip'
             when p.url is not distinct from b.url and p.status in ('bound','ambiguous') and p.bound_at >= v_mapped then 'same'
             else 'write'
           end kind,
           false done
      from _cb_best b left join pipeline.coverage_course_pages p on p.course_id = b.course_id
     where not security.page_refused_v1(b.course_id, b.url);  -- S1: the site-map binder skips refused pages
  -- a. pages already checked this cycle: the same SET and WHERE as the ON CONFLICT update (url is set to itself so the same triggers fire)
  update pipeline.coverage_course_pages p set url=w.url, score=w.score, runner_up=w.runner_up, basis=w.basis, status=w.status, bound_at=now()
    from _cb_w w
   where w.kind = 'same' and p.course_id = w.course_id and p.url is not distinct from w.url
     and (p.status not in ('mismatch') or p.url is distinct from w.url)
     and coalesce(p.basis,'') not in ('cricos_search','title_search','manual','ai_match')
     -- W31 (30 Oct 2026): a page the reader has proved with a code or manual proof is never re-scored on title tokens (unless refused)
     and not (p.read_status = 'read'
              and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')
              and not security.page_refused_v1(p.course_id, p.url));
  get diagnostics v_same = row_count;
  -- b. every other row: the original write, unchanged, a chunk at a time
  loop
    select array_agg(course_id order by course_id) into v_ids
      from (select course_id from _cb_w where kind = 'write' and not done order by course_id limit v_chunk) z;
    exit when v_ids is null;
    if v_deadline is not null and clock_timestamp() >= v_deadline then v_partial := true; exit; end if;
    insert into pipeline.coverage_course_pages(course_id,provider_id,url,score,runner_up,basis,status,bound_at,next_read_at)
    select course_id, p_provider_id, url, score, runner_up, basis, status, now(), now()
      from _cb_w where course_id = any(v_ids)
    on conflict (course_id) do update set url=excluded.url, score=excluded.score, runner_up=excluded.runner_up, basis=excluded.basis,
           status=excluded.status, bound_at=now(),
           read_status=case when pipeline.coverage_course_pages.url is distinct from excluded.url then null else pipeline.coverage_course_pages.read_status end,
           next_read_at=case when pipeline.coverage_course_pages.url is distinct from excluded.url then now() else pipeline.coverage_course_pages.next_read_at end
     where (pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url)
       and coalesce(pipeline.coverage_course_pages.basis,'') not in ('cricos_search','title_search','manual','ai_match')
       -- W31 (30 Oct 2026): a page the reader has proved with a code or manual proof is never re-scored on title tokens (unless refused)
       and not (pipeline.coverage_course_pages.read_status = 'read'
                and pipeline.coverage_course_pages.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')
                and not security.page_refused_v1(pipeline.coverage_course_pages.course_id, pipeline.coverage_course_pages.url));
    v_changed := v_changed + cardinality(v_ids);
    update _cb_w set done = true where course_id = any(v_ids);
  end loop;
  if not v_partial then
    -- courses whose earlier binding no longer holds (page gone or no longer a mutual best) are released
    update pipeline.coverage_course_pages p set status='ambiguous'
     where p.provider_id=p_provider_id and p.status='bound' and coalesce(p.basis,'') in ('title_match','cricos_code','nzqa_code','adapter_code')  -- W31: rows this binder bound
       and not (p.read_status = 'read' and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual') and not security.page_refused_v1(p.course_id, p.url))
       and not exists(select 1 from _cb_best b where b.course_id=p.course_id and b.url=p.url and b.mutual);
    update pipeline.coverage_provider_discovery set bound_at=now() where provider_id=p_provider_id;
  end if;
  select count(*) filter (where status='bound'), count(*) filter (where status='ambiguous') into v_bound, v_amb from pipeline.coverage_course_pages where provider_id=p_provider_id;
  return jsonb_build_object('bound',v_bound,'ambiguous',v_amb,'unchanged_written',v_same,'changed_written',v_changed,
                            'changed_waiting',(select count(*) from _cb_w where kind = 'write' and not done),'partial',v_partial);
end $function$;

create or replace function security.coverage_bind_tick_v1(p_limit integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'pipeline', 'security'
as $function$
-- s1363: each university binds in its own subtransaction, and none starts after the run's time budget (binding.tick_budget_seconds)
declare r record; v jsonb:='[]'::jsonb; v_res jsonb;
        v_deadline timestamptz := clock_timestamp() + make_interval(secs => security.pipeline_num_v1('binding.tick_budget_seconds', 50));
begin
  perform set_config('cf.coverage_bind_deadline', v_deadline::text, true);
  for r in select provider_id from pipeline.coverage_provider_discovery
            where mapped_at is not null and (bound_at is null or bound_at<mapped_at)
              and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = coverage_provider_discovery.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
            order by mapped_at limit greatest(1,least(p_limit,50)) loop
    if clock_timestamp() >= v_deadline then
      v := v||jsonb_build_object('stopped','time budget spent; the rest continue in the next run');
      exit;
    end if;
    begin
      v_res := security.coverage_bind_v2(r.provider_id);
    exception when others then
      -- DR-19: isolate, record, continue; this university stays waiting and is tried again next run
      v_res := jsonb_build_object('parked', true, 'sqlstate', sqlstate, 'error', left(sqlerrm, 300));
      raise warning 'coverage_bind_v2 parked for %: % %', r.provider_id, sqlstate, left(sqlerrm, 300);
    end;
    v:=v||jsonb_build_object('provider_id',r.provider_id,'result',v_res);
  end loop;
  return v;
end $function$;

do $e$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks)::text <> current_setting('cf.s1363_locks') then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active)::text <> current_setting('cf.s1363_jobs') then raise exception 'post-check: active job count changed'; end if;
end $e$;
