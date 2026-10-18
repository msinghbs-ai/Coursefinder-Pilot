-- CF-247 (19 Oct 2026, relink follow-up). Found in the live check of 20261018150000 (course-relink):
-- 1 Universities split their course addresses by level (Sydney: courses/pc/{name}.html for postgraduate, courses/uc/{name}.html for
--   undergraduate; Swinburne: course/undergraduate/{name} and course/postgraduate/{name}). The first rule used only the single most common
--   address form, so its share was under the minimum and courses at Sydney (199) and Swinburne (158) were recorded as absent. Now every
--   form followed by at least relink.pattern_min_pages verified pages counts, the forms together must reach relink.pattern_min_share, and
--   each course gets up to three candidates from the forms used by verified pages of its own study level first, then the most common.
--   Courses recorded as absent under the first rule ("no address ...") are relinked again under this rule (rule 2).
-- 2 The worker jobs that read pages (mode read) and search for course pages (mode link_search) had been paused by the idle-job flag
--   (30 runs with nothing to do) shortly before the relink bound its first 200 pages, and the flag only tries them again after 6 hours. A
--   paused worker job now switches on again at the next flag check (every 10 minutes) when work is waiting for it:
--   security.worker_mode_waiting_v1 (read: pages due to be read, the same rule the reader uses; link_search: asked-for searches queued for
--   a Firecrawl target university whose search is not stopped).
-- Guarded: each live definition is md5-checked before it is replaced or edited.
-- Replaces: security.course_relink_provider_v1 (address forms by study level); the wake rule in security.flag_jobs_v1
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('security.course_relink_provider_v1(uuid,integer)'::regprocedure)) <> 'f51e31cceffbd15ffc906d01dfb12220' then raise exception 'live security.course_relink_provider_v1 differs from the definition this change replaces'; end if;
  if md5(pg_get_functiondef('security.flag_jobs_v1()'::regprocedure)) <> '90379a09e3b89d031add182acc339bca' then raise exception 'live security.flag_jobs_v1 differs from the definition this change edits'; end if;
end $guard$;

alter table pipeline.course_relink add column if not exists rule int not null default 1;
comment on column pipeline.course_relink.rule is 'Relink rule the row was decided under: 1 first rule (one address form), 2 address forms by study level (19 Oct 2026).';

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
     where p.provider_id = p_provider_id and p.read_status = 'identity_mismatch'
       and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id
                        and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%'))
     order by p.course_id
     limit greatest(1, p_limit)
  loop
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
      select distinct on (lower(q.url)) q.url, q.src, q.rk from (
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
        union all
        select l.url, 'url_list', 3 from (
          select pu.url from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l
         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug) q
      where lower(q.url) <> lower(r.old_url)
        and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = r.course_id and b.url = q.url)
      order by lower(q.url), q.rk) z;
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
end $function$;

-- the tick picks universities with refused pages not yet relinked, or relinked as absent under the first rule
do $tick$
declare v_def text := pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure); v_new text;
        v_old text := '                where p.read_status = ''identity_mismatch'' and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id)';
begin
  if md5(v_def) <> '99bf9f8c25020375e5c27ce66d0e160c' then raise exception 'live security.course_relink_tick_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'course_relink_tick_v1: the edited line must appear exactly once'; end if;
  v_new := replace(v_def, v_old, '                where p.read_status = ''identity_mismatch'' and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = ''absent'' and x.rule < 2 and x.reason like ''no address%''))');
  execute v_new;
end $tick$;

-- work waiting for a worker mode (the same rules the worker uses to pick its work)
CREATE OR REPLACE FUNCTION security.worker_mode_waiting_v1(p_mode text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case p_mode
    when 'read' then exists (select 1 from pipeline.coverage_course_pages p
                              where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and coalesce(p.leased_until, '-infinity') < now() and p.read_attempts < 3
                                and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id))
    when 'link_search' then exists (select 1 from pipeline.course_link_search s
                              where s.state = 'queued' and s.requested_at is not null
                                and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
                                     or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included))
                                and s.provider_id <> all (array(select x.provider_id from security.fc_search_stopped_v1() x)))
    else false end
$function$;
revoke execute on function security.worker_mode_waiting_v1(text) from public, anon, authenticated;

do $wake$
declare v_def text := pg_get_functiondef('security.flag_jobs_v1()'::regprocedure); v_new text;
        v_old text := 'elsif not j.active and f.state = ''raised'' and f.reason_code = ''idle_paused'' and f.next_check_at <= now() then';
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'flag_jobs_v1: the edited line must appear exactly once'; end if;
  v_new := replace(v_def, v_old, 'elsif not j.active and f.state = ''raised'' and f.reason_code = ''idle_paused'' and (f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode)) then  -- 19 Oct: on again when work is waiting');
  execute v_new;
end $wake$;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.worker_mode_waiting_v1', 'Operations', 'Whether work is waiting for a paused worker job (read, link_search), so the flag check switches it on again', 'active', '20261018160000')
on conflict (kind, name) do nothing;

do $post$
begin
  if position('security.worker_mode_waiting_v1(j.mode)' in pg_get_functiondef('security.flag_jobs_v1()'::regprocedure)) = 0 then raise exception 'post-check: wake rule'; end if;
  if position('x.rule < 2' in pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure)) = 0 then raise exception 'post-check: tick'; end if;
  if not security.worker_mode_waiting_v1('read') then raise exception 'post-check: the relinked pages should be waiting to be read'; end if;
end $post$;
