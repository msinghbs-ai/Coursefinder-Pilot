CREATE OR REPLACE FUNCTION security.scholarship_award_tiers_from_page_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_sch int := 0; v_tiers int := 0;
begin
  -- the value text first (the candidate set is unchanged by it), then every tier in one statement
  update scholarship.scholarships s set award_value_type = 'text_only', award_value_is_maximum = c.up_to, updated_at = now(), award_value_text = security.scholarship_tier_text(c.pcts, c.amts, c.up_to, scholarship.provider_currency(s.provider_id)) from security.scholarship_page_tier_candidates() c where c.id = s.id;
  get diagnostics v_sch = row_count;
  insert into scholarship.award_tiers(scholarship_id, tier_code, label, percentage, amount, currency_code, basis, notes, display_order, source_id, evidence_id)
  select c.id, 'page_tier_p' || o, 'Stated on the page', p, null, null, 'tuition_fee_reduction', 'One of several values stated on the provider page (Decision 245)', 100 + o, c.source_id, c.evidence_id
    from security.scholarship_page_tier_candidates() c, unnest(c.pcts) with ordinality u(p, o)
  union all
  select c.id, 'page_tier_a' || o, 'Stated on the page', null, a, scholarship.provider_currency((select x.provider_id from scholarship.scholarships x where x.id = c.id)), 'as_stated', 'One of several values stated on the provider page (Decision 245)', 200 + o, c.source_id, c.evidence_id
    from security.scholarship_page_tier_candidates() c, unnest(c.amts) with ordinality u(a, o);
  get diagnostics v_tiers = row_count;
  if v_sch > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'award_tiers_from_page', 'Award tiers recorded from pages stating several values', jsonb_build_object('scholarships', v_sch, 'tiers', v_tiers, 'decision', 'Decision 245'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('scholarships', v_sch, 'tiers', v_tiers);
end $function$
