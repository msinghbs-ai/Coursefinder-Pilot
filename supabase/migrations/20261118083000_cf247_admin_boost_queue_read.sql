-- CF-247 Boost queue view (Platform Admin decision 18 Nov 2026 07:03, chat S1-RM-Design): Country tier and Priority score are worked out when the
-- queue is read, from the live boost.matrix.* settings, and shown and filtered only on the Boost queue (Platform health > Queues & yield). Nothing is
-- stored on a course and the Course catalogue is unchanged.
--   * Priority score = country weight x category weight, through S2 - BOOST's own security.boost_country_category_weight_v1 (aliases included), so the
--     screen and the Boost workers read one definition. Country tier 1 and 2 are the boost.matrix.tier_1 and tier_2 lists; a country in neither has no tier.
--   * One read function for Curator and above. It reads pipeline.boost_extract_items (the queue) and the latest pipeline.boost_inbound_staging row of each
--     item; it writes nothing. The score is worked out once per lane and country, not per row.
-- Replaces: nothing
-- Retires: nothing

do $pre$ begin
  if to_regclass('pipeline.boost_extract_items') is null or to_regclass('pipeline.boost_inbound_staging') is null or to_regclass('ref.enrichment_categories') is null
     or to_regprocedure('security.boost_country_category_weight_v1(text,text)') is null or to_regprocedure('security.boost_lane_category_v1(text)') is null
     or to_regprocedure('security.pipeline_list_v1(text,jsonb)') is null or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null
     or to_regclass('pipeline.platform_toolset_settings') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'admin.boost_queue_page_rows', 'Boost queue: rows per page',
  'How many Boost queue items the list on Platform health > Queues & yield shows at a time.',
  'number', to_jsonb(50), 10, 200, 'rows', 3272, 'Boost queue view (Platform Admin 18 Nov 2026 07:03)', 'Boost', 'public.admin_boost_queue_read')
on conflict (toolset_key, key) do nothing;

