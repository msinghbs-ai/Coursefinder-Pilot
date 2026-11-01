-- CF-247 SS-016 UR-18, slice 1: provider-level bulk review for country, state/territory, campus and course delivery location.
-- Platform Admin decisions, 2 Nov 2026 05:18 AEDT: D-B1 (eligible-field policy, order country, state, campus, location, then intake and
-- English; AER never in bulk), D-B2 (Platform Admin applies, other reviewers preview only; manual locks and course-specific overrides stay
-- protected; every included course needs applicability evidence), D-B3 (build and isolated fixture testing; production bulk-write capability
-- disabled by default). D-B4 (production activation) is NOT approved: setting layer4.bulk_review_enabled is 0 and nothing here turns it on.
-- Design: admin docs/platform/nz-enrichment-brief/2026-11-01-provider-bulk-review-design.md (sections 3, 4, 5 and the admission contract, 10).
-- Why: catalogue gaps (5,870 active courses with no campus link, courses with no delivery mode, campuses with no state) are filled one item at
--   a time today, although the evidence often covers a whole group of courses. Bulk review closes gaps with the same admission and audit path.
-- What:
--   1. Four settings (G2), section Layer 4: the switch layer4.bulk_review_enabled (default 0), courses written per apply, most courses in one
--      operation, and how long an unfinished operation holds its university and field.
--   2. Two tables beside the catalogue (G3-safe): pipeline.layer4_bulk_operations (one row per applied plan) and
--      pipeline.layer4_bulk_operation_items (one row per course or campus in the plan: class, reason, evidence, before and after value, outcome,
--      reversal). Nothing in the consumer API reads them.
--   3. security.layer4_bulk_plan_v1: the deterministic plan for one university and field. Every candidate is put in one class: eligible,
--      unchanged, protected (manual lock or course-specific exclusion), excluded_exception, excluded_conflict, excluded_unsupported, with a
--      plain reason and its course-level evidence (the bound official course page, its stored copy and the adapter's latest reading of it; for
--      campus fields, the campus record and its stored source). Country and state are campus-level (design section 3): the plan lists campuses,
--      each with the number of active courses linked to it. Read only.
--   4. security.layer4_bulk_review_v1 (reached through public.admin_layer4_inbox): bulk_preview (any reviewer, rank 3, never writes): exact
--      counts, the paged list and the plan fingerprint (md5 of the sorted plan); bulk_apply (Platform Admin, rank 6, only when the switch is 1):
--      refuses a changed plan, applies at most layer4.bulk_batch_size rows per call, creates one review item per row and decides it through
--      security.layer4_review_decide_impl (the existing admission and audit path, design section 10), re-checks each row before writing,
--      reads the destination back, records one outcome per row and an audit event per row, and is safe to call again with the same plan
--      (rows already applied are never written twice); bulk_reverse (Platform Admin): restores each applied row's before value through the same
--      path, unless it changed since; bulk_operation: reads an operation and its rows.
--   5. security.layer4_bulk_field_apply_v1: the apply function for the four new field codes (bulk_campus_country, bulk_campus_state,
--      bulk_course_campus, bulk_course_location). It refuses unless called inside a Platform Admin bulk apply or reversal.
--   6. Two md5-guarded edits: security.layer4_review_decide_impl routes the four field codes to (5); public.admin_layer4_inbox routes the four
--      bulk actions to (4). Nothing else in either function changes.
-- Before/after md5 (after: dry run in a rolled-back transaction on the live project, 2 Nov 2026; live unchanged afterwards):
--   security.layer4_review_decide_impl(uuid,text,text,jsonb)  Before: 67966cebe3184b9acad1a3451fd0021b. After: 26efc646bd65c181da99b4c6b5945205
--   public.admin_layer4_inbox(text,jsonb)                      Before: 417f181d12155f79f68c1e70c27a1892. After: ce6e8c4c5bf89a319eb7bc5e9c05f07d
-- Rollback: switch layer4.bulk_review_enabled stays 0 (nothing can be applied); reverse any applied operation with bulk_reverse; re-apply the
--   two before definitions (the same edits reversed). Dropping the new tables and functions is a paste file for the Platform Admin.
-- Replaces: security.layer4_review_decide_impl, public.admin_layer4_inbox (same names; md5-guarded edits)
-- Retires: nothing
-- No job (G1 not needed). Nothing dropped or deleted by this migration. Consumer API untouched (G3): no website_*, zoho_* or api.* object, and no
--   catalogue table changes shape. A reversal of a campus link removes only the exact link row its own operation added (recorded in the item).

-- 1. settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.bulk_review_enabled', 'Bulk review: apply switched on',
  'When 1, the Platform Admin can apply a previewed provider bulk review (Layer 4 › Review, university view). 0 keeps bulk apply off: reviewers can still preview, and nothing is written. Turning it on in production is a separate Platform Admin decision (D-B4).', 'number',
  to_jsonb(0), 0, 1, 'on/off', 888, 'Layer 4', 'security.layer4_bulk_review_v1 (bulk_apply); Layer 4 › Review bulk panel',
  'UR-18 slice 1 (Platform Admin D-B3, 2 Nov 2026 05:18): built and fixture-tested with bulk writes off; activation is D-B4'),
 ('pipeline', 'layer4.bulk_batch_size', 'Bulk review: rows written per apply',
  'One Apply writes at most this many courses (or campuses). Apply again with the same preview to write the next batch; rows already written are not written twice.', 'number',
  to_jsonb(50), 1, 200, 'courses', 889, 'Layer 4', 'security.layer4_bulk_review_v1 (bulk_apply, bulk_reverse)',
  'UR-18 slice 1 (design section 5: batches of 50)'),
 ('pipeline', 'layer4.bulk_max_courses', 'Bulk review: most rows in one operation',
  'An operation may include at most this many eligible courses (or campuses). Above it, tick the rows to include.', 'number',
  to_jsonb(500), 1, 2000, 'courses', 890, 'Layer 4', 'security.layer4_bulk_review_v1 (bulk_apply)',
  'UR-18 slice 1 (design section 5: never more than 500 in one operation)'),
 ('pipeline', 'layer4.bulk_open_minutes', 'Bulk review: an unfinished operation holds its university and field for',
  'While an operation is part-applied, no other operation may start for the same university and field until it is finished or this time has passed since its last batch.', 'number',
  to_jsonb(60), 5, 1440, 'minutes', 891, 'Layer 4', 'security.layer4_bulk_review_v1 (bulk_apply)',
  'UR-18 slice 1 (design section 5: one controller per provider and field)')
on conflict (toolset_key, key) do nothing;

