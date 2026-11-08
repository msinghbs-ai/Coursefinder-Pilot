-- CF-247 AER: a course page that prints a whole qualification-by-country table is mapped as an entry matrix SOURCE from its stored copy (Platform Admin directive 8 Nov 2026:
-- "resolve QUT matrix mapping ... Keep the 24 locked courses ... held unless individually authorised ... Preserve all previous readings, supersessions and review history ... nothing
-- auto-admitted; human Layer 4 decisions remain mandatory ... no additional Firecrawl credits or any paid recovery"). Development agent, branch cf247-aer-qut-shared.
-- Guards: G1 (no job here), G2 (the activation size is a setting), G3 (no consumer API object, table or column is touched), Decision 260 (housekeeping),
--   "a passing qualification never switches anything on by itself" (sources are attached HELD; reading them is a separate, capped, Platform Admin call),
--   "nothing is dropped or deleted by an applied migration" (no old item, read, row or history is changed).
-- Replaces: nothing (security.aer_route_v1 already names the route source_is_matrix; this is the mapping step that route has been waiting for)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 8 Nov 2026), QUT (provider 2c4f515c-c146-4e90-ba8a-294130aa1f40):
--   * 38 waiting course reads are technical holds; 37 were cut at the row limit with 30 to 111 rows cut (the 38th, 8 rows, is an ordinary row-limit case and is not mapped).
--     All 37 have a stored HTML copy (evidence with a storage path and a content hash) whose address is the course page the read used. QUT has no pipeline.entry_matrix_sources row.
--   * The table is printed on EACH course page and differs by course: of 467 distinct cut quotes 206 occur on one course only, and the same qualification carries different
--     thresholds (CBSE: "60.00%" on 16 courses, "75.00%" on 6). It is therefore not one provider matrix; each page is a course-level matrix source. Rows from it are
--     course_minimum rows, and the matrix writer never set course_id (no matrix row written by the reader carries one), so two QUT pages would write competing provider-level rows.
--   * 14 of the 37 are courses whose page address is locked by hand. Those stay held: they are not mapped unless the Platform Admin names them (p_include_items).
--   * QUT is AER-eligible and security.entry_matrix_enabled_v1 turns true for a provider as soon as it has any source row; every reader step only touches sources in status
--     found or read, so a source attached as 'inactive' starts nothing.
-- What this does:
--   1. pipeline.aer_matrix_route: one row per mapped course page (old waiting item, course, source, stored copy, rows cut, state held / activated / closed). History is never deleted.
--   2. security.aer_matrix_route_candidates_v1(provider): the waiting course reads of a provider cut at aer.row_limit_matrix_rows or more rows (the same setting security.aer_route_v1
--      uses for source_is_matrix), with a stored HTML copy, no hand lock, nothing mapped yet. Read only.
--   3. security.aer_matrix_route_attach_v1(provider, expected, md5, reason, include_items): Platform Admin (postgres) only, count and md5 guarded. For each candidate it adds a
--      pipeline.entry_matrix_sources row (found_via manual, read_via stored, the stored copy, status inactive), a route row (held) and one audit event in admin_control_events.
--      No fetch, no AI call, no spend. The waiting course read items are NOT touched: they stay pending with all their history until the matrix rows from the same page are
--      decided and a corrected course read (table rows set aside) replaces them through pipeline.aer_read_supersessions.
--   4. security.aer_matrix_route_activate_v1(provider, expected, reason): Platform Admin (postgres) only. Moves at most aer.matrix_route_activate_max held sources to status read,
--      so the EXISTING reader (entry-matrix-read, pinned model, AI daily guard) reads them; every result goes to Layer 4 as a proposed matrix run. Not called here.
--   5. A trigger on catalogue.provider_entry_matrix stamps a row that comes from a mapped source with that source's course (course_id, matrix_kind course_minimum, course_label).
--      No column, type or function the consumer reads changes (G3); rows are still proposed and a person admits them.
--   6. Applied here for QUT only, under a count and md5 guard measured live (23 candidates, md5 e132941111515af718e4822f24275a03): if the live set differs the data step is
--      skipped with a notice and nothing changes; a second run reports already applied.
-- Not changed: the 37 waiting items, aer.row_limit_matrix_rows, entry.matrix_enabled, entry.providers, the readers, E13, D-R2, D-R3, the replay, every other switch.

