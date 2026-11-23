-- CF-247 s991 (S2-CF; Platform Admin 23 Nov 2026 17:50 AEDT: "do not leave known-wrong URLs masquerading as valid ... demote or quarantine non-locked wrong URLs
-- (never touch the 7,585 manual locks) and re-resolve them"). Data only: accepted official course URLs that the platform's own current page check refuses
-- (security.course_page_check_v1 verdict 'refuse') or that are soft-404 pages are demoted through the EXISTING governed remediation function
-- security.binding_remediation_apply_v1 (the SS-007 route): one hold record in pipeline.course_remediation_holds with the before state, a page_rejections row so the
-- page is never bound to the course again, the page record set to 'mismatch', the official link set to the existing status 'unverified', and a search refresh
-- request. courses.course_url is taken back by the existing job course-url-fill. The course then goes back to the existing relink and link-search path.
-- Classes (reason codes): shared_fee_list_page, old_handbook_year, soft_404, wrong_course_level_or_award.
-- Never changed: a course with a manual lock on official_url, course_url or all; a manual binding; a held course; a link whose page record is not bound. A refused
-- link that cannot be demoted this way is counted and left as it is (held_other). Nothing is deleted. No description, intake or other field is written.
-- Cost: $0 (no Firecrawl, no AI, no fetch). G1: no job. G2: the batch size is the existing setting remediation.max_batch_courses. G3: consumer API baseline read
-- before and after (75 functions, 48 relations); no consumer object is touched. The official URL served by Website and Zoho v3 for a demoted course follows the
-- link status (data, not shape).
-- Counts are written to pipeline.admin_control_events (area course_link, action s991_demote_wrong_urls) so the rolled-back rehearsal can report them.
-- Replaces: nothing.
-- Retires: nothing.
-- Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '540s';  -- fixed: one governed pass of the page check over the active official links (rolled-back rehearsal measures the time)

do $m$
declare
  v_api jsonb := security.consumer_api_check_v1();
  v_max int := greatest(security.pipeline_num_v1('remediation.max_batch_courses', 50)::int, 1);
  v_locks_before int; v_locks_after int; v_desc_before int; v_desc_after int; v_links_before int; v_links_after int;
  v_all jsonb; v_cand int; r record; v_res jsonb; v_by jsonb := '{}'::jsonb; v_demoted int := 0; v_unv int := 0; v_chunks int := 0;
  v_approval constant text := 'Platform Admin 23 Nov 2026 17:50 AEDT (S2-CF s991): demote known-wrong accepted official URLs';  -- fixed: the approval reference the remediation function records
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v_api;
  end if;
  select count(*) into v_locks_before from pipeline.manual_locks;
  select count(*) into v_desc_before from catalogue.courses where nullif(btrim(description), '') is not null;
  select count(*) into v_links_before from catalogue.course_links where link_type = 'official_course' and status = 'active';

  -- every candidate: an active official link on an active course whose bound, non-manual page record is the same page and which the page check refuses (or a soft 404)
  select coalesce(jsonb_agg(jsonb_build_object('pid', q.pid, 'cid', q.cid, 'url', q.url, 'cls', q.cls)), '[]'::jsonb) into v_all
    from (
      select c.provider_id pid, c.id cid, g.url,
             case when x.chk->>'reason' ilike '%shared by several%' then 'shared_fee_list_page'
                  when x.chk->>'reason' ilike '%handbook%' then 'old_handbook_year'
                  when x.chk->>'verdict' is distinct from 'refuse' then 'soft_404'
                  else 'wrong_course_level_or_award' end cls
        from catalogue.course_links l
        join catalogue.courses c on c.id = l.course_id and c.lifecycle_status = 'active'
        join pipeline.coverage_course_pages g on g.course_id = c.id and g.url = l.url and g.status = 'bound' and g.provider_id = c.provider_id and coalesce(g.basis, '') <> 'manual'
        cross join lateral (select security.course_page_check_v1(c.id, coalesce(nullif(g.candidates->>'final_url', ''), g.url),
                                                              coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1'), g.identity_basis) chk) x
       where l.link_type = 'official_course' and l.status = 'active'
         and (x.chk->>'verdict' = 'refuse' or (g.http_status = 200 and coalesce(g.candidates->>'h1', '') ~* '(page|course|program(me)?) not found|^404\b'))
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('official_url', 'course_url', 'all'))
         and not security.course_held_v1(c.id)) q;
  v_cand := jsonb_array_length(v_all);

  -- one remediation call per university, class and chunk of the existing batch limit
  for r in
    select z.pid, z.cls, z.chunk, jsonb_agg(jsonb_build_object('course_id', z.cid, 'url', z.url, 'class', z.cls)) items, count(*)::int n
      from (select (e->>'pid')::uuid pid, (e->>'cid')::uuid cid, e->>'url' url, e->>'cls' cls,
                   ((row_number() over (partition by e->>'pid', e->>'cls' order by e->>'cid') - 1) / v_max)::int chunk
              from jsonb_array_elements(v_all) e) z
     group by z.pid, z.cls, z.chunk order by z.pid, z.cls, z.chunk loop
    v_res := security.binding_remediation_apply_v1(r.pid, r.items, r.n, v_approval, 's991 ' || r.cls || ': the page check refuses this page as the course page');
    v_chunks := v_chunks + 1; v_demoted := v_demoted + coalesce((v_res->>'re_roled')::int, 0); v_unv := v_unv + coalesce((v_res->>'links_unverified')::int, 0);
    v_by := jsonb_set(v_by, array[r.cls], to_jsonb(coalesce((v_by->>r.cls)::int, 0) + r.n));
  end loop;

  select count(*) into v_locks_after from pipeline.manual_locks;
  select count(*) into v_desc_after from catalogue.courses where nullif(btrim(description), '') is not null;
  select count(*) into v_links_after from catalogue.course_links where link_type = 'official_course' and status = 'active';
  if v_locks_after is distinct from v_locks_before then raise exception 'post-check: manual locks changed (% to %)', v_locks_before, v_locks_after; end if;
  if v_desc_after is distinct from v_desc_before then raise exception 'post-check: descriptions changed (% to %)', v_desc_before, v_desc_after; end if;
  if v_demoted <> v_cand then raise exception 'post-check: % candidates, % demoted', v_cand, v_demoted; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('course_link', 's991_demote_wrong_urls', 's991', jsonb_build_object('candidates', v_cand, 'demoted', v_demoted, 'links_unverified', v_unv, 'by_class', v_by,
          'calls', v_chunks, 'active_official_links_before', v_links_before, 'active_official_links_after', v_links_after, 'manual_locks', v_locks_after,
          'approval', v_approval), null);
  raise notice 's991: candidates %, demoted %, links unverified %, by class %, active official links % to %, locks %', v_cand, v_demoted, v_unv, v_by, v_links_before, v_links_after, v_locks_after;
end $m$;