-- 2. tables
create table if not exists pipeline.layer4_bulk_operations (
  id uuid primary key default gen_random_uuid(),
  operation_key text not null unique,
  plan_fingerprint text not null,
  provider_id uuid not null,
  field text not null check (field in ('country', 'state', 'campus', 'location')),
  value jsonb not null,
  selected uuid[],
  counts jsonb not null,
  state text not null default 'applying' check (state in ('applying', 'partial', 'done', 'reversed', 'reversed_partial')),
  reason text not null,
  reversal_reason text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists layer4_bulk_operations_provider_idx on pipeline.layer4_bulk_operations (provider_id, field, state);
comment on table pipeline.layer4_bulk_operations is 'CF-247 UR-18 (Platform Admin D-B1 to D-B3, 2 Nov 2026): one row per applied provider bulk review plan (university, field, value, plan fingerprint, operation key, counts at the start, state). Written only by security.layer4_bulk_review_v1; never read by the consumer API.';
alter table pipeline.layer4_bulk_operations enable row level security;
revoke all on pipeline.layer4_bulk_operations from public, anon, authenticated;

create table if not exists pipeline.layer4_bulk_operation_items (
  operation_id uuid not null references pipeline.layer4_bulk_operations(id),
  entity_type text not null check (entity_type in ('course', 'campus')),
  entity_id uuid not null,
  class text not null check (class in ('eligible', 'unchanged', 'protected', 'excluded_exception', 'excluded_conflict', 'excluded_unsupported')),
  reason text not null,
  selected boolean not null default false,
  before_value jsonb,
  proposed_value jsonb,
  evidence jsonb not null default '{}'::jsonb,
  evidence_id uuid,
  outcome text check (outcome in ('applied', 'unchanged', 'conflicted', 'failed')),
  outcome_reason text,
  after_value jsonb,
  review_item_id uuid,
  decision_id uuid,
  attempts integer not null default 0,
  applied_at timestamptz,
  reversal text check (reversal in ('reversed', 'conflicted', 'failed')),
  reversal_reason text,
  reversal_review_item_id uuid,
  reversed_at timestamptz,
  primary key (operation_id, entity_type, entity_id)
);
comment on table pipeline.layer4_bulk_operation_items is 'CF-247 UR-18: one row per course or campus in an applied bulk review plan: its class and reason at preview, evidence, before, proposed and read-back value, outcome (applied, unchanged, conflicted, failed; empty while waiting), the review item and decision that admitted it, and its reversal. Written only by security.layer4_bulk_review_v1; never read by the consumer API.';
alter table pipeline.layer4_bulk_operation_items enable row level security;
revoke all on pipeline.layer4_bulk_operation_items from public, anon, authenticated;

-- 3. helpers
create or replace function security.layer4_bulk_field_codes_v1()
returns text[] language sql immutable set search_path = '' as $function$
  select array['bulk_campus_country', 'bulk_campus_state', 'bulk_course_campus', 'bulk_course_location']::text[]
$function$;
comment on function security.layer4_bulk_field_codes_v1() is 'CF-247 UR-18: the Layer 4 field codes written by provider bulk review (slice 1). AER kinds are never among them (D-B1).';

-- the place words of a text: lower case, letters and digits only, single spaces, padded so a whole phrase is found with like '% x %'
create or replace function security.layer4_bulk_words_v1(p text)
returns text language sql immutable set search_path = '' as $function$
  select ' ' || btrim(regexp_replace(regexp_replace(lower(coalesce(p, '')), '[^[:alnum:]]+', ' ', 'g'), ' +', ' ', 'g')) || ' '
$function$;

-- the delivery stated by a course page's "mode" text: on_campus, online, blended, on_campus_and_online, or null when it is not clear
create or replace function security.layer4_bulk_mode_v1(p text)
returns text language plpgsql immutable set search_path = '' as $function$
declare t text := lower(coalesce(p, '')); v_on boolean; v_bl boolean; v_ca boolean;
begin
  if t = '' or t like '%{{%' then return null; end if;
  v_on := t ~ '\m(online|distance|remote|virtual)\M';
  v_bl := t ~ '\m(blended|hybrid|mixed|multi-?modal|flexible)\M';
  v_ca := t ~ '(face[- ]?to[- ]?face|on[- ]?campus|in[- ]?person|classroom|\mcampus\M|\mattendance\M|on[- ]?site)';
  return case when v_on and v_ca then 'on_campus_and_online'
              when v_bl and v_on then null
              when v_bl then 'blended'
              when v_on then 'online'
              when v_ca then 'on_campus' end;
end $function$;

-- the current value of a field, in the shape the plan, the apply and the read-back all compare
create or replace function security.layer4_bulk_current_v1(p_field text, p_entity uuid, p_value jsonb)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select case p_field
    when 'country' then (select jsonb_build_object('country', k.iso_alpha2::text, 'country_id', c.country_id)
                           from catalogue.campuses c left join ref.countries k on k.id = c.country_id where c.id = p_entity)
    when 'state' then (select jsonb_build_object('state', s.code, 'subdivision_id', c.subdivision_id)
                         from catalogue.campuses c left join ref.subdivisions s on s.id = c.subdivision_id where c.id = p_entity)
    when 'campus' then jsonb_build_object('campus_id', p_value->>'campus_id',
                         'linked', exists (select 1 from catalogue.course_campuses l where l.course_id = p_entity and l.campus_id = (p_value->>'campus_id')::uuid))
    when 'location' then (select jsonb_build_object('mode', c.delivery_mode) from catalogue.courses c where c.id = p_entity) end
$function$;

-- 4. the plan (read only, deterministic). p_entity limits it to one row (the re-check before each write).
create or replace function security.layer4_bulk_plan_v1(p_provider uuid, p_field text, p_value jsonb, p_entity uuid default null)
returns table(entity_type text, entity_id uuid, code text, title text, level text, campus text, current_value jsonb, proposed jsonb,
              class text, reason text, evidence jsonb, evidence_id uuid, courses integer)
language plpgsql stable security definer set search_path = '' as $function$
declare v_cc text; v_country uuid; v_state text; v_campus catalogue.campuses%rowtype; v_terms text[]; v_mode text;
begin
  if p_field = 'country' then
    v_cc := upper(btrim(coalesce(p_value->>'country', '')));
    select k.id into v_country from ref.countries k where k.iso_alpha2 = v_cc;
    if v_country is null then raise exception 'choose a country (two-letter code), for example AU'; end if;
    return query
    with c as (
      select c.*, (select count(*) from catalogue.course_campuses l join catalogue.courses x on x.id = l.course_id
                    where l.campus_id = c.id and x.lifecycle_status = 'active')::int n,
             security.layer4_bulk_current_v1('country', c.id, null) cur,
             (select s.country_id from ref.subdivisions s where s.id = c.subdivision_id) sub_country,
             (select k2.iso_alpha2::text from ref.subdivisions s join ref.countries k2 on k2.id = s.country_id where s.id = c.subdivision_id) sub_cc,
             e.captured_at, e.source_url
        from catalogue.campuses c left join pipeline.evidence_artifacts e on e.id = c.evidence_id
       where c.provider_id = p_provider and c.status = 'active' and (p_entity is null or c.id = p_entity))
    select 'campus', c.id, c.campus_code, c.name, null::text, concat_ws(', ', c.city, c.postcode), c.cur,
           jsonb_build_object('country', v_cc, 'country_id', v_country), x.cl, x.why,
           jsonb_build_object('kind', 'campus record', 'campus_evidence_id', c.evidence_id, 'source_id', c.source_id, 'captured_at', c.captured_at,
                              'url', c.source_url, 'address', concat_ws(', ', c.name, c.address_line1, c.city, c.postcode)),
           c.evidence_id, c.n
      from c cross join lateral (select case
          when exists (select 1 from pipeline.manual_locks l where l.entity = 'campus' and l.entity_id = c.id and l.field in ('country_id', 'country')) then 'protected'
          when c.country_id = v_country then 'unchanged'
          when c.sub_country is not null and c.sub_country <> v_country then 'excluded_conflict'
          when c.evidence_id is null and c.source_id is null then 'excluded_unsupported'
          else 'eligible' end cl) k
      cross join lateral (select k.cl, case k.cl
          when 'protected' then 'the campus country was set by hand on the campus record'
          when 'unchanged' then 'already ' || v_cc
          when 'excluded_conflict' then 'its state or region belongs to ' || coalesce(c.sub_cc, 'another country') || ': correct the state first, one at a time'
          when 'excluded_unsupported' then 'no official campus record (no stored source) supports a change'
          else 'official campus record; country on record is ' || coalesce(c.cur->>'country', 'not held') end why) x;

  elsif p_field = 'state' then
    v_state := upper(btrim(coalesce(p_value->>'state', '')));
    if v_state !~ '^([A-Z]{2}-)?[A-Z0-9]{1,4}$' then raise exception 'choose a state or territory code, for example NSW or AU-NSW'; end if;
    return query
    with c as (
      select c.*, (select count(*) from catalogue.course_campuses l join catalogue.courses x on x.id = l.course_id
                    where l.campus_id = c.id and x.lifecycle_status = 'active')::int n,
             security.layer4_bulk_current_v1('state', c.id, null) cur, k.iso_alpha2::text cc,
             case when v_state like '%-%' then v_state else k.iso_alpha2::text || '-' || v_state end want,
             case when k.iso_alpha2 = 'AU' then 'AU-' || security.au_state_from_postcode_v1(btrim(c.postcode)) end derived,
             e.captured_at, e.source_url, rc.reason cleared
        from catalogue.campuses c join ref.countries k on k.id = c.country_id
        left join pipeline.evidence_artifacts e on e.id = c.evidence_id
        left join pipeline.campus_region_cleared rc on rc.campus_id = c.id
       where c.provider_id = p_provider and c.status = 'active' and (p_entity is null or c.id = p_entity)),
    w as (select c.*, (select s.id from ref.subdivisions s where s.country_id = c.country_id and s.code = c.want) want_id from c)
    select 'campus', c.id, c.campus_code, c.name, null::text, concat_ws(', ', c.city, c.postcode), c.cur,
           jsonb_build_object('state', c.want, 'subdivision_id', c.want_id), x.cl, x.why,
           jsonb_build_object('kind', 'campus record', 'campus_evidence_id', c.evidence_id, 'source_id', c.source_id, 'captured_at', c.captured_at,
                              'url', c.source_url, 'address', concat_ws(', ', c.name, c.address_line1, c.city, c.postcode), 'postcode_state', c.derived),
           c.evidence_id, c.n
      from w c cross join lateral (select case
          when exists (select 1 from pipeline.manual_locks l where l.entity = 'campus' and l.entity_id = c.id and l.field in ('subdivision_id', 'state', 'region')) then 'protected'
          when c.want_id is null then 'excluded_exception'
          when c.subdivision_id = c.want_id then 'unchanged'
          when c.cleared is not null then 'excluded_exception'
          when c.subdivision_id is not null then 'excluded_conflict'
          when c.evidence_id is null and c.source_id is null then 'excluded_unsupported'
          when c.derived is null then 'excluded_unsupported'
          when c.derived <> c.want then 'excluded_exception'
          else 'eligible' end cl) k
      cross join lateral (select k.cl, case
          when k.cl = 'protected' then 'the state was set by hand on the campus record'
          when k.cl = 'excluded_exception' and c.want_id is null then c.want || ' is not a state or region of ' || c.cc
          when k.cl = 'unchanged' then 'already ' || c.want
          when k.cl = 'excluded_exception' and c.cleared is not null then 'the region was cleared on purpose: ' || c.cleared
          when k.cl = 'excluded_conflict' then 'holds ' || coalesce(c.cur->>'state', 'another state') || ': change it one at a time'
          when k.cl = 'excluded_unsupported' and c.evidence_id is null and c.source_id is null then 'no official campus record (no stored source)'
          when k.cl = 'excluded_unsupported' then 'the address does not map to one state (no Australian postcode); a city name alone is not used'
          when k.cl = 'excluded_exception' then 'the campus postcode is in ' || c.derived
          else 'official campus record; postcode ' || c.postcode || ' is in ' || c.derived end why) x;

  elsif p_field in ('campus', 'location') then
    if p_field = 'campus' then
      select * into v_campus from catalogue.campuses c where c.id = nullif(p_value->>'campus_id', '')::uuid;
      if v_campus.id is null or v_campus.provider_id <> p_provider or v_campus.status <> 'active' then
        raise exception 'choose one of this university''s active campuses';
      end if;
      -- the campus's place words (its name without "campus", and its city); a word another campus also uses cannot tell them apart and is not used
      select coalesce(array_agg(t), '{}') into v_terms
        from (select distinct btrim(t) t
                from unnest(array[security.layer4_bulk_words_v1(regexp_replace(lower(v_campus.name), '\m(campus|the|of)\M', ' ', 'g')),
                                  security.layer4_bulk_words_v1(v_campus.city)]) t
               where length(btrim(t)) >= 3) z
       where not exists (select 1 from catalogue.campuses o
                          where o.provider_id = p_provider and o.status = 'active' and o.id <> v_campus.id
                            and (security.layer4_bulk_words_v1(o.name) like '% ' || z.t || ' %' or security.layer4_bulk_words_v1(o.city) like '% ' || z.t || ' %'));
      if cardinality(v_terms) = 0 then
        raise exception 'this campus cannot be told apart from the university''s other campuses by name: link its courses one at a time';
      end if;
      p_value := jsonb_build_object('campus_id', v_campus.id::text);
    else
      v_mode := p_value->>'mode';
      if v_mode is null or v_mode not in ('on_campus', 'online', 'blended', 'on_campus_and_online') then
        raise exception 'choose a delivery: on_campus, online, blended or on_campus_and_online';
      end if;
    end if;
    return query
    with c as (
      select c.id, c.course_code, coalesce(c.display_title, c.canonical_title) t, sl.name lv, c.delivery_mode,
             (select string_agg(m.name, ', ' order by m.name) from catalogue.course_campuses l join catalogue.campuses m on m.id = l.campus_id where l.course_id = c.id) campuses,
             security.layer4_bulk_current_v1(p_field, c.id, p_value) cur,
             g.status gs, g.url, g.evidence_id gev, e.captured_at, e.storage_path,
             r.id rid, r.at rat, r.fields->'extra'->>'campus' rcampus, r.fields->'extra'->>'location' rloc, r.fields->'extra'->>'mode' rmode
        from catalogue.courses c
        left join ref.study_levels sl on sl.id = c.study_level_id
        left join pipeline.coverage_course_pages g on g.course_id = c.id
        left join pipeline.evidence_artifacts e on e.id = g.evidence_id
        left join lateral (select r.* from pipeline.uni_adapter_results r where r.course_id = c.id order by r.at desc, r.id desc limit 1) r on true
       where c.provider_id = p_provider and c.lifecycle_status = 'active' and (p_entity is null or c.id = p_entity)),
    d as (select c.*, security.layer4_bulk_words_v1(concat_ws(' ', c.rcampus, c.rloc)) place,
                 security.layer4_bulk_mode_v1(c.rmode) said,
                 (c.gs = 'bound' and c.gev is not null and c.rid is not null) has_page,
                 exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id
                          and l.field in ('delivery_mode', 'delivery', 'location', 'campus', 'campuses', 'course_campuses')) locked,
                 (select x.reason from pipeline.uni_adapter_delivery_exclusions x where x.course_id = c.id and x.active) del_ex,
                 exists (select 1 from pipeline.uni_adapter_exclusions x where x.course_id = c.id and x.active and x.field in ('delivery', 'campus', 'location')) fld_ex,
                 exists (select 1 from pipeline.layer4_override_decisions o where o.entity_type = 'course' and o.entity_id = c.id
                          and o.field_code in ('delivery_mode', 'course.delivery_mode')) overridden,
                 exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c.id and i.status = 'pending'
                          and i.field_code = 'official_course_url') page_waits
            from c),
    k as (select d.*, case
          when d.locked or d.del_ex is not null or d.fld_ex or (p_field = 'location' and d.overridden) then 'protected'
          when p_field = 'campus' and (d.cur->>'linked')::boolean then 'unchanged'
          when p_field = 'location' and d.delivery_mode = v_mode then 'unchanged'
          when d.page_waits then 'excluded_conflict'
          when p_field = 'location' and d.delivery_mode is not null then 'excluded_conflict'
          when not d.has_page then 'excluded_unsupported'
          when p_field = 'campus' and btrim(d.place) = '' then 'excluded_unsupported'
          when p_field = 'campus' and d.said = 'online' then 'excluded_exception'
          when p_field = 'campus' and not exists (select 1 from unnest(v_terms) t where d.place like '% ' || t || ' %') then 'excluded_exception'
          when p_field = 'location' and nullif(btrim(coalesce(d.rmode, '')), '') is null then 'excluded_unsupported'
          when p_field = 'location' and d.said is null then 'excluded_exception'
          when p_field = 'location' and d.said <> v_mode then 'excluded_exception'
          when p_field = 'location' and d.said = 'online' and btrim(d.place) <> '' and d.place !~ '^ (online|distance|remote|virtual)( online| distance| remote| virtual)* $' then 'excluded_exception'
          else 'eligible' end cl
            from d)
    select 'course', k.id, k.course_code, k.t, k.lv, k.campuses, k.cur,
           case when p_field = 'campus' then jsonb_build_object('campus_id', v_campus.id::text, 'linked', true) else jsonb_build_object('mode', v_mode) end,
           k.cl, case
             when k.cl = 'protected' and k.locked then 'set by hand on the course record'
             when k.cl = 'protected' and k.del_ex is not null then 'delivery is excluded for this course: ' || k.del_ex
             when k.cl = 'protected' then 'course-specific exclusion or override'
             when k.cl = 'unchanged' and p_field = 'campus' then 'already linked to ' || v_campus.name
             when k.cl = 'unchanged' then 'already ' || v_mode
             when k.cl = 'excluded_conflict' and k.page_waits then 'its course page waits for review in Layer 4'
             when k.cl = 'excluded_conflict' then 'holds ' || k.delivery_mode || ': change it one at a time'
             when k.cl = 'excluded_unsupported' and not k.has_page then 'no bound official course page with a stored copy and a reading'
             when k.cl = 'excluded_unsupported' and p_field = 'campus' then 'the course page does not name a campus'
             when k.cl = 'excluded_unsupported' then 'the course page does not say how it is delivered'
             when p_field = 'campus' and k.said = 'online' then 'the course page says online only'
             when k.cl = 'excluded_exception' and p_field = 'campus' then 'the course page names another place: ' || left(btrim(concat_ws(' ', k.rcampus, k.rloc)), 120)
             when k.cl = 'excluded_exception' and k.said is null then 'the course page''s delivery is not clear: ' || left(btrim(k.rmode), 120)
             when k.cl = 'excluded_exception' and k.said <> v_mode then 'the course page says ' || k.said || ': ' || left(btrim(k.rmode), 120)
             when k.cl = 'excluded_exception' then 'the course page says online but names a campus: decide this one alone'
             when p_field = 'campus' then 'the course page names ' || v_campus.name
             else 'the course page says ' || v_mode end,
           jsonb_build_object('kind', 'course page', 'page_url', k.url, 'evidence_id', k.gev, 'captured_at', k.captured_at, 'stored', k.storage_path is not null,
                              'read_id', k.rid, 'read_at', k.rat, 'stated_campus', left(btrim(concat_ws(' ', k.rcampus, k.rloc)), 200), 'stated_mode', left(btrim(k.rmode), 200)),
           k.gev, null::int
      from k;
  else
    -- D-B1: AER, intake and English are not bulk fields in this slice; AER never is
    raise exception 'bulk review covers country, state, campus and location only (intake and English follow later; academic entry requirements are never bulk-approved)';
  end if;
