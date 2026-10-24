-- CF-247 R2 (24 Oct 2026, v2.15.350). Throughput record section 3.3 (C-Q1), standing order audit → O10 → R2; Platform Admin O10 decision
-- 24 Oct 19:12 and approval 23:07 ("apply tranche 1 as part of the R2 release"). Record: admin repo
-- docs/platform/nz-enrichment-brief/2026-10-24-target-only-audit.md and 2026-10-23-platform-throughput-gap-schema.md section 3.3.
-- 1. search.daily_picked_cap (100, 10–2,000 courses a UTC day): the course search picker takes no more than this many courses a UTC day
--    (counted from the picker's own "sent" mark, the same count the per-mode ledger records as items). A person's running Find course
--    pages task is counted but not held by it (same on-demand rule as the search stop, setting search.person_task_bypass).
-- 2. search.stop_per_course_after (6, 3–20 distinct wrong pages): a course with that many distinct rejected pages (pipeline.page_rejections,
--    S1 negative evidence) is not searched again. The university-wide stop (search_stop_after) stays as the ceiling behind it.
-- 3. The stall cause names the cap (Task manager, watcher, gap causes read security.link_search_block_v1).
-- Ramp: 100 for the first ledger week; the Platform Admin raises it on the ledger's correct-page rate. Tranche 1 (25 named overrides,
-- PASTE-20261024-target-tranche-1-overrides.sql) is applied after this lands; its guard requires search.daily_picked_cap.
-- Replaces: nothing (public.svc_course_link_search_next and security.link_search_block_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'search.daily_picked_cap', 'Course search: courses a day', 'The course page search takes no more than this many courses a UTC day (11:00 Melbourne in summer). A person''s running Find course pages task is counted but not held. 100 for the first ledger week; raise it on the ledger''s correct-page rate.', 'number', '100'::jsonb, '10', '2000', 'courses a day', 779, 'Course page search', 'public.svc_course_link_search_next, security.link_search_block_v1', 'R2 (C-Q1), O10 approved 24 Oct 2026'),
 ('pipeline', 'search.stop_per_course_after', 'Course search: stop a course after', 'A course with this many different pages rejected as wrong (negative evidence) is not searched again; the university-wide stop stays behind it.', 'number', '6'::jsonb, '3', '20', 'wrong pages', 780, 'Course page search', 'public.svc_course_link_search_next', 'R2 (C-Q1), O10 approved 24 Oct 2026')
on conflict (toolset_key, key) do nothing;

create index if not exists course_link_search_sent_at_idx on pipeline.course_link_search (sent_at);

select pg_temp.edit_n('public.svc_course_link_search_next(integer)', '1e80c0641e6d73a2b7f756c45a7a9c5e', array[
  array[$o$declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;$o$,
        $n$declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
        v_daycap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_room int;
        v_course_stop int := security.pipeline_num_v1('search.stop_per_course_after', 6)::int;$n$],
  array[$o$  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);$o$,
        $n$  -- R2 (C-Q1): the day's picked-courses cap (UTC day); a person's running Find course pages task is counted but not held
  select v_daycap - count(*) into v_room from pipeline.course_link_search where sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');
  if v_room > 0 then v_lim := least(v_lim, v_room); end if;
  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);$n$],
  array[$o$       and (pv.focus or s.requested_at is not null)$o$,
        $n$       and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- R2: the daily cap
       and (select count(distinct r.url) from pipeline.page_rejections r where r.course_id = s.course_id) < v_course_stop  -- R2: per-course stop
       and (pv.focus or s.requested_at is not null)$n$]],
  array[1, 1, 1]);

select pg_temp.edit_n('security.link_search_block_v1(uuid,uuid[])', '8b891f7366267c1f3b4729bfa8f3cb5a', array[
  array[$o$  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;$o$,
        $n$  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;
  -- R2: the day's picked-courses cap (a person's running task is not held by it)
  if not (v_bypass and v_person) and (select count(*) from pipeline.course_link_search s where s.sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))
       >= security.pipeline_num_v1('search.daily_picked_cap', 100) then
    return jsonb_build_object('code', 'daily_cap', 'words', 'Today''s course search cap (' || security.pipeline_num_v1('search.daily_picked_cap', 100)::int || ' courses) is reached; searching resumes at 00:00 UTC', 'fix', 'Settings › Pipeline settings › Course search: courses a day');
  end if;$n$]],
  array[1]);

