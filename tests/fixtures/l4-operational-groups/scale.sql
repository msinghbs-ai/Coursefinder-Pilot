-- CF-247 Layer 4 operational groups at production scale (Integration Controller 4 Nov 2026: 5,000 items, including 3,000 Course Link). Run by
-- run.sh after ../l4-inbox-perf/indexes.sql and seed-scale.sql (about 5,000 waiting items over 200 universities: 3,300 official links, 600 AER,
-- 465 descriptions, 132 held scholarships, 150 stopped onboardings, 140 holds, 75 course pages needed, 20 reports, 7 departures). Every waiting
-- review item gets a readiness row in the live proportions (17:16 AEDT); official links are routed by the Course Link classifier stand-in, which
-- costs here what a classifier with a few indexed look-ups costs. Then: the full fill (as on release) within its budget, an incremental run,
-- and every first-load read of the Inbox and of the three choices under the paging contract budget (300 ms each). Scratch PostgreSQL only.
\set ON_ERROR_STOP on
select set_config('fx.uid', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', false), set_config('fx.rank', '6', false);
create table fx.budget_ms(ms numeric); insert into fx.budget_ms values (300);
-- live has 5,213 waiting (17:26 AEDT): 300 more official links bring the seed above 5,000
alter table pipeline.layer4_review_items disable trigger user;
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, before_value, proposed_value, status, escalation_reason, created_at)
select 'course', ('20000000-0000-0000-0000-' || lpad((1 + (g * 37) % 24000)::text, 12, '0'))::uuid, 'official_course_url', jsonb_build_array('https://u.example.edu/old-' || g),
       jsonb_build_object('url', 'https://u.example.edu/new-' || g), 'pending', 'A different page was found for this course', timestamptz '2026-10-21 00:00+00' + (g % 50) * interval '1 hour'
  from generate_series(1, 300) g;
alter table pipeline.layer4_review_items enable trigger user;
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route)
select r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, 'pending',
       case when r.field_code = 'course_entry_first_read' and n % 9 < 4 then 'technical_blocked' when r.field_code = 'official_course_url' and n % 100 < 9 then 'resolvable'
            when r.field_code = 'official_course_url' and n % 100 < 11 then 'technical_blocked' else 'judgement_ready' end, '{}',
       case when r.field_code = 'course_entry_first_read' and n % 9 < 4 then 'repair:completeness_gate' when r.field_code = 'official_course_url' and n % 100 < 9 then 'platform:covered_by_active'
            when r.field_code = 'official_course_url' and n % 100 < 11 then 'repair:invalid_link' else 'review:curator' end
  from (select r.*, row_number() over (order by r.id) n from pipeline.layer4_review_items r where r.status = 'pending'
          and not exists (select 1 from pipeline.layer4_item_readiness x where x.item_id = r.id)) r;
-- the Course Link classifier stand-in with the cost of a real one: the item, its course, the course's active links and its readiness, each indexed
create or replace function security.course_link_route_class_v1(p_item uuid) returns jsonb language sql stable security definer set search_path to '' as $f$
  select case when r.id is null then jsonb_build_object('item', p_item, 'group', null)
              when c.item is not null then jsonb_build_object('item', p_item, 'group', c.grp, 'class', c.cls, 'action', c.action, 'authority', c.authority)
              else jsonb_build_object('item', p_item,
                     'group', case when rd.route = 'platform:covered_by_active' or exists (select 1 from catalogue.course_links l where l.course_id = r.entity_id and l.status = 'active') then 'A'
                                   when rd.readiness = 'technical_blocked' then 'B' else 'C' end,
                     'class', case when rd.route = 'platform:covered_by_active' then 'covered_by_active' when rd.readiness = 'technical_blocked' then 'evidence_missing' else 'cricos_page_differs' end,
                     'action', 'keep', 'authority', case when rd.route = 'platform:covered_by_active' then 'security.layer4_reconcile_v1 (layer4.reconcile_supersede_on)' end,
                     'evidence', jsonb_build_object('course', (select co.lifecycle_status from catalogue.courses co where co.id = r.entity_id))) end
    from (select 1) z left join pipeline.layer4_review_items r on r.id = p_item and r.status = 'pending' and r.field_code = 'official_course_url'
    left join pipeline.layer4_item_readiness rd on rd.item_id = r.id left join fx.cl_route c on c.item = p_item
