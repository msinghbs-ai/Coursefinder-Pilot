-- CF-247 s1260 (S1-Build / Release Controller; SS-Programme-Control 26 Nov 2026 17:01 AEDT item 5: "Coordinate execution of the approved s1240 A1-A4
-- decisions after the respective evidence conditions are satisfied"; decision pack admin docs/platform/p0-aer-activation/2026-11-26-s1240-au-aer-source-
-- identity-alias-decisions.md, S1-AER-Claude).
-- A1 CQU: approved once the link target was confirmed. Confirmed 26 Nov 2026 17:50 AEDT on the live official page
--    https://www.cqu.edu.au/study/international/entry-requirements/academic-requirements: its "Country equivalents" and "country-specific academic
--    requirements" links go to https://delivery-cqucontenthub.stylelabs.cloud/api/public/content/country-specific-academic-requirements, the stored
--    source 50e4031c without its edition tag. Alias for provider f02d9d9b only.
-- A2 AIBT: alias aibtglobal.edu.au for provider eb9e3903 only (CRICOS 03430J). AIBT International fc6f01a7 (CRICOS 03610E) is not aliased.
-- A3 Excelsia: the International Students Guide source a9e409bc holds no entry table; it is set inactive (kept, not deleted).
-- A4 Le Cordon Bleu (reader page scope 15 to 33) is not in this change: it needs the stored-copy check (entry_inspect) first, with S2-AER.
-- Then the two declined matrix decisions (CQU 96f4e11a, AIBT 44c0a54f) are decided again by the existing machine admission
-- (security.aer_matrix_machine_admit_v1), which applies every other check as before.
-- G1: no job. G2: the existing protected setting aer.provider_host_aliases, changed with its reason (Platform Admin approval). G3: no consumer object
-- changed (checked). Locks and cron checked unchanged.
-- Replaces: aer.provider_host_aliases (two entries added).
-- Retires: entry-matrix source a9e409bc (set inactive). Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and two machine decisions

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where key = 'aer.provider_host_aliases') then raise exception 'guard: aer.provider_host_aliases is not a setting'; end if;
  if not exists (select 1 from pipeline.entry_matrix_sources where id = 'a9e409bc-0560-4598-a940-994fde3374a2' and url like '%International-Students-Guide.pdf') then raise exception 'guard: the Excelsia guide source is not the one recorded'; end if;
  if not exists (select 1 from pipeline.entry_matrix_sources where id = '50e4031c-da08-489e-a34a-e87659820ede' and provider_id = 'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6' and url like 'https://delivery-cqucontenthub.stylelabs.cloud/api/public/content/country-specific-academic-requirements%') then raise exception 'guard: the CQU source is not the one recorded'; end if;
end $g$;
create temp table s1260_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1260_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none

do $a$
declare s record; v_new jsonb; v_r jsonb := '[]'::jsonb; v_item uuid;
  v_reason constant text := 'Platform Admin approval of s1240 A1 and A2 (relayed by SS-Programme-Control 26 Nov 2026 17:01 AEDT): CQU content hub and AIBT site, one provider each (CF-247 s1260)';
begin
  select * into s from pipeline.platform_toolset_settings where key = 'aer.provider_host_aliases' for update;
  v_new := (select jsonb_agg(distinct x) from (select jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) x
              union select 'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6:delivery-cqucontenthub.stylelabs.cloud'
              union select 'eb9e3903-6d92-4502-a2b3-51cb231b21fc:aibtglobal.edu.au') z);
  update pipeline.platform_toolset_settings set value = v_new, reason = v_reason, updated_at = now() where toolset_key = s.toolset_key and key = s.key;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', s.toolset_key || '.aer.provider_host_aliases', jsonb_build_object('before', s.value, 'after', v_new, 'reason', v_reason,
          'approved_by', 'Platform Admin (s1240 A1, A2; relayed by SS-Programme-Control 26 Nov 2026 17:01 AEDT)', 'evidence_a1', 'live official page links to the content hub file, checked 26 Nov 2026 17:50 AEDT', 'via', 'CF-247 s1260 migration'), null);
  update pipeline.entry_matrix_sources set status = 'inactive', error = left('s1260 (s1240 A3): guide holds no entry table; course pages carry Excelsia entry rows', 300), updated_at = now()
   where id = 'a9e409bc-0560-4598-a940-994fde3374a2';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'source_retired', 'pipeline.entry_matrix_sources', jsonb_build_object('source', 'a9e409bc-0560-4598-a940-994fde3374a2', 'reason', 's1240 A3 approved: no entry table in the guide', 'by', 'migration CF-247 s1260'), null);
  foreach v_item in array array['96f4e11a-7578-425e-8c00-6fec369a24fb', '44c0a54f-2b7e-47a3-a6ad-8634d05d5dcd']::uuid[] loop
    v_r := v_r || jsonb_build_object('item', v_item, 'result', security.aer_matrix_machine_admit_v1(v_item, 'run'));
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'machine_redecide', 'security.aer_matrix_machine_admit_v1', jsonb_build_object('reason', 'aliases A1 and A2 approved', 'by', 'migration CF-247 s1260', 'results', v_r), null);
  raise notice 's1260: %', v_r;
end $a$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1260_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1260_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from jsonb_array_elements_text((select value from pipeline.platform_toolset_settings where key = 'aer.provider_host_aliases')) x where x like 'fc6f01a7%') then raise exception 'post-check: AIBT International was aliased'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
