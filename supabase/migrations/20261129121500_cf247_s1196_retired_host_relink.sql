-- CF-247 s1196 (S1-Build / Release Controller; Platform Admin decision D1, 26 Nov 2026 15:09 AEDT, relayed by SS-Programme-Control: "Prevent retired
-- hosts from being reused by relink address learning, stored-list candidates and site-map binding ... Rediscover the affected Adelaide courses using
-- the current official website ... Preserve existing valid canonical requirements and manual locks until a verified successor is available.").
-- Found live (26 Nov 2026, rolled back): the 18 Oct page refind (security.page_refind_start_v1) moved 229 Adelaide University pages from adelaide.edu.au
-- to adelaideuni.edu.au. Afterwards course relink learnt address forms from 22 verified pages still on the old host, and the stored list (9,399
-- addresses) is the old host's site map, so 56 active courses were bound to the retired host again; it now answers 404.
-- What this does:
--   1. security.page_hosts_retired_v1(): the hosts a page refind retired, per provider (an old page's host that is neither the provider's website host
--      nor a subdomain of it). Live: one provider, Adelaide University, adelaide.edu.au. Official domains and subdomains are never in it.
--   2. Course relink (security.course_relink_provider_v1) learns no address form from a retired host, takes no stored address and no candidate from
--      any source on one, and takes a page bound on a retired host as due for relink. The universities it takes (security.course_relink_order_v1,
--      security.course_relink_tick_v1) count such pages the same way.
--   3. The site-map binder (security.coverage_bind_v2) never reads a stored address on a retired host.
--   4. A trigger on pipeline.coverage_course_pages (security.course_page_retired_host_guard_v1) refuses any machine write that would move or add a
--      page on a retired host, whichever function makes it; a person's manual binding is left to them.
--   5. The Adelaide courses bound on the retired host are asked again through the existing route (pipeline.source_proof_requests, route relink), and
--      the provider's site map is due now (the /bin/bash site-map read of its current website through the existing discovery).
-- Unchanged: a binding changes only when the reader verifies a successor page (existing relink and course-page search); canonical requirements, manual
-- locks, Layer 4, identity rules and the 35 courses with no page on the new site (D2: retained, no lifecycle change) are not touched.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: security.course_relink_provider_v1, security.course_relink_order_v1, security.course_relink_tick_v1, security.coverage_bind_v2 (same
-- functions, retired hosts left out).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and four function replacements

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) <> '07bd965bac8b7cd7b41a3092c447d677' then raise exception 'guard: security.course_relink_provider_v1 is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('security.course_relink_order_v1()'::regprocedure)) <> 'c10ec3367cbd409f255afecf52248ce9' then raise exception 'guard: security.course_relink_order_v1 is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure)) <> '656d308b1b12532a7e3e4335cf0f21ea' then raise exception 'guard: security.course_relink_tick_v1 is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure)) <> 'ec5087e303c70ecee9cd9fae705b78a8' then raise exception 'guard: security.coverage_bind_v2 is not the definition read on 26 Nov 2026'; end if;
end $g$;
create temp table s1196_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1196_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none
create temp table s1196_rows on commit drop as select status, count(*) n from catalogue.course_entry_requirements group by 1;
create temp table s1196_pages on commit drop as select course_id, url, status, read_status, basis from pipeline.coverage_course_pages;

create or replace function security.page_hosts_retired_v1() returns table(provider_id uuid, host text)
language sql stable security definer set search_path to '' as $function$
  -- CF-247 s1196: the hosts a page refind retired for a provider: an old page's host that is neither the provider's website host nor a subdomain of it
  select distinct r.provider_id, security.site_host_v1(r.old_url)
    from pipeline.page_refind r join catalogue.providers pr on pr.id = r.provider_id
   where security.site_host_v1(r.old_url) is not null
     and security.site_host_v1(r.old_url) <> coalesce(security.site_host_v1(pr.website), '')
     and security.site_host_v1(r.old_url) not like '%.' || coalesce(security.site_host_v1(pr.website), '-')