do $g$
begin
  if to_regclass('pipeline.entry_matrix_sources') is null or to_regclass('catalogue.provider_entry_matrix') is null or to_regclass('pipeline.manual_locks') is null
     or to_regprocedure('security.ai_use_allowed_v1(text)') is null then
    raise exception 'needs the entry matrix tables, pipeline.manual_locks and security.ai_use_allowed_v1';
  end if;
end $g$;

-- 1 settings (G2) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_route_activate_max', 'Entry requirements: mapped course pages read per activation',
  'One activation of mapped course-table pages (security.aer_matrix_route_activate_v1, Platform Admin) sets at most this many held pages to be read by the entry matrix reader. Each page is read with AI, so this caps the spend of one step.',
  'number', to_jsonb(5), 1, 50, 'pages', 1472, 'Entry requirements', 'security.aer_matrix_route_activate_v1',
  'CF-247 AER (directive 8 Nov 2026): a mapped page is read only on a deliberate, capped Platform Admin step')
on conflict (toolset_key, key) do nothing;

-- 2 the route record --------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_matrix_route (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  course_id uuid not null references catalogue.courses(id),
  old_item_id uuid not null unique references pipeline.layer4_review_items(id),
  source_id uuid not null unique references pipeline.entry_matrix_sources(id),
  url text not null,
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  content_hash text not null,
  rows_cut int not null,
  state text not null default 'held' check (state in ('held', 'activated', 'closed')),
  reason text not null,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  closed_at timestamptz,
  closed_note text
);
comment on table pipeline.aer_matrix_route is 'CF-247 AER (8 Nov 2026): a course page that prints a qualification-by-country table, mapped as an entry matrix source from its stored copy. One row per page: the waiting course read it came from (kept, with its history), the course, the matrix source, the stored copy and the rows the course read cut. State held (source attached inactive), activated (a Platform Admin step set it to be read by the matrix reader) or closed. Never deleted.';
create index if not exists aer_matrix_route_provider_idx on pipeline.aer_matrix_route (provider_id, state);
alter table pipeline.aer_matrix_route enable row level security;
revoke all on pipeline.aer_matrix_route from public, anon, authenticated;

-- 3 candidates (read only) ---------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_matrix_route_candidates_v1(p_provider uuid, p_include_items uuid[] default '{}')
returns table(item_id uuid, course_id uuid, course_title text, url text, evidence_id uuid, content_hash text, rows_cut int, locked boolean)
language sql stable security definer set search_path = '' as $function$
  select i.id, i.entity_id, k.canonical_title, a.source_url, a.id, a.content_hash, x.cut::int,
         exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('official_url', 'course_url'))
    from pipeline.layer4_review_items i
    join catalogue.courses k on k.id = i.entity_id and k.provider_id = p_provider
    join pipeline.evidence_artifacts a on a.id = i.evidence_id and a.storage_path is not null and a.content_hash is not null and a.mime_type like 'text/html%'
         and a.source_url ~ '^https?://'
    cross join lateral (select count(*) cut from jsonb_array_elements(coalesce(i.proposed_value->'dropped', '[]'::jsonb)) d where d->>'reason' = 'over_row_limit') x
   where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course'
     and x.cut >= security.pipeline_num_v1('aer.row_limit_matrix_rows', 30)
     and not exists (select 1 from pipeline.aer_matrix_route r where r.old_item_id = i.id)
     and not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p_provider and s.url = a.source_url)
     and (i.id = any (coalesce(p_include_items, '{}'::uuid[]))
          or not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('official_url', 'course_url')))
