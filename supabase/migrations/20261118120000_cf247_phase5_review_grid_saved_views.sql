-- CF-247 UI/UX audit Phase 5, first slice (admin docs/platform/ui-audit/ui-ux-settings-audit-2026-11-15.md §4.2, §5, §7.3; Platform Admin 16 Nov
-- 2026 10:59 "Phase 5 goes before Phase 4", 18 Nov 2026 10:09 "Ship Phase 5 first slice now"): the Review grid on Layer 4 › Inbox, saved views and
-- the Source Quote vs Extracted Value drawer.
-- 1. pipeline.saved_views: shared views (visible to every Curator and above; changed by a Platform Admin only, checked here on the server) and
--    personal views (owner only). Views only choose what the grid SHOWS (kind, a reason filter, a search, sort, columns): the 5% AER audit sample
--    (aer.machine_audit_pct, aer.matrix_machine_audit_pct) and the Layer 4 URL rules stay unchanged (holds B and F); AER v1 stays frozen.
--    Three shared default views, mapped from the live Layer 4 kinds (read 18 Nov 2026 10:11 AEDT):
--      AER Audit Samples: kind aer_review, reason containing audit_sample (488 of 2,661 waiting AER items);
--      Official URLs: kinds course_link (1,487) and course_page_needed (1,958);
--      Provider Blockers: website_needed, site_down, pages_not_found, too_few_pages, nothing_ready, onboarding_failed, no_page_first_run,
--      central_to_approve, provider_departure (752 in all).
-- 2. public.admin_layer4_grid_read_v1: one built-in Layer 4 kind as rows, paged on the server (page size layer4.inbox_page_size), with the reason
--    filter, a search over the item and university, oldest or newest first, and a bounded CSV export (layer4.grid_export_max_rows). Registered
--    kinds (intervention, campus_locality) stay on By kind; the grid says so.
-- 3. public.admin_layer4_item_trace_v1: the drawer of one item: the item with its detail (proposed value, before, quote, evidence), the evidence
--    links, and its decision history from pipeline.admin_control_events (area layer4, target = the item reference). Decisions are still taken
--    only through public.admin_layer4_inbox (every current action, decision path and audit trail kept).
-- Nothing is written to the catalogue or to any Layer 4 item here. G3 surface untouched; nothing dropped.
-- Replaces: nothing yet (Layer4Inbox's By university, By kind and Decided views stay; the grid is a fourth view; the Evidence table and the Field
--           History drawer are the next slices, §5 and §7.3).
-- Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.grid_export_max_rows', 'Layer 4 grid: rows a CSV export holds',
  'The most rows one CSV export of the Layer 4 › Inbox grid holds. A larger result is cut at this number and the file says so.',
  'number', to_jsonb(5000), 100, 50000, 'rows', 1250, 'UI/UX audit Phase 5 (18 Nov 2026)', 'Layer 4 review', 'Layer 4 › Inbox › Grid (CSV export)')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.saved_views (
  id uuid primary key default gen_random_uuid(),
  screen text not null check (screen in ('layer4_inbox')),
  scope text not null check (scope in ('shared', 'personal')),
  code text,
  owner_id uuid,
  name text not null check (length(btrim(name)) between 2 and 80),
  description text,
  definition jsonb not null default '{}'::jsonb,
  sort_order integer not null default 100,
  status text not null default 'active' check (status in ('active', 'archived')),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  check ((scope = 'shared' and owner_id is null and code is not null) or (scope = 'personal' and owner_id is not null))
);
comment on table pipeline.saved_views is 'CF-247 UI/UX audit Phase 5 (18 Nov 2026): saved filter views of the review grid (Layer 4 › Inbox › Grid). Shared views are seen by every Curator and above and changed by a Platform Admin only; personal views by their owner only. A view chooses what is shown (kinds, reason filter, search, sort, columns) and never changes a rule: the AER audit sample and the Layer 4 URL rules are unchanged.';
create unique index if not exists saved_views_shared_code_uq on pipeline.saved_views(screen, code) where scope = 'shared';
create index if not exists saved_views_owner_idx on pipeline.saved_views(owner_id) where scope = 'personal';
alter table pipeline.saved_views enable row level security;
revoke all on pipeline.saved_views from anon, authenticated;

