-- noop
insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason) values ('pipeline','search.daily_picked_cap','dry','dry','number','100'::jsonb,'0','1000','searches',1,'Course page search','dry','dry run stand-in');
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

do $t$ begin perform security.firecrawl_targets_refresh_v1();
  raise exception 'DRYRUN OK %', (select jsonb_build_object('tranche_included', count(*) filter (where tc.included), 'tranche_rows', count(*)) from pipeline.firecrawl_target_cache tc join pipeline.firecrawl_targets t using (provider_id) where t.reason like 'Tranche 1%'); end $t$;