end $function$;
comment on function security.layer4_bulk_plan_v1(uuid, text, jsonb, uuid) is 'CF-247 UR-18: the deterministic bulk review plan for one university and field (country, state, campus or location): each candidate with its class, reason, current and proposed value and course-level evidence. Read only.';

create or replace function security.layer4_bulk_fingerprint_v1(p_field text, p_value jsonb, p_rows jsonb)
returns text language sql immutable set search_path = '' as $function$
  -- p_rows: [{entity_type, entity_id, class, current_value, proposed, evidence}] in any order; the fingerprint sorts them
  select md5(p_field || '|' || coalesce(p_value::text, '') || '|' || coalesce((
    select string_agg(concat_ws('|', r->>'entity_type', r->>'entity_id', r->>'class', (r->'current_value')::text, (r->'proposed')::text, (r->'evidence')::text), E'\n'
                      order by r->>'entity_type', r->>'entity_id')
      from jsonb_array_elements(p_rows) r), ''))
$function$;

-- 5. the apply function for the four bulk field codes (routed by security.layer4_review_decide_impl)
create or replace function security.layer4_bulk_field_apply_v1(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_item pipeline.layer4_review_items%rowtype; v_key text := coalesce(current_setting('cf.bulk_operation', true), ''); v_n int := 0; v_src uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id = p_item_id;
  if security.current_role_rank() < 6 then raise exception 'Platform Admin role required: bulk review is applied by the Platform Admin (decision D-B2)' using errcode = '42501'; end if;
  if v_key = '' or v_item.change_control_ref is distinct from 'UR-18 bulk ' || v_key then
    raise exception 'bulk review fields are written only inside a bulk apply or reversal';
  end if;
  if v_item.field_code = 'bulk_campus_country' then
    update catalogue.campuses set country_id = (p_value->>'country_id')::uuid, updated_at = now() where id = v_item.entity_id and country_id is distinct from (p_value->>'country_id')::uuid;
  elsif v_item.field_code = 'bulk_campus_state' then
    update catalogue.campuses set subdivision_id = nullif(p_value->>'subdivision_id', '')::uuid, updated_at = now()
     where id = v_item.entity_id and subdivision_id is distinct from nullif(p_value->>'subdivision_id', '')::uuid;
  elsif v_item.field_code = 'bulk_course_location' then
    update catalogue.courses set delivery_mode = p_value->>'mode', updated_at = now() where id = v_item.entity_id and delivery_mode is distinct from p_value->>'mode';
  elsif v_item.field_code = 'bulk_course_campus' and (p_value->>'linked')::boolean then
    select id into v_src from pipeline.sources where source_type = 'layer4_human_review' order by created_at, id limit 1;
    insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary, source_id, evidence_id)
    values (v_item.entity_id, (p_value->>'campus_id')::uuid, 'on_campus', false, v_src, v_item.evidence_id)
    on conflict do nothing;
  elsif v_item.field_code = 'bulk_course_campus' then
    -- reversal: removes only the link row this operation added (same course, campus, delivery and evidence), recorded in the operation item
    delete from catalogue.course_campuses
     where course_id = v_item.entity_id and campus_id = (p_value->>'campus_id')::uuid and delivery_mode = 'on_campus'
       and evidence_id is not distinct from v_item.evidence_id;
  else
    raise exception 'not a bulk review field: %', v_item.field_code;
  end if;
  get diagnostics v_n = row_count;
  return jsonb_build_object('written', v_n, 'field_code', v_item.field_code);
