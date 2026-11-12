-- CF-247 Website API v3 with R28 (Decision 277, Platform Admin 12 Nov 2026 20:59 and 21:00 AEDT: "is it possible to create API v3 and keep the API
-- v2 intact ?"; "1. Build R28 in v3 instead of v2? yes 2. ... keep v3 open to additions until the website goes live on it, then freeze it").
-- What:
--   1. security.intake_start_date_status_v1(intake): why an intake has, or has not, an exact start date (R28), one value of a closed list:
--      known, no_official_calendar, month_only, not_on_course_page, course_page_not_verified, next_year_calendar_pending, not_yet_read,
--      own_calendar, conflicting_evidence, held_for_review, rolling. Worked out from catalogue.course_intakes.start_date and the intake planner's
--      last decision (pipeline.course_intake_dates next_action and reason), as listed in admin docs/integrations/WEBSITE-DEVELOPER-REQUIREMENTS.md
--      "Intake start-date status". Read only.
--   2. public.website_v3_course_item_r28(item): adds start_date_status to each element of a v2 course item's intakes[] (matched to the course's
--      active intakes by label and year; the element is otherwise returned unchanged).
--   3. public.website_v3_course (both forms), website_v3_course_search, website_v3_sync: call the frozen v2 function and return its answer with
--      item 2 applied to each course item. Nothing else in the answer changes.
--   4. public.website_v3_reference, _providers, _provider (both forms), _rankings, _scholarships, _scholarship: the v2 answer unchanged (WP-0.2).
--   5. Edge function website-api-v3 (same key, rate limit and request log as website-api-v2; actions logged as "v3:<action>"); every action calls a
--      website_v3_* function.
-- Guards: G1 (no job), G2 (no operational value), G3 (website-api-v2, public.website_v2_*, api.* and their tables are only read: nothing is
--   altered, dropped, renamed or retyped; v3 is outside the frozen surface until the website goes live on it, Decision 277), G4 (cf-247-s538).
-- Replaces: nothing (v2 stays live and frozen).
-- Retires: nothing.
-- Reversal: drop the five functions by paste file and delete the edge function; v2 is unaffected.

