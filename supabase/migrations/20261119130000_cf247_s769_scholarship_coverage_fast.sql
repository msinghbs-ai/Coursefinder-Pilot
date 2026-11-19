-- CF-247 s769: Scholarships › Coverage loads again (ref 8XEY7B; Platform Admin 19 Nov 2026 13:04 AEDT, chat S1-Build).
-- Measured read only on production 19 Nov 2026 13:05–13:40 AEDT:
--   * The page calls public.admin_scholarship_coverage_read with p_limit 300. It builds one row per provider with
--     security.scholarship_coverage_row_v1, whose list of matches comes from security.scholarship_listing_match_v1. Watch list (27 providers):
--     about 12 s for 12 of them, so the 8-second statement limit of the authenticated role cancels the read and the page shows 8XEY7B.
--     All with scholarships (208 providers) cannot finish at all.
--   * Inside the matcher the planner inlined both CTEs, so security.scholarship_series_key_v1 (regular expressions) ran again for every
--     listed item against every record: 138 items x 21 records took 6.86 s for one provider, and The University of Sydney
--     (582 items x 257 records, 149,574 pairs) did not finish in 58 s. The totals on the page take 14 ms.
--   * The new matcher works out each item's key, address and words once and each record's key, words and addresses once (materialised),
--     then compares them: 92 ms for the 6.86-second provider, 721 ms for Sydney. Same rows on 1,633 matches of 65 providers compared
--     read only; the one other difference was an item listed twice on one page with two links, where distinct on picked either link.
--     The first one on the page is now kept (with ordinality), so the result no longer varies.
--   * The read returns at most 50 providers a page (offset for the next), with limit and offset in its answer; the screen pages through them.
-- Replaces: the inlined matcher in security.scholarship_listing_match_v1; the 300-row page of admin_scholarship_coverage_read.
-- Retires: nothing.
-- No table, column, index or job is added or changed. G1: no job. G2: no setting (a screen's page size is a display window). G3: untouched
-- (security.scholarship_listing_match_v1 and public.admin_scholarship_coverage_read are not consumer API; signatures and grants unchanged).

do $$
begin
  if md5(pg_get_functiondef('security.scholarship_listing_match_v1(uuid)'::regprocedure)) <> '2725ab7c6bde402d50083dbe9fbec90a' then
    raise exception 'pre-check: security.scholarship_listing_match_v1 changed since it was read (19 Nov 2026 13:10)';
  end if;
  if md5(pg_get_functiondef('security.scholarship_coverage_row_v1(uuid)'::regprocedure)) <> '9d1daac45a20a180f0ac03891a479976' then
    raise exception 'pre-check: security.scholarship_coverage_row_v1 changed since it was read (19 Nov 2026 13:10)';
  end if;
  if md5(pg_get_functiondef('public.admin_scholarship_coverage_read(text,text,integer,integer)'::regprocedure)) <> '1c27d8194e2da7c6e8e9ced614caed6e' then
    raise exception 'pre-check: public.admin_scholarship_coverage_read changed since it was read (19 Nov 2026 13:10)';
  end if;
  -- the matches of the smaller watch-list providers as they are now, compared again after the replacement (transaction-local)
  perform set_config('cf247.s769_before', (
    select coalesce(jsonb_agg(jsonb_build_array(w.provider_id, m.listing_id, m.item_name, m.scholarship_id, m.matched_by)
                              order by w.provider_id, m.item_name), '[]'::jsonb)::text
      from pipeline.scholarship_watch w cross join lateral security.scholarship_listing_match_v1(w.provider_id) m
     where w.active
       and (select count(*) from scholarship.scholarships s where s.provider_id = w.provider_id and s.lifecycle_status = 'active')
         * (select count(*) from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) e
             where l.provider_id = w.provider_id and l.active and l.source <> 'suggested') <= 600), true);  -- fixed: post-check sample size
end $$;

