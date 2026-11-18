-- CF-247 SS-021 work continuity: course-relink university isolation (Integration Controller 3 Nov 2026 22:16: production verification of
-- v2.15.443 failed; mandate 21:19 §4 "a failed item must not cause an otherwise valid batch to be discarded").
-- Why (live, read-only, 3 Nov 2026 22:17-22:30 AEDT; DIAGNOSIS):
--   * course-relink still failed at 22:04 and 22:14 (2:00.02) on the 120 s statement time-out, inside course_relink_slugs_v1 and
--     course_relink_url_norm_v1, called from one statement of security.course_relink_provider_v1: the per-course candidate query. For every
--     course of a university it re-reads the university's stored address lists (coverage_provider_urls and provider_discovery_links, each
--     de-duplicated by a union), works out every address's last part (course_relink_url_seg_v1, regular expressions) and the course title's
--     address forms (course_relink_slugs_v1, about 20 regular expressions) again for every address, and the page-swap titles of every refused
--     page again: addresses x courses regular-expression work in one statement.
--   * Measured (read-only, 22:25-22:27): the head of the order now, de2201a1, has 14,189 stored addresses (9,399 list + 4,790 discovery) and 204
--     refused active courses; working out its addresses once takes 2.6 s, one title's address forms 3.2 ms. The live step does both for every
--     address and course: about 14,189 x 3.2 ms = 45 s for each course, so two or three courses pass the 120 s limit. The next in line have
--     2,457-11,959 addresses (22657140, 719403bc, 8e1adb6c); 9d22a19e has 3,886 and 170 courses. 6c7c4d60 (32 addresses, 5 courses), parked by
--     the 22:18 attribution, is most likely not the cause: attribution after a rolled-back run can only name the head of the order at that time.
--     A fixture with 305 addresses and 6 courses calls the title forms 1,830 times on the live step and 6 times after this change.
--   * v2.15.443's fair order moved the first slow university (9d22a19e) behind its backoff at 22:08, and the next (6c7c4d60) timed out at
--     22:14: fair order does not isolate a university whose single statement outlasts the run's statement limit.
-- What:
--   1 security.course_relink_provider_v1 (md5-guarded edit, same answers): the address lists, their last parts, the stored titles and the
--     page-swap titles are prepared once a university (at most relink.urls_per_university addresses); each course works out its title forms
--     once and compares plain text against the prepared arrays. It stops between courses at the university's deadline (cf247.relink_deadline,
--     set by the run) and says so ({stopped: 'deadline'}).
--   2 security.course_relink_fair_run_v1 (md5-guarded replacement): each university gets a deadline of wc.relink_university_seconds (never past
--     the run's wc.relink_run_seconds). A university that settles nothing within it is recorded through security.work_item_report_v1 as a
--     transient failure (backoff, parked after wc.transient_max_attempts); one that settled some courses is done for this turn and goes to the
--     back. Last resort: if the statement limit still fires inside a university, the explicit "when query_canceled" handler rolls back only
--     that university, records it (sqlstate 57014) and ends the run, which then commits what the other universities did (the limit is not
--     re-armed within a statement, so the run never continues past it).
-- Activation: ships ON with wc.relink_fair_on (already 1): it only bounds and isolates; it asks no more searches than before.
-- md5 (before = live, read 3 Nov 2026 22:17-22:20 AEDT; after = this change):
--   security.course_relink_provider_v1(uuid,integer) 776844024ca5ee99011ad73dfd36360b -> 07bd965bac8b7cd7b41a3092c447d677
--   security.course_relink_fair_run_v1(integer)      cd5a842d0f87bbe5439934eec66af4ac -> 772a488ece3dc0bc9dc21cd8a9dc9f64
-- Unchanged (live md5): security.course_relink_tick_v1(integer) 656d308b1b12532a7e3e4335cf0f21ea, security.course_relink_slugs_v1(text)
--   e23ce200e949319136eff9e1a2abd74a, security.course_relink_url_norm_v1(text) c1b2eed2bb21d0ab92c500d88afe022c, security.course_relink_url_seg_v1(text)
--   306fcb507a215e5ed6b16f4876598fa7, security.work_item_report_v1(text,text,text,text,jsonb) 6a15318c0ecd6644b32f1883463c542e.
-- Replaces: security.course_relink_provider_v1, security.course_relink_fair_run_v1 (same names; md5-guarded)
-- Retires: nothing
-- Nothing is dropped or deleted. Consumer API untouched (G3). No Firecrawl or AI spend.

do $g$
declare r record;
begin
  if to_regclass('pipeline.work_items') is null then raise exception 'work continuity (migration 20261104170000) must be applied before this change'; end if;
  for r in select * from (values ('security.course_relink_tick_v1(integer)', '656d308b1b12532a7e3e4335cf0f21ea'),
                                 ('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

-- an edit applied once, only from the definition it was written against (the 20261103050000 helper)
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- a whole definition replaced, only from the definition it was written against
create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'wc.relink_university_seconds', 'Work continuity: course re-linking time for one university',
  'A university stops starting new courses after this long in one run; one that settled none in this time waits for its next attempt (and is parked after its attempts). Keep it well under the run''s time budget.',
  'number', to_jsonb(20), 5, 100, 'seconds', 1320, 'Work continuity', 'security.course_relink_fair_run_v1; security.course_relink_provider_v1', 'Integration Controller 3 Nov 2026 22:16: course-relink still timed out at 22:04 and 22:14 inside one university'),
 ('pipeline', 'relink.urls_per_university', 'Course re-linking: stored addresses compared per university',
  'At most this many stored addresses of a university (its address list and discovery links) are prepared once and compared with each refused course.',
  'number', to_jsonb(50000), 1000, 500000, 'addresses', 1321, 'Work continuity', 'security.course_relink_provider_v1', 'Integration Controller 3 Nov 2026 22:16 (bounded per-university work)')
on conflict do nothing;

-- 2 the university step: prepared once a university, compared per course, stopped at the deadline
select pg_temp.edit_once('security.course_relink_provider_v1(uuid,integer)', '776844024ca5ee99011ad73dfd36360b', '07bd965bac8b7cd7b41a3092c447d677',
  array[array[$o$declare v_forms jsonb; v_share numeric; v_try int := 0; v_absent int := 0; r record; v_c text[]; v_s text[];
$o$, $n$declare v_forms jsonb; v_share numeric; v_try int := 0; v_absent int := 0; r record; v_c text[]; v_s text[];
        -- 3 Nov 2026 (SS-021 relink isolation): the university's addresses and swap titles, prepared once a university (not once a course)
        v_u text[]; v_ut text[]; v_useg text[]; v_usl text[]; v_utn text[]; v_ou text[]; v_oc uuid[]; v_ok1 text[]; v_ok2 text[]; v_sl text[];
        v_deadline timestamptz := nullif(current_setting('cf247.relink_deadline', true), '')::timestamptz; v_stopped text;
        v_cap int := security.pipeline_num_v1('relink.urls_per_university', 50000)::int;
$n$],
  array[$o$  for r in
    select p.course_id, p.url old_url,$o$, $n$  -- 3 Nov 2026 (SS-021 relink isolation, live 22:04 and 22:14 AEDT): the stored address lists were read, and every address's last part and the
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
           order by u.url, u.title limit v_cap) l;
  select array_agg(o.url), array_agg(o.course_id),
         array_agg(regexp_replace(regexp_replace(lower(coalesce(o.candidates->>'h1', '')), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g')),
         array_agg(regexp_replace(regexp_replace(split_part(split_part(split_part(lower(coalesce(o.candidates->>'page_title', '')), ' | ', 1), ' – ', 1), ' - ', 1), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'))
    into v_ou, v_oc, v_ok1, v_ok2
    from pipeline.coverage_course_pages o where o.provider_id = p_provider_id and o.read_status = 'identity_mismatch';
  for r in
    select p.course_id, p.url old_url,$n$],
  array[$o$regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt
$o$, $n$regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt, c.canonical_title ttl
$n$],
  array[$o$  loop
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
$o$, $n$  loop
    -- 3 Nov 2026 (SS-021 relink isolation): stop between courses at the university's deadline (set by security.course_relink_fair_run_v1)
    if v_deadline is not null and clock_timestamp() >= v_deadline then v_stopped := 'deadline'; exit; end if;
    v_sl := security.course_relink_slugs_v1(r.ttl);
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
$n$],
  array[$o$        select o.url, 'page_swap' src, 1::numeric rk from pipeline.coverage_course_pages o
         where o.provider_id = p_provider_id and o.course_id <> r.course_id and o.read_status = 'identity_mismatch' and length(r.nt) > 8
           and r.nt in (regexp_replace(regexp_replace(lower(coalesce(o.candidates->>'h1', '')), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'),
                        regexp_replace(regexp_replace(split_part(split_part(split_part(lower(coalesce(o.candidates->>'page_title', '')), ' | ', 1), ' – ', 1), ' - ', 1), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'))
$o$, $n$        select o.url, 'page_swap' src, 1::numeric rk from unnest(v_ou, v_oc, v_ok1, v_ok2) o(url, course_id, k1, k2)
         where o.course_id <> r.course_id and length(r.nt) > 8 and r.nt in (o.k1, o.k2)
$n$],
  array[$o$        select l.url, 'url_list', 3 from (
          select pu.url from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l
         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug
$o$, $n$        select l.url, 'url_list', 3 from unnest(v_u, v_usl) l(url, sl)
         where length(r.slug) > 10 and l.sl = r.slug
$n$],
  array[$o$        select l.url, 'url_list_variant', 3.5 from (
          select pu.url, pu.title from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url, dl.anchor_text from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l,
          lateral (select c2.canonical_title t from catalogue.courses c2 where c2.id = r.course_id) ct
         where security.pipeline_num_v1('relink.slug_variants_on', 0) >= 1
           and (security.course_relink_url_seg_v1(l.url) = any (security.course_relink_slugs_v1(ct.t))
                or (length(ct.t) > 10 and lower(btrim(split_part(split_part(coalesce(l.title, ''), ' | ', 1), ' - ', 1))) = lower(btrim(ct.t))))
$o$, $n$        select l.url, 'url_list_variant', 3.5 from unnest(v_u, v_useg, v_utn) l(url, seg, tn)
         where security.pipeline_num_v1('relink.slug_variants_on', 0) >= 1
           and (l.seg = any (v_sl) or (length(r.ttl) > 10 and l.tn = lower(btrim(r.ttl))))
$n$],
  array[$o$  return jsonb_build_object('forms', jsonb_array_length(v_forms), 'trying', v_try, 'absent', v_absent);$o$, $n$  return jsonb_build_object('forms', jsonb_array_length(v_forms), 'trying', v_try, 'absent', v_absent, 'stopped', v_stopped);$n$]], array[1, 1, 1, 1, 1, 1, 1, 1]);

-- 3 the run: a deadline per university, a slow one recorded, the statement limit caught only as the last resort
select pg_temp.replace_once('security.course_relink_fair_run_v1(integer)', 'cd5a842d0f87bbe5439934eec66af4ac', '772a488ece3dc0bc9dc21cd8a9dc9f64', $def$
create or replace function security.course_relink_fair_run_v1(p_left int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§4): course-relink's university loop with continuity. Each university runs in its own block with a deadline of
-- wc.relink_university_seconds (never past the run's wc.relink_run_seconds), checked by security.course_relink_provider_v1 between courses.
-- A university that settles nothing by its deadline, or raises, is recorded through security.work_item_report_v1 (transient: backoff, then
-- parked) and the run goes on. Last resort: the statement limit firing inside a university is caught explicitly (query_canceled), only that
-- university is rolled back and recorded, and the run ends there so the other universities' work commits (the limit is not re-armed within
-- the statement). No new university starts once the run has taken wc.relink_run_seconds.
declare v_left int := greatest(1, coalesce(p_left, 1)); v_start timestamptz := clock_timestamp(); v_budget numeric := security.pipeline_num_v1('wc.relink_run_seconds', 60);
        v_each numeric := security.pipeline_num_v1('wc.relink_university_seconds', 20);
        r record; v_r jsonb; v_prov int := 0; v_err int := 0; v_slow int := 0; v_stopped text; v_state text; v_msg text; v_t0 timestamptz; v_moved int;
begin
  for r in select * from security.course_relink_order_v1() loop
    if v_left <= 0 then v_stopped := 'batch'; exit; end if;
    if extract(epoch from clock_timestamp() - v_start) >= v_budget then v_stopped := 'time_budget'; exit; end if;
    v_t0 := clock_timestamp();
    perform set_config('cf247.relink_deadline', least(v_start + make_interval(secs => v_budget::float8), v_t0 + make_interval(secs => v_each::float8))::text, true);
    begin
      v_r := security.course_relink_provider_v1(r.provider_id, v_left);
      v_moved := coalesce((v_r->>'trying')::int, 0) + coalesce((v_r->>'absent')::int, 0);
      v_left := v_left - v_moved;
      v_prov := v_prov + 1;
      if v_moved = 0 and v_r->>'stopped' = 'deadline' then
        v_slow := v_slow + 1;
        perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'failed',
                  jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink', 'class', 'transient',
                                     'message', 'no course settled within the university''s time (wc.relink_university_seconds)',
                                     'evidence', jsonb_build_object('pages', r.pages, 'seconds', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1))));
      else
        perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'succeeded',
                  jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink',
                                     'outcome', case when v_moved > 0 then 'succeeded_with_result' else 'succeeded_no_movement' end));
      end if;
    exception
      when query_canceled then
        -- last resort: the statement limit fired inside this university; its work is rolled back, the others' is kept, and the run ends here
        get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
        v_err := v_err + 1;
        perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'failed',
                  jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink', 'class', 'transient', 'sqlstate', v_state, 'message', v_msg,
                                     'evidence', jsonb_build_object('pages', r.pages, 'seconds', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1))));
        v_stopped := 'statement_timeout';
        exit;
      when others then
        get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
        v_err := v_err + 1;
        perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'failed',
                  jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink', 'sqlstate', v_state, 'message', v_msg, 'evidence', jsonb_build_object('pages', r.pages)));
    end;
  end loop;
  perform set_config('cf247.relink_deadline', '', true);
  return jsonb_build_object('providers', v_prov, 'failed', v_err, 'slow', v_slow, 'stopped', v_stopped, 'seconds', round(extract(epoch from clock_timestamp() - v_start)::numeric, 1));
end $function$;
$def$);
revoke all on function security.course_relink_fair_run_v1(int) from public, anon, authenticated;
