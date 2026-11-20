-- CF-247 s862 (session S1-Structure-Outcomes, Platform Admin 20 Nov 2026 15:19 AEDT: "< 300 ms per query"). Measured live after s861 went live (16:31 AEDT, rolled-back
-- read through GitHub Actions, run 44682857433): the structure sweep's ticks took 6.6 s and 9.8 s, and the shared-page check of the promoter took 2,842 ms for 160 pages
-- (about 18 ms a page): its "same evidence id OR same address" test cannot use an index, so each page scanned the bound pages (23,989 of 35,873 rows).
-- What changes: a partial index on the bound pages' evidence id, and the one test written as two EXISTS (evidence id; address, on the existing coverage_course_pages_bound_url_idx).
-- The result is the same pages (a page is shared when another course is bound to the same stored copy or the same address); nothing else in the function changes.
-- The live definition was read on 20 Nov 2026 16:45 AEDT (md5 below); a changed definition stops this migration.
-- Parity before writing (read live 16:45 AEDT): head 20261120163500 (s861); numbered above every open pull request (Pilot #1425 holds 20261120165000 and 165100, #1428 holds 20261120170000).
-- G1: no job. G2: no setting. G3: no consumer object (security.consumer_api_check_v1() is read after: 75, 48). No spend.
-- Replaces: the shared-page test inside security.struct_det_promote_v1 (same result, indexed).
-- Retires: nothing.
set local lock_timeout = '5s';

create index if not exists coverage_course_pages_bound_evidence_idx on pipeline.coverage_course_pages (evidence_id) where status = 'bound';

do $r$
declare v_def text; v_new text;
        a1 constant text := 'v_shared := exists (select 1 from pipeline.coverage_course_pages o where o.course_id <> pg.course_id and o.status = ''bound''
                           and (o.evidence_id = pg.evidence_id or (g.url is not null and o.url = g.url)));';
        b1 constant text := 'v_shared := exists (select 1 from pipeline.coverage_course_pages o where o.status = ''bound'' and o.evidence_id = pg.evidence_id and o.course_id <> pg.course_id)
                        or (g.url is not null and exists (select 1 from pipeline.coverage_course_pages o where o.status = ''bound'' and o.url = g.url and o.course_id <> pg.course_id));';
begin
  select pg_get_functiondef('security.struct_det_promote_v1()'::regprocedure) into v_def;
  if md5(v_def) is distinct from 'bf0bc0d643a0df2cdabeb37b688ea3d7' then raise exception 'guard: security.struct_det_promote_v1 is not the definition this change was written against'; end if;
  if (length(v_def) - length(replace(v_def, a1, ''))) / length(a1) <> 1 then raise exception 'guard: the shared-page test is not found exactly once'; end if;
  v_new := replace(v_def, a1, b1);
  execute v_new;
end $r$;

-- post-checks: the index is used, the test is replaced, the result is the same pages, and the check of every read page stays well under 300 ms
do $c$
declare v_api jsonb; v_t0 timestamptz; v_ms numeric; v_old int; v_new int; v_def text;
begin
  select pg_get_functiondef('security.struct_det_promote_v1()'::regprocedure) into v_def;
  if position('o.url = g.url and o.course_id <> pg.course_id' in v_def) = 0 then raise exception 'post-check: the shared-page test was not replaced'; end if;
  if to_regclass('pipeline.coverage_course_pages_bound_evidence_idx') is null then raise exception 'post-check: the index is missing'; end if;
  select count(*) into v_old from pipeline.struct_det_pages d
    cross join lateral (select p.url from pipeline.coverage_course_pages p where p.course_id = d.course_id and p.status = 'bound' order by p.bound_at desc nulls last limit 1) g
   where exists (select 1 from pipeline.coverage_course_pages o where o.course_id <> d.course_id and o.status = 'bound' and (o.evidence_id = d.evidence_id or (g.url is not null and o.url = g.url)));
  v_t0 := clock_timestamp();
  select count(*) into v_new from pipeline.struct_det_pages d
    cross join lateral (select p.url from pipeline.coverage_course_pages p where p.course_id = d.course_id and p.status = 'bound' order by p.bound_at desc nulls last limit 1) g
   where exists (select 1 from pipeline.coverage_course_pages o where o.status = 'bound' and o.evidence_id = d.evidence_id and o.course_id <> d.course_id)
      or (g.url is not null and exists (select 1 from pipeline.coverage_course_pages o where o.status = 'bound' and o.url = g.url and o.course_id <> d.course_id));
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  if v_new <> v_old then raise exception 'post-check: the shared pages differ (% before, % after)', v_old, v_new; end if;
  if v_ms > 300 then raise exception 'post-check: the shared-page check of % read pages took % ms (target under 300 ms)', (select count(*) from pipeline.struct_det_pages), round(v_ms); end if;
  raise notice 's862: % shared of the read pages, % ms', v_new, round(v_ms);
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
