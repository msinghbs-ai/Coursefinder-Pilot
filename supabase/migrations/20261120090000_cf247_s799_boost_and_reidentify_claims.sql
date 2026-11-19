-- CF-247 s799 (Platform Admin 20 Nov 2026 05:42 AEDT, chat S1-Build, item 3): the two claims that still time out under load, after s788 closed enrich_ai.
-- Read live 20 Nov 2026 06:40 AEDT (rolled back): svc_boost_extract_claim(40) 1,526 ms with nothing to hand out; svc_coverage_reidentify_next(100) 588 ms;
-- 3 and 2 HTTP 500 statement time-outs in the last 24 hours. Causes: the boost claim grouped every stored page text by content hash (20,855 rows) once per
-- country (six) to find shared provider pages, then looked up each course's latest page text through the general entity index; the reidentify claim
-- walked the page status index and sorted.
-- Fix (the s788 pattern: an index that matches the claim, and the claim states it): two partial indexes on stored page texts (by hash, and by course
-- and capture time), and one on the pages waiting to be re-identified (by course, the claim's order). The boost claim now checks "is this page shared
-- with another course" per candidate through the hash index; same rule, same output, same lease, same lock, same lanes and weights. The reidentify
-- claim is unchanged; its index now matches its filter and order.
-- The boost claim also keeps the s797 rule: a B7 rule value (source register, no evidence id) is still open to a reading.
-- Parity before writing (read live 20 Nov 2026 05:45 AEDT): head 20261120010000; merged after s797 (20261120070000), whose edit of the same function it keeps.
-- G3: no consumer object. No spend (claims only hand out work that was already due).
-- Replaces: the per-country course walk and content-hash grouping in security.boost_extract_claim_v1; the page check before the done check in
--   public.svc_coverage_reidentify_next.
-- Retires: nothing.

create index if not exists evidence_artifacts_page_text_hash_idx on pipeline.evidence_artifacts (content_hash, entity_id)
  where evidence_type = 'provider_course_page_text' and storage_path is not null and content_hash is not null;
create index if not exists evidence_artifacts_page_text_entity_idx on pipeline.evidence_artifacts (entity_id, captured_at desc nulls last) include (id, content_hash)
  where evidence_type = 'provider_course_page_text' and storage_path is not null;
create index if not exists courses_study_load_open_idx on catalogue.courses (id) include (provider_id)
  where lifecycle_status = 'active' and (study_load is null or (study_load_source = 'register' and study_load_evidence_id is null));
create index if not exists coverage_reidentify_done_rule_idx on pipeline.coverage_reidentify_done (rule, course_id, evidence_id);
create index if not exists coverage_course_pages_reidentify_idx on pipeline.coverage_course_pages (course_id)
  where status = 'mismatch' and read_status = 'identity_mismatch';

do $pre$
declare v_def text := replace(pg_get_functiondef('security.boost_extract_claim_v1(integer)'::regprocedure), chr(13), '');
begin
  if md5(v_def) <> 'a80ff8e9ce2989abe8f786b0748c9357' and v_def not like '%c.study_load_evidence_id is null))  -- s797%' then
    raise exception 'pre-check: security.boost_extract_claim_v1 changed since it was read (definition md5 %)', md5(v_def);
  end if;
end $pre$;

create or replace function security.boost_extract_claim_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_extract
  v_batch text := 'bx-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_cat text := security.boost_lane_category_v1('study_load');
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record; v_codes text[]; v_pool jsonb;
begin
  if not ('study_load' = any (security.pipeline_list_v1('boost.extract_lanes'))) or v_cat is null or v_left = 0 then
    return jsonb_build_object('batch_id', v_batch, 'items', v_items);
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_extract_claim'));
  -- s799: the pages still due are found once, set-based, for every country (each course's latest stored page text, not yet settled or leased,
  -- not shared with another course, no lock); then handed out country by country in the matrix order, as before. At most v_left per country.
  with lp as materialized (
    select distinct on (e.entity_id) e.entity_id, e.id, e.content_hash
      from pipeline.evidence_artifacts e
     where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
     order by e.entity_id, e.captured_at desc nulls last),
  settled as materialized (
    select x.entity_id, x.evidence_id from pipeline.boost_extract_items x
     where x.lane = 'study_load' and (x.state in ('verified', 'rejected', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes'))),  -- fixed: claim lease
  open_courses as materialized (
    select c.id, c.provider_id from catalogue.courses c
     where c.lifecycle_status = 'active' and (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null))),  -- s797
  pick as materialized (
    select lp.entity_id, lp.id evidence_id, lp.content_hash, oc.provider_id
      from lp join open_courses oc on oc.id = lp.entity_id
      left join settled st on st.entity_id = lp.entity_id and st.evidence_id = lp.id
     where st.entity_id is null),
  due as (
    select c.id entity_id, a.id evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) source_url, c.display_title, k.iso_alpha2 cc,
           row_number() over (partition by k.iso_alpha2 order by c.id) n
      from pick
      join catalogue.courses c on c.id = pick.entity_id
      join pipeline.evidence_artifacts a on a.id = pick.evidence_id
      join catalogue.providers p on p.id = pick.provider_id
      join ref.countries k on k.id = p.country_id
       -- a stored page whose text is also stored for another course is a general page of the provider, not this course's page: not read
     where not exists (select 1 from pipeline.evidence_artifacts h where h.content_hash = pick.content_hash and h.evidence_type = 'provider_course_page_text'
                        and h.storage_path is not null and h.content_hash is not null and h.entity_id <> pick.entity_id)
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')))
  select coalesce(jsonb_agg(to_jsonb(due)), '[]'::jsonb) into v_pool from due where n <= v_left;
  if jsonb_array_length(v_pool) = 0 then return jsonb_build_object('batch_id', v_batch, 'items', v_items); end if;
  for r in select m.country_code, m.weight from security.boost_country_category_matrix_v1() m
            where m.enrichment_category = v_cat and m.weight > 0 order by m.priority_rank loop
    exit when v_left <= 0;
    v_codes := array[r.country_code] || array(select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x
                                              where split_part(x, '=', 2) = r.country_code);
    with cand as materialized (
      select d.entity_id, d.evidence_id, d.storage_path, d.source_url, d.display_title
        from jsonb_to_recordset(v_pool) d(entity_id uuid, evidence_id uuid, storage_path text, source_url text, display_title text, cc text, n int)
       where d.cc = any (v_codes)
         and not exists (select 1 from pipeline.boost_extract_items x where x.lane = 'study_load' and x.entity_id = d.entity_id and x.evidence_id = d.evidence_id
                          and x.state = 'claimed' and x.batch_id = v_batch)
       order by d.n limit v_left),
    ins as (
      insert into pipeline.boost_extract_items as t (item_key, lane, entity, entity_id, evidence_id, country_code, state, batch_id, claimed_at)
      select 'sl-' || d.entity_id || '-' || d.evidence_id, 'study_load', 'course', d.entity_id, d.evidence_id, r.country_code, 'claimed', v_batch, now() from cand d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, claimed_at = now(), done_at = null, result_path = null, note = null,
                                          cost = null, model_called = null
      returning t.item_key, t.entity_id, t.evidence_id)
    select coalesce(jsonb_agg(jsonb_build_object('item_key', i.item_key, 'lane', 'study_load', 'entity', 'course', 'entity_id', i.entity_id, 'evidence_id', i.evidence_id,
             'storage_path', d.storage_path, 'source_url', d.source_url, 'country_code', r.country_code, 'weight', r.weight,
             'context', jsonb_build_object('title', d.display_title))), '[]'::jsonb)
      into v_got from ins i join cand d on d.entity_id = i.entity_id and d.evidence_id = i.evidence_id;
    v_items := v_items || v_got;
    v_left := v_left - jsonb_array_length(v_got);
  end loop;
  return jsonb_build_object('batch_id', v_batch, 'items', v_items);
end $function$;

do $pre2$
begin
  if md5(replace(pg_get_functiondef('public.svc_coverage_reidentify_next(integer,text)'::regprocedure), chr(13), '')) <> '7ff3b754b2f78c04835587e0799ece8a' then
    raise exception 'pre-check: public.svc_coverage_reidentify_next changed since it was read';
  end if;
end $pre2$;

create or replace function public.svc_coverage_reidentify_next(p_limit integer, p_rule text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security'
as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- s799: pages already re-identified under this rule are dropped first (index), so the page check runs only on what is still due
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v from (
    with done as materialized (
      select d.course_id, d.evidence_id from pipeline.coverage_reidentify_done d where d.rule = p_rule),
    due as materialized (
      select q.course_id, q.url from pipeline.coverage_course_pages q
        join catalogue.courses co on co.id = q.course_id and co.lifecycle_status = 'active'
        left join done on done.course_id = q.course_id and done.evidence_id = q.evidence_id
       where q.status = 'mismatch' and q.read_status = 'identity_mismatch' and coalesce(q.basis, '') <> 'manual' and done.course_id is null
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
    ok as materialized (
      select due.course_id from due where not security.page_refused_v1(due.course_id, due.url))  /* 24 Oct 2026; S1: a rejected or blocked page is never re-bound */
    select p.course_id, p.evidence_id, e.storage_path, coalesce(nullif(p.candidates->>'final_url', ''), p.url) url, co.canonical_title title, co.course_code code,
           security.coverage_country(p.provider_id) country
      from ok
      join pipeline.coverage_course_pages p on p.course_id = ok.course_id
      join pipeline.evidence_artifacts e on e.id = p.evidence_id
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.status = 'mismatch' and p.read_status = 'identity_mismatch' and coalesce(p.basis, '') <> 'manual' and e.storage_path is not null
       and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)
     order by p.course_id limit greatest(1, least(coalesce(p_limit, 100), 400)) for update of p skip locked) x;  -- fixed: claim bounds
  return v;
end $function$;

-- post-checks: the same work is handed out, and both claims answer in time (timed in a sub-block that is always rolled back: nothing stays claimed)
do $$
declare t timestamptz; ms1 int; ms2 int; ms1b int; n1 int; n2 int; v jsonb; v_rule text; v_o text; a1 int[] := '{}'; a2 int[] := '{}'; i int;
begin
  select max(rule) into v_rule from pipeline.coverage_reidentify_done;
  begin
    t := clock_timestamp(); v := public.svc_boost_extract_claim(security.pipeline_num_v1('batch.boost_extract', 40)::int); ms1 := round(extract(epoch from clock_timestamp() - t) * 1000); n1 := jsonb_array_length(v->'items');
    for i in 1 .. 3 loop
      t := clock_timestamp(); perform public.svc_boost_extract_claim(40); a1 := a1 || round(extract(epoch from clock_timestamp() - t) * 1000)::int;
      t := clock_timestamp(); v := public.svc_coverage_reidentify_next(100, v_rule); a2 := a2 || round(extract(epoch from clock_timestamp() - t) * 1000)::int; n2 := jsonb_array_length(v);
    end loop;
    ms1b := (select percentile_disc(0.5) within group (order by x) from unnest(a1) x); ms2 := (select percentile_disc(0.5) within group (order by x) from unnest(a2) x);
    raise exception 'cf-s799-undo';
  exception when raise_exception then if sqlerrm <> 'cf-s799-undo' then raise; end if;
  end;
  v_o := format('boost claim first %s ms (%s items); warm median %s ms %s | reidentify(100, %s) warm median %s ms %s (%s rows)', ms1, n1, ms1b, a1, v_rule, ms2, a2, n2);
  if ms1b > 200 or ms2 > 200 then raise exception 'post-check: a claim is still slow: %', v_o; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