create or replace function security.scholarship_listing_match_v1(p_provider_id uuid)
 returns table(listing_id bigint, item_name text, item_url text, scholarship_id uuid, matched_by text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- s769 (19 Nov 2026): each item's and each record's key, words and addresses are worked out once (materialised), not for every pair.
  with items as (
    select distinct on (lower(btrim(e->>'name'))) l.id listing_id, btrim(e->>'name') item_name, nullif(btrim(e->>'url'), '') item_url
      from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) with ordinality e(e, ord)
     where l.provider_id = p_provider_id and l.active and l.source <> 'suggested' and coalesce(btrim(e->>'name'), '') <> ''
     order by lower(btrim(e->>'name')), (nullif(btrim(e->>'url'), '') is null), l.id, e.ord),
  ix as materialized (
    select it.listing_id, it.item_name, it.item_url, q.ik, length(q.ik) >= 15 il, security.scholarship_url_norm(it.item_url) iu,
           array(select w from unnest(regexp_split_to_array(q.ik, '[^a-z0-9]+')) w
                  where length(w) > 3 and w not in ('scholarship', 'scholarships', 'university', 'international')) ikw
      from items it cross join lateral (select security.scholarship_series_key_v1(it.item_name) ik) q),
  recs as materialized (
    select s.id, s.publication_status, kk.k, length(kk.k) >= 15 rl, regexp_split_to_array(kk.k, '[^a-z0-9]+') kw,
           array_remove(array[security.scholarship_url_norm(s.source_url)]
             || array(select security.scholarship_url_norm(i.identifier_value) from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme = 'first_party_detail_url')
             || array(select security.scholarship_url_norm(coalesce(sp.final_url, sp.url)) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id)
             || array(select security.scholarship_url_norm(sp.url) from pipeline.scholarship_pages sp where sp.scholarship_id = s.id), null) urls
      from scholarship.scholarships s cross join lateral (select security.scholarship_series_key_v1(s.name) k) kk
     where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select x.listing_id, x.item_name, x.item_url, m.id, m.how
    from ix x
    left join lateral (
      select r.id, case when x.iu is not null and x.iu = any(r.urls) then 'page' when r.k = x.ik then 'name' else 'similar name' end how
        from recs r
       -- the same rule as v2.15.249 (Fix 5), cheapest test first: the same key; or both keys long and one inside the other; or a link match
       -- whose names agree (one inside the other, or two shared words that are not generic)
       where r.k = x.ik
          or (x.il and r.rl and (strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0))
          or (x.iu is not null and x.iu = any(r.urls)
              and (strpos(r.k, x.ik) > 0 or strpos(x.ik, r.k) > 0 or (select count(*) from unnest(x.ikw) w where w = any(r.kw)) >= 2))
       order by (x.iu is not null and x.iu = any(r.urls)) desc, (r.k = x.ik) desc, (r.publication_status = 'published') desc, r.id
       limit 1) m on true
$function$;

create or replace function public.admin_scholarship_coverage_read(p_scope text default 'watch'::text, p_query text default null::text, p_limit integer default 100, p_offset integer default 0)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_q text := nullif(btrim(coalesce(p_query, '')), ''); v_rows jsonb; v_total int;
  -- s769 (19 Nov 2026): one page is at most 50 providers; the screen asks for the next page with p_offset
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 50)); v_offset int := greatest(0, coalesce(p_offset, 0));
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  with ids as (
    select p.id, coalesce(p.display_name, p.canonical_name) n, upper(substring(p.stable_key from '^provider:cricos:(.+)$')) code from catalogue.providers p
     where p.lifecycle_status = 'active'
       and (case when coalesce(p_scope, 'watch') = 'watch' then exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active)
                 else exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')
                   or exists (select 1 from pipeline.scholarship_listing_pages l where l.provider_id = p.id and l.active)
                   or exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active) end)
       and (v_q is null or p.canonical_name ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'))
  select (select count(*) from ids), coalesce(jsonb_agg(security.scholarship_coverage_row_v1(x.id) || jsonb_build_object('code', x.code) order by x.n, x.code), '[]'::jsonb)
    into v_total, v_rows from (select * from ids order by n, code limit v_limit offset v_offset) x;
  return jsonb_build_object('scope', coalesce(p_scope, 'watch'), 'total', v_total, 'rows', v_rows, 'limit', v_limit, 'offset', v_offset,
    'can_manage', v_rank >= 6, 'can_watch', v_rank >= 5,
    'auto_publish', jsonb_build_object('on', security.scholarship_setting('auto_publish', 0) >= 1,
      'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'provider', coalesce(p.display_name, p.canonical_name), 'at', b.created_at,
                    'status', s.publication_status, 'value', s.award_value_text, 'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'))
                    order by b.created_at desc, s.name), '[]'::jsonb)
                   from pipeline.scholarship_publication_batches b cross join lateral unnest(b.scholarship_ids) sid
                   join scholarship.scholarships s on s.id = sid join catalogue.providers p on p.id = s.provider_id
                  where b.kind = 'publish' and b.approval_ref like 'auto-publish%' and b.created_at > now() - interval '3 days')),
    'totals', jsonb_build_object(
      'watch', (select count(*) from pipeline.scholarship_watch w where w.active),
      'with_listing', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.active and l.source <> 'suggested'),
      'suggested', (select count(distinct l.provider_id) from pipeline.scholarship_listing_pages l where l.source = 'suggested' and not exists (select 1 from pipeline.scholarship_listing_pages a where a.provider_id = l.provider_id and a.active and a.source <> 'suggested')),
      'checked', (select count(*) from pipeline.scholarship_coverage_checks),
      'active', (select count(*) from scholarship.scholarships where lifecycle_status = 'active'),
      'published', (select count(*) from scholarship.scholarships where lifecycle_status = 'active' and publication_status = 'published')));
