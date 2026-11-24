-- CF-247 s1090 (S1-API-Frontend-Delivery, Platform Admin 24 Nov 2026 22:35: Layer 4 Review "Why items are held").
-- (1) The hold reasons and the items behind a reason take the screen's University (provider_id) and Destination country (country, ISO alpha-2) filters,
--     so the table follows the filters instead of always counting every pending item.
-- (2) The catch-all "Other" is replaced by the stored reason of the item's latest machine check (security.layer4_aer_hold_base_v1 now returns that reason code),
--     with a plain label for the one code that held 386 items (active_rows_exist) and a words-from-the-code label for any code not named yet.
-- Read only. Same function signatures; no consumer API, cron, setting, lock or data change. 7,585 manual locks and G3 75/48 untouched.
-- Replaces: security.layer4_aer_hold_base_v1 and security.layer4_aer_hold_reasons_v1 bodies (S831). Retires: nothing.
create or replace function security.layer4_aer_hold_base_v1()
 returns table(id uuid, entity_id uuid, field_code text, code text, reason text, checked_at timestamp with time zone)
 language sql
 stable security definer
 set search_path to ''
as $function$
-- S831 (20 Nov 2026), s1090: every pending AER item with the class of its latest stored machine check; read only. A reason code this list does not name keeps its own code (never "other").
  with p as (select i.id, i.field_code, i.entity_id from pipeline.layer4_review_items i
              where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')),
  l as (select distinct on (a.review_item_id) a.review_item_id, a.reason_code, a.outcome, a.reason, a.created_at
          from pipeline.aer_machine_admissions a join p on p.id = a.review_item_id order by a.review_item_id, a.created_at desc)
  select p.id, p.entity_id, p.field_code,
         case when p.field_code = 'entry_matrix_first_run' then 'matrix_first_run'
              when p.field_code = 'entry_matrix_change' then 'matrix_change'
              when l.review_item_id is null then 'not_checked'
              when l.outcome = 'audit_sample' then 'audit_sample'
              else coalesce(nullif(btrim(l.reason_code), ''), 'other') end,
         l.reason, l.created_at
    from p left join l on l.review_item_id = p.id
$function$;

create or replace function security.layer4_aer_hold_reasons_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- S831 (20 Nov 2026), s1090: why each pending AER item waits, from the stored result of its latest machine check; read only.
-- {provider_id} and {country} (the provider's ISO alpha-2) narrow both the counts and the list.
declare
  v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
  v_provider uuid := nullif(btrim(coalesce(p_args->>'provider_id', '')), '')::uuid;
  v_country text := nullif(upper(btrim(coalesce(p_args->>'country', ''))), '');
  v_off int := greatest(0, coalesce(nullif(p_args->>'offset', '')::int, 0));
  v_lim int := least(100, greatest(1, coalesce(nullif(p_args->>'limit', '')::int, 25))); -- fixed: bound on one page
  v_out jsonb;
begin
  if v_reason is null then
    with b as materialized (
           select h.*, coalesce(c.provider_id, case when h.field_code <> 'course_entry_first_read' then h.entity_id end) pid
             from security.layer4_aer_hold_base_v1() h
             left join catalogue.courses c on c.id = h.entity_id and h.field_code = 'course_entry_first_read'),
         f as materialized (
           select b.* from b
             left join catalogue.providers pr on pr.id = b.pid
             left join ref.countries co on co.id = pr.country_id
            where (v_provider is null or b.pid = v_provider) and (v_country is null or co.iso_alpha2 = v_country)),
         z as (select code, count(*) n from f group by 1)
    select jsonb_build_object('as_at', now(), 'total', coalesce((select sum(n) from z), 0),
      'reasons', coalesce((select jsonb_agg(jsonb_build_object('code', z.code, 'n', z.n, 'label', case z.code
          when 'gate_incomplete' then 'Completeness gate (partial table read)'
          when 'audit_sample' then 'Audit sample (a person checks it)'
          when 'all_rows_held' then 'All rows held (every row fails a row rule)'
          when 'identity_not_admitted' then 'Page identity (the stored page is not proven to be this course''s)'
          when 'no_bound_page' then 'No stored page bound'
          when 'matrix_first_run' then 'Provider matrix, first run'
          when 'matrix_change' then 'Provider matrix, change of an admitted table'
          when 'not_checked' then 'Not checked yet'
          when 'active_rows_exist' then 'Course already has active entry requirements (replacing them is a person''s decision)'
          when 'other' then 'Held by a check (no reason stored)'
          else upper(left(replace(z.code, '_', ' '), 1)) || substr(replace(z.code, '_', ' '), 2) end) order by z.n desc, z.code) from z), '[]'::jsonb)) into v_out;
    return v_out;
  end if;
  with b as materialized (select h.*, coalesce(c.provider_id, case when h.field_code <> 'course_entry_first_read' then h.entity_id end) pid
                            from security.layer4_aer_hold_base_v1() h
                            left join catalogue.courses c on c.id = h.entity_id and h.field_code = 'course_entry_first_read'
                           where h.code = v_reason),
       f as materialized (select b.* from b
                            left join catalogue.providers pr on pr.id = b.pid
                            left join ref.countries co on co.id = pr.country_id
                           where (v_provider is null or b.pid = v_provider) and (v_country is null or co.iso_alpha2 = v_country)),
       pg as (select f.id, f.reason, f.checked_at, coalesce(c.display_title, c.canonical_title) ct, coalesce(pr.display_name, pr.canonical_name) pn, co.iso_alpha2 cc
                from f
                left join catalogue.courses c on c.id = f.entity_id and f.field_code = 'course_entry_first_read'
                left join catalogue.providers pr on pr.id = f.pid
                left join ref.countries co on co.id = pr.country_id
               order by pr.display_name nulls last, coalesce(c.display_title, c.canonical_title) nulls last, f.id offset v_off limit v_lim)
  select jsonb_build_object('reason', v_reason, 'offset', v_off, 'total', (select count(*) from f),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', pg.id, 'course', coalesce(pg.ct, '—'), 'provider', coalesce(pg.pn, '—'), 'country', pg.cc,
                         'checked_at', pg.checked_at, 'why', left(coalesce(pg.reason, ''), 300)) order by pg.pn nulls last, pg.ct nulls last, pg.id) from pg), '[]'::jsonb)) into v_out;
  return v_out;
end $function$;
