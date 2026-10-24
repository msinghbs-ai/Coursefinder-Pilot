-- noop
-- PASTE FILE — CF-247 HOTFIX v2.15.342, decision D-stopped (Platform Admin 24 Oct 2026 13:55)
-- Applied by: the Platform Admin, in the Supabase SQL editor of project fxcwkweaxjtknorudmwp, AFTER v2.15.343 (hotfix 2: the credit check) is merged and live; v2.15.342 alone hands the rows to the search but every credit is refused.
-- Record: docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md (section 11).
--
-- What it does: re-opens the person-requested course page searches that the search-stop list held (1,549 rows at 24 universities on
-- 24 Oct 13:40) by starting ONE "Find course pages" task per university for exactly those courses, as the Platform Admin. A person's
-- task passes the stop (search.person_task_bypass), so the rows go to the search; each task shows Last forwarded / Blocked in the Task
-- manager. Budgets, the month cap and the day share still apply (about 2 credits a search; today's share is far above 3,100).
-- It does NOT resume the universities' automatic search, change any gate, or delete anything.
-- Interim handling until S1 (per-course stop + negative evidence) lands; S1 is the permanent fix.
--
-- Count guards: the hotfix must be live; the rows to re-open must be no more than 1,549 at no more than these 24 universities (fewer is
-- fine: some may have been searched since, e.g. by the Otago E2E task); a university that already has a waiting or running Find course
-- pages task is skipped and counted. An unpublished or archived university is skipped and named (a task cannot start there): on 24 Oct
-- that is Nova Institute of Technology (16 rows), so 1,533 rows at 23 universities are re-opened.

do $p$
declare
  v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- Platform Admin
  v_list constant uuid[] := array[
    '570ddbbd-f07e-4060-b52d-c5322dcdaa00','1b8f2f2f-d3d2-455e-a9fd-5a65744352ec','22657140-1cb0-4fa7-91df-90518ea8b35b','188103a5-1aba-4f99-bd3e-0416659086d3',
    'bac82321-ded7-4e10-a71d-b18f3ae4d1c7','27349414-019b-4c0b-a38d-db92aaaf5e68','014118a6-54ea-4f36-ba05-a363b73b7979','0e1532b8-de30-4761-87fe-460684608633',
    'ab12c7f8-e368-453d-9dfe-4ab8bd744829','2a97c91d-9340-49fa-a437-6c76ea01edd9','3f48840c-8038-42a0-805e-8f7974301b23','5d21e4d4-73b4-4ad6-b100-199264540e72',
    '9e46baf2-694b-4d79-889e-b956d144c930','131ef262-b6e4-40a3-b8bf-7e4d6098eba8','8e1adb6c-e069-43db-9584-bd054255e702','d3f9ed02-2cca-4370-8070-7e52f381d1ba',
    '72a15f12-f3ee-40d7-8edf-af648ee10e14','ef420a23-6e62-47d3-9ab0-fdc35ebe97a0','dce6f5a7-c912-4a07-b9c6-7cf230a0e13b','47c734fe-9c1d-403f-b7cc-c4c77ad742fd',
    'a886a995-0315-4c92-9a74-697a2d0e014f','719403bc-6957-4d21-af69-2b3b102df578','cffa9cab-0a3b-458b-8383-483ce622c9c3','fac03540-a412-4c76-a5ab-cd338d7760db']::uuid[];
  v_rows int; v_provs int; r record; v jsonb; v_started int := 0; v_courses int := 0; v_skipped int := 0; v_hidden text := ''; v_failed text := '';
begin
  if to_regprocedure('security.link_search_person_task_v1(uuid,uuid)') is null
     or coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'search.person_task_bypass'), 0) < 1 then
    raise exception 'v2.15.342 is not live (or search.person_task_bypass is off): merge PR #686 first';
  end if;
  if pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure) not like '%hotfix 2%' then
    raise exception 'v2.15.343 (hotfix 2) is not live: without it every search credit of these tasks is refused';
  end if;
  select count(*), count(distinct s.provider_id) into v_rows, v_provs
    from pipeline.course_link_search s
   where s.state = 'queued' and s.requested_at is not null and s.provider_id = any (v_list)
     and s.provider_id in (select x.provider_id from security.fc_search_stopped_v1() x);
  if v_rows > 1549 or v_provs > 24 then raise exception 'count guard: expected at most 1,549 rows at 24 universities, found % at %', v_rows, v_provs; end if;
  if v_rows = 0 then raise exception 'count guard: nothing left to re-open (0 rows)'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  for r in select s.provider_id, array_agg(s.course_id) ids
             from pipeline.course_link_search s
            where s.state = 'queued' and s.requested_at is not null and s.provider_id = any (v_list)
              and s.provider_id in (select x.provider_id from security.fc_search_stopped_v1() x)
            group by s.provider_id loop
    if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id) then
      v_hidden := v_hidden || (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = r.provider_id) || ' (' || cardinality(r.ids) || '); '; continue;
    end if;
    if exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running') and j.args->>'provider_id' = r.provider_id::text) then
      v_skipped := v_skipped + 1; continue;
    end if;
    begin
      v := public.admin_jobs('start', jsonb_build_object('kind', 'course_page_find',
             'args', jsonb_build_object('provider_id', r.provider_id, 'course_ids', to_jsonb(r.ids)),
             'reason', 'Hotfix D-stopped (24 Oct 2026): re-open the searches the stop list held'));
      v_started := v_started + 1; v_courses := v_courses + cardinality(r.ids);
    exception when others then v_failed := v_failed || r.provider_id || ': ' || sqlerrm || '; ';
    end;
  end loop;
  if v_failed <> '' then raise exception 'not applied (rolled back): %', v_failed; end if;
  raise exception 'DRYRUN OK Re-opened: % task(s), % course(s) (guard: % rows at % universities); % skipped (task already waiting or running); not started, unpublished: %', v_started, v_courses, v_rows, v_provs, v_skipped, coalesce(nullif(v_hidden, ''), 'none');
end $p$;

-- Check afterwards (expect the tasks running, rows moving from queued to sent within a few minutes):