end $function$;
comment on function security.layer4_bulk_field_apply_v1(uuid, uuid, jsonb, text) is 'CF-247 UR-18: writes one bulk review row (campus country or state, course campus link, course delivery) for security.layer4_review_decide_impl; refuses outside a Platform Admin bulk apply or reversal.';

-- 6. the bulk review actions (reached through public.admin_layer4_inbox)
create or replace function security.layer4_bulk_review_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_uid uuid := auth.uid(); v_rank int := security.current_role_rank();
  v_provider uuid; v_field text := p_args->>'field'; v_value jsonb := coalesce(p_args->'value', '{}'::jsonb); v_fp text; v_key text; v_reason text;
  v_sel uuid[]; v_op pipeline.layer4_bulk_operations%rowtype; v_rows jsonb; v_counts jsonb; v_lim int; v_off int;
  v_on boolean := security.pipeline_num_v1('layer4.bulk_review_enabled', 0) >= 1;
  v_batch int := greatest(1, security.pipeline_num_v1('layer4.bulk_batch_size', 50)::int);
  v_max int := greatest(1, security.pipeline_num_v1('layer4.bulk_max_courses', 500)::int);
  v_open int := greatest(1, security.pipeline_num_v1('layer4.bulk_open_minutes', 60)::int);
  r record; p record; v_item uuid; v_dec jsonb; v_after jsonb; v_out text; v_why text; v_done jsonb := '[]'::jsonb; v_courses uuid[] := '{}'; v_refresh text;
  v_code text; v_etype text;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_code := case v_field when 'country' then 'bulk_campus_country' when 'state' then 'bulk_campus_state' when 'campus' then 'bulk_course_campus' when 'location' then 'bulk_course_location' end;
  v_etype := case when v_field in ('country', 'state') then 'campus' else 'course' end;

  if p_action = 'bulk_operation' then
    select * into v_op from pipeline.layer4_bulk_operations where operation_key = p_args->>'operation_key';
    if v_op.id is null then raise exception 'no bulk operation with this key'; end if;
    return jsonb_build_object('operation', to_jsonb(v_op),
      'outcomes', (select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) from (select coalesce(i.outcome, case when i.selected and i.class = 'eligible' then 'waiting' else 'excluded' end) o, count(*) n
                                                               from pipeline.layer4_bulk_operation_items i where i.operation_id = v_op.id group by 1) z),
      'items', (select coalesce(jsonb_agg(to_jsonb(i) order by i.entity_type, i.entity_id), '[]'::jsonb) from pipeline.layer4_bulk_operation_items i where i.operation_id = v_op.id and i.selected));
  end if;

  if p_action = 'bulk_reverse' then
    if v_rank < 6 then raise exception 'Platform Admin role required: only the Platform Admin applies or reverses bulk review (decision D-B2)' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 5 then raise exception 'give a reason (kept with every course''s reversal)'; end if;
    select * into v_op from pipeline.layer4_bulk_operations where operation_key = p_args->>'operation_key' for update;
    if v_op.id is null then raise exception 'no bulk operation with this key'; end if;
    v_code := case v_op.field when 'country' then 'bulk_campus_country' when 'state' then 'bulk_campus_state' when 'campus' then 'bulk_course_campus' else 'bulk_course_location' end;
    perform set_config('cf.bulk_operation', v_op.operation_key, true);
    for r in select i.* from pipeline.layer4_bulk_operation_items i
              where i.operation_id = v_op.id and i.outcome = 'applied' and (i.reversal is null or i.reversal = 'failed')
              order by i.entity_type, i.entity_id limit v_batch loop
      v_item := null;
      begin
        if security.layer4_bulk_current_v1(v_op.field, r.entity_id, r.proposed_value) is distinct from r.after_value then
          v_out := 'conflicted'; v_why := 'changed since it was applied: left as it is';
        else
          insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
          values (r.entity_type, r.entity_id, v_code, r.evidence_id, r.after_value, r.before_value,
                  jsonb_build_object('source', 'UR-18 bulk review reversal', 'operation_key', v_op.operation_key), '{}'::jsonb, 'pending',
                  'Bulk review reversal: restores the value held before the operation', 'UR-18 bulk ' || v_op.operation_key)
          returning id into v_item;
          v_dec := security.layer4_review_decide_impl(v_item, 'approve', 'Bulk review reversal: ' || v_reason, null);
          v_after := security.layer4_bulk_current_v1(v_op.field, r.entity_id, r.proposed_value);
          if v_after is distinct from r.before_value then raise exception 'the destination does not show the restored value after the write'; end if;
          v_out := 'reversed'; v_why := 'restored';
        end if;
        update pipeline.layer4_bulk_operation_items i set reversal = v_out, reversal_reason = v_why, reversal_review_item_id = case when v_out = 'reversed' then v_item end,
               reversed_at = now()
         where i.operation_id = v_op.id and i.entity_type = r.entity_type and i.entity_id = r.entity_id;
      exception when others then
        v_out := 'failed'; v_why := left(sqlerrm, 300);
        update pipeline.layer4_bulk_operation_items i set reversal = 'failed', reversal_reason = v_why
         where i.operation_id = v_op.id and i.entity_type = r.entity_type and i.entity_id = r.entity_id;
      end;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('layer4', 'bulk_reverse_' || v_out, 'pipeline.layer4_bulk_operation_items',
              jsonb_build_object('operation_key', v_op.operation_key, 'field', v_op.field, 'entity_type', r.entity_type, 'entity_id', r.entity_id,
                                 'restored', r.before_value, 'reason', v_reason, 'detail', v_why), v_uid);
      v_done := v_done || jsonb_build_object('entity_id', r.entity_id, 'reversal', v_out, 'reason', v_why);
      if v_out = 'reversed' then
        v_courses := v_courses || case when r.entity_type = 'course' then array[r.entity_id]
                       else array(select l.course_id from catalogue.course_campuses l where l.campus_id = r.entity_id) end;
      end if;
    end loop;
    update pipeline.layer4_bulk_operations o set reversal_reason = v_reason, updated_at = now(),
           state = case when exists (select 1 from pipeline.layer4_bulk_operation_items i where i.operation_id = o.id and i.outcome = 'applied' and (i.reversal is null or i.reversal = 'failed'))
                        then 'reversed_partial' else 'reversed' end
     where o.id = v_op.id returning * into v_op;
    if cardinality(v_courses) > 0 then
      begin perform search.refresh_course_enrichment_scoped_v1(v_courses, true); v_refresh := 'refreshed';
      exception when others then v_refresh := 'not refreshed: ' || left(sqlerrm, 200); end;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'bulk_reverse', 'pipeline.layer4_bulk_operations', jsonb_build_object('operation_key', v_op.operation_key, 'state', v_op.state, 'rows', v_done, 'reason', v_reason), v_uid);
    return jsonb_build_object('ok', true, 'operation_key', v_op.operation_key, 'state', v_op.state, 'rows', v_done, 'search', v_refresh,
      'reversal', (select coalesce(jsonb_object_agg(coalesce(i.reversal, 'waiting'), n), '{}'::jsonb) from (select i.reversal, count(*) n from pipeline.layer4_bulk_operation_items i
                    where i.operation_id = v_op.id and i.outcome = 'applied' group by 1) i));
  end if;

  if p_action not in ('bulk_preview', 'bulk_apply') then raise exception 'unknown bulk action %', p_action; end if;
  v_provider := nullif(p_args->>'provider_id', '')::uuid;
  if v_provider is null or not exists (select 1 from catalogue.providers x where x.id = v_provider) then raise exception 'choose a university'; end if;
  if v_code is null then
    raise exception 'bulk review covers country, state, campus and location only (intake and English follow later; academic entry requirements are never bulk-approved)';
  end if;

  if p_action = 'bulk_preview' then
    -- no value chosen yet: the university's active campuses to choose from (read only)
    if not (v_value ?| array['country', 'state', 'campus_id', 'mode']) then
      return jsonb_build_object('provider_id', v_provider, 'field', v_field, 'needs_value', true, 'enabled', v_on, 'can_apply', v_rank >= 6,
        'country', (select k.iso_alpha2::text from catalogue.providers x join ref.countries k on k.id = x.country_id where x.id = v_provider),
        'campuses', coalesce((select jsonb_agg(jsonb_build_object('campus_id', m.id, 'name', m.name, 'city', m.city, 'postcode', m.postcode, 'state', s.code,
                                     'courses', (select count(*) from catalogue.course_campuses l where l.campus_id = m.id)) order by m.name, m.id)
                                from catalogue.campuses m left join ref.subdivisions s on s.id = m.subdivision_id
                               where m.provider_id = v_provider and m.status = 'active'), '[]'::jsonb));
    end if;
    v_lim := least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500); v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);  -- fixed: page size bounds
    return (with pl as (select * from security.layer4_bulk_plan_v1(v_provider, v_field, v_value)),
                 o as (select pl.*, array_position(array['eligible', 'unchanged', 'protected', 'excluded_exception', 'excluded_conflict', 'excluded_unsupported'], pl.class) co from pl)
      select jsonb_build_object(
        'provider_id', v_provider, 'field', v_field, 'value', v_value, 'unit', v_etype,
        'fingerprint', security.layer4_bulk_fingerprint_v1(v_field, v_value,
                         (select coalesce(jsonb_agg(jsonb_build_object('entity_type', o.entity_type, 'entity_id', o.entity_id, 'class', o.class, 'current_value', o.current_value,
                                                                      'proposed', o.proposed, 'evidence', o.evidence)), '[]'::jsonb) from o)),
        'counts', jsonb_build_object('candidate', (select count(*) from o),
                    'eligible', (select count(*) from o where o.class = 'eligible'), 'unchanged', (select count(*) from o where o.class = 'unchanged'),
                    'protected', (select count(*) from o where o.class = 'protected'), 'excluded_exception', (select count(*) from o where o.class = 'excluded_exception'),
                    'excluded_conflict', (select count(*) from o where o.class = 'excluded_conflict'), 'excluded_unsupported', (select count(*) from o where o.class = 'excluded_unsupported'),
                    'courses_affected', (select coalesce(sum(case when o.entity_type = 'campus' then o.courses else 1 end), 0) from o where o.class = 'eligible')),
        'enabled', v_on, 'can_apply', v_rank >= 6, 'batch_size', v_batch, 'max_rows', v_max,
        'filter', nullif(p_args->>'class', ''), 'limit', v_lim, 'offset', v_off,
        'total', (select count(*) from o where nullif(p_args->>'class', '') is null or o.class = p_args->>'class'),
        'rows', coalesce((select jsonb_agg(jsonb_build_object('entity_type', z.entity_type, 'entity_id', z.entity_id, 'code', z.code, 'title', z.title, 'level', z.level,
                     'campus', z.campus, 'current', z.current_value, 'proposed', z.proposed, 'class', z.class, 'reason', z.reason, 'evidence', z.evidence, 'courses', z.courses)
                     order by z.co, z.title, z.code, z.entity_id)
                   from (select * from o where nullif(p_args->>'class', '') is null or o.class = p_args->>'class'
                          order by o.co, o.title, o.code, o.entity_id limit v_lim offset v_off) z), '[]'::jsonb)));
  end if;

  -- bulk_apply: Platform Admin only (D-B2), only while switched on (D-B3, D-B4)
  if v_rank < 6 then raise exception 'Platform Admin role required: only the Platform Admin applies or reverses bulk review (decision D-B2)' using errcode = '42501'; end if;
  if not v_on then raise exception 'bulk apply is switched off (setting layer4.bulk_review_enabled is 0): nothing was changed'; end if;
  v_reason := btrim(coalesce(p_args->>'reason', ''));
  if length(v_reason) < 5 then raise exception 'give a reason (kept with every course''s decision)'; end if;
  v_fp := nullif(p_args->>'fingerprint', '');
  if v_fp is null then raise exception 'preview first: apply needs the preview''s fingerprint'; end if;
  if jsonb_typeof(p_args->'course_ids') = 'array' then
    v_sel := array(select distinct x::uuid from jsonb_array_elements_text(p_args->'course_ids') x order by 1);
    if cardinality(v_sel) = 0 then raise exception 'tick at least one eligible row'; end if;
  end if;
  v_key := md5(v_fp || ':' || coalesce(array_to_string(v_sel, ','), 'all'));
  -- one controller per university and field
  perform pg_advisory_xact_lock(hashtextextended('cf247.ur18.bulk:' || v_provider::text || ':' || v_field, 0));

  select * into v_op from pipeline.layer4_bulk_operations where operation_key = v_key for update;
  if v_op.id is not null and (v_op.provider_id <> v_provider or v_op.field <> v_field) then raise exception 'this key belongs to another university or field'; end if;
  if v_op.id is not null and v_op.state in ('reversed', 'reversed_partial') then raise exception 'this operation was reversed: preview again'; end if;
  if v_op.id is null then
    if exists (select 1 from pipeline.layer4_bulk_operations o where o.provider_id = v_provider and o.field = v_field and o.state in ('applying', 'partial')
                and o.updated_at > now() - make_interval(mins => v_open)) then
      raise exception 'another bulk operation for this university and field is not finished: finish it (apply again with its preview) or wait until it has been idle for % minutes', v_open;
    end if;
    create temp table if not exists _ur18_plan (entity_type text, entity_id uuid, code text, title text, level text, campus text, current_value jsonb, proposed jsonb,
                                                class text, reason text, evidence jsonb, evidence_id uuid, courses int) on commit drop;
    truncate _ur18_plan;
    insert into _ur18_plan select * from security.layer4_bulk_plan_v1(v_provider, v_field, v_value);
    if security.layer4_bulk_fingerprint_v1(v_field, v_value, (select coalesce(jsonb_agg(jsonb_build_object('entity_type', x.entity_type, 'entity_id', x.entity_id, 'class', x.class,
            'current_value', x.current_value, 'proposed', x.proposed, 'evidence', x.evidence)), '[]'::jsonb) from _ur18_plan x)) <> v_fp then
      raise exception 'the plan has changed since the preview (a value, lock or reading changed): preview again; nothing was changed';
    end if;
    if v_sel is not null and exists (select 1 from unnest(v_sel) s(id) where not exists (select 1 from _ur18_plan x where x.entity_id = s.id and x.class = 'eligible')) then
      raise exception 'only eligible rows can be applied: preview again';
    end if;
    if (select count(*) from _ur18_plan x where x.class = 'eligible' and (v_sel is null or x.entity_id = any (v_sel))) = 0 then raise exception 'nothing eligible to apply'; end if;
    if (select count(*) from _ur18_plan x where x.class = 'eligible' and (v_sel is null or x.entity_id = any (v_sel))) > v_max then
      raise exception 'more than % rows would be written: tick at most % eligible rows (setting layer4.bulk_max_courses)', v_max, v_max;
    end if;
    select jsonb_object_agg(x.class, x.n) into v_counts from (select class, count(*) n from _ur18_plan group by 1) x;
    insert into pipeline.layer4_bulk_operations(operation_key, plan_fingerprint, provider_id, field, value, selected, counts, state, reason, created_by)
    values (v_key, v_fp, v_provider, v_field, v_value, v_sel, v_counts, 'applying', v_reason, v_uid) returning * into v_op;
    insert into pipeline.layer4_bulk_operation_items(operation_id, entity_type, entity_id, class, reason, selected, before_value, proposed_value, evidence, evidence_id)
    select v_op.id, x.entity_type, x.entity_id, x.class, x.reason, x.class = 'eligible' and (v_sel is null or x.entity_id = any (v_sel)),
           x.current_value, x.proposed, x.evidence, x.evidence_id
      from _ur18_plan x;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'bulk_operation_start', 'pipeline.layer4_bulk_operations',
            jsonb_build_object('operation_key', v_key, 'fingerprint', v_fp, 'provider_id', v_provider, 'field', v_field, 'value', v_value, 'counts', v_counts, 'reason', v_reason), v_uid);
  end if;

  perform set_config('cf.bulk_operation', v_key, true);
  for r in select i.* from pipeline.layer4_bulk_operation_items i
            where i.operation_id = v_op.id and i.selected and (i.outcome is null or i.outcome = 'failed')
            order by i.entity_type, i.entity_id limit v_batch loop
    v_item := null; v_dec := null; v_after := null;
    begin
      -- re-check this row against the current state (value, lock, page and its reading) before writing
      select * into p from security.layer4_bulk_plan_v1(v_provider, v_field, v_value, r.entity_id);
      if p.class = 'unchanged' then
        v_out := 'unchanged'; v_why := 'already holds the value (set since the preview)';
      elsif p.class is distinct from 'eligible' or p.current_value is distinct from r.before_value or p.evidence is distinct from r.evidence then
        v_out := 'conflicted';
        v_why := 'changed since the preview: ' || case when p.class is null then 'no longer a candidate'
                                                       when p.class <> 'eligible' then p.class || ' (' || p.reason || ')'
                                                       when p.evidence is distinct from r.evidence then 'the course page or its reading changed'
                                                       else 'the value changed' end;
      else
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values (r.entity_type, r.entity_id, v_code, r.evidence_id, r.before_value, r.proposed_value,
                jsonb_build_object('source', 'UR-18 bulk review', 'operation_key', v_key, 'evidence', r.evidence), '{}'::jsonb, 'pending',
                'Bulk review: ' || r.reason, 'UR-18 bulk ' || v_key)
        returning id into v_item;
        v_dec := security.layer4_review_decide_impl(v_item, 'approve', 'Bulk review: ' || v_reason, null);
        -- the destination is read back; a write a guard skipped is a failure, never "applied"
        v_after := security.layer4_bulk_current_v1(v_field, r.entity_id, r.proposed_value);
        if v_after is distinct from r.proposed_value then raise exception 'the destination does not show the value after the write (it holds %)', v_after; end if;
        v_out := 'applied'; v_why := 'written and read back';
      end if;
      update pipeline.layer4_bulk_operation_items i
         set outcome = v_out, outcome_reason = v_why, after_value = coalesce(v_after, p.current_value), review_item_id = v_item,
             decision_id = nullif(v_dec->>'decision_id', '')::uuid, attempts = i.attempts + 1, applied_at = case when v_out = 'applied' then now() end
       where i.operation_id = v_op.id and i.entity_type = r.entity_type and i.entity_id = r.entity_id;
    exception when others then
      v_out := 'failed'; v_why := left(sqlerrm, 300);
      update pipeline.layer4_bulk_operation_items i set outcome = 'failed', outcome_reason = v_why, attempts = i.attempts + 1
       where i.operation_id = v_op.id and i.entity_type = r.entity_type and i.entity_id = r.entity_id;
    end;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'bulk_item_' || v_out, 'pipeline.layer4_bulk_operation_items',
            jsonb_build_object('operation_key', v_key, 'field', v_field, 'entity_type', r.entity_type, 'entity_id', r.entity_id, 'before', r.before_value,
                               'proposed', r.proposed_value, 'after', v_after, 'evidence', r.evidence, 'detail', v_why, 'review_item_id', v_item,
                               'decision_id', v_dec->>'decision_id', 'reason', v_reason), v_uid);
    v_done := v_done || jsonb_build_object('entity_id', r.entity_id, 'outcome', v_out, 'reason', v_why);
    if v_out = 'applied' then
      v_courses := v_courses || case when r.entity_type = 'course' then array[r.entity_id]
                     else array(select l.course_id from catalogue.course_campuses l where l.campus_id = r.entity_id) end;
    end if;
  end loop;

  update pipeline.layer4_bulk_operations o set updated_at = now(),
         state = case when exists (select 1 from pipeline.layer4_bulk_operation_items i where i.operation_id = o.id and i.selected and (i.outcome is null or i.outcome = 'failed'))
                      then 'partial' else 'done' end
   where o.id = v_op.id returning * into v_op;
  if cardinality(v_courses) > 0 then
    begin perform search.refresh_course_enrichment_scoped_v1(v_courses, true); v_refresh := 'refreshed';
    exception when others then v_refresh := 'not refreshed: ' || left(sqlerrm, 200); end;
  end if;
  v_counts := (select jsonb_build_object(
      'applied', count(*) filter (where i.outcome = 'applied'),
      'unchanged', count(*) filter (where i.outcome = 'unchanged' or (not i.selected and i.class = 'unchanged')),
      'excluded', count(*) filter (where not i.selected and i.class <> 'unchanged'),
      'conflicted', count(*) filter (where i.outcome = 'conflicted'),
      'failed', count(*) filter (where i.outcome = 'failed'),
      'remaining', count(*) filter (where i.selected and i.outcome is null))
    from pipeline.layer4_bulk_operation_items i where i.operation_id = v_op.id);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'bulk_apply', 'pipeline.layer4_bulk_operations',
          jsonb_build_object('operation_key', v_key, 'state', v_op.state, 'this_call', v_done, 'totals', v_counts, 'search', v_refresh, 'reason', v_reason), v_uid);
  return jsonb_build_object('ok', true, 'operation_key', v_key, 'state', v_op.state, 'this_call', v_done, 'totals', v_counts, 'search', v_refresh);
