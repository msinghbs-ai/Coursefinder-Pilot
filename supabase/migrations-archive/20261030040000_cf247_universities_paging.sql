-- CF-247 decision W33 (30 Oct 2026, Workstream 3 release health, lane J): Layer 2/3 › Universities reads one page at a time.
-- Numbered 20261030040000 by the integrator (release v2.15.371, with W31).
-- Why: public.admin_layer23('universities') answered every university in one reply: 2,421 rows, 1,967,164 bytes and about 3.2 s measured
-- by the deployed performance test (budgets 700,000 bytes and 3 s, unchanged). Most of the bytes are the onboarding object (611 KB), the
-- Firecrawl target (238 KB), the adapter (234 KB) and the latest Qualify (157 KB); the onboarding stage was worked out for all 1,757
-- onboarding rows (about 0.4 s) and the course-page counts for every university (about 0.3 s) on each open.
-- What: a new action 'universities_page' beside 'universities' in the same function. It applies the screen's filters (country, state,
-- provider kind, adapter, latest Qualify, Firecrawl target, journey stage), the name search and the order (by name) on the server and
-- answers one page of the same rows, with the counts the screen shows (matched, total, the adapter tally) and the country and state
-- choices. mode 'ticks' answers every matching row in short form for "Tick every row shown". The page size and the most rows ticked at
-- once are settings (G2). Measured read-only on 30 Oct 2026: the first page of 100 rows is about 69 KB in 0.65 to 1.0 s.
-- Replaces: public.admin_layer23('universities') (the whole list in one reply) with public.admin_layer23('universities_page') for the Universities screen (screen release in the same change)
-- Retires: the 'universities' action of public.admin_layer23 and, through it, public.admin_adapters('list'): kept answering until the screen release that reads 'universities_page' is live, then taken out by a later md5-guarded edit after hygiene.retire_after_days (no table, job or edge function retires)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266): admin_layer23 is an admin read. No new job or table.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer23.universities_page_size', 'Layer 2/3 › Universities: rows a page',
  'The Universities list is read this many rows at a time, filtered, searched and ordered on the server; Show more reads the next page. A larger page is a larger, slower reply.', 'number',
  to_jsonb(100), 25, 500, 'rows', 691, 'Onboarding', 'public.admin_layer23 (universities_page); Layer 2/3 › Universities',
  'CF-247 decision W33 (30 Oct 2026): the whole list was 1.97 MB in one reply against the 700 KB screen budget'),
 ('pipeline', 'layer23.universities_tick_max', 'Layer 2/3 › Universities: most rows ticked at once',
  '"Tick every row shown" ticks at most this many of the rows the filters match, in name order. Bulk actions on adapters take at most 2,000 at a time.', 'number',
  to_jsonb(2000), 100, 2000, 'rows', 692, 'Onboarding', 'public.admin_layer23 (universities_page, mode ticks); Layer 2/3 › Universities',
  'CF-247 decision W33 (30 Oct 2026): ticking every matching row reads them in short form from the server')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- the new action is answered before the temporary tables the other actions build (it needs neither); 'operations' and 'universities' are unchanged