end $function$;

-- post-checks
do $$
declare v_before jsonb := current_setting('cf247.s769_before')::jsonb; v_after jsonb; v_t timestamptz; v_ms numeric; v_n int;
begin
  select coalesce(jsonb_agg(jsonb_build_array(w.provider_id, m.listing_id, m.item_name, m.scholarship_id, m.matched_by)
                            order by w.provider_id, m.item_name), '[]'::jsonb)
    into v_after
    from pipeline.scholarship_watch w cross join lateral security.scholarship_listing_match_v1(w.provider_id) m
   where w.active
     and (select count(*) from scholarship.scholarships s where s.provider_id = w.provider_id and s.lifecycle_status = 'active')
       * (select count(*) from pipeline.scholarship_listing_pages l, jsonb_array_elements(l.items) e
           where l.provider_id = w.provider_id and l.active and l.source <> 'suggested') <= 600;  -- fixed: post-check sample size
  if jsonb_array_length(v_before) = 0 then raise exception 'post-check: the sample of matches is empty'; end if;
  if v_after is distinct from v_before then
    raise exception 'post-check: the matches of the sampled watch-list providers changed (% before, % after)', jsonb_array_length(v_before), jsonb_array_length(v_after);
  end if;
  -- the whole watch list in one pass, as the page reads it, inside the authenticated role's 8-second limit with room to spare
  v_t := clock_timestamp();
  select count(*) into v_n from (select security.scholarship_coverage_row_v1(w.provider_id) from pipeline.scholarship_watch w where w.active) z;
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  raise notice 's769: % watch-list rows in % ms; % matches compared', v_n, round(v_ms), jsonb_array_length(v_after);
  if v_ms > 4000 then raise exception 'post-check: the watch-list rows took % ms', round(v_ms); end if;  -- fixed: post-check bound
  -- the largest provider (The University of Sydney: 582 listed, 257 records) in one row
  v_t := clock_timestamp();
  perform security.scholarship_coverage_row_v1('68022bdf-43e8-44b3-ac14-e9eed9f71e83');
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  raise notice 's769: the largest provider row in % ms', round(v_ms);
  if v_ms > 4000 then raise exception 'post-check: the largest provider row took % ms', round(v_ms); end if;  -- fixed: post-check bound
  if position('least(coalesce(p_limit, 50), 50)' in (select prosrc from pg_proc where oid = 'public.admin_scholarship_coverage_read(text,text,integer,integer)'::regprocedure)) = 0 then
    raise exception 'post-check: the coverage read is not capped at 50 a page';
  end if;
end $$;