-- PASTE FILE — CF-247 target route, TRANCHE 1 (Platform Admin decision D1, 24 Oct 2026 19:23: staged (c)-then-(b))
-- Record: docs/platform/nz-enrichment-brief/2026-10-24-target-only-audit.md (thread, section 3). FOR REVIEW BEFORE APPLYING.
-- Applied by: the Platform Admin, Supabase SQL editor, project fxcwkweaxjtknorudmwp — AFTER R2 is live (the guard below checks).
--
-- What it does: adds one named override row per provider in pipeline.firecrawl_targets (included = true, reason, set_by, set_at) for the
-- 25 providers listed. The job firecrawl-targets includes them in the cache within a minute. Nothing else changes: the target rule's
-- excluded words and course minimums stay as they are for everyone else; no task is started; no row is re-queued.
-- How they search: through the standard search → AI page match path only — the daily picked cap (search.daily_picked_cap, R2), the
-- per-course stops, negative evidence (page_rejections) and the day's Firecrawl share. No Task manager bypass, no bulk shortcut: their
-- 581 already-queued searches (all person-requested) wait their turn like the re-opened 24 did.
--
-- Tranche (25, cap per decision): the 3 polytechnics among the 120 never evaluated, then the 22 largest PRIVATE providers by active
-- courses (ties by courses without a page). NOTE: the 12 other NZ institutes of technology / polytechnics (SIT, EIT, Otago Polytechnic,
-- Ara, Toi Ohomai, NMIT, Wintec, MIT, Unitec, NorthTec, Whitireia and WelTec, WITT) are ALREADY targets through existing override rows.
--
-- | #  | Provider (stable key)                                         | Kind        | Active | No page | Queued |
-- |----|---------------------------------------------------------------|-------------|--------|---------|--------|
-- |  1 | Universal College of Learning (UCOL) (nzqa:6009)               | Polytechnic |    115 |      22 |     74 |
-- |  2 | The Open Polytechnic of New Zealand (nzqa:6022)                | Polytechnic |     92 |      18 |     22 |
-- |  3 | Tai Poutini Polytechnic (nzqa:6024)                            | Polytechnic |     42 |      31 |     31 |
-- |  4 | New Zealand Management Academies (NZMA) (nzqa:8661)           | Private NZ  |     76 |      70 |     70 |
-- |  5 | Le Cordon Bleu Australia (cricos:02380m)                      | Private AU  |     69 |      52 |     53 |
-- |  6 | ICMS / Aspire Institute (cricos:01484m)                       | Private AU  |     65 |      30 |     30 |
-- |  7 | Yoobee Colleges (nzqa:9324)                                   | Private NZ  |     52 |      35 |     35 |
-- |  8 | New Zealand School of Education (NZSE) (nzqa:7647)            | Private NZ  |     42 |      18 |     19 |
-- |  9 | Academy of Interactive Technology (cricos:02155j)             | Private AU  |     41 |      31 |     31 |
-- | 10 | The Australian Institute of Music (cricos:00665c)             | Private AU  |     39 |       7 |     23 |
-- | 11 | AAPoly, AMI Education (cricos:02439g)                         | Private AU  |     37 |      26 |     27 |
-- | 12 | JMC Academy (cricos:01259j)                                   | Private AU  |     37 |       6 |      8 |
-- | 13 | Future Skills Academy (nzqa:7372)                             | Private NZ  |     36 |      21 |     21 |
-- | 14 | Kaplan Business School (cricos:02426b)                        | Private AU  |     34 |       3 |      6 |
-- | 15 | People Potential (nzqa:9964)                                  | Private NZ  |     32 |      19 |     19 |
-- | 16 | Whitecliffe Education (nzqa:8509)                             | Private NZ  |     32 |      11 |     11 |
-- | 17 | UTS College (cricos:00859d)                                   | Private AU  |     30 |       9 |      9 |
-- | 18 | Stanley College (cricos:03047e)                               | Private AU  |     27 |       5 |      5 |
-- | 19 | Australian College of Physical Education (cricos:01822j)      | Private AU  |     23 |       2 |      9 |
-- | 20 | Polytechnic Institute Australia (cricos:03535m)               | Private AU  |     21 |       6 |      6 |
-- | 21 | Kent Institute Australia (cricos:00161e)                      | Private AU  |     21 |       5 |      8 |
-- | 22 | National Trade Academy (nzqa:7402)                            | Private NZ  |     21 |      10 |     10 |
-- | 23 | Christian Heritage College (cricos:01016f)                    | Private AU  |     20 |       1 |      1 |
-- | 24 | UOW College Australia (cricos:02723d)                         | Private AU  |     20 |       9 |     10 |
-- | 25 | Bethlehem Tertiary Institute (nzqa:8694)                      | Private NZ  |     19 |      12 |     13 |
-- Totals: 581 queued searches (about 1,160 credits at 2 a search; at 100 a day, about six days alongside other work).
--
-- Left OUT of tranche 1 on purpose (candidates for a later tranche or (b)): public TAFEs (Holmesglen 43, Canberra Institute of Technology 39,
-- Box Hill 37, TasTAFE 34, Chisholm 32, Bendigo TAFE/Kangan 20) — not private providers; wānanga (Te Wānanga o Aotearoa 85, Te Whare Wānanga
-- o Awanuiārangi 52) — not PTEs; industry training organisations (Skills Active Te Mahi Ako 41, MITO 31).
--
-- Count guards: R2 live (setting search.daily_picked_cap exists); exactly 25 providers found by stable key, all published, active, with an
-- active search recipe, none already carrying an override row; exactly 25 rows inserted.