-- live md5 aaf0e7d8438ffb863375c9617e619fea read on 30 Oct 2026 (lane J, read-only)
select pg_temp.edit_n('public.admin_layer23(text,jsonb)', 'aaf0e7d8438ffb863375c9617e619fea', array[
  array[$o$  create temp table if not exists _l23_inbox$o$,
        $n$  if p_action = 'universities_page' then
    -- CF-247 W33 (30 Oct 2026): one page of Layer 2/3 › Universities. The filters, the name search and the order (by name) the screen
    -- offered on the whole list are applied here; the page size and the most rows ticked at once are settings (layer23.*). The same
    -- rows and fields as 'universities'; the onboarding stage and the course-page counts are worked out for the rows of the page only.
    -- mode 'ticks' answers every matching row in short form (for Tick every row shown), and no page.
    declare
      v_size int := greatest(security.pipeline_num_v1('layer23.universities_page_size', 100)::int, 1);
      v_tick_max int := greatest(security.pipeline_num_v1('layer23.universities_tick_max', 2000)::int, 1);
      v_off int := greatest(coalesce(nullif(p_args->>'offset', '')::int, 0), 0);
      v_ticks boolean := coalesce(p_args->>'mode', '') = 'ticks';
      v_pid uuid := nullif(p_args->>'provider_id', '')::uuid;
      v_country text := nullif(btrim(coalesce(p_args->>'country', '')), '');
      v_state text := nullif(btrim(coalesce(p_args->>'state', '')), '');
      v_kind text := coalesce(nullif(btrim(coalesce(p_args->>'kind', '')), ''), 'any');
      v_adapter text := nullif(btrim(coalesce(p_args->>'adapter', '')), '');
      v_qualify text := nullif(btrim(coalesce(p_args->>'qualify', '')), '');
      v_target text := nullif(btrim(coalesce(p_args->>'target', '')), '');
      v_stage text := nullif(btrim(coalesce(p_args->>'stage', '')), '');
      v_q text := nullif(btrim(coalesce(p_args->>'q', '')), '');
      v_pat text := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
      -- the read-cycle bounds are those public.admin_adapters enforces in set_cycle and answers in 'list' (kept identical to it)
      v_settings jsonb := case when v_rank >= 4 then jsonb_build_object('read_cycle_default', 90, 'read_cycle_min', 7, 'read_cycle_max', 365,
                            'min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb),
                            'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)) end;
    begin
        with t as materialized (select x.provider_id, x.included, x.rule_match, x.override_reason from security.firecrawl_targets_fast() x where v_rank >= 4),
        ob as materialized (select distinct on (o.provider_id) o.id, o.provider_id, o.status, o.stop_reason, o.note, o.result, o.updated_at
                              from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
        ib as materialized (select i.provider_id, i.kind, count(*) c from security.layer4_inbox_items_v1() i where i.provider_id is not null group by 1, 2),
        ibn as (select ib.provider_id, sum(ib.c)::int n from ib group by 1),
        q as (select distinct on (x.provider_id) x.provider_id, x.job_id, x.measured_at, x.passing, x.pages_read
                from pipeline.adapter_qualifications x join pipeline.admin_jobs j on j.id = x.job_id and j.kind = 'qualify_adapters' and j.state = 'done'
               where v_rank >= 4 order by x.provider_id, x.measured_at desc),
        ids as (select a.provider_id from pipeline.uni_adapters a where v_rank >= 4 union select t.provider_id from t where t.included union select ob.provider_id from ob),
        u as materialized (
          select p.id provider_id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country, s.code state, l.inlist,
                 case when l.inlist then coalesce(p.display_name, p.canonical_name) ~* v_pat else true end university,
                 case when l.inlist and a.provider_id is not null then case when not a.enabled then 'off' when a.admit then 'admitting' else 'testing' end end adapter_state,
                 case when l.inlist and a.admit then coalesce(a.admit_fields, '{}') else '{}' end admit_fields,
                 l.inlist and q.provider_id is not null qualified, case when l.inlist then coalesce(q.passing, '{}') else '{}' end passing,
                 case when l.inlist then t.included end target_included,
                 ob.id ob_id, ob.status ob_status, ob.stop_reason ob_stop, coalesce(ibn.n, 0) inbox
            from ids join catalogue.providers p on p.id = ids.provider_id
            left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
            left join pipeline.uni_adapters a on a.provider_id = p.id and v_rank >= 4
            left join t on t.provider_id = p.id left join q on q.provider_id = p.id
            left join ob on ob.provider_id = p.id left join ibn on ibn.provider_id = p.id
            cross join lateral (select v_rank >= 4 and (a.provider_id is not null or coalesce(t.included, false)) inlist) l),
        f as materialized (
          select u.* from u
           where (v_pid is null or u.provider_id = v_pid)
             and (v_country is null or u.country = v_country) and (v_state is null or u.state = v_state)
             and (v_kind <> 'university' or u.university)
             and (v_adapter is null or (v_adapter = 'none' and u.adapter_state is null) or u.adapter_state = v_adapter)
             and (v_qualify is null
                  or (v_qualify = 'never' and not u.qualified)
                  or (v_qualify = 'passing' and cardinality(u.passing) > 0)
                  or (v_qualify = 'waiting' and u.adapter_state is not null and u.adapter_state <> 'off' and exists (select 1 from unnest(u.passing) x where x <> all (u.admit_fields)))
                  or (v_qualify not in ('never', 'passing', 'waiting') and u.qualified and cardinality(u.passing) = 0))
             and (v_target is null or (v_target = 'in' and coalesce(u.target_included, false)) or (v_target <> 'in' and not coalesce(u.target_included, false)))
             and (v_q is null or strpos(lower(u.name), lower(v_q)) > 0)
             and (v_stage is null
                  or (v_stage = 'none' and u.ob_id is null)
                  or (v_stage = 'inbox' and u.inbox > 0)
                  or (u.ob_id is not null and (
                       (v_stage = 'working' and u.ob_status in ('queued', 'website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships', 'waiting_admit', 'waiting_courses'))
                    or (v_stage = 'person' and u.ob_status = 'stopped' and coalesce(u.ob_stop, '') in ('nothing_ready', 'approve_central'))
                    or (v_stage = 'stopped' and u.ob_status = 'stopped' and coalesce(u.ob_stop, '') not in ('nothing_ready', 'approve_central'))
                    or (v_stage = 'done' and u.ob_status = 'done')
                    or v_stage not in ('none', 'inbox', 'working', 'person', 'stopped', 'done'))))),
        pg as (select f.* from f order by f.name, f.provider_id offset v_off limit v_size)
        select jsonb_build_object('as_at', now(), 'can_manage', v_rank >= 6, 'can_qualify', v_rank >= 5, 'can_onboard', v_rank >= 6, 'settings', v_settings,
          'paged', true, 'page_size', v_size, 'offset', v_off,
          'total', (select count(*) from u), 'matched', (select count(*) from f),
          'tally', (select jsonb_build_object('admitting', count(*) filter (where f.adapter_state = 'admitting'), 'testing', count(*) filter (where f.adapter_state = 'testing'),
                                              'off', count(*) filter (where f.adapter_state = 'off'), 'none', count(*) filter (where f.adapter_state is null)) from f),
          'countries', (select coalesce(jsonb_agg(z.c order by z.c collate "C"), '[]'::jsonb) from (select distinct u.country c from u where u.country is not null) z),
          'states', (select coalesce(jsonb_agg(z.c order by z.c collate "C"), '[]'::jsonb) from (select distinct u.state c from u where u.state is not null and (v_country is null or u.country = v_country)) z),
          'adapters', case when v_ticks then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object(
              'provider_id', pg.provider_id, 'name', pg.name, 'country', pg.country, 'state', pg.state, 'university', pg.university,
              'adapter', case when pg.adapter_state is null then null else jsonb_build_object('state', pg.adapter_state, 'fields', to_jsonb(pg.admit_fields), 'read_cycle_days', a.read_cycle_days, 'updated_at', a.updated_at, 'admit_changed_at', a.admit_changed_at) end,
              'target', case when pg.target_included is null then null else jsonb_build_object('included', t.included, 'rule_match', t.rule_match, 'override_reason', t.override_reason,
                             'rule_reason', (select c.rule_reason from pipeline.firecrawl_target_cache c where c.provider_id = pg.provider_id)) end,
              'pages', gp.pages, 'pages_read', gp.pages_read, 'next_read', gp.next_read, 'last_read', gp.last_read,
              'qualify', case when not pg.qualified then null else jsonb_build_object('job_id', q.job_id, 'at', q.measured_at, 'passing', to_jsonb(q.passing), 'pages_read', q.pages_read) end,
              'onboarding', case when pg.ob_id is null then null else jsonb_build_object('id', ob.id, 'status', ob.status, 'stage', security.provider_onboarding_stage_v1(ob.status, ob.stop_reason, ob.result),
                             'phase', ob.result->>'phase', 'stop_reason', ob.stop_reason, 'note', ob.note, 'updated_at', ob.updated_at) end,
              'inbox', pg.inbox, 'inbox_kinds', coalesce((select jsonb_object_agg(ib.kind, ib.c) from ib where ib.provider_id = pg.provider_id), '{}'::jsonb))
              order by pg.name, pg.provider_id), '[]'::jsonb)
            from pg left join pipeline.uni_adapters a on a.provider_id = pg.provider_id left join t on t.provider_id = pg.provider_id
            left join q on q.provider_id = pg.provider_id left join ob on ob.provider_id = pg.provider_id
            cross join lateral (select count(*) pages, count(*) filter (where g.read_status = 'read') pages_read,
                                       min(g.next_read_at) filter (where g.read_status in ('read', 'identity_mismatch')) next_read, max(g.read_at) last_read
                                  from pipeline.coverage_course_pages g where g.provider_id = pg.provider_id) gp) end,
          'ticks', case when not v_ticks then null else (select jsonb_build_object('capped', count(*) > v_tick_max, 'rows', coalesce(jsonb_agg(jsonb_build_object(
              'provider_id', z.provider_id, 'name', z.name,
              'adapter', case when z.adapter_state is null then null else jsonb_build_object('state', z.adapter_state, 'fields', to_jsonb(z.admit_fields)) end,
              'qualify', case when not z.qualified then null else jsonb_build_object('passing', to_jsonb(z.passing)) end,
              'onboarding', case when z.ob_id is null then null else jsonb_build_object('id', z.ob_id, 'status', z.ob_status) end) order by z.name, z.provider_id)
              filter (where z.rn <= v_tick_max), '[]'::jsonb))
            from (select f.*, row_number() over (order by f.name, f.provider_id) rn from f) z) end)
          into v_out;
      return v_out;
    end;
  end if;

  create temp table if not exists _l23_inbox$n$]],
  array[1]);

-- post-check: two settings with label, range, unit and used_by; the new action is in place and the two old ones are kept
do $$ declare v_n int; v_def text := pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure); begin
  select count(*) into v_n from pipeline.platform_toolset_settings
   where toolset_key = 'pipeline' and key in ('layer23.universities_page_size', 'layer23.universities_tick_max')
     and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null;
  if v_n <> 2 then raise exception 'W33 post-check: expected 2 Universities paging settings, found %', v_n; end if;
  if v_def not like '%if p_action = ''universities_page'' then%' or v_def not like '%if p_action = ''universities'' then%' or v_def not like '%if p_action = ''operations'' then%' then
    raise exception 'W33 post-check: public.admin_layer23 does not hold operations, universities and universities_page';
  end if;
  if v_def not like '%security.pipeline_num_v1(''layer23.universities_page_size''%' then raise exception 'W33 post-check: the page size is not read from its setting'; end if;
end $$;