$f$;
analyze;
do $$
declare v jsonb; t timestamptz; ms numeric; b numeric := (select x.ms from fx.budget_ms x); g text; w int; r jsonb; m jsonb := '{}';
begin
  w := (select count(*) from security.layer4_inbox_items_v2(null, null, null, false));
  if w < 5000 or (select count(*) from security.layer4_inbox_items_v2(null, 'course_link', null, false)) < 3000 then raise exception 'S: not at production scale (%)', w; end if;
  -- the full fill, as on release, within its time budget
  t := clock_timestamp(); v := security.layer4_groups_fill_v1(true); ms := extract(epoch from clock_timestamp() - t) * 1000;
  if (v->>'not_grouped_yet')::int <> 0 then raise exception 'S: the full fill did not finish within layer4.groups_fill_seconds: %', v; end if;
  if ms > security.pipeline_num_v1('layer4.groups_fill_seconds', 30) * 1000 + 2000 then raise exception 'S: fill took % ms', round(ms); end if;
  m := m || jsonb_build_object('fill_full_ms', round(ms), 'grouped', v->'grouped', 'waiting', v->'waiting');
  -- an incremental run with nothing changed
  t := clock_timestamp(); v := security.layer4_groups_fill_v1(false); m := m || jsonb_build_object('fill_unchanged_ms', round(extract(epoch from clock_timestamp() - t) * 1000), 'regrouped', v->'grouped');
  if (v->>'grouped')::int <> 0 then raise exception 'S: an unchanged run regrouped %', v; end if;
  -- every first-load read, three times each, the slowest kept
  for g in select unnest(array['inbox_summary', 'inbox_universities', 'inbox_first_university', 'groups_summary', 'groups_C', 'groups_D', 'groups_B', 'lifecycle_page']) loop
    ms := 0;
    for i in 1 .. 3 loop
      t := clock_timestamp();
      case g
        when 'inbox_summary' then perform public.admin_layer4_inbox('summary', '{}');
        when 'inbox_universities' then perform public.admin_layer4_inbox('universities', '{"limit": 25, "offset": 0}');
        when 'inbox_first_university' then perform public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000001", "limit": 25}');
        when 'groups_summary' then perform public.admin_layer4_groups('{}');
        when 'groups_C' then r := public.admin_layer4_groups('{"action": "items", "group": "C", "limit": 25}');
        when 'groups_D' then r := public.admin_layer4_groups('{"action": "items", "group": "D", "limit": 25}');
        when 'groups_B' then r := public.admin_layer4_groups('{"action": "items", "group": "B", "limit": 25}');
        else perform public.admin_layer4_lifecycle(jsonb_build_object('items', (select jsonb_agg(z.x) from (select jsonb_build_object('kind', i.kind, 'ref', i.ref) x
                                                    from pipeline.layer4_item_groups i where i.state = 'waiting' and i.grp = 'C' order by i.item_created_at limit 25) z)));
      end case;
      ms := greatest(ms, extract(epoch from clock_timestamp() - t) * 1000);
    end loop;
    m := m || jsonb_build_object(g || '_ms', round(ms));
    if ms > b then raise exception 'S: % took % ms (budget % ms)', g, round(ms), b; end if;
  end loop;
  raise notice 'S ok (production scale: % waiting, % official links): %', w, (select count(*) from security.layer4_inbox_items_v2(null, 'course_link', null, false)), m;
  raise notice 'S groups: %', (public.admin_layer4_groups('{}'))->'groups';
end $$;
