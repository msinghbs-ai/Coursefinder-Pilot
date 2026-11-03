CREATE OR REPLACE FUNCTION security.course_relink_provider_v1(p_provider_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_forms jsonb; v_share numeric; v_try int := 0; v_absent int := 0; r record; v_c text[]; v_s text[];
        v_min int := security.pipeline_num_v1('relink.pattern_min_pages', 10)::int;
begin
  -- the university's address forms, learnt from its own verified pages: each form with enough pages, and the study level it serves
  with g as (select replace(lower(g.url), s.slug, '{slug}') tpl, c.study_level_id lvl, s.slug
               from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
               cross join lateral (select regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug) s
              where g.provider_id = p_provider_id and g.status = 'bound' and g.read_status = 'read' and g.identity_basis is not null),
  t as (select tpl, count(*) n from g where length(slug) > 5 and strpos(tpl, '{slug}') > 0 group by 1 having count(*) >= v_min)
  select coalesce(jsonb_agg(jsonb_build_object('tpl', t.tpl, 'n', t.n, 'levels',
           (select coalesce(jsonb_agg(distinct g2.lvl), '[]'::jsonb) from g g2 where g2.tpl = t.tpl and g2.lvl is not null)) order by t.n desc), '[]'::jsonb),
         coalesce(sum(t.n), 0)::numeric / nullif((select count(*) from g), 0)
    into v_forms, v_share from t;
  if coalesce(v_share, 0) < security.pipeline_num_v1('relink.pattern_min_share', 0.5) then v_forms := '[]'::jsonb; end if;
  for r in
    select p.course_id, p.url old_url, c.study_level_id lvl, regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug,
           regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt
      from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
     where p.provider_id = p_provider_id and p.read_status = any (security.course_relink_statuses_v1())
       and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id
                        and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
     order by p.course_id
     limit greatest(1, p_limit)
  loop
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
      select distinct on (security.course_relink_url_norm_v1(q.url)) q.url, q.src, q.rk from (
        -- another course's refused page whose title is exactly this course's title
        select o.url, 'page_swap' src, 1::numeric rk from pipeline.coverage_course_pages o
         where o.provider_id = p_provider_id and o.course_id <> r.course_id and o.read_status = 'identity_mismatch' and length(r.nt) > 8
           and r.nt in (regexp_replace(regexp_replace(lower(coalesce(o.candidates->>'h1', '')), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'),
                        regexp_replace(regexp_replace(split_part(split_part(split_part(lower(coalesce(o.candidates->>'page_title', '')), ' | ', 1), ' – ', 1), ' - ', 1), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'))
        union all
        -- address forms: those used by verified pages of the same study level first, then by number of pages
        select replace(fm.form->>'tpl', '{slug}', r.slug), 'url_pattern',
               2 + (case when r.lvl is not null and (fm.form->'levels') @> to_jsonb(r.lvl) then 0 else 0.5 end) + fm.ord / 1000.0
          from jsonb_array_elements(v_forms) with ordinality fm(form, ord) where length(r.slug) > 5
           -- 22 Oct 2026 (NZ review fix 3): address guesses only in relink.url_pattern_countries
           and security.coverage_country(p_provider_id) in (select jsonb_array_elements_text(sx.value) from pipeline.platform_toolset_settings sx
                                                             where sx.toolset_key = 'pipeline' and sx.key = 'relink.url_pattern_countries')
        union all
        select l.url, 'url_list', 3 from (
          select pu.url from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l
         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug
        union all
        -- CF-247 ops B (S5, relink.slug_variants_on): title forms (diacritics, apostrophes, "&", "(Level n)", bracketed qualifiers) and stored page titles
        select l.url, 'url_list_variant', 3.5 from (
          select pu.url, pu.title from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url, dl.anchor_text from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l,
          lateral (select c2.canonical_title t from catalogue.courses c2 where c2.id = r.course_id) ct
         where security.pipeline_num_v1('relink.slug_variants_on', 0) >= 1
           and (security.course_relink_url_seg_v1(l.url) = any (security.course_relink_slugs_v1(ct.t))
                or (length(ct.t) > 10 and lower(btrim(split_part(split_part(coalesce(l.title, ''), ' | ', 1), ' - ', 1))) = lower(btrim(ct.t))))
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
  return jsonb_build_object('forms', jsonb_array_length(v_forms), 'trying', v_try, 'absent', v_absent);
end $function$
