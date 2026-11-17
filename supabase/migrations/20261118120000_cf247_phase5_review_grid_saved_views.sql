-- CF-247 UI audit Phase 5, first slice (Platform Admin 18 Nov 2026 09:30 "Phase 5 before Phase 4", and 10:09; decisions of 16 Nov 2026 05:12 in
-- admin docs/platform/ui-audit/ui-ux-settings-audit-2026-11-15.md §4.2 and §6): the Review & Evidence grid on Layer 4 Review › Review grid.
--   * pipeline.saved_views: saved filter views. Shared views are seen by everyone who opens the grid and changed only by a Platform Admin (rank 6),
--     with a reason; personal views are seen and changed by their owner only. Three shared views are seeded: AER Audit Samples, Official URLs and
--     Provider Blockers. A view only filters what is shown: it changes no item, no AER audit sample rate and no Layer 4 URL rule (holds B and F).
--   * public.admin_review_grid(action, args): the grid's one entry point, Curator (rank 3) and above. 'rows' pages the items that wait for a person
--     (the same source as Layer 4 › Inbox, security.layer4_inbox_items_v2, read only); 'drawer' gives one item's saved source quotes beside the
--     values they produced, its evidence link and its decision history; 'views', 'view_save' and 'view_archive' list and keep views.
--   * Decisions are still taken in Layer 4 › Inbox (the drawer opens the item there); this slice changes no decision path.
--   * Sizes are settings (G2): layer4.grid_page_rows, layer4.grid_page_max, layer4.grid_drawer_pairs_max, layer4.grid_history_rows,
--     layer4.saved_views_per_user. Nothing is deleted: a view that is no longer wanted is archived.
-- Replaces: nothing (first slice; Layer4Inbox, Groups, Intervention, ArchivedReview and the Evidence table move onto the grid in later slices)
-- Retires: nothing

do $pre$ begin
  if to_regprocedure('security.layer4_inbox_items_v2(uuid,text,text[],boolean)') is null or to_regprocedure('security.layer4_inbox_kinds_v1()') is null
     or to_regprocedure('security.current_role_rank()') is null or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null
     or to_regclass('pipeline.platform_toolset_settings') is null or to_regclass('pipeline.admin_control_events') is null
     or to_regclass('pipeline.component_register') is null or to_regclass('catalogue.providers') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.grid_page_rows', 'Review grid: rows per page',
  'How many items Layer 4 Review › Review grid shows at a time.', 'number', to_jsonb(50), 10, 200, 'rows', 330,
  'UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30)', 'Layer 4', 'public.admin_review_grid'),
 ('pipeline', 'layer4.grid_page_max', 'Review grid: most rows one page may ask for',
  'The largest page a person can choose on the Review grid; a larger request is cut to this.', 'number', to_jsonb(200), 50, 500, 'rows', 331,
  'UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30)', 'Layer 4', 'public.admin_review_grid'),
 ('pipeline', 'layer4.grid_drawer_pairs_max', 'Review grid: quotes shown in the drawer',
  'How many saved source quotes the Source quote vs extracted value drawer shows for one item.', 'number', to_jsonb(50), 5, 200, 'quotes', 332,
  'UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30)', 'Layer 4', 'public.admin_review_grid'),
 ('pipeline', 'layer4.grid_history_rows', 'Review grid: decision history rows in the drawer',
  'How many earlier decisions on the item the drawer lists, newest first.', 'number', to_jsonb(20), 5, 100, 'rows', 333,
  'UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30)', 'Layer 4', 'public.admin_review_grid'),
 ('pipeline', 'layer4.saved_views_per_user', 'Review grid: personal views a person may keep',
  'How many personal saved views one person may keep on the Review grid (archived views do not count).', 'number', to_jsonb(25), 1, 100, 'views', 334,
  'UI audit Phase 5 first slice (Platform Admin 18 Nov 2026 09:30)', 'Layer 4', 'public.admin_review_grid')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.saved_views (
  id uuid primary key default gen_random_uuid(),
  surface text not null default 'layer4_review_grid' check (surface in ('layer4_review_grid')),
  scope text not null check (scope in ('shared', 'personal')),
  owner_id uuid,
  view_key text,
  name text not null check (length(btrim(name)) between 1 and 80),
  description text,
  filters jsonb not null default '{}'::jsonb check (jsonb_typeof(filters) = 'object'),
  columns jsonb not null default '[]'::jsonb check (jsonb_typeof(columns) = 'array'),
  sort jsonb not null default '{}'::jsonb check (jsonb_typeof(sort) = 'object'),
  sort_order int not null default 100,
  reason text,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  archived_at timestamptz,
  archived_by uuid,
  check ((scope = 'shared' and owner_id is null and view_key is not null) or (scope = 'personal' and owner_id is not null))
);
comment on table pipeline.saved_views is 'CF-247 UI audit Phase 5 (18 Nov 2026): saved filter views of the Review & Evidence grid (Layer 4 Review › Review grid). A shared view (view_key set, no owner) is seen by everyone who opens the grid and changed only by a Platform Admin with a reason; a personal view is seen and changed by its owner only. filters, columns and sort describe what the grid shows; a view never changes an item, the AER audit sample or a Layer 4 rule. Rows are archived, never deleted. Read and written only through public.admin_review_grid.';
create unique index if not exists saved_views_shared_key_uq on pipeline.saved_views (surface, view_key) where scope = 'shared';
create unique index if not exists saved_views_personal_name_uq on pipeline.saved_views (surface, owner_id, lower(name)) where scope = 'personal' and archived_at is null;
create index if not exists saved_views_owner_idx on pipeline.saved_views (owner_id, surface) where archived_at is null;
alter table pipeline.saved_views enable row level security;
revoke all on pipeline.saved_views from anon, authenticated;

