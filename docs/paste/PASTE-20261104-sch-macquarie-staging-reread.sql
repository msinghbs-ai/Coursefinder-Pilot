-- CF-247 Macquarie staging addresses (handover 3 Nov 2026 Priority 3 item 11). APPROVED: Platform Admin decisions D5 and D6, overnight mandate
-- 3 Nov 2026 21:59 (D5: re-read the eight staging pages through the normal evidence path, avoiding duplicate credits; D6: the seven published
-- records stay published pending the results; a confirmed misleading current record is escalated for a separate consumer correction).
-- Eight active Macquarie scholarships are read from students.mq.edu.au/study/course/overseas/staging/details/... (7 published, 1 unpublished);
-- the pages state start years 2016 to 2019. Stored evidence holds no official (mq.edu.au) page for any of them except the Vice-Chancellor's
-- International Scholarship, already published as a347e086 from the official page (held ref 1184 duplicates it: the duplicate close route).
-- Effect: asks the existing "Read again" route (pipeline.scholarship_pages.requested_at) to read each page now (scheduled re-reads are 12 Nov 2026
-- to 11 Jan 2027). A moved or redirected page is recorded in pipeline.scholarship_source_moves (F7) and stored as evidence. Nothing is withdrawn,
-- replaced or unpublished by this file (D6).
-- No duplicate credits: a page is skipped when it is already asked for (requested_at set), already read since 21:59 AEDT 3 Nov 2026, stored as
-- evidence since then, or already queued for an AI read. A second run therefore asks for nothing.
-- PASTE FILE. Not applied by any migration. Sets requested_at on at most 8 rows (the 8 named below). Nothing is deleted.
begin;
do $$
declare v_found int; v_skip int; v_n int;
  v_since timestamptz := '2026-11-03 21:59:00+11';  -- the decision time (D5)
  v_ids uuid[] := array['863c8914-a6ec-521d-a7a1-af352d6562f2', '95906adb-c369-51f3-a7d0-894648416ddd', 'f04dd87f-8128-59c9-a21b-b771efc7c2b1', '4ed7a374-6ace-5daf-ad9f-b1ae997e983a',
                        '094b89a5-4b52-5a28-a077-2681fe24ad1f', '6426899a-446b-58bb-adcc-7606efb645f1', 'a9b90b2b-a7c0-59da-a4c3-775f13349ae8', '9184031a-188f-50c7-af48-b1253bc3fdf9']::uuid[];
begin
  create temporary table pg(scholarship_id uuid primary key, url text, skip text) on commit drop;
  insert into pg
  select sp.scholarship_id, sp.url,
         case when sp.requested_at is not null then 'already asked for'
              when sp.read_at >= v_since then 'read since the decision'
              when exists (select 1 from pipeline.evidence_artifacts e where lower(e.source_url) = lower(coalesce(sp.final_url, sp.url)) and e.captured_at >= v_since) then 'stored since the decision'
              when exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = sp.scholarship_id and q.state in ('queued', 'leased')) then 'queued for an AI read' end
    from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
   where sp.scholarship_id = any (v_ids) and sp.url ~* '^https://students\.mq\.edu\.au/study/course/overseas/staging/details/' and s.lifecycle_status = 'active'
     and s.provider_id = '188103a5-1aba-4f99-bd3e-0416659086d3';
  select count(*), count(skip) into v_found, v_skip from pg;
  if v_found <> 8 then raise exception 'guard: % of the 8 staging-address scholarships are active, Macquarie''s and on the staging path; nothing changed', v_found; end if;
  update pipeline.scholarship_pages sp set requested_at = now() from pg where pg.scholarship_id = sp.scholarship_id and pg.skip is null and sp.requested_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 8 - v_skip then raise exception 'guard: % rows requested, expected %; rolled back', v_n, 8 - v_skip; end if;
  raise notice 'requested % re-reads; skipped %: %', v_n, v_skip, (select coalesce(string_agg(left(scholarship_id::text, 8) || ' ' || skip, '; '), 'none') from pg where skip is not null);
end $$;
commit;

-- After the reads (read only): what each page now says, and any move recorded
select s.id, s.name, s.publication_status, sp.read_at, sp.read_status, sp.final_url, sp.http_status, sp.requested_at
  from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
 where sp.url ~* '^https://students\.mq\.edu\.au/study/course/overseas/staging/details/' and s.lifecycle_status = 'active' order by s.name;
select * from pipeline.scholarship_source_moves where old_url ~* '^https://students\.mq\.edu\.au/study/course/overseas/staging/details/';