end $function$;
comment on function security.layer4_bulk_review_v1(text, jsonb) is 'CF-247 UR-18 (Platform Admin D-B1 to D-B3, 2 Nov 2026): provider bulk review. bulk_preview (rank 3, read only), bulk_apply and bulk_reverse (Platform Admin, through security.layer4_review_decide_impl; apply needs layer4.bulk_review_enabled = 1), bulk_operation (read).';

revoke all on function security.layer4_bulk_field_codes_v1() from public, anon, authenticated;
revoke all on function security.layer4_bulk_words_v1(text) from public, anon, authenticated;
revoke all on function security.layer4_bulk_mode_v1(text) from public, anon, authenticated;
revoke all on function security.layer4_bulk_current_v1(text, uuid, jsonb) from public, anon, authenticated;
revoke all on function security.layer4_bulk_plan_v1(uuid, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function security.layer4_bulk_fingerprint_v1(text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function security.layer4_bulk_field_apply_v1(uuid, uuid, jsonb, text) from public, anon, authenticated;
revoke all on function security.layer4_bulk_review_v1(text, jsonb) from public, anon, authenticated;

-- 7. md5-guarded edits of the two existing functions
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.layer4_review_decide_impl(uuid,text,text,jsonb)', '67966cebe3184b9acad1a3451fd0021b', '26efc646bd65c181da99b4c6b5945205', array[
 array[$o$    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$o$,
       $n$    elsif v_item.field_code = any (security.layer4_bulk_field_codes_v1()) then
      -- UR-18 (Platform Admin D-B1 to D-B3, 2 Nov 2026): provider bulk review fields, written only inside a Platform Admin bulk apply or reversal
      v_scalar:=security.layer4_bulk_field_apply_v1(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then$n$]
], array[1]);

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', '417f181d12155f79f68c1e70c27a1892', 'ce6e8c4c5bf89a319eb7bc5e9c05f07d', array[
 array[$o$  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$o$,
       $n$  -- UR-18 (Platform Admin D-B1 to D-B3, 2 Nov 2026): provider bulk review. Any reviewer previews; only the Platform Admin applies or reverses,
  -- and only while layer4.bulk_review_enabled is 1 (security.layer4_bulk_review_v1 checks both)
  if p_action in ('bulk_preview', 'bulk_apply', 'bulk_reverse', 'bulk_operation') then return security.layer4_bulk_review_v1(p_action, p_args); end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$n$]
], array[1]);

