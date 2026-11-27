-- CF-247 s1306 (S1-Data-Gaps; SS-Programme-Control 27 Nov 2026 13:07 AEDT, Complete Relink Recovery and International Source Verification, Priority 1, Admin #1271):
-- the 227 requests s1302 sent to course relink (Pilot #1721) were never taken. Traced live (27 Nov 2026, rolled-back reads, no interactive SQL):
--   1. Selection. Course relink takes a page only when its read status is on the list in the setting relink.statuses (identity_mismatch, identity_refused,
--      page_refused, refused_host, not_course_page) or it sits on a retired host. The cohort's pages are fetch_failed: 186 with HTTP 404, 1 with no status
--      (Swinburne 164 course-planner PDFs from 2020; Western Sydney 35 /future/study/courses addresses), plus 31 read with HTTP 200 (the 33 audience
--      suspects, which need audience proof, not relink) and 1 unread. A dead page is on none of those lists, so security.course_relink_provider_v1,
--      security.course_relink_order_v1 and security.course_relink_tick_v1 counted none of them; the four scheduled runs since s1302 ran with nothing to take.
--      security.source_proof_relink_asked_v1 and security.work_item_eligible_v1 were not the cause (a queued request after the last decision counts as asked;
--      the four providers' course_relink work items are in stage done, which is eligible; the lane is not paused; wc.relink_fair_on is 1).
--   2. Settlement. 156 of the cohort already had a course relink row in state trying (Swinburne 134, Western Sydney 22, started 18 Oct to 18 Nov). Relink
--      bound its first candidate, the reader read it (HTTP 404), and then a person's Find course pages task (security.provider_task_prepare_v1, 12 Nov) reset
--      the course's search row to queued, cand_idx 0, keeping the candidates. Course relink settles only a search row in state found or verified, and the
--      paid title search cannot send (the course page search share left today is 0), so those rows sit in trying with nothing to move them. Selecting the
--      course again (point 1) rewrites the relink row and the search row (state found), which hands the course back to the existing move-on step.
--   3. A second selection would otherwise repeat itself: the same address forms give the same first candidates, so a dead address could be bound again.
-- What this does (three existing functions, same signatures, same job, no new queue, job, scheduler, table or setting):
--   a. A page whose read failed with HTTP 404 or 410 is due for relink while a relink request is queued for its course (the request is the owner's release,
--      so nothing is taken in bulk: 1,029 other held no_route courses with a gone page are not taken until their owners release them).
--   b. A course's relink does not take an address its own earlier relink already tried (all of them when it ended absent; otherwise those up to and
--      including the page now bound), so a dead address is not bound again.
-- Unchanged: candidates come from the same sources (the provider's own stored lists, learnt address forms, year rollover, stored search results), none on a
--   retired host; a binding changes only when the reader proves the exact course (CRICOS code) on that page; canonical requirements, manual locks, Layer 4,
--   audience (S1-Build phase B) and every link are untouched; no value is written by this file. Shared with S1-Build (s1196 owner): the three functions are
--   replaced with their live text plus these two changes only (md5 of the live source is checked below before replacing).
-- G1: no job. G2: no new value. G3: no consumer object changed (checked before and after). Locks, cron, pages, links and requests checked unchanged. Spend: US$0.
-- Replaces: security.course_relink_provider_v1, security.course_relink_order_v1, security.course_relink_tick_v1 (same functions, gone pages asked for are due; tried addresses left out).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the function replacement
set local statement_timeout = '120s';  -- fixed: the consumer API check and three function replacements

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  -- the live functions must still be the ones this file was written against (s1196 text)
  if (select md5(prosrc) from pg_proc where oid = 'security.course_relink_provider_v1(uuid,integer)'::regprocedure) <> 'aa3fcbf4800ffebce87cf0fce07af18e'
     or (select md5(prosrc) from pg_proc where oid = 'security.course_relink_order_v1()'::regprocedure) <> 'dde514d6978f72abb58ce65ce45904e1'
     or (select md5(prosrc) from pg_proc where oid = 'security.course_relink_tick_v1(integer)'::regprocedure) <> '9f453d4787a3b6177a190bea20465eff' then
    raise exception 'guard: a course relink function was changed since s1196; this file replaces the s1196 text';
  end if;
end $g$;

create temp table s1306_guard on commit drop as
select (select count(*) from cron.job) cron_before,
       (select count(*) from pipeline.manual_locks) locks_before,
       (select count(*) from catalogue.course_links) links_before,
       (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') official_before,
       (select count(*) from pipeline.coverage_course_pages) pages_before,
       (select count(*) from pipeline.source_proof_requests) requests_before,
       (select count(*) from pipeline.source_proof_requests where route = 'relink' and state = 'queued') queued_before;

CREATE OR REPLACE FUNCTION security.course_relink_provider_v1(p_provider_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_forms jsonb; v_share numeric; v_try int := 0; v_absent int := 0; r record; v_c text[]; v_s text[];
        -- 3 Nov 2026 (SS-021 relink isolation): the university's addresses and swap titles, prepared once a university (not once a course)
        v_u text[]; v_ut text[]; v_useg text[]; v_usl text[]; v_utn text[]; v_ou text[]; v_oc uuid[]; v_ok1 text[]; v_ok2 text[]; v_sl text[];
        v_deadline timestamptz := nullif(current_setting('cf247.relink_deadline', true), '')::timestamptz; v_stopped text;
        v_cap int := security.pipeline_num_v1('relink.urls_per_university', 50000)::int;
        v_min int := security.pipeline_num_v1('relink.pattern_min_pages', 10)::int;
begin
  -- the university's address forms, learnt from its own verified pages: each form with enough pages, and the study level it serves
  with g as (select replace(lower(g.url), s.slug, '{slug}') tpl, c.study_level_id lvl, s.slug
               from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
               cross join lateral (select regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug) s
              where g.provider_id = p_provider_id and g.status = 'bound' and g.read_status = 'read' and g.identity_basis is not null
                and security.site_host_v1(g.url) not in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id)),  -- s1196: no address form is learnt from a retired host
  t as (select tpl, count(*) n from g where length(slug) > 5 and strpos(tpl, '{slug}') > 0 group by 1 having count(*) >= v_min)
  select coalesce(jsonb_agg(jsonb_build_object('tpl', t.tpl, 'n', t.n, 'levels',
           (select coalesce(jsonb_agg(distinct g2.lvl), '[]'::jsonb) from g g2 where g2.tpl = t.tpl and g2.lvl is not null)) order by t.n desc), '[]'::jsonb),
         coalesce(sum(t.n), 0)::numeric / nullif((select count(*) from g), 0)
    into v_forms, v_share from t;
  if coalesce(v_share, 0) < security.pipeline_num_v1('relink.pattern_min_share', 0.5) then v_forms := '[]'::jsonb; end if;
  -- 3 Nov 2026 (SS-021 relink isolation, live 22:04 and 22:14 AEDT): the stored address lists were read, and every address's last part and the
  -- course title's address forms worked out, once for every course (addresses x courses regular expressions in one statement), so one large
  -- university passed the 120-second statement limit and the whole run rolled back. They are prepared once here (at most
  -- relink.urls_per_university addresses), and each course compares plain text.
  select array_agg(l.url order by l.url, l.title), array_agg(l.title order by l.url, l.title),
         array_agg(security.course_relink_url_seg_v1(l.url) order by l.url, l.title),
         array_agg(regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') order by l.url, l.title),
         array_agg(lower(btrim(split_part(split_part(coalesce(l.title, ''), ' | ', 1), ' - ', 1))) order by l.url, l.title)
    into v_u, v_ut, v_useg, v_usl, v_utn
    from (select distinct u.url, u.title from (
            select pu.url, pu.title from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
            union select dl.url, dl.anchor_text from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) u
           where security.site_host_v1(u.url) not in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id)  -- s1196: stored addresses on a retired host are not candidates
           order by u.url, u.title limit v_cap) l;
  select array_agg(o.url), array_agg(o.course_id),
         array_agg(regexp_replace(regexp_replace(lower(coalesce(o.candidates->>'h1', '')), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g')),
         array_agg(regexp_replace(regexp_replace(split_part(split_part(split_part(lower(coalesce(o.candidates->>'page_title', '')), ' | ', 1), ' – ', 1), ' - ', 1), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'))
    into v_ou, v_oc, v_ok1, v_ok2
    from pipeline.coverage_course_pages o where o.provider_id = p_provider_id and o.read_status = 'identity_mismatch';
  for r in
    select p.course_id, p.url old_url, c.study_level_id lvl, regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug,
           regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt, c.canonical_title ttl,
           -- s1306: candidates this course's earlier relink already tried and the reader could not use (all of them when it ended absent; otherwise
           -- those up to and including the page now bound), so a dead address is never bound again
           (select case when x2.state = 'absent' then array(select jsonb_array_elements_text(coalesce(x2.candidates, '[]'::jsonb)))
                        else array(select e.u from jsonb_array_elements_text(coalesce(x2.candidates, '[]'::jsonb)) with ordinality e(u, o)
                                    where e.o <= coalesce((select e2.o from jsonb_array_elements_text(coalesce(x2.candidates, '[]'::jsonb)) with ordinality e2(u, o)
                                                            where security.course_relink_url_norm_v1(e2.u) = security.course_relink_url_norm_v1(p.url) limit 1), 0)) end
              from pipeline.course_relink x2 where x2.course_id = p.course_id) tried
      from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
     where p.provider_id = p_provider_id and ((p.read_status = any (security.course_relink_statuses_v1())
            or (p.read_status = 'fetch_failed' and p.http_status in (404, 410)
            and exists (select 1 from pipeline.source_proof_requests q0 where q0.course_id = p.course_id and q0.route = 'relink' and q0.state = 'queued')))
            or security.site_host_v1(p.url) in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id))  -- s1196: a page on a retired host is relinked
       and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id
                        and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
     order by p.course_id
     limit greatest(1, p_limit)
  loop
    -- 3 Nov 2026 (SS-021 relink isolation): stop between courses at the university's deadline (set by security.course_relink_fair_run_v1)
    if v_deadline is not null and clock_timestamp() >= v_deadline then v_stopped := 'deadline'; exit; end if;
    v_sl := security.course_relink_slugs_v1(r.ttl);
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
      select distinct on (security.course_relink_url_norm_v1(q.url)) q.url, q.src, q.rk from (
        -- another course's refused page whose title is exactly this course's title
        select o.url, 'page_swap' src, 1::numeric rk from unnest(v_ou, v_oc, v_ok1, v_ok2) o(url, course_id, k1, k2)
         where o.course_id <> r.course_id and length(r.nt) > 8 and r.nt in (o.k1, o.k2)
        union all
        -- address forms: those used by verified pages of the same study level first, then by number of pages
        select replace(fm.form->>'tpl', '{slug}', r.slug), 'url_pattern',
               2 + (case when r.lvl is not null and (fm.form->'levels') @> to_jsonb(r.lvl) then 0 else 0.5 end) + fm.ord / 1000.0
          from jsonb_array_elements(v_forms) with ordinality fm(form, ord) where length(r.slug) > 5
           -- 22 Oct 2026 (NZ review fix 3): address guesses only in relink.url_pattern_countries
           and security.coverage_country(p_provider_id) in (select jsonb_array_elements_text(sx.value) from pipeline.platform_toolset_settings sx
                                                             where sx.toolset_key = 'pipeline' and sx.key = 'relink.url_pattern_countries')
        union all
        select l.url, 'url_list', 3 from unnest(v_u, v_usl) l(url, sl)
         where length(r.slug) > 10 and l.sl = r.slug
        union all
        -- CF-247 ops B (S5, relink.slug_variants_on): title forms (diacritics, apostrophes, "&", "(Level n)", bracketed qualifiers) and stored page titles
        select l.url, 'url_list_variant', 3.5 from unnest(v_u, v_useg, v_utn) l(url, seg, tn)
         where security.pipeline_num_v1('relink.slug_variants_on', 0) >= 1
           and (l.seg = any (v_sl) or (length(r.ttl) > 10 and l.tn = lower(btrim(r.ttl))))
        union all
        -- CF-247 ops B (S8, relink.year_current_on): the refused page's address with the current handbook year
        select security.course_relink_year_url_v1(r.old_url), 'url_year', 2.4
         where security.pipeline_num_v1('relink.year_current_on', 0) >= 1 and security.course_relink_year_url_v1(r.old_url) is not null
        union all
        -- CF-247 ops B (S7, relink.stored_search_reuse_on): candidates a previous course-page search found and did not try (paid evidence, stored)
        select su.u, 'stored_search', 4 + su.o / 1000.0
          from unnest(security.course_relink_stored_untried_v1(r.course_id)) with ordinality su(u, o)
         where security.pipeline_num_v1('relink.stored_search_reuse_on', 0) >= 1) q
      where q.url is not null
        and security.site_host_v1(q.url) not in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id)  -- s1196: no candidate on a retired host, from any source
        and security.course_relink_url_norm_v1(q.url) is distinct from security.course_relink_url_norm_v1(r.old_url)  -- CF-247 ops B (S6): the refused page in another spelling is not a candidate
        and not (security.course_relink_url_norm_v1(q.url) = any (select security.course_relink_url_norm_v1(u) from unnest(r.tried) u))  -- s1306: not an address this course's relink already tried and failed
        and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = r.course_id and security.course_relink_url_norm_v1(b.url) = security.course_relink_url_norm_v1(q.url))
        and not exists (select 1 from pipeline.page_rejections pr where pr.course_id = r.course_id and security.course_relink_url_norm_v1(pr.url) = security.course_relink_url_norm_v1(q.url))
      order by security.course_relink_url_norm_v1(q.url), q.rk) z;
    if coalesce(cardinality(v_c), 0) = 0 then
      insert into pipeline.course_relink(course_id, provider_id, old_url, pattern, state, reason, decided_at, rule)
      values (r.course_id, p_provider_id, r.old_url, v_forms->0->>'tpl', 'absent', 'no address from the university''s address forms or stored lists', now(), 2)
      on conflict (course_id) do update set pattern = excluded.pattern, reason = excluded.reason, decided_at = now(), rule = 2;
      update pipeline.course_link_search set state = 'none', done_at = coalesce(done_at, now()) where course_id = r.course_id and state = 'queued' and requested_at is null;
      v_absent := v_absent + 1;
    else
      v_c := v_c[1:3]; v_s := v_s[1:3];  -- fixed: at most three candidates a course
      insert into pipeline.course_relink(course_id, provider_id, old_url, candidates, sources, pattern, state, rule)
      values (r.course_id, p_provider_id, r.old_url, to_jsonb(v_c), to_jsonb(v_s), v_forms->0->>'tpl', 'trying', 2)
      on conflict (course_id) do update set candidates = excluded.candidates, sources = excluded.sources, pattern = excluded.pattern, state = 'trying',
             reason = null, decided_at = null, started_at = now(), rule = 2;
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, candidates, cand_idx, bound_url, queued_at, done_at)
      values (r.course_id, p_provider_id, 'title', 'found', to_jsonb(v_c), 1, v_c[1], now(), null)
      on conflict (course_id) do update set stage = 'title', state = 'found', candidates = excluded.candidates, cand_idx = 1, bound_url = excluded.bound_url,
             results = null, attempts = 0, done_at = null;
      perform security.course_link_bind_v1(r.course_id, p_provider_id, v_c[1], v_s[1]);
      v_try := v_try + 1;
    end if;
  end loop;
  return jsonb_build_object('forms', jsonb_array_length(v_forms), 'trying', v_try, 'absent', v_absent, 'stopped', v_stopped);
end $function$;

CREATE OR REPLACE FUNCTION security.course_relink_order_v1()
 RETURNS TABLE(provider_id uuid, pages bigint, pos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 SS-021 (§4): the universities course-relink would take, in the order it takes them: the same candidate rule as
-- security.course_relink_tick_v1 (refused pages not yet relinked, unpublished universities left out), less universities not eligible
-- (waiting for their next attempt or parked), least recently tried first, then the most refused pages.
  select z.provider_id, z.pages, (row_number() over (order by z.la nulls first, z.pages desc, z.provider_id))::int from (
    select p.provider_id, count(*) pages, max(w.last_attempt_at) la
      from pipeline.coverage_course_pages p
      left join pipeline.work_items w on w.lane = 'course_relink' and w.entity = p.provider_id::text and w.work_kind = 'relink'
     where ((p.read_status = any (security.course_relink_statuses_v1())
            or (p.read_status = 'fetch_failed' and p.http_status in (404, 410)
            and exists (select 1 from pipeline.source_proof_requests q0 where q0.course_id = p.course_id and q0.route = 'relink' and q0.state = 'queued'))) or (p.provider_id = any (array(select h.provider_id from security.page_hosts_retired_v1() h)) and (p.provider_id::text || '|' || security.site_host_v1(p.url)) = any (array(select h.provider_id::text || '|' || h.host from security.page_hosts_retired_v1() h)))) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
     group by 1) z
   where security.work_item_eligible_v1('course_relink', z.provider_id::text, 'relink')
   order by 3
$function$;

CREATE OR REPLACE FUNCTION security.course_relink_tick_v1(p_batch integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(1, coalesce(p_batch, 200)); v_pid uuid; v_r jsonb; v_found int; v_absent int; v_prov int := 0;
begin
  perform security.page_refind_settle_v1();  -- 19 Oct 2026: re-finds on a provider's current website
  -- settle: a candidate the reader accepted, or every candidate refused
  update pipeline.course_relink x set state = 'found', decided_at = now(), result_url = s.bound_url, reason = 'the reader confirmed the page'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state = 'verified';
  get diagnostics v_found = row_count;
  update pipeline.course_relink x set state = 'absent', decided_at = now(), reason = 'every candidate address was refused by the reader or did not answer'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state in ('none', 'error');
  get diagnostics v_absent = row_count;
  -- 3 Nov 2026 (SS-021 work continuity §4, wc.relink_fair_on): universities in turn, each isolated, within the run's time budget
  if security.pipeline_num_v1('wc.relink_fair_on', 0) >= 1 then
    return jsonb_build_object('found', v_found, 'absent', v_absent) || security.course_relink_fair_run_v1(v_left);
  end if;
  -- next universities with refused pages not yet relinked
  for v_pid in select p.provider_id from pipeline.coverage_course_pages p
                where ((p.read_status = any (security.course_relink_statuses_v1())
            or (p.read_status = 'fetch_failed' and p.http_status in (404, 410)
            and exists (select 1 from pipeline.source_proof_requests q0 where q0.course_id = p.course_id and q0.route = 'relink' and q0.state = 'queued'))) or (p.provider_id = any (array(select h.provider_id from security.page_hosts_retired_v1() h)) and (p.provider_id::text || '|' || security.site_host_v1(p.url)) = any (array(select h.provider_id::text || '|' || h.host from security.page_hosts_retired_v1() h)))) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
                  and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                group by 1 order by count(*) desc loop
    exit when v_left <= 0;
    v_r := security.course_relink_provider_v1(v_pid, v_left);
    v_left := v_left - (v_r->>'trying')::int - (v_r->>'absent')::int;
    v_prov := v_prov + 1;
  end loop;
  return jsonb_build_object('found', v_found, 'absent', v_absent, 'providers', v_prov);
end $function$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; v_in_order int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  select * into b from s1306_guard;
  if (select count(*) from cron.job) <> b.cron_before then raise exception 'post-check: the number of cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from catalogue.course_links) <> b.links_before then raise exception 'post-check: course links changed'; end if;
  if (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') <> b.official_before then raise exception 'post-check: official links changed'; end if;
  if (select count(*) from pipeline.coverage_course_pages) <> b.pages_before then raise exception 'post-check: course pages changed'; end if;
  if (select count(*) from pipeline.source_proof_requests) <> b.requests_before then raise exception 'post-check: a request was added or removed'; end if;
  if (select count(*) from pipeline.source_proof_requests where route = 'relink' and state = 'queued') <> b.queued_before then raise exception 'post-check: a request changed state'; end if;
  if position('http_status in (404, 410)' in pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) = 0
     or position('http_status in (404, 410)' in pg_get_functiondef('security.course_relink_order_v1()'::regprocedure)) = 0
     or position('http_status in (404, 410)' in pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure)) = 0 then
    raise exception 'post-check: a relink function does not take a gone page that was asked for';
  end if;
  if position('r.tried' in pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) = 0 then raise exception 'post-check: relink does not leave out tried addresses'; end if;
  if position('page_hosts_retired_v1' in pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) = 0 then raise exception 'post-check: relink no longer leaves retired hosts out'; end if;
  -- the priority providers' queued requests now put them in relink's order (before this change none of them was in it for these pages)
  select count(*) into v_in_order from security.course_relink_order_v1() o
   where o.provider_id in ('349da14b-66b1-4c57-9dfd-6f9c36412432'::uuid, '1719c3ba-1ddf-483e-935e-c750124ba99c'::uuid);
  if b.queued_before >= 100 and v_in_order = 0 then raise exception 'post-check: Swinburne and Western Sydney are still not in the relink order'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'relink_gone_pages', 'security.course_relink_provider_v1 / order_v1 / tick_v1',
          jsonb_build_object('reason', 'S1-DG-6 (SS-Programme-Control 27 Nov 2026 13:07), Priority 1: a gone page (fetch_failed, HTTP 404 or 410) with a queued relink request is due for relink; tried addresses are not bound again',
                             'by', 'migration CF-247 s1306', 'queued_requests', b.queued_before, 'priority_providers_in_order', v_in_order), null);
end $p$;