-- the columns the grid offers (data, not code)
create or replace function security.layer4_grid_columns_v1()
 returns text[]
 language sql
 immutable
 set search_path to ''
as $function$ select array['kind', 'subject', 'provider', 'country', 'why', 'suggestion', 'created_at', 'age_days'] $function$;
comment on function security.layer4_grid_columns_v1() is 'CF-247 Phase 5 (18 Nov 2026): the columns the Layer 4 review grid can show and a saved view can choose.';
revoke all on function security.layer4_grid_columns_v1() from public, anon, authenticated;

-- a view definition is checked on the server: built-in kinds only, a short reason filter, known columns and sort
create or replace function security.saved_view_definition_check_v1(p_def jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare d jsonb := coalesce(p_def, '{}'::jsonb); k text; e text[] := '{}';
begin
  if jsonb_typeof(d) <> 'object' then return jsonb_build_object('ok', false, 'errors', jsonb_build_array('A view is a JSON object.')); end if;
  for k in select jsonb_object_keys(d) loop
    if k <> all (array['kinds', 'why_contains', 'q', 'sort', 'columns']) then e := e || format('Unknown key "%s" in the view.', k); end if;
  end loop;
  if jsonb_typeof(d->'kinds') <> 'array' or jsonb_array_length(d->'kinds') = 0 then e := e || 'A view names at least one kind.'::text;
  else
    for k in select jsonb_array_elements_text(d->'kinds') loop
      if not (security.layer4_inbox_kinds_v1() ? k) then e := e || format('Kind "%s" is not one the grid reads.', k); end if;
    end loop;
  end if;
  if d ? 'why_contains' and length(coalesce(d->>'why_contains', '')) > 80 then e := e || 'The reason filter is 80 characters at most.'::text; end if; -- fixed: input-safety bound
  if d ? 'q' and length(coalesce(d->>'q', '')) > 80 then e := e || 'The search is 80 characters at most.'::text; end if; -- fixed: input-safety bound
  if d ? 'sort' and coalesce(d->>'sort', '') not in ('oldest', 'newest') then e := e || 'Sort is oldest or newest.'::text; end if;
  if d ? 'columns' then
    if jsonb_typeof(d->'columns') <> 'array' then e := e || 'Columns is a list.'::text;
    else
      for k in select jsonb_array_elements_text(d->'columns') loop
        if k <> all (security.layer4_grid_columns_v1()) then e := e || format('Column "%s" is not one the grid shows.', k); end if;
      end loop;
    end if;
  end if;
  return jsonb_build_object('ok', cardinality(e) = 0, 'errors', to_jsonb(e));
end $function$;
comment on function security.saved_view_definition_check_v1(jsonb) is 'CF-247 Phase 5 (18 Nov 2026): checks a saved view definition (built-in Layer 4 kinds, reason filter, search, sort, columns).';
revoke all on function security.saved_view_definition_check_v1(jsonb) from public, anon, authenticated;

insert into pipeline.saved_views(screen, scope, code, name, description, definition, sort_order) values
 ('layer4_inbox', 'shared', 'aer_audit_samples', 'AER Audit Samples',
  'AER readings the machine rule held for the 5% audit sample (reason audit_sample). Decide each one as before: approve, reject or approve except.',
  jsonb_build_object('kinds', jsonb_build_array('aer_review'), 'why_contains', 'audit_sample', 'sort', 'oldest', 'columns', jsonb_build_array('subject', 'provider', 'why', 'created_at', 'age_days')), 10),
 ('layer4_inbox', 'shared', 'official_urls', 'Official URLs',
  'Course links and course pages a person decides: the proposed official course address beside the one held.',
  jsonb_build_object('kinds', jsonb_build_array('course_link', 'course_page_needed'), 'sort', 'oldest', 'columns', jsonb_build_array('kind', 'subject', 'provider', 'country', 'why', 'age_days')), 20),
 ('layer4_inbox', 'shared', 'provider_blockers', 'Provider Blockers',
  'Universities whose onboarding or coverage is stopped: website needed or not answering, course pages not found or too few, adapter has nothing ready or failed, no page published, central pages to approve, left the register.',
  jsonb_build_object('kinds', jsonb_build_array('website_needed', 'site_down', 'pages_not_found', 'too_few_pages', 'nothing_ready', 'onboarding_failed', 'no_page_first_run', 'central_to_approve', 'provider_departure'),
                     'sort', 'oldest', 'columns', jsonb_build_array('kind', 'provider', 'country', 'why', 'suggestion', 'age_days')), 30)
on conflict do nothing;

create or replace function public.admin_saved_views_read_v1(p_screen text default 'layer4_inbox')
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_rank int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if; -- fixed: who opens Layer 4
  return jsonb_build_object('rank', v_rank, 'can_edit_shared', v_rank >= 6, 'columns', to_jsonb(security.layer4_grid_columns_v1()),
    'grid_kinds', coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(security.layer4_inbox_kinds_v1()) k), '[]'::jsonb),
    'views', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'scope', v.scope, 'code', v.code, 'name', v.name, 'description', v.description,
                                   'definition', v.definition, 'mine', v.owner_id = auth.uid(), 'updated_at', v.updated_at) order by v.scope desc, v.sort_order, v.name)
                         from pipeline.saved_views v where v.screen = p_screen and v.status = 'active' and (v.scope = 'shared' or v.owner_id = auth.uid())), '[]'::jsonb));