insert into pipeline.saved_views (scope, view_key, name, description, filters, columns, sort, sort_order, reason) values
 ('shared', 'aer_audit_samples', 'AER Audit Samples',
  'Entry requirement reads the machine held back as the audit sample: they always stay with a person.',
  '{"kinds": ["aer_review"], "why_codes": ["audit_sample"]}', '["subject", "provider", "why", "created_at", "source_url"]', '{"key": "created_at", "direction": "asc"}', 10,
  'UI audit decision 16 Nov 2026 05:12: shared default view'),
 ('shared', 'official_urls', 'Official URLs',
  'Proposed official course pages waiting for a person, grouped by university when sorted by university.',
  '{"kinds": ["course_link"], "field_codes": ["official_course_url"]}', '["subject", "provider", "why", "created_at", "source_url"]', '{"key": "provider", "direction": "asc"}', 20,
  'UI audit decision 16 Nov 2026 05:12: shared default view'),
 ('shared', 'provider_blockers', 'Provider Blockers',
  'Universities held at onboarding or reading: no website, too few pages, nothing ready, site down, pages not found, central approval, departures.',
  '{"kinds": ["website_needed", "too_few_pages", "nothing_ready", "site_down", "pages_not_found", "central_to_approve", "onboarding_failed", "provider_departure"]}',
  '["kind", "provider", "why", "created_at"]', '{"key": "created_at", "direction": "asc"}', 30,
  'UI audit decision 16 Nov 2026 05:12: shared default view')
on conflict do nothing;

