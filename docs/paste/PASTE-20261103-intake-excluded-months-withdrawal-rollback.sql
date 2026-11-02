-- CF-247 Workstream D, intake wording: ROLLBACK of PASTE-20261103-intake-excluded-months-withdrawal.sql.
-- PASTE FILE. Not applied by any migration. Run only if the Platform Admin asks to undo the withdrawal.
-- Changes catalogue.course_intakes.status withdrawn -> active for exactly the same 94 rows. Nothing is deleted.
-- the 94 active month intakes whose own stored page wording names the month only to exclude it (the rule of security.intake_month_negated_v1):
--   UWA 64 (Master of Philosophy "Starting dates Throughout the year excluding January & December"; Doctor of Philosophy and several masters
--   "students may commence at any time throughout the year, except December (and January)"), GHMC 14 and AIBT 2 ("Monthly intakes except June and
--   December"), OPIE 7 ("Intake Every Month (15th), except December"), UED 7 ("Intake Dates Every month on the 15th (Except December)").
-- Not included: the SSC adapter pattern "Except January February March April May July August September October November" (ambiguous run-together list;
--   left for a person). Read-only list taken 3 Nov 2026 00:06 AEDT; md5 of the sorted ids df15c7c6555c4096f30f4c2a5886a156.
begin;
do $$
declare
  v_ids uuid[] := array[
    '008294e6-7fb1-4954-9ee0-8067de3533cd', '02168d40-d741-4909-9caf-1ed89db46137', '02aec773-7670-4000-992f-f6d6ebece7bf', '043bfbdf-c04e-44b1-ae68-e7e91add61ad',
    '051441ad-3a87-4dd8-a04b-3acecbc80d0a', '053d36c1-4d69-4e3b-a22f-26e31cd4f550', '08632502-4bb3-4b86-9cf2-8ed8de15eaf7', '0b97702a-0888-474e-b939-29bb401c7602',
    '0bcd4ae1-716c-4391-9f2e-0380265837f6', '1096dca7-67e4-4dfc-9d8a-9f55a6750ca9', '130df3b4-7eb9-43b7-9776-634fc830b7bc', '13da143d-6663-4dd8-9157-a095283839dc',
    '14a6bd92-7d05-43d7-9ede-ce709046af80', '14ddf840-3f9c-4c4e-add6-2807f502e75d', '166eccce-19de-4274-9afd-22377ac3be69', '18963aa9-af01-4574-86b0-21a1890f57df',
    '198dea2a-f49f-476a-a19f-df67ab15f562', '1b55c9c3-7e5f-426f-a0c1-536ca7e630b8', '1bb0a133-049e-4350-937f-e89cde1b754f', '1da430fb-80e1-4630-a52b-38a9cf9f69f7',
    '20d56c37-8738-466c-9bbc-1720ffa4e5c3', '237866b2-f921-4700-b545-c4b894f525fd', '25879bd9-ffd0-4d16-9dd2-bbd0d0a48b4b', '29f3f610-0e17-49d9-9efe-1e82abdf6dfd',
    '2ea20c5c-8e38-4b93-be81-15616ea116ce', '31c277c5-9cee-4964-9006-f3ec88d24218', '330e8786-aebf-496e-8d80-f018add0cef0', '36cf3a73-2dcf-4053-bbe8-c6c99e1d413d',
    '3b112d64-e0e3-4c37-912a-f69acf35362f', '3b83a62a-9011-48f7-8abc-8862cc9d6299', '3c5a070b-a363-4b3b-9deb-6b769b9ec03a', '3c698943-d456-4413-a7f0-d51605243a0d',
    '3fbc7456-a232-4e8e-b2a8-7e8c3f0a2168', '484b7f8d-a82e-47b7-b43e-694a716791cd', '49599633-37cd-4027-af43-b8bfe75c48bd', '506c31d1-1617-4e9c-b11d-0723f0e9176b',
    '544a8547-c1a5-4504-abc5-e96dc2c2def7', '571c8c45-32d4-4dee-a70c-dc11a81d3e98', '596d1e02-0cd2-4b33-bc09-66a2868d9f1b', '59a32bec-c49a-4828-9e18-484a49597938',
    '61e94a29-367a-4d78-aaad-12fbb9b25132', '6330e539-1a9f-4427-aee1-fafb4f350bb7', '6dea4882-fb11-40da-a396-aad6ebe2cdba', '6eb97574-8add-411a-958e-f144b72da676',
    '6f396bae-9fb5-4c48-8446-db247aa01d67', '769e72e2-125f-4979-8ef5-ccb0241c0209', '7f4e25c7-32a3-46f5-abc8-fdf6b6170133', '7f6a0c22-1f37-40c7-a9be-4250e47848ce',
    '8137c59c-6018-4d39-87fc-92e1106bdde3', '82a3fc45-196d-4971-9390-1505c60b1651', '850d1160-5593-47c7-afc4-9543d38a9ec4', '89e3ed7b-792c-47a8-ba8f-e0efef84c929',
    '8a56604b-3d58-4126-8678-896ee8b39a0f', '8afa1037-fb9e-46a7-a5de-c475b4ebeba9', '9097750d-529a-4f8c-85a5-d1156121765c', '94647270-c396-4135-bee6-1b733ae22b11',
    '9484e58d-7dfb-429f-a41c-e1e5e5909278', '9aad5bbd-08d2-46c3-bab8-1b2d1ec5374d', '9b8cd0e5-475c-4f8c-9fcf-e3315544c9b6', '9c2aeba7-5368-468f-88cc-7608eead0ec7',
    '9e2c8130-6e32-4d29-997b-53a86fdffc28', 'a17d9852-612f-4c4b-805f-34f48a9125b9', 'a62dbd9b-3b54-42ec-9e03-e74a2a5b1ae3', 'aa509265-7a0a-4cf9-8015-cde5dcaf3a9c',
    'b2890ade-48d8-43c4-b032-7eeb8f4fca7a', 'b89e8c8d-c4f1-4974-9f00-3c1828682a65', 'ba756068-f778-43ba-8cdc-273d7ac7ddaa', 'c1f1c837-19ed-4e97-bc95-7f7cb10fb804',
    'c58df87c-8f44-4195-8397-c6be712ca0f2', 'c69cc875-9d89-47b3-9bd1-b07afa498e21', 'c97fc667-99cf-4f1d-a8af-302089319c7a', 'ca0a48cd-8935-42aa-9ca0-4f6f8c798475',
    'cb0796c5-edfc-46ae-9bea-f5456b2aaa94', 'd12c75af-df8d-4f5a-8385-7745c4f9b84f', 'd45168d0-8e2d-4992-a8cd-ffea026aa841', 'd46b485c-0c10-48da-953f-7af8f0afa95f',
    'd54b762b-c51a-4027-a3dc-ad5cf04d7fee', 'd57ca386-571a-4b66-9e13-50bff97854a4', 'd7ca846e-e025-4385-be63-82c4116757aa', 'ddb34f47-ed35-4d60-b927-336b1eab977e',
    'df516e7b-9687-4326-877f-1c31f7e474ef', 'e1bb474b-4fd1-4138-b9d3-c540ea4aec6a', 'e4223dd9-8001-47ee-8a59-0e5b53e6d392', 'e62a1453-da8b-4302-abb0-0b770b8fe1de',
    'e99ab529-ab22-4a8f-b19e-86c87de06c31', 'ee361866-ea1b-45e4-918b-5f761f8cd56f', 'ee6adb1f-33cb-4c01-8021-d8e09f811e31', 'f40864ff-1bf8-42bf-94c7-242b09e3983f',
    'f6774768-c942-49a3-a940-3b2b81297769', 'f685ff19-2238-40b3-b923-f457c5e42190', 'f83c426d-f17d-4976-8d2f-973d535a710d', 'f930c18d-0e3d-45b1-819b-3a3c86b8f4f6',
    'f9b53e67-6cc5-4cdf-99b3-90a84e13d3d9', 'ffa77b3a-ddef-4f5e-bfb0-0a32f662bb5d'
  ]::uuid[];
  v_n int; v_md5 text; v_upd int;
begin
  select count(distinct x), md5(string_agg(x::text, ',' order by x)) into v_n, v_md5 from unnest(v_ids) x;
  if v_n <> 94 or v_md5 <> 'df15c7c6555c4096f30f4c2a5886a156' then raise exception 'rollback guard: id set is % / %', v_n, v_md5; end if;
  select count(*) into v_n from catalogue.course_intakes where id = any(v_ids) and status = 'withdrawn';
  if v_n <> 94 then raise exception 'rollback guard: % of 94 rows are withdrawn; nothing changed', v_n; end if;
  perform set_config('cf.manual_edit', 'on', true);  -- fixed: a recorded human decision, not a pipeline write
  update catalogue.course_intakes set status = 'active' where id = any(v_ids) and status = 'withdrawn';
  get diagnostics v_upd = row_count;
  if v_upd <> 94 then raise exception 'rollback guard: updated %, expected 94; rolled back', v_upd; end if;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('layer4', 'intake_excluded_months_withdrawal_rollback', 'catalogue.course_intakes', jsonb_build_object('count', v_upd, 'ids_md5', 'df15c7c6555c4096f30f4c2a5886a156'));
  insert into search.refresh_requests(requested_by) values ('Intake months restored: rollback of the 94-row excluded-months withdrawal');
end $$;
commit;
