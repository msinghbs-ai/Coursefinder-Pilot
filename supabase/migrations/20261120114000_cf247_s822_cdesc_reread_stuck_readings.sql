-- CF-247 s822 (Platform Admin 20 Nov 2026 10:39 AEDT directive, chat S1-Courses: raise course descriptions from the pages already stored, $0 extra crawl spend,
-- keep the quote, length and originality rules). Data only: three groups of stuck course description readings are marked reread:, which the live gap picker
-- (security.enrich_course_text_gaps_v1, unchanged) already reads again with the released prompt. The 12 Nov 2026 re-read (733 readings, US$1.1) is the precedent.
--
-- Measured live (20 Nov 2026 10:50 to 11:05 AEDT, rolled-back dry-run route, read only). 20,721 active courses hold no description. 7,916 of them have a stored
-- page the picker accepts (bound or ambiguous, read, with an identity basis); 7,306 of those wait in a skipped reading that the picker does not offer again:
--   2,290  insufficient_verified_course_facts, judged by prompt v1, v2 or v3, which needed 3 or more verified sentences; v4 needs 1 to 2. Their stored pages are
--          not thin: median 20.7 KB of page text, against 18.9 KB for the 523 courses v4 filled in the last 24 hours (only 102 of the 2,290 are under 3 KB).
--   1,895  "no proven course page", although the course now has a page with an identity basis: the reading was skipped before the page was proven and then
--          waits out the 60 day recheck (gaps.recheck_days).
--     227  "the page does not state it", made by the first, general reader before the description had its own call (prompt v1 and later).
--   Not touched: 2,730 held by v4 under the originality, length and sentence rules (policy settings the Platform Admin owns), 159 judged insufficient by v4 itself,
--   and 5 others. A course with a manual lock, a hidden provider or a description already held is never marked (the picker applies the same tests).
-- Cost: 4,400 reads at the measured US$0.00044 is about US$1.9, inside the US$14 a day ceiling and the 8,000 a day gap queue cap
--   (enrich.course_text_items_per_day). Firecrawl: none (stored pages only). Every new reading goes through the same rule chain as any other: nothing here admits
--   or publishes a description, and a reading that fails a rule stays held exactly as before.
-- What changes: pipeline.field_enrich_items.reason of the latest description reading of each such course becomes 'reread: s822 <prompt>; was: <old reason>'.
--   Nothing else: no function, setting, table, job or catalogue row. One audit row in pipeline.admin_control_events (area course_description, action reread_mark).
-- G1: no job. G2: no operational value in code (the pace and the spend are the existing settings; 300 is the reason column's text limit, marked fixed).
-- G3: the consumer API baseline check is read before and after (75 functions, 48 relations); no consumer object is touched. catalogue.courses is not written.
-- Parity before writing (read live 20 Nov 2026 10:50 AEDT): head 20261120110000, 2,208 history rows; no open Pilot pull request carries a migration above it except
--   S1-Build's 20261120112000 (s815) and S1-RM-Design's s819 files, which renumber above this file or below it on their own rebase.
-- Replaces: nothing.
-- Retires: nothing.
-- Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: one data update over about 4,400 readings (the live read of the same set takes about 25 s)

do $m$
declare
  v_ver text := security.cdesc_prompt_version_v1();
  v_api jsonb := security.consumer_api_check_v1();
  v_desc_before int; v_desc_after int; v_marked int; v_by jsonb;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v_api;
  end if;
  select count(*) into v_desc_before from catalogue.courses where nullif(btrim(description), '') is not null;

  with miss as (
    select c.id cid, c.provider_id pid from catalogue.courses c
     where c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
       -- the picker's own test of a page it will read from: bound or ambiguous, read, stored, with an identity basis
       and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                     and g.read_status = 'read' and g.identity_basis is not null)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('description', 'course_description', 'all'))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)),
  last as (
    select distinct on (e.course_id) e.id, e.course_id cid, e.state, e.reason,
           coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') pv
      from pipeline.field_enrich_items e where e.field = 'description' and e.course_id in (select cid from miss)
     order by e.course_id, e.id desc),
  pick as (
    select l.id,
           case when l.reason like 'insufficient\_verified\_course\_facts%' then 'insufficient_older_prompt'
                when l.reason like 'no proven course page%' then 'no_proven_page_now_proven'
                else 'page_does_not_state_older_reader' end cls
      from last l
     where l.state = 'skipped'
       and ((l.reason like 'insufficient\_verified\_course\_facts%' and l.pv <> v_ver)
         or (l.reason like 'the page does not state it%' and l.pv <> v_ver)
         or l.reason like 'no proven course page%')),
  upd as (
    update pipeline.field_enrich_items e
       set reason = left('reread: s822 ' || v_ver || '; was: ' || coalesce(e.reason, ''), 300),  -- fixed: the reason text limit used by every earlier reread: mark
           updated_at = now()
      from pick p where e.id = p.id and e.state = 'skipped'
    returning p.cls)
  select coalesce(jsonb_object_agg(cls, n), '{}'::jsonb) into v_by from (select cls, count(*) n from upd group by cls) q;
  v_marked := (select coalesce(sum(value::int), 0) from jsonb_each_text(v_by));

  select count(*) into v_desc_after from catalogue.courses where nullif(btrim(description), '') is not null;
  if v_desc_after is distinct from v_desc_before then raise exception 'post-check: catalogue.courses descriptions changed (% to %)', v_desc_before, v_desc_after; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('course_description', 'reread_mark', 's822', jsonb_build_object('prompt', v_ver, 'by_class', v_by, 'marked', v_marked,
          'directive', 'Platform Admin 20 Nov 2026 10:39 AEDT, S1-Courses'), null);
  raise notice 's822: readings marked reread: % (%)', v_marked, v_by;
end $m$;