-- the filters a view or a request may carry, cleaned: unknown keys are dropped, lists are text arrays, numbers are bounded
create or replace function security.review_grid_filters_v1(p jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kinds', case when jsonb_typeof(p->'kinds') = 'array' and jsonb_array_length(p->'kinds') > 0 then (select jsonb_agg(distinct x) from jsonb_array_elements_text(p->'kinds') x where x ~ '^[a-z_]{1,40}$') end,
    'field_codes', case when jsonb_typeof(p->'field_codes') = 'array' and jsonb_array_length(p->'field_codes') > 0 then (select jsonb_agg(distinct x) from jsonb_array_elements_text(p->'field_codes') x where x ~ '^[a-z0-9_]{1,60}$') end,
    'why_codes', case when jsonb_typeof(p->'why_codes') = 'array' and jsonb_array_length(p->'why_codes') > 0 then (select jsonb_agg(distinct x) from jsonb_array_elements_text(p->'why_codes') x where x ~ '^[a-z0-9_]{1,60}$') end,
    'provider_id', case when coalesce(p->>'provider_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p->>'provider_id' end,
    'q', nullif(left(btrim(coalesce(p->>'q', '')), 120), ''),
    'older_than_days', case when coalesce(p->>'older_than_days', '') ~ '^[0-9]{1,4}$' then to_jsonb((p->>'older_than_days')::int) end))
$$;
revoke all on function security.review_grid_filters_v1(jsonb) from public, anon, authenticated;