-- 8. component register (housekeeping, Decision 260)
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_bulk_operations', 'L4 admit', 'Layer 4', 'UR-18: applied provider bulk review plans (operation key, fingerprint, state)', 'active', '{}', '20261102020000'),
 ('table', 'pipeline.layer4_bulk_operation_items', 'L4 admit', 'Layer 4', 'UR-18: one row per course or campus in a bulk review plan (class, evidence, outcome, reversal)', 'active', '{}', '20261102020000'),
 ('function', 'security.layer4_bulk_plan_v1', 'L4 admit', 'Layer 4', 'UR-18: deterministic bulk review plan (read only)', 'active', '{}', '20261102020000'),
 ('function', 'security.layer4_bulk_review_v1', 'L4 admit', 'Layer 4', 'UR-18: bulk preview, apply, reverse and read (through public.admin_layer4_inbox)', 'active', '{}', '20261102020000'),
 ('function', 'security.layer4_bulk_field_apply_v1', 'L4 admit', 'Layer 4', 'UR-18: writes one bulk review row for security.layer4_review_decide_impl', 'active', '{}', '20261102020000')
on conflict do nothing;

-- 9. post-check: bulk apply stays off (D-B4 not approved)
do $$
begin
  if security.pipeline_num_v1('layer4.bulk_review_enabled', 0) <> 0 then
    raise exception 'UR-18 post-check: layer4.bulk_review_enabled must be 0 after this migration (production activation is a separate decision, D-B4)';
  end if;
end $$;