$function$;
comment on function security.aer_matrix_route_candidates_v1(uuid, uuid[]) is 'CF-247 AER (8 Nov 2026): the waiting course reads of a provider cut at aer.row_limit_matrix_rows or more rows with a stored HTML copy, nothing mapped yet; courses with a hand lock on the page address only when named in p_include_items. Read only.';
revoke all on function security.aer_matrix_route_candidates_v1(uuid, uuid[]) from public, anon, authenticated;

-- 4 attach (held) -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_matrix_route_attach_v1(p_provider uuid, p_expected int, p_md5 text, p_reason text, p_include_items uuid[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_n int; v_md5 text; v_added int := 0; r record; v_src uuid;
begin
  if current_user <> 'postgres' then raise exception 'mapping a course page as a matrix source is a Platform Admin step'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  select count(*), md5(string_agg(c.item_id::text || ':' || c.content_hash, ',' order by c.item_id)) into v_n, v_md5
    from security.aer_matrix_route_candidates_v1(p_provider, p_include_items) c;
  if v_n <> p_expected or v_md5 is distinct from p_md5 then
    raise exception 'count and md5 guard: % candidates (md5 %), expected % (md5 %); nothing changed', v_n, v_md5, p_expected, p_md5;
  end if;
  for r in select * from security.aer_matrix_route_candidates_v1(p_provider, p_include_items) order by item_id loop
    insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via, status, read_via, evidence_id, content_hash, read_at, error)
    values (p_provider, r.url, left(r.course_title, 200), 1, 'manual', 'inactive', 'stored', r.evidence_id, r.content_hash, now(),
            'held: course page mapped as a matrix source (aer_matrix_route), waiting for a Platform Admin activation')
    on conflict (provider_id, url) do nothing
    returning id into v_src;
    if v_src is null then continue; end if;
    insert into pipeline.aer_matrix_route(provider_id, course_id, old_item_id, source_id, url, evidence_id, content_hash, rows_cut, reason)
    values (p_provider, r.course_id, r.item_id, v_src, r.url, r.evidence_id, r.content_hash, r.rows_cut, btrim(p_reason));
    v_added := v_added + 1;
  end loop;
  if v_added <> p_expected then raise exception 'count guard after change: % mapped, % expected', v_added, p_expected; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'route_attach', 'provider: ' || p_provider,
          jsonb_build_object('mapped', v_added, 'expected', p_expected, 'md5', v_md5, 'reason', btrim(p_reason), 'status', 'inactive (held)', 'fetch', false, 'ai', false,
                             'locked_included', coalesce(cardinality(p_include_items), 0), 'old_items_changed', 0), null);
  return jsonb_build_object('ok', true, 'mapped', v_added, 'md5', v_md5);
end $function$;
comment on function security.aer_matrix_route_attach_v1(uuid, int, text, text, uuid[]) is 'CF-247 AER (8 Nov 2026): Platform Admin only, count and md5 guarded. Maps each candidate course page as a matrix source in status inactive (read_via stored, the stored copy) with a held route row and one audit event. No fetch, no AI, no change to the waiting items.';
revoke all on function security.aer_matrix_route_attach_v1(uuid, int, text, text, uuid[]) from public, anon, authenticated;

-- 5 activation (deliberate, capped) ----------------------------------------------------------------------------------------------------------------
create or replace function security.aer_matrix_route_activate_v1(p_provider uuid, p_expected int, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_max int := security.pipeline_num_v1('aer.matrix_route_activate_max', 5)::int; v_ids uuid[]; v_n int;
begin
  if current_user <> 'postgres' then raise exception 'activating mapped course pages is a Platform Admin step'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if not security.ai_use_allowed_v1('entry_matrix') then raise exception 'entry matrix AI use is stopped (daily guard or credit floor); nothing changed'; end if;
  select array_agg(x.id) into v_ids from (select r.id from pipeline.aer_matrix_route r where r.provider_id = p_provider and r.state = 'held' order by r.created_at, r.id limit v_max) x;
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n <> p_expected then raise exception 'count guard: % held pages would be activated (cap %), expected %; nothing changed', v_n, v_max, p_expected; end if;
  update pipeline.entry_matrix_sources s set status = 'read', error = null, read_at = now(), updated_at = now()
    from pipeline.aer_matrix_route r where r.id = any (v_ids) and s.id = r.source_id and s.status = 'inactive';
  update pipeline.aer_matrix_route r set state = 'activated', activated_at = now() where r.id = any (v_ids);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'route_activate', 'provider: ' || p_provider, jsonb_build_object('activated', v_n, 'cap', v_max, 'reason', btrim(p_reason), 'route_ids', to_jsonb(v_ids)), null);
  return jsonb_build_object('ok', true, 'activated', v_n);