end $function$;
comment on function public.admin_saved_views_read_v1(text) is 'CF-247 Phase 5 (18 Nov 2026): the shared views and the caller''s personal views of a grid screen. Curator and above.';
revoke all on function public.admin_saved_views_read_v1(text) from public, anon;
grant execute on function public.admin_saved_views_read_v1(text) to authenticated;

-- save: a personal view by its owner; a shared view by a Platform Admin only (rank 6, checked here). Every save is logged.
create or replace function public.admin_saved_view_save_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_rank int; v_row pipeline.saved_views; v_id uuid := nullif(a->>'id', '')::uuid;
        v_scope text := coalesce(nullif(a->>'scope', ''), 'personal'); v_check jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if; -- fixed: who opens Layer 4
  v_check := security.saved_view_definition_check_v1(a->'definition');
  if not (v_check->>'ok')::boolean then raise exception '%', (select string_agg(x, ' ') from jsonb_array_elements_text(v_check->'errors') x) using errcode = '22023'; end if;
  if v_id is not null then
    select * into v_row from pipeline.saved_views where id = v_id and status = 'active' for update;
    if v_row.id is null then raise exception 'view not found' using errcode = '22023'; end if;
    v_scope := v_row.scope;
  end if;
  if v_scope = 'shared' and v_rank < 6 then raise exception 'a shared view is changed by a Platform Admin only' using errcode = '42501'; end if; -- fixed: shared views are the Platform Admin's
  if v_scope = 'personal' and v_row.id is not null and v_row.owner_id is distinct from auth.uid() then raise exception 'a personal view is changed by its owner only' using errcode = '42501'; end if;
  if v_scope not in ('shared', 'personal') then raise exception 'scope is shared or personal' using errcode = '22023'; end if;
  if v_row.id is null then
    insert into pipeline.saved_views(screen, scope, code, owner_id, name, description, definition, sort_order, created_by, updated_by)
    values ('layer4_inbox', v_scope, case when v_scope = 'shared' then coalesce(nullif(a->>'code', ''), 'shared_' || substr(md5(random()::text), 1, 8)) end,
            case when v_scope = 'personal' then auth.uid() end, btrim(a->>'name'), nullif(btrim(coalesce(a->>'description', '')), ''), a->'definition',
            coalesce(nullif(a->>'sort_order', '')::int, 100), auth.uid(), auth.uid())
    returning * into v_row;
  else
    update pipeline.saved_views set name = coalesce(nullif(btrim(a->>'name'), ''), name), description = case when a ? 'description' then nullif(btrim(a->>'description'), '') else description end,
           definition = a->'definition', updated_by = auth.uid(), updated_at = now()
     where id = v_row.id returning * into v_row;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'saved_view_save', v_row.id::text, jsonb_build_object('scope', v_row.scope, 'name', v_row.name, 'definition', v_row.definition), auth.uid());
  return jsonb_build_object('ok', true, 'id', v_row.id, 'scope', v_row.scope);
end $function$;
comment on function public.admin_saved_view_save_v1(jsonb) is 'CF-247 Phase 5 (18 Nov 2026): saves a grid view; personal by its owner, shared by a Platform Admin only (checked on the server). Logged in admin_control_events.';
revoke all on function public.admin_saved_view_save_v1(jsonb) from public, anon;
grant execute on function public.admin_saved_view_save_v1(jsonb) to authenticated;

