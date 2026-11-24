-- CF-247 s1110 (S1-Build / Integration Controller; Admin #1048, 25 Nov 2026 05:55 AEDT: "Fix extension-less PDF acquisition using verified HTTP
-- Content-Type and PDF file signatures. Do not depend on URL extensions or the #.pdf workaround ... Investigate historical OpenRouter weekly-limit
-- failures against the actual worker credential and polled key telemetry. Preserve spending controls.")
-- Found live (rolled back, 25 Nov 2026 06:05 AEDT):
--   * CQUniversity's country table is served by a content store at an address with no ".pdf". The entry-page fetch reads a source as a PDF only
--     when its address ends in .pdf (svc_entry_matrix_fetch_next 'pdf'), so source 50e4031c failed three times as not_html (HTTP 200). A copy of
--     the same address with "#.pdf" appended (source 55de8e6d) was registered as a workaround and read as a PDF.
--   * Worker v1.0.40 (this change, entry-pdf-sniff.ts) reads such an address as a PDF when the server names a PDF or no type, or sends text that
--     starts like one, and the file's own "%PDF-" signature proves it. This migration hands the original address back to the fetch and retires the
--     workaround copy, unless the copy already holds proposed or active rows or waiting work (then nothing of CQU is touched and a notice says so).
--   * OpenRouter weekly-limit failures: 4 entry-matrix runs failed with "Key limit exceeded (weekly limit)" on 12 Nov (key limit $50.00) and
--     15 Nov 01:39 UTC (key limit $70.00), before worker v1.0.3 made a key-limit refusal an account stop that gives the run back (15 Nov 12:53 AEDT).
--     The key polled by job openrouter-balance (same worker, same credential resolution) read $70 weekly at -$0.01 at 02:35 UTC, then $100 weekly,
--     then $50 daily from 22 Nov; no key_limit attempt and no refusal record since. The 4 runs (Top Education 3, AGI 1) were never read again.
--     They are read again from their stored copies through the existing re-read (public.admin_entry_matrix_reread); spending limits unchanged.
-- G1: no job. G2: no new value (the PDF size cap is entry.pdf_max_bytes). G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: the address-extension test as the only way an entry page is read as a PDF; the "#.pdf" workaround source for CQUniversity.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1110_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1110_cron on commit drop as select count(*) n from cron.job where active;

-- 1. CQUniversity: the original address is read by content type; the "#.pdf" copy is retired
do $cqu$
declare
  v_orig constant uuid := '50e4031c-da08-489e-a34a-e87659820ede';
  v_copy constant uuid := '55de8e6d-385a-409f-a759-aa3585f9bb3a';
  v_reason constant text := 'CF-247 s1110 (Admin #1048): the address serves a PDF without ".pdf"; worker v1.0.40 reads it by its Content-Type and %PDF- signature';
  v_o pipeline.entry_matrix_sources%rowtype; v_c pipeline.entry_matrix_sources%rowtype; v_rows int; v_wait int;
begin
  select * into v_o from pipeline.entry_matrix_sources where id = v_orig for update;
  select * into v_c from pipeline.entry_matrix_sources where id = v_copy for update;
  if v_o.id is null or v_c.id is null or v_o.provider_id <> v_c.provider_id or v_c.url <> v_o.url || '#.pdf' then
    raise notice 's1110: the CQU sources are not as found; nothing of CQU changed'; return;
  end if;
  select count(*) into v_rows from catalogue.provider_entry_matrix m join pipeline.entry_matrix_runs r on r.id = m.run_id
   where r.source_id = v_copy and m.status in ('proposed', 'active');
  select count(*) into v_wait from pipeline.entry_matrix_runs r where r.source_id in (v_orig, v_copy) and r.state in ('queued', 'leased');
  if v_rows > 0 or v_wait > 0 or v_o.status not in ('failed', 'found') then
    raise notice 's1110: CQU left as it is (% rows from the copy, % runs waiting, original %)', v_rows, v_wait, v_o.status; return;
  end if;
  -- handed back as an expired claim (the fetch takes a 'reading' source 20 minutes after its claim), so the first fetch is made by worker v1.0.40,
  -- which deploys after this migration, not by the running worker in the minute between the two
  update pipeline.entry_matrix_sources set status = 'reading', attempts = 0, error = null, updated_at = now() where id = v_orig;
  update pipeline.entry_matrix_sources set status = 'inactive', error = left('superseded by source ' || v_orig || ': ' || v_reason, 400), updated_at = now() where id = v_copy;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'source_by_content_type', 'pipeline.entry_matrix_sources',
          jsonb_build_object('reason', v_reason, 'by', 'migration 20261126090000 (CF-247 s1110)', 'approved_by', 'Admin #1048 (Platform Admin 25 Nov 2026 05:55 AEDT)',
                             'fetched_again', v_orig, 'retired_copy', v_copy, 'copy_rows', v_rows), null);
end $cqu$;

-- 2. Entry-matrix runs failed by the historical OpenRouter weekly key limit (an account stop, not the page): read again from the stored copy
do $key$
declare v_src uuid[]; v_out jsonb;
begin
  select array_agg(distinct r.source_id order by r.source_id) into v_src
    from pipeline.entry_matrix_runs r join pipeline.entry_matrix_sources s on s.id = r.source_id
   where r.state = 'failed' and r.error ~* 'key limit exceeded' and s.status = 'read'
     and not exists (select 1 from pipeline.entry_matrix_runs r2 where r2.source_id = r.source_id and r2.created_at > r.created_at)
     and not exists (select 1 from pipeline.entry_matrix_runs r3 where r3.source_id = r.source_id and r3.state in ('queued', 'leased'));
  if coalesce(array_length(v_src, 1), 0) = 0 then raise notice 's1110: no key-limit runs to read again'; return; end if;
  if array_length(v_src, 1) > 10 then raise exception 'guard: % key-limit sources, more than found (4); nothing read again', array_length(v_src, 1); end if;
  v_out := public.admin_entry_matrix_reread(v_src, 'CF-247 s1110 (Admin #1048): failed by the OpenRouter weekly key limit before worker v1.0.3 gave such runs back; read again from the stored copy');
  raise notice 's1110: key-limit re-read %', v_out;
end $key$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1110_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1110_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from pipeline.entry_matrix_sources where id = '55de8e6d-385a-409f-a759-aa3585f9bb3a' and status = 'inactive')
     and not exists (select 1 from pipeline.entry_matrix_sources where id = '50e4031c-da08-489e-a34a-e87659820ede' and status = 'reading' and attempts = 0) then
    raise exception 'post-check: the CQU copy was retired but the original address is not waiting to be fetched';
  end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