do $p$
declare
  v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- Platform Admin
  v_keys constant text[] := array['provider:nzqa:6009','provider:nzqa:6022','provider:nzqa:6024','provider:nzqa:8661','provider:cricos:02380m',
    'provider:cricos:01484m','provider:nzqa:9324','provider:nzqa:7647','provider:cricos:02155j','provider:cricos:00665c','provider:cricos:02439g',
    'provider:cricos:01259j','provider:nzqa:7372','provider:cricos:02426b','provider:nzqa:9964','provider:nzqa:8509','provider:cricos:00859d',
    'provider:cricos:03047e','provider:cricos:01822j','provider:cricos:03535m','provider:cricos:00161e','provider:nzqa:7402','provider:cricos:01016f',
    'provider:cricos:02723d','provider:nzqa:8694'];
  v_n int; v_ins int;
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'search.daily_picked_cap') then
    raise exception 'R2 is not live yet (no search.daily_picked_cap): apply this after R2 so the tranche searches under the 100-a-day cap';
  end if;
  select count(*) into v_n from catalogue.providers p
   where p.stable_key = any (v_keys) and p.publication_status = 'published' and p.lifecycle_status = 'active'
     and exists (select 1 from pipeline.course_link_recipes rc where rc.provider_id = p.id and rc.active)
     and not exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = p.id);
  if v_n <> 25 then raise exception 'count guard: expected 25 eligible providers without an override, found %', v_n; end if;
  insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at)
  select p.id, true, 'Tranche 1 (Platform Admin 24 Oct 2026 19:23, target route (c)-then-(b)): ' ||
         case when p.stable_key in ('provider:nzqa:6009','provider:nzqa:6022','provider:nzqa:6024') then 'polytechnic' else 'private provider, by active courses' end ||
         '; standard search path, daily cap and per-course stops', v_admin, now()
    from catalogue.providers p where p.stable_key = any (v_keys);
  get diagnostics v_ins = row_count;
  if v_ins <> 25 then raise exception 'count guard: inserted %, expected 25 (rolled back)', v_ins; end if;
  raise notice 'Tranche 1: % override rows added; firecrawl-targets includes them within a minute', v_ins;
end $p$;

do $t$ declare v jsonb; c uuid; p uuid; r jsonb := '{}'; tp uuid[] := array(select provider_id from pipeline.firecrawl_targets where reason like 'Tranche 1%');
begin
  perform security.firecrawl_targets_refresh_v1();
  r := r || jsonb_build_object('tranche_included', (select count(*) from pipeline.firecrawl_target_cache where included and provider_id = any(tp)));
  v := public.svc_course_link_search_next(50);
  r := r || jsonb_build_object('picked_at_cap', jsonb_array_length(v), 'block', security.link_search_block_v1(tp[1], null)->>'code');
  update pipeline.platform_toolset_settings set value = '2000'::jsonb where toolset_key='pipeline' and key='search.daily_picked_cap';
  select s.course_id, s.provider_id into c, p from pipeline.course_link_search s where s.state='queued' and s.provider_id = any(tp) order by s.requested_at limit 1;
  insert into pipeline.page_rejections(course_id, url, provider_id, source, reason, rejected_at) select c, 'https://example.invalid/'||g, p, 'dry run', 'dry run', now() from generate_series(1,6) g;
  v := public.svc_course_link_search_next(200);
  r := r || jsonb_build_object('picked_after_raise', jsonb_array_length(v), 'tranche_picked', (select count(*) from jsonb_array_elements(v) x where (x->>'provider_id')::uuid = any(tp)),
     'stopped_course_picked', exists (select 1 from jsonb_array_elements(v) x where x->>'course_id' = c::text),
     'tai_poutini_picked', (select count(*) from jsonb_array_elements(v) x where x->>'provider_id' = (select id::text from catalogue.providers where stable_key='provider:nzqa:6024')));
  raise exception 'DRYRUN OK %', r;
end $t$;