end $function$;
comment on function security.aer_matrix_route_activate_v1(uuid, int, text) is 'CF-247 AER (8 Nov 2026): Platform Admin only. Sets at most aer.matrix_route_activate_max held mapped pages to status read so the existing entry matrix reader reads them (AI, pinned model, daily guard); results go to Layer 4 as proposed runs.';
revoke all on function security.aer_matrix_route_activate_v1(uuid, int, text) from public, anon, authenticated;

-- 6 rows from a mapped source carry its course ----------------------------------------------------------------------------------------------------
create or replace function security.aer_matrix_route_stamp_tg() returns trigger language plpgsql security definer set search_path = '' as $function$
declare r pipeline.aer_matrix_route%rowtype;
begin
  if new.source_id is null or new.course_id is not null then return new; end if;
  select * into r from pipeline.aer_matrix_route where source_id = new.source_id and state <> 'closed';
  if r.id is null then return new; end if;
  new.course_id := r.course_id;
  new.matrix_kind := 'course_minimum';
  new.course_label := coalesce(new.course_label, (select k.canonical_title from catalogue.courses k where k.id = r.course_id));
  return new;
end $function$;
comment on function security.aer_matrix_route_stamp_tg() is 'CF-247 AER (8 Nov 2026): a matrix row written from a mapped course page (pipeline.aer_matrix_route) is that course''s row: course_id, matrix_kind course_minimum, course_label. Sorts before the identity trigger so the row hash includes the course.';
revoke all on function security.aer_matrix_route_stamp_tg() from public, anon, authenticated;
do $t$
begin
  if not exists (select 1 from pg_trigger where tgname = 'provider_entry_matrix_a_route' and tgrelid = 'catalogue.provider_entry_matrix'::regclass) then
    create trigger provider_entry_matrix_a_route before insert on catalogue.provider_entry_matrix for each row execute function security.aer_matrix_route_stamp_tg();
  end if;
end $t$;

-- 7 the QUT data move, under a live count and md5 guard ------------------------------------------------------------------------------------------
do $apply$
declare v_p constant uuid := '2c4f515c-c146-4e90-ba8a-294130aa1f40'; v_n int; v_md5 text;
begin
  if not exists (select 1 from catalogue.providers p where p.id = v_p) then raise notice 'QUT route: provider not present, skipped'; return; end if;
  if exists (select 1 from pipeline.aer_matrix_route r where r.provider_id = v_p) then raise notice 'QUT route: already applied'; return; end if;
  select count(*), md5(string_agg(c.item_id::text || ':' || c.content_hash, ',' order by c.item_id)) into v_n, v_md5 from security.aer_matrix_route_candidates_v1(v_p) c;
  if v_n = 23 and v_md5 = 'e132941111515af718e4822f24275a03' then
    perform security.aer_matrix_route_attach_v1(v_p, 23, 'e132941111515af718e4822f24275a03',
      'QUT: 23 unlocked course pages that print a qualification-by-country table are mapped as held matrix sources from their stored copies (directive 8 Nov 2026)');
    raise notice 'QUT route: 23 course pages mapped (held, inactive)';
  else
    raise notice 'QUT route: not applied, the live set differs (% candidates, md5 %); nothing changed', v_n, v_md5;
  end if;
end $apply$;