create or replace function public.admin_saved_view_archive_v1(p_id uuid, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rank int; v_row pipeline.saved_views;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  select * into v_row from pipeline.saved_views where id = p_id and status = 'active' for update;
  if v_row.id is null then raise exception 'view not found' using errcode = '22023'; end if;
  if v_row.scope = 'shared' and v_rank < 6 then raise exception 'a shared view is changed by a Platform Admin only' using errcode = '42501'; end if; -- fixed: shared views are the Platform Admin's
  if v_row.scope = 'personal' and v_row.owner_id is distinct from auth.uid() then raise exception 'a personal view is changed by its owner only' using errcode = '42501'; end if;
  update pipeline.saved_views set status = 'archived', updated_by = auth.uid(), updated_at = now() where id = p_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'saved_view_archive', p_id::text, jsonb_build_object('scope', v_row.scope, 'name', v_row.name, 'reason', left(coalesce(p_reason, ''), 300)), auth.uid());
  return jsonb_build_object('ok', true);
end $function$;
comment on function public.admin_saved_view_archive_v1(uuid, text) is 'CF-247 Phase 5 (18 Nov 2026): archives a grid view (kept, not deleted); a personal view by its owner, a shared view by a Platform Admin only.';
revoke all on function public.admin_saved_view_archive_v1(uuid, text) from public, anon;
grant execute on function public.admin_saved_view_archive_v1(uuid, text) to authenticated;