create or replace function security.intake_start_date_status_v1(p_intake_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when i.start_date is not null then 'known'
    when d.intake_id is null then
      case when exists (select 1 from pipeline.provider_policy_proposals pp
                         where pp.provider_id = c.provider_id and pp.kind = 'intake_calendar' and pp.status = 'approved')
           then 'not_yet_read' else 'no_official_calendar' end
    when d.reason ~* 'rolling|flexible start|start any ?time' then 'rolling'
    when d.next_action in ('human_decision_required', 'complete') then 'held_for_review'
    when d.next_action in ('calendar_needs_correction', 'awaiting_official_calendar') then 'no_official_calendar'
    when d.next_action = 'course_identity_unresolved' or d.reason ~* 'not proved to be the course''s own' then 'course_page_not_verified'
    when d.next_action = 'waiting_for_next_academic_year' then
      case when d.reason ~* 'does not state .* as (an|its own) intake' then 'not_on_course_page' else 'next_year_calendar_pending' end
    when d.next_action = 'reader_correction_needed' then 'not_yet_read'
    when d.reason ~* 'vocational or pathway|research degree' then 'own_calendar'
    when d.reason ~* 'names no study period' then 'month_only'
    else 'conflicting_evidence' end
  from catalogue.course_intakes i
  join catalogue.courses c on c.id = i.course_id
  left join pipeline.course_intake_dates d on d.intake_id = i.id
  where i.id = p_intake_id
$$;
comment on function security.intake_start_date_status_v1(uuid) is
  'R28 (Decision 277): why an intake has or has not an exact start date; closed list; read by Website API v3 only.';
revoke all on function security.intake_start_date_status_v1(uuid) from public, anon, authenticated;

create or replace function public.website_v3_course_item_r28(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_course uuid; v_out jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or jsonb_typeof(p_item->'intakes') is distinct from 'array' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
  select coalesce(jsonb_agg(e || jsonb_build_object('start_date_status',
           case when nullif(e->>'start_date', '') is not null then 'known'
                else coalesce((select security.intake_start_date_status_v1(i.id)
                                 from catalogue.course_intakes i
                                where i.course_id = v_course and i.status = 'active'
                                  and lower(btrim(i.intake_label)) = lower(btrim(e->>'label'))
                                  and i.intake_year is not distinct from (case when jsonb_typeof(e->'year') = 'number' then (e->>'year')::int end)
                                order by i.start_date is not null desc, i.id limit 1), 'not_yet_read') end)
           order by ord), '[]'::jsonb)
    into v_out
    from jsonb_array_elements(p_item->'intakes') with ordinality x(e, ord);
  return jsonb_set(p_item, '{intakes}', v_out);
end $$;
comment on function public.website_v3_course_item_r28(jsonb) is
  'Website API v3 (Decision 277): a v2 course item with intakes[].start_date_status (R28) added; nothing else changed.';

create or replace function public.website_v3_course(p_identifier text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier);
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  return v;
end $$;

create or replace function public.website_v3_course(p_identifier text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier, p_edu_country);
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  return v;
end $$;

create or replace function public.website_v3_course_search(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course_search(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_course_item_r28(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;

create or replace function public.website_v3_sync(p_cursor text, p_full boolean, p_entities text[], p_page_size integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v jsonb := public.website_v2_sync(p_cursor, p_full, p_entities, p_page_size);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(case when x->>'entity' = 'course' and x ? 'item'
                                                                  then jsonb_set(x, '{item}', public.website_v3_course_item_r28(x->'item')) else x end order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;

comment on function public.website_v3_course(text) is 'Website API v3 (Decision 277): website_v2_course with intakes[].start_date_status (R28).';
comment on function public.website_v3_course(text, text) is 'Website API v3 (Decision 277): website_v2_course with intakes[].start_date_status (R28).';
comment on function public.website_v3_course_search(jsonb, integer, integer, text) is 'Website API v3 (Decision 277): website_v2_course_search with intakes[].start_date_status (R28).';
comment on function public.website_v3_sync(text, boolean, text[], integer) is 'Website API v3 (Decision 277): website_v2_sync with intakes[].start_date_status (R28) on course items.';

revoke all on function public.website_v3_course_item_r28(jsonb) from public, anon, authenticated;
revoke all on function public.website_v3_course(text) from public, anon, authenticated;
revoke all on function public.website_v3_course(text, text) from public, anon, authenticated;
revoke all on function public.website_v3_course_search(jsonb, integer, integer, text) from public, anon, authenticated;
revoke all on function public.website_v3_sync(text, boolean, text[], integer) from public, anon, authenticated;
grant execute on function public.website_v3_course_item_r28(jsonb) to service_role;
grant execute on function public.website_v3_course(text) to service_role;
grant execute on function public.website_v3_course(text, text) to service_role;
grant execute on function public.website_v3_course_search(jsonb, integer, integer, text) to service_role;
grant execute on function public.website_v3_sync(text, boolean, text[], integer) to service_role;


-- WP-0.2 (build brief docs/integrations/api-v3/WEBSITE-API-V3-BUILD-BRIEF.md): every other action has its own v3 function, today the v2 answer
-- unchanged, so later v3 additions change website_v3_* only and never the edge function's routing or v2.
create or replace function public.website_v3_reference()
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_reference() $$;
comment on function public.website_v3_reference() is 'Website API v3 (Decision 277): public.website_v2_reference unchanged (WP-0.2).';
create or replace function public.website_v3_providers(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_providers(p_filters, p_page, p_page_size, p_sort) $$;
comment on function public.website_v3_providers(jsonb, integer, integer, text) is 'Website API v3 (Decision 277): public.website_v2_providers unchanged (WP-0.2).';
create or replace function public.website_v3_provider(p_provider_id text)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_provider(p_provider_id) $$;
comment on function public.website_v3_provider(text) is 'Website API v3 (Decision 277): public.website_v2_provider unchanged (WP-0.2).';
create or replace function public.website_v3_provider(p_provider_id text, p_edu_country text)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_provider(p_provider_id, p_edu_country) $$;
comment on function public.website_v3_provider(text, text) is 'Website API v3 (Decision 277): public.website_v2_provider unchanged (WP-0.2).';
create or replace function public.website_v3_rankings(p_filters jsonb, p_page integer, p_page_size integer)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_rankings(p_filters, p_page, p_page_size) $$;
comment on function public.website_v3_rankings(jsonb, integer, integer) is 'Website API v3 (Decision 277): public.website_v2_rankings unchanged (WP-0.2).';
create or replace function public.website_v3_scholarships(p_filters jsonb, p_page integer, p_page_size integer)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_scholarships(p_filters, p_page, p_page_size) $$;
comment on function public.website_v3_scholarships(jsonb, integer, integer) is 'Website API v3 (Decision 277): public.website_v2_scholarships unchanged (WP-0.2).';
create or replace function public.website_v3_scholarship(p_scholarship_id text)
returns jsonb language sql stable security definer set search_path = '' as $$ select public.website_v2_scholarship(p_scholarship_id) $$;
comment on function public.website_v3_scholarship(text) is 'Website API v3 (Decision 277): public.website_v2_scholarship unchanged (WP-0.2).';
revoke all on function public.website_v3_reference() from public, anon, authenticated;
grant execute on function public.website_v3_reference() to service_role;
revoke all on function public.website_v3_providers(jsonb, integer, integer, text) from public, anon, authenticated;
grant execute on function public.website_v3_providers(jsonb, integer, integer, text) to service_role;
revoke all on function public.website_v3_provider(text) from public, anon, authenticated;
grant execute on function public.website_v3_provider(text) to service_role;
revoke all on function public.website_v3_provider(text, text) from public, anon, authenticated;
grant execute on function public.website_v3_provider(text, text) to service_role;
revoke all on function public.website_v3_rankings(jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.website_v3_rankings(jsonb, integer, integer) to service_role;
revoke all on function public.website_v3_scholarships(jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.website_v3_scholarships(jsonb, integer, integer) to service_role;
revoke all on function public.website_v3_scholarship(text) from public, anon, authenticated;
grant execute on function public.website_v3_scholarship(text) to service_role;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('edge_function', 'website-api-v3', 'Website API', 'Website API v3 (Decision 277): copy of website-api-v2 plus R28; open to additions until the website goes live on it', 'active', '{}', '20261113180000')
on conflict do nothing;

do $post$ begin
  if to_regprocedure('public.website_v3_course_search(jsonb,integer,integer,text)') is null then raise exception 'post-check: v3 search missing'; end if;
  if security.intake_start_date_status_v1('00000000-0000-0000-0000-000000000000') is not null then raise exception 'post-check: status of a missing intake must be null'; end if;
end $post$;