$function$;
comment on function security.page_hosts_retired_v1() is 'CF-247 s1196: hosts a page refind retired per provider (never the website host or a subdomain of it); left out of course relink and the site-map binder.';
revoke all on function security.page_hosts_retired_v1() from public, anon, authenticated;

-- s1196: one guard for every writer of a course page (the binders, relink, page search, AI match, refind, rollover): a machine write never moves a page
-- onto a host a refind retired, and never adds one there. A person's manual binding (basis manual) is left to them; a row already on such a host keeps
-- its other updates until relink finds its successor.
create or replace function security.course_page_retired_host_guard_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
begin
  if new.url is null or coalesce(new.basis, '') = 'manual' then return new; end if;
  if tg_op = 'UPDATE' and old.url is not distinct from new.url then return new; end if;
  if not exists (select 1 from pipeline.page_refind r where r.provider_id = new.provider_id) then return new; end if;
  if (new.provider_id::text || '|' || security.site_host_v1(new.url)) = any (array(select h.provider_id::text || '|' || h.host from security.page_hosts_retired_v1() h)) then
    if tg_op = 'UPDATE' then return old; end if;
    return null;
  end if;
  return new;
end $function$;
comment on function security.course_page_retired_host_guard_v1() is 'CF-247 s1196: no machine write moves a course page onto, or adds one on, a host a page refind retired (manual bindings excepted).';
revoke all on function security.course_page_retired_host_guard_v1() from public, anon, authenticated;

