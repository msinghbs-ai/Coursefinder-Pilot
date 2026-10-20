-- CF-247 (21 Oct 2026). NZ Destination Page review, website developer feedback 21 Oct (items 2 and 7: course locations and campuses).
-- Platform Admin choice "Quick fixes first (Recommended)". Three data corrections, New Zealand only:
-- 1 Ten Maori provider names lost their macrons on the NZQA register page (the page sends a literal "?" for each macron vowel, e.g.
--   "Te W?nanga o Aotearoa"). Each name is set to its macron spelling; the change is only made when the stored name is exactly the
--   new name with each macron vowel turned into "?", so nothing else in a name can change. The register import only writes a name when
--   it creates a provider, so the fix holds; a manual lock is added as well.
-- 2 73 NZ campuses had no city, so the courses linked to them showed no location (Lincoln University's one campus among them); 65 are
--   set here, giving about 646 more courses a city. Each city
--   is read from the campus name the provider publishes (a named city, suburb or street address); suburbs of Auckland and Christchurch
--   take the city. Campuses whose name covers several towns or no place ("Napier, Palmerston North, Hastings", "Centre-Based",
--   "Hawke's Bay", "Tongariro Centre", "Varda Academy", "1B Beatrice Tinsley Crescent", "Auckland, Christchurch", "Kerikeri, Whangārei,
--   Kaitaia") stay blank (8). Locked as manual values.
-- 3 Courses at a provider with exactly one campus, with no campus link and not delivered online only, are linked to that campus (290 on
--   21 Oct, 81 of them Lincoln University's).
-- Replaces: nothing (data only)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): only values change.

do $nz$
declare v_n int; v_bad text;
begin
  -- 1 provider names
  create temp table nz_names(id uuid, name text) on commit drop;
  insert into nz_names values
    ('ea0f4e14-e790-4c62-886f-3ec5bc040b4a', 'Te Wānanga o Aotearoa'),
    ('f145b8e9-36dd-4f96-b1f5-bb453ced3a45', 'Te Wānanga o Raukawa'),
    ('f26b52ba-e1e8-4047-af18-27bf3843aaa6', 'Ngā Kura ā Iwi o Aotearoa Incorporated'),
    ('5c067273-5f41-4da0-a16c-b2eac17f4306', 'Te Whare Wānanga o Awanuiārangi'),
    ('cb964c9c-d09d-4228-aab8-b41860422362', 'Te Pou Oranga o Whakatōhea Limited'),
    ('2a97c91d-9340-49fa-a437-6c76ea01edd9', 'Te Rūnanga-o-Tūranganui-a-Kiwa'),
    ('f8d06b5c-aed0-4704-8731-77ccb36e4a0f', 'Te Kōhanga Reo National Trust Board'),
    ('c78614b7-7562-43f7-87cc-fce788a46450', 'Te Rūnanga o Ngā Maata Waka Incorporated'),
    ('2738563e-c86a-4404-af16-8510816e0b02', 'Te Wānanga Takiura o Ngā Kura Kaupapa Māori o Aotearoa Incorporated'),
    ('b2db22ac-5714-4020-b81c-aff08d44ca08', 'Te Whānau Tupu Ngātahi o Aotearoa - Playcentre Aotearoa');
  select string_agg(n.name, '; ') into v_bad from nz_names n left join catalogue.providers p on p.id = n.id
   where p.id is null or p.display_name <> translate(n.name, 'āēīōūĀĒĪŌŪ', '??????????')
      or p.canonical_name <> translate(n.name, 'āēīōūĀĒĪŌŪ', '??????????');
  if v_bad is not null then raise exception 'stored provider name is not the expected register text: %', v_bad; end if;
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.providers p set display_name = n.name, canonical_name = n.name, updated_at = now() from nz_names n where p.id = n.id;
  insert into pipeline.manual_locks(entity, entity_id, field, mode)
  select 'provider', n.id, f, 'value' from nz_names n cross join unnest(array['display_name', 'canonical_name']) f
  on conflict (entity, entity_id, field) do nothing;

  -- 2 campus cities
  create temp table nz_cities(id uuid, city text) on commit drop;
  insert into nz_cities values
    ('bed6cb73-f882-4344-bb7c-7921c3eaee7e', 'Auckland'),          -- AcademyEx: Auckland
    ('8f19d1b6-3467-4331-93d4-5d762a586fcb', 'Auckland'),          -- Adventure Works: 9 Geddes Terrace, Avondale, Auckland
    ('2bdc9a2d-a3b5-4a80-979e-0918fdf0d77c', 'Christchurch'),      -- Aesthetics House: Christchurch
    ('ead71353-d9b5-4bea-931e-554f1ec93fb1', 'Auckland'),          -- AGI: Auckland City
    ('d5cc9775-0cce-4592-844e-6de125bcc7b6', 'Christchurch'),      -- AGI: Christchurch
    ('fef89280-d28c-4f1e-b0e0-f8ed9ce70ad7', 'Christchurch'),      -- Airways: Christchurch Training Centre
    ('a1ccee3d-d54e-47a4-a659-251c9f78d08c', 'Auckland'),          -- Alpha: Auckland
    ('94565227-23c0-485a-90c5-37ee2394b2e2', 'Christchurch'),      -- Ara: Sullivan Ave Campus (Woolston, Christchurch)
    ('0cbcead5-3ebf-4d22-8176-ddc7b6d1d1a4', 'Dunedin'),           -- Arai te Uru: 51 Macandrew Road, South Dunedin
    ('d9157bf1-658c-4fc0-b78b-202131d2934a', 'Auckland'),          -- ATMC: Auckland CBD
    ('8d3abd99-de46-4351-ae90-5306481324c3', 'Tauranga'),          -- Bethlehem Tertiary Institute: Bethlehem Campus (Tauranga)
    ('2058997b-a2ef-4b2e-805d-cb33248f765f', 'Wellington'),        -- Capital Training: Thorndon Quay Campus
    ('3a8b31b0-2454-49ea-bf13-5fefe7883ec9', 'Upper Hutt'),        -- Capital Training: Upper Hutt Campus
    ('f298c58c-21c9-4008-bfe5-5686b919c091', 'Waipukurau'),        -- Capital Training: Waipukurau Campus
    ('c67915f0-dfa2-40c1-9247-18a04af8e837', 'Auckland'),          -- Communications International: Auckland CBD
    ('e4407767-9076-4b95-b5a8-daed3472d1af', 'Palmerston North'),  -- ETC NZ: Palmerston North Campus
    ('e56dc3b7-fcea-4e49-8dad-59b77858e530', 'Auckland'),          -- Employment Focus: Auckland
    ('e7b6a4a8-75d1-4848-a2ef-b746d045fdc6', 'Auckland'),          -- Excel Ministries: 20 Portage Road, Avondale, Auckland
    ('2549a41e-39bd-4bfd-8314-16a42fc4c9b2', 'Stratford'),         -- Feats: Stratford
    ('fad25899-4fb9-4284-baf9-4201c83894f5', 'Auckland'),          -- Future Skills: Auckland Central (Queen St)
    ('0e0565cf-4064-432f-8762-482bb49284f8', 'Auckland'),          -- Future Skills: Manukau
    ('926ee366-c90b-4d0d-9e58-66e196672f80', 'Auckland'),          -- Future Skills: Royal Oak
    ('8b7ef3ed-ff9b-41ef-98c5-d5092a849ffa', 'Auckland'),          -- Good Shepherd College: Auckland Campus
    ('3df409f3-c77c-4407-843a-2759abb3bff7', 'Auckland'),          -- ICL: Auckland CBD
    ('05a314b9-87a5-494b-ab8f-5c9b527264a4', 'Auckland'),          -- Kiwidotcom: Albany on the North Shore of Auckland
    ('3c135e80-425f-4670-b22f-01d79443cbf8', 'Auckland'),          -- Laidlaw College: Henderson
    ('6c707eff-e5ed-4ab2-97e6-d3c3051da822', 'Lincoln'),           -- Lincoln University Campus
    ('1197d3b2-671b-4fcb-a9fd-07decff003d2', 'Auckland'),          -- MIT Manukau
    ('25d55fa7-dc2c-45b2-8083-1f793d2250ec', 'Auckland'),          -- MIT Ōtara
    ('ae9447d2-74d7-47a3-b3b9-279151218813', 'Auckland'),          -- MIT TechPark
    ('7a08cfea-178c-4dcf-b712-2dee8f6e7e0b', 'Auckland'),          -- New Zealand Maritime School (MIT)
    ('1b6563dc-abbe-4922-8c47-ead322743fb8', 'Auckland'),          -- Unitec: Mt Albert
    ('676e1426-d247-4202-9d83-983296cbd6b7', 'Auckland'),          -- Unitec: Waitākere
    ('5bf9864c-a045-4bb7-92de-28c4ef882c6e', 'Lower Hutt'),        -- NZIST (Wellington region): Lower Hutt Campus
    ('6b36b51a-4f65-400c-9dda-cbfb60058d92', 'Lower Hutt'),        -- NZIST (Wellington region): Petone Campus
    ('2e558252-bd45-461b-801a-5f4f71ad951c', 'Porirua'),           -- NZIST (Wellington region): Porirua Campus
    ('b9d5a991-428a-401f-8bc9-7e45fe6cf0d8', 'Auckland'),          -- NZ School of Education: Auckland CBD
    ('49e1d5d5-04e7-44a5-831a-40fc70638e27', 'Auckland'),          -- NZ School of Education: Manukau
    ('d17533e3-8617-4502-acf1-3ef47ea87baa', 'Auckland'),          -- NZ School of Education: New Lynn
    ('b14a3f40-1481-4ef0-9fa0-7452ce193e89', 'Cambridge'),         -- NZTI: Cambridge
    ('aa475f49-0768-4d4c-aef5-7c982da2c289', 'Auckland'),          -- Oceania Career Academy: Māngere Campus
    ('b4bd999f-b837-4b6c-98ea-b879d1f1df0c', 'New Plymouth'),      -- PIHMS hotel campus (New Plymouth)
    ('02b80259-5861-4b63-b0db-093038a65a88', 'Christchurch'),      -- PEETO: 22 Twigger Street, Addington, Christchurch
    ('6361e214-e46e-4ec2-8cae-880d1b9bdcc5', 'Auckland'),          -- Personalised Education: Manurewa
    ('224ee8cb-7c10-4477-b27b-b893695a182f', 'Rotorua'),           -- Personalised Education: Rotorua
    ('040f36dc-d9fb-4698-b55a-95a5759bc63c', 'Queenstown'),        -- QRC: Queenstown
    ('4fa7f5e0-5706-4b1b-abdf-b0ea415c1be9', 'Auckland'),          -- SAE: Auckland
    ('d345d385-a7b2-492d-900c-f5bc4ba07f52', 'Auckland'),          -- Seafield: City Campus / Auckland CBD
    ('4a4f694c-e44e-4a65-ab88-bb11d150d3cf', 'Auckland'),          -- Skill New Zealand: Manukau Campus
    ('9e90c0a7-dcc2-4cd4-b419-cf6617b677d5', 'Balclutha'),         -- SIT: Telford (Balclutha)
    ('1e08561d-b2c2-4ed5-9b47-498f5d2ca54a', 'Hamilton'),          -- SPI Institute: 43 Lake Road, Frankton Hamilton
    ('dc25f988-0ffe-4ae8-a670-8353bf8ca765', 'Gisborne'),          -- Te Rūnanga-o-Tūranganui-a-Kiwa: Gisborne and across Tairāwhiti
    ('40d96be1-b175-4971-a9af-83be4c2d8cd1', 'Upper Hutt'),        -- Booth College of Mission: Upper Hutt
    ('2cd1b462-3779-4b59-b41f-585b34a6ad0a', 'Rotorua'),           -- Toi Ohomai: Rotorua Mokoia Campus
    ('de3742ca-a724-471d-8097-35328c015644', 'Taupō'),             -- Toi Ohomai: Taupō Campus
    ('890566e2-bec0-4b29-b9f6-4c3ded44a648', 'Tauranga'),          -- Toi Ohomai: Tauranga Windermere Campus
    ('99443c0e-6f0a-4126-8871-e0bca29de560', 'Tokoroa'),           -- Toi Ohomai: Tokoroa Campus
    ('bf156fa4-3d41-4dc4-a5b9-6e428a353a4f', 'Whakatāne'),         -- Toi Ohomai: Whakatāne Campus
    ('744891ff-6677-40c9-9172-4fe488d291a1', 'Whanganui'),         -- Training For You: Whanganui Campus
    ('8060b3b2-2a8f-4a61-8d24-d4398385473d', 'Auckland'),          -- UUNZ: Auckland CBD
    ('52f23d44-242b-44f8-8019-7610d6ae5d6c', 'Thames'),            -- Valley Education: Thames
    ('4175674b-faab-4147-ba04-88eeba8e0ed5', 'Auckland'),          -- Vision College: Auckland
    ('404d425a-3b2c-4719-ae6f-aa0a4a6074d4', 'Christchurch'),      -- Vision College: Christchurch
    ('e2372b7d-5355-42a5-9897-fad9720b1122', 'Hamilton'),          -- Vision College: Hamilton
    ('c9be0268-4ee0-4213-aa0a-2aa162d1eedc', 'Wānaka');            -- Wanaka Helicopters: Wānaka
  select count(*) into v_n from nz_cities n join catalogue.campuses k on k.id = n.id
   where k.city is null and security.coverage_country(k.provider_id) = 'NZ';
  if v_n <> (select count(*) from nz_cities) then raise exception 'campus cities: % of % campuses are still blank NZ campuses', v_n, (select count(*) from nz_cities); end if;
  update catalogue.campuses k set city = n.city, updated_at = now() from nz_cities n where k.id = n.id and k.city is null;
  insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'campus', n.id, 'city', 'value' from nz_cities n
  on conflict (entity, entity_id, field) do nothing;

  -- 3 single-campus links
  insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary)
  select c.id, k.id, coalesce(c.delivery_mode, 'on_campus'), true
    from catalogue.courses c join catalogue.campuses k on k.provider_id = c.provider_id
   where security.coverage_country(c.provider_id) = 'NZ' and c.lifecycle_status = 'active'
     and c.delivery_mode is distinct from 'online'
     and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = c.id)
     and (select count(*) from catalogue.campuses k2 where k2.provider_id = c.provider_id) = 1;
  get diagnostics v_n = row_count;

  insert into search.refresh_requests(requested_by) values ('cf247_nz_names_campus_cities');
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values
   ('layer1', 'nz_location_fix', 'NZ', jsonb_build_object('provider_names', 10, 'campus_cities', (select count(*) from nz_cities),
      'single_campus_links', v_n, 'decision', 'Platform Admin 21 Oct 2026 "Quick fixes first (Recommended)"; NZ Destination Page review items 2 and 7'), null);
end $nz$;
