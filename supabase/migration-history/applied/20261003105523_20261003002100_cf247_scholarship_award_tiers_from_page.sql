-- CF-247 (3 Oct 2026, 21:10 AEST). Decision 245. Scholarship plan step 2 (value): 194 scholarships open to
-- international students have no usable award value. The stored page reading already holds the reason for 118 of
-- them: the page states several values (tiers by result, region or level — "20% or 70% of tuition", "A$2,500, A$5,000
-- or A$15,000"), which the single-value rule rightly refused. Those values are now recorded as award tiers (tier codes
-- page_tier_*), each with the page as evidence, and the scholarship's value text becomes the range in words (value
-- type stays text_only: the column's check allows percentage, fixed_amount and text_only, and no constraint is
-- rewritten here). A value with page tiers counts as a stated value for publishing; it is never used for a fee saving
-- (only a single percentage is, Decision 212). A value set by hand is never changed; a page in another currency is
-- left alone; a page with no value stays without one.
-- the scholarships whose stored page reading holds several values and no single one
create or replace function security.scholarship_page_tier_candidates()
returns table(id uuid, source_id uuid, evidence_id uuid, up_to boolean, pcts numeric[], amts numeric[])
language sql stable security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline' as $f$
  with src as (
    select s.id, s.source_id, sp.evidence_id,
           coalesce((sp.facts->'value'->>'up_to')::boolean, false) up_to,
           coalesce((select array_agg(x::numeric order by x::numeric) from jsonb_array_elements_text(coalesce(sp.facts->'value'->'percentages', '[]'::jsonb)) x), '{}'::numeric[]) pcts,
           coalesce((select array_agg(x::numeric order by x::numeric) from jsonb_array_elements_text(coalesce(sp.facts->'value'->'amounts', '[]'::jsonb)) x), '{}'::numeric[]) amts
      from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
     where s.lifecycle_status = 'active' and (s.award_value_type is null or s.award_value_type = 'text_only')
       and sp.read_status = 'read' and sp.facts->'value'->>'type' = 'ambiguous' and coalesce((sp.facts->'value'->>'foreign_currency')::boolean, false) = false
       and not exists (select 1 from scholarship.award_tiers t where t.scholarship_id = s.id)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field in ('award', 'award_value')))
  select src.id, src.source_id, src.evidence_id, src.up_to, src.pcts, src.amts from src
   where cardinality(src.pcts) + cardinality(src.amts) >= 1 and cardinality(src.pcts) <= 6 and cardinality(src.amts) <= 6
$f$;
revoke all on function security.scholarship_page_tier_candidates() from public, anon, authenticated;

create or replace function security.scholarship_award_tiers_from_page_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline', 'security' as $f$
declare v_sch int := 0; v_tiers int := 0;
begin
  -- the value text first (the candidate set is unchanged by it), then every tier in one statement
  update scholarship.scholarships s set award_value_type = 'text_only', award_value_is_maximum = c.up_to, updated_at = now(), award_value_text = security.scholarship_tier_text(c.pcts, c.amts, c.up_to) from security.scholarship_page_tier_candidates() c where c.id = s.id;
  get diagnostics v_sch = row_count;
  insert into scholarship.award_tiers(scholarship_id, tier_code, label, percentage, amount, currency_code, basis, notes, display_order, source_id, evidence_id)
  select c.id, 'page_tier_p' || o, 'Stated on the page', p, null, null, 'tuition_fee_reduction', 'One of several values stated on the provider page (Decision 245)', 100 + o, c.source_id, c.evidence_id
    from security.scholarship_page_tier_candidates() c, unnest(c.pcts) with ordinality u(p, o)
  union all
  select c.id, 'page_tier_a' || o, 'Stated on the page', null, a, 'AUD', 'as_stated', 'One of several values stated on the provider page (Decision 245)', 200 + o, c.source_id, c.evidence_id
    from security.scholarship_page_tier_candidates() c, unnest(c.amts) with ordinality u(a, o);
  get diagnostics v_tiers = row_count;
  if v_sch > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'award_tiers_from_page', 'Award tiers recorded from pages stating several values', jsonb_build_object('scholarships', v_sch, 'tiers', v_tiers, 'decision', 'Decision 245'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('scholarships', v_sch, 'tiers', v_tiers);
end $f$;
revoke all on function security.scholarship_award_tiers_from_page_v1() from public, anon, authenticated;

-- the range in words: "20% to 70% of tuition fees", "A$2,500 to A$15,000", "Up to A$15,000 (A$2,500, A$5,000 or A$15,000 stated)"
create or replace function security.scholarship_tier_text(p_pcts numeric[], p_amts numeric[], p_up_to boolean)
returns text language sql immutable as $f$
  select array_to_string(array_remove(array[
    case when cardinality(coalesce(p_pcts, '{}'::numeric[])) = 1 then p_pcts[1]::int || '% of tuition fees'
         when cardinality(coalesce(p_pcts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees (' || (select string_agg(x::int || '%', ', ') from unnest(p_pcts) x) || ' stated)'
                                                                       else p_pcts[1]::int || '% to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees' end end,
    case when cardinality(coalesce(p_amts, '{}'::numeric[])) = 1 then 'A$' || to_char(p_amts[1], 'FM999,999,999')
         when cardinality(coalesce(p_amts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to A$' || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') || ' (' || (select string_agg('A$' || to_char(x, 'FM999,999,999'), ', ') from unnest(p_amts) x) || ' stated)'
                                                                       else 'A$' || to_char(p_amts[1], 'FM999,999,999') || ' to A$' || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') end end
  ], null), ' or ')
$f$;

-- publishing: a value with tiers read from the page is a stated value (never a saving)
do $g$ declare v_oid oid; v_def text; begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'scholarship_publishability_v1';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '62fca5d320e13c732785bc2c3248c390' then raise exception 'scholarship_publishability_v1 changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (select count(*) from regexp_matches(v_def, 'when not \(s\.award_value_type in \(''percentage'',''fixed_amount''\) and coalesce\(s\.award_percentage,s\.award_amount\) is not null\) then ''no stated award value''', 'g')) <> 1
  then raise exception 'publishability value rule not found exactly once'; end if;
  execute replace(v_def,
    $x$when not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then 'no stated award value'$x$,
    $x$when not ((s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%')) then 'no stated award value'$x$);
end $g$;

select security.scholarship_award_tiers_from_page_v1();