create or replace function public.admin_boost_queue_read(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := coalesce(p_args, '{}'::jsonb);
        v_page int := greatest(1, security.pipeline_num_v1('admin.boost_queue_page_rows', 50)::int);
        v_off int := greatest(0, coalesce(nullif(a->>'offset', '')::int, 0));
        v_tier text := nullif(a->>'tier', ''); v_country text := upper(nullif(a->>'country', '')); v_lane text := nullif(a->>'lane', ''); v_state text := nullif(a->>'state', '');
        v_sort text := lower(coalesce(nullif(a->>'sort', ''), 'score')); v_dir text := case when lower(coalesce(nullif(a->>'direction', ''), 'desc')) = 'asc' then 'asc' else 'desc' end;
        v_t1 text[] := security.pipeline_list_v1('boost.matrix.tier_1'); v_t2 text[] := security.pipeline_list_v1('boost.matrix.tier_2');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for the Boost queue' using errcode = '42501'; end if; -- fixed: who opens Queues & yield
  if v_tier is not null and v_tier not in ('1', '2', 'none') then raise exception 'tier is 1, 2 or none' using errcode = '22023'; end if;
  return (
    with al as (select split_part(x, '=', 1) src, split_part(x, '=', 2) dst from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x),
    -- the score and tier of each lane and country in the queue, worked out once
    w as materialized (
      select c.lane, c.country_code, k.category, k.canon,
             security.boost_country_category_weight_v1(c.country_code, k.category) priority_score,
             case when k.canon = any(v_t1) then 1 when k.canon = any(v_t2) then 2 end country_tier
        from (select distinct e.lane, e.country_code from pipeline.boost_extract_items e) c
        cross join lateral (select security.boost_lane_category_v1(c.lane) category,
                                   coalesce((select al.dst from al where al.src = upper(c.country_code) limit 1), upper(c.country_code)) canon) k),
    q as (select e.item_key, e.lane, e.entity, e.entity_id, e.evidence_id, e.country_code, e.state, e.batch_id, e.model_called, e.cost, e.note, e.claimed_at, e.done_at,
                 w.category, w.priority_score, w.country_tier
            from pipeline.boost_extract_items e join w on w.lane = e.lane and w.country_code is not distinct from e.country_code),
    f as (select * from q
           where (v_tier is null or (v_tier = 'none' and q.country_tier is null) or q.country_tier::text = v_tier)
             and (v_country is null or upper(q.country_code) = v_country) and (v_lane is null or q.lane = v_lane) and (v_state is null or q.state = v_state)),
    pg as (select n.*, row_number() over () ord from (
             select * from f order by
               case when v_sort = 'score' and v_dir = 'desc' then f.priority_score end desc nulls last,
               case when v_sort = 'score' and v_dir = 'asc' then f.priority_score end asc nulls last,
               case when v_sort = 'tier' and v_dir = 'asc' then f.country_tier end asc nulls last,
               case when v_sort = 'tier' and v_dir = 'desc' then f.country_tier end desc nulls last,
               case when v_sort = 'done' and v_dir = 'desc' then f.done_at end desc nulls last,
               case when v_sort = 'done' and v_dir = 'asc' then f.done_at end asc nulls last,
               f.priority_score desc nulls last, f.done_at desc nulls last, f.item_key
             limit v_page offset v_off) n)
    select jsonb_build_object(
      'total', (select count(*) from f), 'all_rows', (select count(*) from q), 'page_rows', v_page, 'offset', v_off, 'sort', v_sort, 'direction', v_dir,
      'tiers', jsonb_build_object('tier_1', to_jsonb(v_t1), 'tier_2', to_jsonb(v_t2)),
      'summary', (select coalesce(jsonb_agg(jsonb_build_object('country_tier', s.country_tier, 'country_code', s.country_code, 'lane', s.lane, 'category', s.category, 'priority_score', s.priority_score, 'items', s.n,
                                                                'waiting', s.waiting) order by s.priority_score desc nulls last, s.country_code, s.lane), '[]'::jsonb)
                    from (select q.country_tier, q.country_code, q.lane, q.category, q.priority_score, count(*) n, count(*) filter (where q.done_at is null) waiting from q group by 1, 2, 3, 4, 5) s),
      'filters', jsonb_build_object(
        'countries', (select coalesce(jsonb_agg(x.c order by x.c), '[]'::jsonb) from (select distinct upper(q.country_code) c from q where q.country_code is not null) x),
        'lanes', (select coalesce(jsonb_agg(x.c order by x.c), '[]'::jsonb) from (select distinct q.lane c from q) x),
        'states', (select coalesce(jsonb_agg(x.c order by x.c), '[]'::jsonb) from (select distinct q.state c from q) x)),
      'rows', (select coalesce(jsonb_agg(jsonb_build_object(
                 'item_key', pg.item_key, 'lane', pg.lane, 'entity', pg.entity, 'entity_id', pg.entity_id, 'country_code', pg.country_code, 'state', pg.state, 'batch_id', pg.batch_id,
                 'model_called', pg.model_called, 'cost', pg.cost, 'note', pg.note, 'claimed_at', pg.claimed_at, 'done_at', pg.done_at,
                 'category', pg.category, 'category_label', (select c.label from ref.enrichment_categories c where c.category_key = pg.category),
                 'priority_score', pg.priority_score, 'country_tier', pg.country_tier,
                 'title', case when pg.entity = 'course' then (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = pg.entity_id)
                               when pg.entity = 'provider' then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = pg.entity_id) end,
                 'promotion_state', st.promotion_state, 'worker_status', st.worker_status) order by pg.ord), '[]'::jsonb)
                 from pg
                 -- the latest staged answer of the item (read through the entity index)
                 left join lateral (select s.promotion_state, s.worker_status from pipeline.boost_inbound_staging s
                                     where s.entity_id = pg.entity_id and s.item_key = pg.item_key order by s.loaded_at desc nulls last, s.id desc limit 1) st on true)));
end $$;
comment on function public.admin_boost_queue_read(jsonb) is 'Boost queue view (20261118083000): the queue with Country tier and Priority score worked out from the boost.matrix settings when read. Curator and above. Changes nothing.';
revoke all on function public.admin_boost_queue_read(jsonb) from public, anon;
grant execute on function public.admin_boost_queue_read(jsonb) to authenticated;

do $post$ begin
  if has_function_privilege('anon', 'public.admin_boost_queue_read(jsonb)', 'execute') then raise exception 'post-check: anon can run the Boost queue read'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'admin.boost_queue_page_rows') then raise exception 'post-check: the page size setting is missing'; end if;
end $post$;