-- the saved page quotes behind an item's values, as pairs: what the page said (quote) beside what was taken from it (value)
create or replace function security.review_quote_pairs_v1(p_detail jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  with src as (select coalesce(case when jsonb_typeof(p_detail->'proposed') = 'object' then p_detail->'proposed' end, p_detail, '{}'::jsonb) p),
  arr as (
    select k.ko, k.k, x.ord, x.e from src
      cross join lateral unnest(array['sentences', 'sample', 'qualification_sample', 'rows']) with ordinality k(k, ko)
      cross join lateral jsonb_array_elements(case when jsonb_typeof(src.p->k.k) = 'array' then src.p->k.k else '[]'::jsonb end) with ordinality x(e, ord)
     where jsonb_typeof(x.e) = 'object' and nullif(btrim(coalesce(x.e->>'quote', '')), '') is not null),
  pairs as (
    select arr.ko, arr.ord, jsonb_build_object('label', coalesce(arr.e->>'kind', arr.e->>'audience', arr.k), 'audience', arr.e->>'audience',
           'value', coalesce(arr.e->>'text', arr.e->>'description', arr.e->>'min_entry_score_basis', arr.e->>'value'), 'quote', arr.e->>'quote') j from arr
    union all
    select 10, 1, jsonb_build_object('label', 'value', 'value', coalesce(p_detail->>'recommendation', p_detail->>'url'), 'quote', p_detail->>'value_quote')
     where nullif(btrim(coalesce(p_detail->>'value_quote', '')), '') is not null
    union all
    select 10, 2, jsonb_build_object('label', 'audience', 'value', null, 'quote', p_detail->>'audience_quote')
     where nullif(btrim(coalesce(p_detail->>'audience_quote', '')), '') is not null
    union all
    select 11, 1, jsonb_build_object('label', 'evidence', 'value', null, 'quote', p_detail#>>'{evidence,quote}')
     where nullif(btrim(coalesce(p_detail#>>'{evidence,quote}', '')), '') is not null)
  select coalesce(jsonb_agg(j order by ko, ord), '[]'::jsonb) from pairs
$$;
revoke all on function security.review_quote_pairs_v1(jsonb) from public, anon, authenticated;

create or replace function public.admin_review_grid(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_rank int; v_uid uuid := auth.uid(); v_f jsonb; v_v pipeline.saved_views%rowtype; v_id uuid;
        v_kinds text[]; v_fields text[]; v_whys text[]; v_pid uuid; v_q text; v_old int; v_one text; v_det boolean;
        v_page int; v_max int; v_off int; v_sort text; v_dir text; v_total bigint; v_keys text[]; v_rows jsonb; v_name text; v_reason text;
        v_kinds_meta jsonb := security.layer4_inbox_kinds_v1(); v_item record; v_pairs jsonb; v_pmax int; v_hmax int; v_hist jsonb; v_rev jsonb;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 3 then raise exception 'Curator (rank 3) or above is needed for the Review grid' using errcode = '42501'; end if; -- fixed: who opens Layer 4 Review

  if p_action = 'views' then
    return jsonb_build_object('rank', v_rank, 'can_edit_shared', v_rank >= 6, 'personal_max', security.pipeline_num_v1('layer4.saved_views_per_user', 25)::int,
      'views', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'scope', s.scope, 'view_key', s.view_key, 'name', s.name, 'description', s.description,
                 'filters', s.filters, 'columns', s.columns, 'sort', s.sort, 'mine', s.owner_id = v_uid, 'updated_at', s.updated_at)
                 order by case s.scope when 'shared' then 0 else 1 end, s.sort_order, lower(s.name))
               from pipeline.saved_views s
              where s.surface = 'layer4_review_grid' and s.archived_at is null and (s.scope = 'shared' or s.owner_id = v_uid)), '[]'::jsonb),
      'kinds', coalesce((select jsonb_agg(jsonb_build_object('kind', k.key, 'label', k.value->>'label') order by (k.value->>'order')::int nulls last, k.key)
                           from jsonb_each(v_kinds_meta) k), '[]'::jsonb));

  elsif p_action = 'view_save' then
    v_name := btrim(coalesce(a->>'name', ''));
    v_reason := nullif(btrim(coalesce(a->>'reason', '')), '');
    if length(v_name) not between 1 and 80 then raise exception 'a view needs a name of 1 to 80 characters' using errcode = '22023'; end if;
    v_f := security.review_grid_filters_v1(coalesce(a->'filters', '{}'::jsonb));
    if nullif(a->>'id', '') is not null then
      select * into v_v from pipeline.saved_views s where s.id = (a->>'id')::uuid and s.archived_at is null;
      if not found then raise exception 'that view was not found' using errcode = 'P0002'; end if;
      if v_v.scope = 'shared' and v_rank < 6 then raise exception 'only a Platform Admin (rank 6) can change a shared view' using errcode = '42501'; end if; -- fixed: decision 16 Nov 2026
      if v_v.scope = 'personal' and v_v.owner_id <> v_uid then raise exception 'that view was not found' using errcode = 'P0002'; end if;
      if v_v.scope = 'shared' and v_reason is null then raise exception 'a reason is needed to change a shared view' using errcode = '22023'; end if;
      update pipeline.saved_views s set name = v_name, description = nullif(btrim(coalesce(a->>'description', '')), ''), filters = v_f,
             columns = case when jsonb_typeof(a->'columns') = 'array' then a->'columns' else s.columns end,
             sort = case when jsonb_typeof(a->'sort') = 'object' then a->'sort' else s.sort end,
             reason = coalesce(v_reason, s.reason), updated_at = now(), updated_by = v_uid
       where s.id = v_v.id returning s.id into v_id;
    else
      if coalesce(a->>'scope', 'personal') = 'shared' then
        raise exception 'shared views are the three defaults; a Platform Admin changes them, and new views are personal' using errcode = '22023';
      end if;
      if (select count(*) from pipeline.saved_views s where s.surface = 'layer4_review_grid' and s.scope = 'personal' and s.owner_id = v_uid and s.archived_at is null)
         >= security.pipeline_num_v1('layer4.saved_views_per_user', 25) then
        raise exception 'you already keep the most personal views allowed; archive one first' using errcode = '22023';
      end if;
      if exists (select 1 from pipeline.saved_views s where s.surface = 'layer4_review_grid' and s.scope = 'personal' and s.owner_id = v_uid and s.archived_at is null and lower(s.name) = lower(v_name)) then
        raise exception 'you already have a view with that name' using errcode = '23505';
      end if;
      insert into pipeline.saved_views (scope, owner_id, name, description, filters, columns, sort, created_by, updated_by)
      values ('personal', v_uid, v_name, nullif(btrim(coalesce(a->>'description', '')), ''), v_f,
              case when jsonb_typeof(a->'columns') = 'array' then a->'columns' else '[]'::jsonb end,
              case when jsonb_typeof(a->'sort') = 'object' then a->'sort' else '{}'::jsonb end, v_uid, v_uid)
      returning id into v_id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'saved_view_save', 'saved_view:' || v_id, jsonb_build_object('name', v_name, 'filters', v_f, 'reason', v_reason), v_uid);
    return jsonb_build_object('ok', true, 'id', v_id);

  elsif p_action = 'view_archive' then
    v_reason := nullif(btrim(coalesce(a->>'reason', '')), '');
    select * into v_v from pipeline.saved_views s where s.id = nullif(a->>'id', '')::uuid and s.archived_at is null;
    if not found or (v_v.scope = 'personal' and v_v.owner_id <> v_uid) then raise exception 'that view was not found' using errcode = 'P0002'; end if;
    if v_v.scope = 'shared' and v_rank < 6 then raise exception 'only a Platform Admin (rank 6) can change a shared view' using errcode = '42501'; end if; -- fixed: decision 16 Nov 2026
    if v_v.scope = 'shared' and v_reason is null then raise exception 'a reason is needed to change a shared view' using errcode = '22023'; end if;
    update pipeline.saved_views s set archived_at = now(), archived_by = v_uid, reason = coalesce(v_reason, s.reason) where s.id = v_v.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'saved_view_archive', 'saved_view:' || v_v.id, jsonb_build_object('name', v_v.name, 'reason', v_reason), v_uid);
    return jsonb_build_object('ok', true, 'id', v_v.id);

  elsif p_action = 'rows' then
    v_f := coalesce(a->'filters', '{}'::jsonb);
    if nullif(a->>'view_id', '') is not null then
      select * into v_v from pipeline.saved_views s where s.id = (a->>'view_id')::uuid and s.archived_at is null and (s.scope = 'shared' or s.owner_id = v_uid);
      if not found then raise exception 'that view was not found' using errcode = 'P0002'; end if;
      v_f := v_v.filters || v_f;
    end if;
    v_f := security.review_grid_filters_v1(v_f);
    v_kinds := array(select jsonb_array_elements_text(coalesce(v_f->'kinds', '[]'::jsonb)));
    v_fields := array(select jsonb_array_elements_text(coalesce(v_f->'field_codes', '[]'::jsonb)));
    v_whys := array(select jsonb_array_elements_text(coalesce(v_f->'why_codes', '[]'::jsonb)));
    v_pid := (v_f->>'provider_id')::uuid; v_q := lower(v_f->>'q'); v_old := (v_f->>'older_than_days')::int;
    v_one := case when cardinality(v_kinds) = 1 then v_kinds[1] end;
    v_det := cardinality(v_fields) > 0;
    v_page := greatest(1, security.pipeline_num_v1('layer4.grid_page_rows', 50)::int);
    v_max := greatest(1, security.pipeline_num_v1('layer4.grid_page_max', 200)::int);
    if coalesce(a->>'limit', '') ~ '^[0-9]{1,4}$' then v_page := least(greatest(1, (a->>'limit')::int), v_max); end if;
    v_off := greatest(0, coalesce(nullif(a->>'offset', '')::int, 0));
    v_sort := lower(coalesce(nullif(a->>'sort', ''), nullif(v_v.sort->>'key', ''), 'created_at'));
    if v_sort not in ('created_at', 'kind', 'subject', 'provider') then v_sort := 'created_at'; end if;
    v_dir := case when lower(coalesce(nullif(a->>'direction', ''), nullif(v_v.sort->>'direction', ''), 'asc')) = 'desc' then 'desc' else 'asc' end;
    with base as (
      select i.kind, i.ref, i.provider_id, i.subject, i.why, i.created_at, p.prov
        from security.layer4_inbox_items_v2(v_pid, v_one, null, v_det) i
        left join lateral (select coalesce(nullif(pr.display_name, ''), pr.canonical_name) prov from catalogue.providers pr where pr.id = i.provider_id) p on true
       where (cardinality(v_kinds) = 0 or i.kind = any (v_kinds))
         and (cardinality(v_fields) = 0 or i.detail->>'field_code' = any (v_fields))
         and (cardinality(v_whys) = 0 or exists (select 1 from unnest(v_whys) w where position(': ' || w || '.' in coalesce(i.why, '')) > 0 or right(coalesce(i.why, ''), length(w) + 2) = ': ' || w))
         and (v_q is null or position(v_q in lower(coalesce(i.subject, ''))) > 0 or position(v_q in lower(coalesce(i.why, ''))) > 0 or position(v_q in lower(coalesce(p.prov, ''))) > 0)
         and (v_old is null or i.created_at < now() - make_interval(days => v_old))),
    ordered as (
      select b.*, row_number() over (order by
               case when v_sort = 'created_at' and v_dir = 'asc' then b.created_at end asc nulls last,
               case when v_sort = 'created_at' and v_dir = 'desc' then b.created_at end desc nulls last,
               case when v_sort = 'kind' and v_dir = 'asc' then b.kind end asc nulls last,
               case when v_sort = 'kind' and v_dir = 'desc' then b.kind end desc nulls last,
               case when v_sort = 'subject' and v_dir = 'asc' then lower(b.subject) end asc nulls last,
               case when v_sort = 'subject' and v_dir = 'desc' then lower(b.subject) end desc nulls last,
               case when v_sort = 'provider' and v_dir = 'asc' then lower(b.prov) end asc nulls last,
               case when v_sort = 'provider' and v_dir = 'desc' then lower(b.prov) end desc nulls last,
               b.created_at, b.kind, b.ref) ord, count(*) over () total
        from base b)
    select coalesce(max(o.total), 0), array_agg(o.kind || ':' || o.ref order by o.ord) filter (where o.ord > v_off and o.ord <= v_off + v_page)
      into v_total, v_keys from ordered o;
    select coalesce(jsonb_agg(jsonb_build_object('key', d.kind || ':' || d.ref, 'kind', d.kind, 'kind_label', coalesce(v_kinds_meta#>>array[d.kind, 'label'], d.kind),
             'ref', d.ref, 'provider_id', d.provider_id, 'provider', (select coalesce(nullif(pr.display_name, ''), pr.canonical_name) from catalogue.providers pr where pr.id = d.provider_id),
             'subject', d.subject, 'why', d.why, 'created_at', d.created_at, 'age_days', floor(extract(epoch from now() - d.created_at) / 86400)::int,
             'field_code', d.detail->>'field_code',
             'source_url', coalesce(d.detail->>'source_url', d.detail#>>'{proposed,source_url}', d.detail#>>'{proposed,url}', d.detail#>>'{proposed,course_url}', d.detail->>'url'),
             'quotes', jsonb_array_length(security.review_quote_pairs_v1(d.detail)))
             order by array_position(v_keys, d.kind || ':' || d.ref)), '[]'::jsonb)
      into v_rows
      from security.layer4_inbox_items_v2(null, null, v_keys, true) d
     where v_keys is not null and d.kind || ':' || d.ref = any (v_keys);
    return jsonb_build_object('total', v_total, 'offset', v_off, 'page_rows', v_page, 'page_max', v_max, 'sort', v_sort, 'direction', v_dir, 'filters', v_f, 'rows', v_rows);

  elsif p_action = 'drawer' then
    if coalesce(a->>'kind', '') !~ '^[a-z_]{1,40}$' or coalesce(a->>'ref', '') = '' then raise exception 'kind and ref are needed' using errcode = '22023'; end if;
    select d.* into v_item from security.layer4_inbox_items_v2(null, null, array[(a->>'kind') || ':' || (a->>'ref')], true) d limit 1;
    if v_item.kind is null then raise exception 'that item no longer waits for a person' using errcode = 'P0002'; end if;
    v_pmax := greatest(1, security.pipeline_num_v1('layer4.grid_drawer_pairs_max', 50)::int);
    v_hmax := greatest(1, security.pipeline_num_v1('layer4.grid_history_rows', 20)::int);
    v_pairs := security.review_quote_pairs_v1(v_item.detail);
    select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'by', case when e.action = 'rule_execute' then 'rule' when e.actor is null then 'system' else 'person' end,
             'choice', e.detail->>'choice', 'reason', coalesce(e.detail->>'reason', e.detail->>'note'), 'value', e.detail->>'value', 'rule', e.detail->>'rule') order by e.id desc), '[]'::jsonb)
      into v_hist
      from (select * from pipeline.admin_control_events e
             where e.area = 'layer4' and e.target in (v_item.kind || ':' || v_item.ref, v_item.ref) order by e.id desc limit v_hmax) e;
    if v_item.ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select jsonb_build_object('status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at, 'claimed_at', r.claimed_at, 'field_code', r.field_code)
        into v_rev from pipeline.layer4_review_items r where r.id = v_item.ref::uuid;
    end if;
    return jsonb_build_object(
      'item', jsonb_build_object('key', v_item.kind || ':' || v_item.ref, 'kind', v_item.kind, 'kind_label', coalesce(v_kinds_meta#>>array[v_item.kind, 'label'], v_item.kind),
              'ref', v_item.ref, 'provider_id', v_item.provider_id,
              'provider', (select coalesce(nullif(pr.display_name, ''), pr.canonical_name) from catalogue.providers pr where pr.id = v_item.provider_id),
              'subject', v_item.subject, 'why', v_item.why, 'suggestion', v_item.suggestion, 'created_at', v_item.created_at),
      'value', jsonb_build_object('field_code', v_item.detail->>'field_code', 'before', v_item.detail->'before', 'proposed', coalesce(v_item.detail->'proposed', v_item.detail)),
      'pairs', coalesce((select jsonb_agg(x.e order by x.o) from jsonb_array_elements(v_pairs) with ordinality x(e, o) where x.o <= v_pmax), '[]'::jsonb),
      'pairs_total', jsonb_array_length(v_pairs),
      'evidence', jsonb_strip_nulls(jsonb_build_object('evidence_id', coalesce(v_item.detail->>'evidence_id', v_item.detail#>>'{proposed,evidence_id}'),
              'source_url', coalesce(v_item.detail->>'source_url', v_item.detail#>>'{proposed,source_url}', v_item.detail#>>'{proposed,url}', v_item.detail#>>'{proposed,course_url}', v_item.detail->>'url'),
              'captured_at', coalesce(v_item.detail->>'captured_at', v_item.detail#>>'{proposed,captured_at}'), 'newer_copy', v_item.detail->'newer_copy')),
      'review', v_rev,
      'history', v_hist);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $$;
revoke all on function public.admin_review_grid(text, jsonb) from public, anon;
grant execute on function public.admin_review_grid(text, jsonb) to authenticated;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in)
select v.kind, v.name, 'Layer 4', 'Review grid', v.purpose, 'active', '{}', '20261118120000'
  from (values
    ('table', 'pipeline.saved_views', 'Saved filter views of the Review & Evidence grid: three shared defaults and personal views'),
    ('function', 'public.admin_review_grid', 'Review & Evidence grid: paged items waiting for a person, the quote-versus-value drawer and saved views'),
    ('function', 'security.review_grid_filters_v1', 'Cleans the filters a Review grid view or request carries'),
    ('function', 'security.review_quote_pairs_v1', 'The saved page quotes behind an item''s values, as quote and value pairs')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register c where c.kind = v.kind and c.name = v.name);

do $post$ begin
  if (select count(*) from pipeline.saved_views where scope = 'shared' and archived_at is null and view_key in ('aer_audit_samples', 'official_urls', 'provider_blockers')) <> 3 then
    raise exception 'post-check: the three shared views are not all present';
  end if;
  if has_table_privilege('authenticated', 'pipeline.saved_views', 'select') or has_function_privilege('anon', 'public.admin_review_grid(text,jsonb)', 'execute') then
    raise exception 'post-check: saved views must be reached only through admin_review_grid';
  end if;
end $post$;
