-- CF-247 IQ-00111 read-back (read only; safe to run any time). Shows, for the 13 contained courses and the 3 kept ones, what the consumer
-- API returns now: Zoho (security.course_fee_used_v1, live), the website item (api.website_v2_course_item, search projection; it follows
-- within one search-refresh-requested run, every 10 minutes), the fee rows' status and the scholarship savings.
-- Expected after containment: fee_status inactive for the 13; used_source cricos with used_per_year = the CRICOS figure (Murdoch 28,920;
-- UNSW 31,000 / 31,000 / 31,500 / 31,000 / 30,500 / 31,000; HELI 24,600; Reach 106655B 17,000; VIT 085576A 17,000, 114822C 24,000; WSU 26,526);
-- VIT 114579J page 24,000 (adapter row); savings_on_withdrawn = 0.
begin read only;
with t(id, verdict) as (values
  ('52bc162c-a1e0-4965-af76-d82b4b1e9839'::uuid, 'contain'), ('97c4caca-289f-4801-a473-d52ed821ee22', 'contain'),
  ('9318d94a-9a1e-46d8-8ca8-5e79193aad52', 'contain'), ('00b40eeb-a95c-4af0-88a3-10ef3afec9c8', 'contain'),
  ('b6e2f56c-2a90-4b8c-b972-626b19bf25df', 'contain'), ('c5d7d256-f184-4f6a-b272-5f2ea196c6ce', 'contain'),
  ('6417579c-267d-4dc7-89be-d4b2991b10b2', 'contain'), ('9fb8be47-9216-46c6-8eb1-e62d47aed529', 'contain'),
  ('2bc5fcb3-cb11-4b2e-a0dd-8365a56571cf', 'contain'), ('ad9be016-adeb-4ea1-b100-4dda9455cef0', 'contain'),
  ('99acde0e-293b-41d8-8e93-f9c07bc8b1b6', 'contain'), ('f5c95962-f1c1-4ce4-bb49-c368210077d1', 'contain'),
  ('0e01cb0c-2f78-45e8-b188-cf29751f8df9', 'contain'), ('67e4ceca-cbd8-4d88-943d-1aa583d3f503', 'keep'),
  ('51ebae9d-67d3-4221-9cb3-1308260f4801', 'keep'), ('a805b998-dbb5-47e4-8b3e-05fcb1c3d71f', 'keep'))
select t.verdict, left(f.id::text, 8) fee, c.course_code, f.amount, f.status fee_status,
       u->>'source' used_source, (u->>'per_year')::numeric used_per_year, (u->>'cricos_per_year')::numeric cricos_per_year,
       (select (x->>'annual_amount')::numeric from api.website_v2_course_item(f.course_id, null, null) w,
               jsonb_path_query(to_jsonb(w), 'strict $.**.tuition') x limit 1) website_annual,
       (select count(*) from scholarship.course_financial_calculations fc where fc.course_fee_id = f.id) savings_on_withdrawn,
       (select jsonb_agg(jsonb_build_object('saving', fc.scholarship_saving_amount, 'basis', fc.fee_basis, 'status', fc.calculation_status))
          from scholarship.course_financial_calculations fc where fc.course_id = f.course_id and fc.calculation_status = 'calculated') savings_now
  from t join catalogue.course_fees f on f.id = t.id join catalogue.courses c on c.id = f.course_id
  cross join lateral security.course_fee_used_v1(f.course_id) u
 order by t.verdict, c.course_code;
rollback;