create or replace trigger course_page_retired_host_guard before insert or update of url on pipeline.coverage_course_pages
  for each row execute function security.course_page_retired_host_guard_v1();

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
           regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt, c.canonical_title ttl
      from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
     where p.provider_id = p_provider_id and (p.read_status = any (security.course_relink_statuses_v1())
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
     where (p.read_status = any (security.course_relink_statuses_v1()) or (p.provider_id = any (array(select h.provider_id from security.page_hosts_retired_v1() h)) and (p.provider_id::text || '|' || security.site_host_v1(p.url)) = any (array(select h.provider_id::text || '|' || h.host from security.page_hosts_retired_v1() h)))) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
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
                where (p.read_status = any (security.course_relink_statuses_v1()) or (p.provider_id = any (array(select h.provider_id from security.page_hosts_retired_v1() h)) and (p.provider_id::text || '|' || security.site_host_v1(p.url)) = any (array(select h.provider_id::text || '|' || h.host from security.page_hosts_retired_v1() h)))) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
                  and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                group by 1 order by count(*) desc loop
    exit when v_left <= 0;
    v_r := security.course_relink_provider_v1(v_pid, v_left);
    v_left := v_left - (v_r->>'trying')::int - (v_r->>'absent')::int;
    v_prov := v_prov + 1;
  end loop;
  return jsonb_build_object('found', v_found, 'absent', v_absent, 'providers', v_prov);
end $function$;

CREATE OR REPLACE FUNCTION security.coverage_bind_v2(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v_bound int; v_amb int;
begin
  drop table if exists _cb_c, _cb_u, _cb_s, _cb_best;
  create temp table _cb_c on commit drop as
    select co.id course_id, lower(co.course_code) code, security.coverage_text_tokens(co.canonical_title) tok
      from catalogue.courses co where co.provider_id=p_provider_id and co.lifecycle_status='active';
  create temp table _cb_u on commit drop as
    select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
      from pipeline.coverage_provider_urls where provider_id=p_provider_id
       and security.site_host_v1(url) not in (select h.host from security.page_hosts_retired_v1() h where h.provider_id = p_provider_id)  -- s1196: the site-map binder never binds a retired host
       and url !~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|pathways?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|research|contact|faqs?)(/|$)';
  create temp table _cb_s on commit drop as
    with ct as (select course_id, cardinality(tok) nc, t from _cb_c, unnest(tok) t),
         ut as (select url, 's' k, ns n, t from _cb_u, unnest(tokens) t union all select url, 't', nt, t from _cb_u, unnest(title_tokens) t),
         m as (select ct.course_id, ut.url, ut.k, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1,2,3)
    select course_id, url, max(2.0*hits/nullif(nc+nu,0)) sc, false by_code from m group by 1,2
    union all
    select c.course_id, u.url, 1.0, true from _cb_c c join _cb_u u
      on c.code is not null and length(c.code)>=6 and (position(c.code in lower(u.url))>0 or position(c.code in lower(coalesce(u.title,'')))>0);
  create temp table _cb_best on commit drop as
    with s as (select course_id, url, max(sc) sc, bool_or(by_code) by_code from _cb_s group by 1,2),
         rc as (select *, row_number() over (partition by course_id order by sc desc, length(url)) rk_c,
                          lead(sc) over (partition by course_id order by sc desc, length(url)) nxt_c,
                          row_number() over (partition by url order by sc desc) rk_u,
                          lead(sc) over (partition by url order by sc desc) nxt_u from s)
    select course_id, url, sc, coalesce(nxt_c,0) nxt, by_code,
           by_code or (sc>=0.8 and sc-coalesce(nxt_c,0)>=0.1 and rk_u=1 and sc-coalesce(nxt_u,0)>=0.1) or (sc>=0.999 and coalesce(nxt_c,0)<0.999 and rk_u=1 and coalesce(nxt_u,0)<0.999) mutual
      from rc where rk_c=1 and sc>=0.6;
  insert into pipeline.coverage_course_pages(course_id,provider_id,url,score,runner_up,basis,status,bound_at,next_read_at)
  select course_id, p_provider_id, url, round(sc,3), round(nxt,3), case when by_code then (case security.coverage_country(p_provider_id) when 'AU' then 'cricos_code' when 'NZ' then 'nzqa_code' else 'adapter_code' end) else 'title_match' end,
         case when mutual then 'bound' else 'ambiguous' end, now(), now()
    from _cb_best where not security.page_refused_v1(course_id, url)  -- S1: the site-map binder skips refused pages
  on conflict (course_id) do update set url=excluded.url, score=excluded.score, runner_up=excluded.runner_up, basis=excluded.basis,
         status=excluded.status, bound_at=now(),
         read_status=case when pipeline.coverage_course_pages.url is distinct from excluded.url then null else pipeline.coverage_course_pages.read_status end,
         next_read_at=case when pipeline.coverage_course_pages.url is distinct from excluded.url then now() else pipeline.coverage_course_pages.next_read_at end
   where (pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url)
     and coalesce(pipeline.coverage_course_pages.basis,'') not in ('cricos_search','title_search','manual','ai_match')
     -- W31 (30 Oct 2026): a page the reader has proved with a code or manual proof is never re-scored on title tokens (unless refused)
     and not (pipeline.coverage_course_pages.read_status = 'read'
              and pipeline.coverage_course_pages.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')
              and not security.page_refused_v1(pipeline.coverage_course_pages.course_id, pipeline.coverage_course_pages.url));
  -- courses whose earlier binding no longer holds (page gone or no longer a mutual best) are released
  update pipeline.coverage_course_pages p set status='ambiguous'
   where p.provider_id=p_provider_id and p.status='bound' and coalesce(p.basis,'') in ('title_match','cricos_code','nzqa_code','adapter_code')  -- W31: rows this binder bound
     and not (p.read_status = 'read' and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual') and not security.page_refused_v1(p.course_id, p.url))
     and not exists(select 1 from _cb_best b where b.course_id=p.course_id and b.url=p.url and b.mutual);
  update pipeline.coverage_provider_discovery set bound_at=now() where provider_id=p_provider_id;
  select count(*) filter (where status='bound'), count(*) filter (where status='ambiguous') into v_bound, v_amb from pipeline.coverage_course_pages where provider_id=p_provider_id;
  return jsonb_build_object('bound',v_bound,'ambiguous',v_amb);
end $function$;

do $a$
declare v_pid uuid; v_q int; v_skip int; v_n int; v_d int;
  v_reason constant text := 'Platform Admin decision D1, 26 Nov 2026 15:09 AEDT: rediscover the courses bound on a retired host on the current official website (CF-247 s1196)';
begin
  if (select count(*) from security.page_hosts_retired_v1()) < 1 then raise exception 's1196: no retired host found'; end if;
  create temp table s1196_due on commit drop as
    select p.course_id, p.provider_id, p.url from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
     where p.provider_id in (select h.provider_id from security.page_hosts_retired_v1() h)
       and (p.provider_id, security.site_host_v1(p.url)) in (select h.provider_id, h.host from security.page_hosts_retired_v1() h);
  select count(*) into v_n from s1196_due;
  -- a relink still trying candidates on a retired host (left from before this change) is asked again, so its candidates are worked out anew
  insert into s1196_due select distinct x.course_id, x.provider_id, null from pipeline.course_relink x, jsonb_array_elements_text(coalesce(x.candidates, '[]'::jsonb)) c
   where x.state = 'trying' and (x.provider_id, security.site_host_v1(c)) in (select h.provider_id, h.host from security.page_hosts_retired_v1() h)
     and not exists (select 1 from s1196_due d where d.course_id = x.course_id);
  if v_n < 1 or v_n > 200 then raise exception 's1196: % courses on a retired host, not the 56 measured', v_n; end if;  -- fixed: the measured cohort's size
  insert into pipeline.source_proof_requests (course_id, provider_id, route, state, attempts, requested_at, detail)
  select d.course_id, d.provider_id, 'relink', 'queued', 0, now(), jsonb_build_object('reason', v_reason, 'by', 'migration CF-247 s1196', 'retired_url', d.url)
    from s1196_due d
  on conflict (course_id) do update set route = 'relink', state = 'queued', attempts = 0, requested_at = now(), settled_at = null, outcome = null, detail = excluded.detail
   where pipeline.source_proof_requests.state = 'done'
      or (pipeline.source_proof_requests.state = 'held' and pipeline.source_proof_requests.route = 'no_route');  -- held for want of a route: relink is that route now; a locked or other open request is left as it is
  get diagnostics v_q = row_count;
  v_skip := (select count(*) from s1196_due) - v_q;
  update pipeline.coverage_provider_discovery d set next_due_at = now(), attempts = 0, requested_at = now(), updated_at = now()
   where d.provider_id in (select provider_id from s1196_due) and d.status in ('mapped', 'failed');
  get diagnostics v_d = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'retired_host_relink', 'security.page_hosts_retired_v1', jsonb_build_object('reason', v_reason, 'by', 'migration CF-247 s1196',
          'retired_hosts', (select jsonb_agg(jsonb_build_object('provider_id', provider_id, 'host', host)) from security.page_hosts_retired_v1()),
          'courses_on_retired_host', v_n, 'courses_asked_total', (select count(*) from s1196_due), 'relink_asked', v_q, 'left_open_by_another_lane', v_skip, 'site_map_due', v_d), null);
  raise notice 's1196: % courses on a retired host; % asked again, % left open; % site maps due', v_n, v_q, v_skip, v_d;
end $a$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1196_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1196_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select status, count(*) from catalogue.course_entry_requirements group by 1 except select status, n from s1196_rows) then raise exception 'post-check: canonical requirements changed'; end if;
  if exists (select course_id, url, status, read_status, basis from pipeline.coverage_course_pages except select * from s1196_pages) then raise exception 'post-check: a course page binding changed'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'course_page_retired_host_guard' and tgrelid = 'pipeline.coverage_course_pages'::regclass and not tgisinternal) then raise exception 'post-check: the retired-host guard is not on pipeline.coverage_course_pages'; end if;
  if position('page_hosts_retired_v1' in pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) = 0
     or position('page_hosts_retired_v1' in pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure)) = 0
     or position('page_hosts_retired_v1' in pg_get_functiondef('security.course_relink_order_v1()'::regprocedure)) = 0
     or position('page_hosts_retired_v1' in pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure)) = 0 then
    raise exception 'post-check: a relink or binder function does not leave retired hosts out';
  end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