create or replace function public.admin_layer4_grid_read_v1(p_args jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_rank int; v_kind text := nullif(a->>'kind', ''); v_why text := nullif(btrim(a->>'why_contains'), '');
        v_q text := nullif(btrim(a->>'q'), ''); v_prov uuid := nullif(a->>'provider_id', '')::uuid; v_export boolean := coalesce((a->>'export')::boolean, false);
        v_sort text := case when a->>'sort' = 'newest' then 'newest' else 'oldest' end; v_lim int; v_off int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if; -- fixed: who opens Layer 4
  if v_kind is null or not (security.layer4_inbox_kinds_v1() ? v_kind) then
    raise exception 'the grid reads the built-in kinds; open % on By kind', coalesce(v_kind, 'a kind') using errcode = '22023';
  end if;
  if length(coalesce(v_why, '')) > 80 or length(coalesce(v_q, '')) > 80 then raise exception 'a filter is 80 characters at most' using errcode = '22023'; end if; -- fixed: input-safety bound
  v_lim := least(greatest(case when v_export then security.pipeline_num_v1('layer4.grid_export_max_rows', 5000) else security.pipeline_num_v1('layer4.inbox_page_size', 200) end, 1), 50000)::int; -- fixed: hard ceiling over the settings
  v_off := case when v_export then 0 else greatest(coalesce(nullif(a->>'offset', '')::int, 0), 0) end;
  return (
    with i as (select i.kind, i.ref, i.provider_id, i.subject, i.why, i.suggestion, i.created_at
                 from security.layer4_inbox_items_v2(v_prov, v_kind, null, false) i
                where v_why is null or i.why ilike '%' || v_why || '%'),
         j as (select i.*, coalesce(p.display_name, p.canonical_name) provider, k.iso_alpha2::text country
                 from i left join catalogue.providers p on p.id = i.provider_id left join ref.countries k on k.id = p.country_id
                where v_q is null or i.subject ilike '%' || v_q || '%' or coalesce(p.display_name, p.canonical_name, '') ilike '%' || v_q || '%'),
         pg as (select * from j order by case when v_sort = 'oldest' then created_at end asc nulls last, case when v_sort = 'newest' then created_at end desc nulls last, ref
                 limit v_lim offset v_off)
    select jsonb_build_object('total', (select count(*) from j), 'offset', v_off, 'limit', v_lim, 'kind', v_kind, 'sort', v_sort, 'export', v_export,
             'kind_label', security.layer4_inbox_kinds_v1()->v_kind->>'label', 'rank', v_rank,
             'rows', coalesce((select jsonb_agg(jsonb_build_object('kind', pg.kind, 'ref', pg.ref, 'provider_id', pg.provider_id, 'provider', pg.provider, 'country', pg.country,
                                 'subject', pg.subject, 'why', pg.why, 'suggestion', pg.suggestion, 'created_at', pg.created_at,
                                 'age_days', floor(extract(epoch from now() - pg.created_at) / 86400)::int)
                                 order by case when v_sort = 'oldest' then pg.created_at end asc nulls last, case when v_sort = 'newest' then pg.created_at end desc nulls last, pg.ref)
                               from pg), '[]'::jsonb)));
end $function$;
comment on function public.admin_layer4_grid_read_v1(jsonb) is 'CF-247 Phase 5 (18 Nov 2026): one built-in Layer 4 kind as grid rows, paged on the server (layer4.inbox_page_size), with reason filter, search and sort; a CSV export reads up to layer4.grid_export_max_rows. Read only. Curator and above.';
revoke all on function public.admin_layer4_grid_read_v1(jsonb) from public, anon;
grant execute on function public.admin_layer4_grid_read_v1(jsonb) to authenticated;

create or replace function public.admin_layer4_item_trace_v1(p_kind text, p_ref text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_rank int; v_it record; v_prov text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if; -- fixed: who opens Layer 4
  if coalesce(p_kind, '') = '' or coalesce(p_ref, '') = '' or not (security.layer4_inbox_kinds_v1() ? p_kind) then raise exception 'a built-in kind and an item reference are needed' using errcode = '22023'; end if;
  select * into v_it from security.layer4_inbox_items_v2(null, p_kind, array[p_kind || ':' || p_ref], true) limit 1;
  select coalesce(p.display_name, p.canonical_name) into v_prov from catalogue.providers p where p.id = v_it.provider_id;
  return jsonb_build_object(
    'waiting', v_it.ref is not null,
    'item', case when v_it.ref is null then null else jsonb_build_object('kind', v_it.kind, 'ref', v_it.ref, 'provider_id', v_it.provider_id, 'provider', v_prov,
              'subject', v_it.subject, 'why', v_it.why, 'suggestion', v_it.suggestion, 'created_at', v_it.created_at, 'detail', v_it.detail) end,
    'evidence', case when v_it.detail ? 'evidence_id' and coalesce(v_it.detail->>'evidence_id', '') <> '' then
                  (select jsonb_build_object('id', e.id, 'source_url', e.source_url, 'captured_at', e.captured_at, 'type', e.evidence_type, 'content_hash', e.content_hash)
                     from pipeline.evidence_artifacts e where e.id::text = v_it.detail->>'evidence_id') end,
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', x.created_at, 'action', x.action, 'choice', x.detail->>'choice', 'value', x.detail->>'value', 'reason', x.detail->>'reason',
                                 'auto', coalesce((x.detail->>'auto')::boolean, false), 'machine_rule', x.detail->>'machine_rule',
                                 'by', (select u.email from auth.users u where u.id::text = x.actor::text)) order by x.id desc)
                         from (select * from pipeline.admin_control_events c where c.area = 'layer4' and c.target = p_ref order by c.id desc limit 50) x), '[]'::jsonb)); -- fixed: history rows shown
end $function$;
comment on function public.admin_layer4_item_trace_v1(text, text) is 'CF-247 Phase 5 (18 Nov 2026): the Source Quote vs Extracted Value drawer of one Layer 4 item: the item with its detail, its evidence and its decision history (admin_control_events, area layer4). Read only. Curator and above.';
revoke all on function public.admin_layer4_item_trace_v1(text, text) from public, anon;
grant execute on function public.admin_layer4_item_trace_v1(text, text) to authenticated;

do $$
begin
  if (select count(*) from pipeline.saved_views where scope = 'shared' and screen = 'layer4_inbox' and code in ('aer_audit_samples', 'official_urls', 'provider_blockers')) <> 3 then raise exception 'post-check: the three shared views'; end if;
  if exists (select 1 from pipeline.saved_views v where v.scope = 'shared' and not (security.saved_view_definition_check_v1(v.definition)->>'ok')::boolean) then raise exception 'post-check: a shared view names a kind the grid does not read'; end if;
  if security.pipeline_num_v1('aer.machine_audit_pct', -1) < 0 then raise exception 'post-check: the AER audit sample setting is unchanged and present'; end if;
end $$;
