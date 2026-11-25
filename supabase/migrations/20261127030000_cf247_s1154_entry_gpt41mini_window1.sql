-- CF-247 s1154 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 15:40 AEDT: "Select the most economical model that meets the actual quality
-- requirements ... Following successful qualification, prepare bounded activation for the 172 unread courses"; approval: Platform Admin (chat, 25 Nov 2026 18:26 AEDT)).
-- Qualification (admin docs/platform/p0-aer-activation/2026-11-25-course-entry-model-comparison.md, run s1151-entry-qualify-openai-v6-2026-11-25): on the
-- 83 benchmark pages and their 216 source-verified labels, gpt-4.1-mini reading the whole page found 95% of academic requirements, 92% with admission
-- conditions and 94% of pathway and conditional statements; 34 of 203 rows matched no label; every answer valid. No model reached 90% on the selection.
-- As the audited writers do (public.admin_ai_qualification_set_v1, public.admin_ai_route_set_v1, public.admin_pipeline_settings_write, the automation pause;
-- their sign-in needs a person's session, so a migration is technically necessary), each step logged with its reason:
--   1. records gpt-4.1-mini as qualified for course_entry_requirements (whole-page input), with the measured evidence;
--   2. pauses jobs lean-qualify and lean-sections-eval;
--   3. sets reading.course_entry_sections_on to 0: course entry reads send the whole page (the preprocessing exception the Platform Admin approved);
--   4. sets the route to cascade {gpt-4.1-mini}, switched on, daily US$ cap 0: the scheduled reader stays held for the cap, and the worker hands out
--      capped fields only for providers in an open on-demand request;
--   5. closes request 0de69556 if still open and opens one on-demand request (OpenRouter only, Firecrawl 0) for the 20 AU providers of the 172 courses;
--   6. queues the 172 courses through the entry Read now (security.course_entry_read_enqueue_v1: stored course page, no scraper).
-- The 172 are admin docs/platform/p0-aer-activation/2026-11-25-s1-aer-172-course-ids.csv (md5 4cdaa4921da34247c128cfbc2b1f4d8b). Estimate US$0.31.
-- Post-checks: no entry item outside the 172 can be handed out, the scheduler is held, G3 75/48, locks unchanged, cron down by the two jobs.
-- G1: no new job. G2: existing setting and the route's own audited cap. Nothing admitted by this migration; reads go through the existing gates.
-- Replaces: the s1125 to s1151 qualification window (jobs lean-qualify and lean-sections-eval running); course entry sections-first input.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and 172 queue writes

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1154_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1154_cron on commit drop as select count(*) n, count(*) filter (where jobname in ('lean-qualify', 'lean-sections-eval')) q from cron.job where active;
create temp table s1154_w1 (course_id uuid primary key, provider_id uuid not null) on commit drop;
do $q$
declare n int; d int; v int; usd numeric; v_ev text;
  v_reason constant text := 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT): gpt-4.1-mini meets the source-verified course entry criteria on the whole page (s1151)';
begin
  select count(*), count(*) filter (where state = 'done'), count(*) filter (where state = 'done' and coalesce((result#>>'{arms,baseline,complete}')::boolean, false)), sum(cost_usd)
    into n, d, v, usd from pipeline.lean_qualify_cases where run_label = 's1151-entry-qualify-openai-v6-2026-11-25' and model_code = 'gpt-4.1-mini';
  if n <> 83 or d <> 83 or v <> 83 then raise exception 'guard: the gpt-4.1-mini comparison is not complete and valid (% done, % valid of %)', d, v, n; end if;  -- fixed: the benchmark's size
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 's1152-entry-miss-detail-2026-11-25' and state = 'pending') then raise exception 'guard: the s1152 recall cases are still pending'; end if;
  v_ev := 'Source-verified comparison s1151-entry-qualify-openai-v6-2026-11-25 (83 benchmark pages, 216 labels checked on their stored pages; admin docs/platform/p0-aer-activation/2026-11-25-course-entry-model-comparison.md): '
    || 'gpt-4.1-mini on the whole page: academic recall 95% (of 119), academic and admission conditions 92% (of 180), pathway and conditional 94% (of 89), every requirement on 71 of 83 pages, 34 of 203 rows match no label, 39 unsupported quotes removed by the reader, valid answers 83/83, requirement type 92%, audience 77%, US$0.0018 a page. Input: whole page (reading.course_entry_sections_on 0).';
  insert into pipeline.ai_route_qualifications (service_code, model_code, status, provisional, evidence, qualified_at, qualified_by, note, changed_at)
  values ('course_entry_requirements', 'gpt-4.1-mini', 'qualified', false, v_ev, now(), '63ba56cb-48d4-4169-98c2-7c4d1f72925b', v_reason, now())  -- fixed: the approving Platform Admin
  on conflict (service_code, model_code) do update set status = excluded.status, provisional = false, evidence = excluded.evidence, qualified_at = excluded.qualified_at,
    qualified_by = excluded.qualified_by, note = excluded.note, changed_at = now();
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_qualification', 'course_entry_requirements / gpt-4.1-mini', jsonb_build_object('before', null, 'after', 'qualified', 'evidence', v_ev, 'reason', v_reason,
          'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT)', 'via', 'CF-247 s1154 migration'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
end $q$;

do $act$
declare v_reason constant text := 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT): Window 1, the 172 unprocessed AU courses (20 providers) read on gpt-4.1-mini, whole page, under one scoped on-demand request; US$0 daily cap keeps the scheduled reader held';
  v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- fixed: the Platform Admin, who approved Window 1 (as s1114 and s1115)
  r record; rt pipeline.ai_service_routes%rowtype; v_od jsonb; v_prov uuid[]; v_job uuid; v_n int := 0; v_close jsonb;
begin
  insert into s1154_w1(course_id, provider_id) select x.c::uuid, k.provider_id from unnest(array[
    '0345dedc-8c16-44a5-9b79-614a9990ac7f', '03c8690c-2ac7-490e-a8a9-3dbe9c0a8204', '04ebcaea-a53a-4e8d-8e6f-c7bebf216a08', '0862284b-7f20-418e-a858-3d983ea27b06',
    '0a083225-5853-470b-9066-7df00c359f88', '0abee670-510d-464c-a859-1e780c5c81c0', '0b50a946-95bc-4817-a10d-402ee92e91d9', '110ad283-2321-4bda-a5c6-90de2a2eceea',
    '169b5258-0e1a-471a-807d-8473bdd0dcf2', '19fa1249-f694-479a-8602-0ba0bd7b69f3', '1a8df22a-2739-4226-8856-10dd228e0033', '1a9e0998-1142-43c1-aeb2-5b72b5615f62',
    '1abef804-e85a-467b-8c7e-d205160c6741', '1b27f371-1e3e-47ed-8ae5-0dbb608d31be', '1d6edd10-46c2-410c-a34b-5109fa6fc4ef', '1f87a1c4-1df1-48a4-8fd8-099ccc0955c8',
    '2023c81a-4118-4675-9a41-c7d9288f9146', '20e02c7f-956e-4c7a-80f1-ffcee2e58c16', '234a7edd-b897-4249-9a57-2b60836705e2', '23876a48-d490-479d-bd99-c02db14e2db7',
    '23eed894-e088-4913-bc1a-a07688c9a253', '24748ee1-3693-4f9d-85fe-54ba9455d2b9', '2493488e-3d1e-4591-878a-89bae9d15b0d', '25c2a344-859b-42bf-b73f-1ce9c9dd54f2',
    '2a1e11f4-0338-4b24-b116-56f755c8343c', '2cbb9140-37bc-46d5-b3e9-818efe99f1bc', '340a864c-c7a4-4f77-a502-4d9731f968a7', '3612a502-8f44-46e9-be86-fb0ef9081f03',
    '366c36b5-66c2-48a6-8ed0-e2983ad7e71a', '37949cf4-3bbd-43ed-b077-8ea8589ca604', '395426e6-db10-4a1a-8d5d-4c834a9081f5', '399e3a1f-06fe-4c09-ba63-9ce8f9e4609e',
    '3ac110e5-a29c-48be-80fb-c62ddc0f6ccf', '3acbaad2-36f1-4663-b486-d5ae5b7725e8', '3bb3931d-f10a-4a86-82a5-cc832edea8d0', '3c65c53a-e091-423d-87e6-08ef8902faf9',
    '3de8e1c4-b5ff-4400-abac-6294a1480e57', '3eb31e21-4696-4c10-bf2a-293322d69518', '3f8424e8-33e5-4385-9f2e-e528349e12e4', '3f8bb668-0907-495e-bd40-5e6f9a76f868',
    '410bb5a6-6570-4587-9d58-9f348987ff1a', '44b65129-c466-43a8-a0d9-794a16757821', '4566e975-25d3-4f24-a8a0-1bab3908aad5', '4584f2b2-f0b6-4311-95ce-5dd3559bd79b',
    '45a06868-3691-4ae8-b000-4efdc991ed40', '47d65fef-3088-4880-98c7-a5a0f47dede1', '47e8bf6b-f403-4dca-8c62-eebe39e84642', '488f50c4-e7d3-4b21-a8a1-8ed95fcc0a03',
    '496cd470-7973-44e7-8e1e-68f8bd96329c', '4b514968-4a30-4389-a8ef-e0b79b62925c', '4bb364d3-e8df-48d8-967b-d720903a0ee4', '5083fb7d-fbc3-43f4-bda4-01efc5108a38',
    '50d85808-dda1-47b6-8677-da6cc8426baf', '52d2d1e9-b538-44a8-a889-36f1169543ab', '52e66767-9ae7-4bf9-b0d2-8b392b2c8693', '590a5859-14bb-4d1e-adc3-42c7f9fe9728',
    '5a8286f7-c6c3-4d0b-a62e-f549eef2ed41', '5eb09e0b-2270-47e1-b7f2-865ca7a31987', '5ecad1b8-a4c1-49c2-828a-e95465647525', '5ee1aed4-eb24-4627-b983-a33186a76e92',
    '5fb408a0-4d7d-48cb-b5dd-c2d41b19377d', '61010665-5c51-4fba-b70e-c703b2ba7520', '6115fc48-6e6c-4b62-acc0-1c0f7dbc4233', '62e68fb3-5041-43ba-aea6-138dfe1884cd',
    '669d7e8c-76de-4f6c-9bb2-9410ba17e53d', '674f08ad-937d-4eac-9576-1739ace702f8', '682b57f3-c6c1-4d71-891e-d0e00feecc6f', '6a3f2f38-9432-4b88-92d7-f100f80a197b',
    '6aea9c0c-53ff-45a3-b8b1-287c2f154916', '6b1c0027-4e6c-47a2-939d-6cbe657786ba', '6c38020f-d81e-422b-8716-b7771f995ad3', '6c599729-a00e-4960-952e-5104fec37e48',
    '6ea299dc-b864-422a-b525-cbfbfda0e205', '6f7b18be-7919-4e17-8b52-a41c55fd94ba', '706a4092-54f8-4286-8f2c-7b9cdd119f6f', '7089dc34-8969-4a4c-879a-c44545388bdc',
    '70cfac83-e63c-4129-a348-1c5407e24254', '71c8a7b1-20c2-4d84-b9a8-6b57e12e2684', '7246194c-72e0-4e3c-a272-eb2968a208c0', '72513451-dc92-4136-958d-b245ba2e1fdf',
    '72c7890c-cfee-4788-a9c9-4068088a5722', '74d27f71-1f5b-4910-9c96-14a44661749f', '75595a96-1ef3-4b60-809a-58f694b83767', '761fa22e-dc19-4c1c-b0d8-a483e61fffc0',
    '77620a1b-605b-4c51-a56b-8f20414cb705', '79690cb5-b365-487e-8755-7e656c69c02b', '7a4038ec-a78d-4f1f-9765-a658732e959e', '7ade7efd-0f1f-437f-8a2d-f3da095756de',
    '7eba9f6c-0e5b-4860-baa0-02e01b1a1899', '8396b2f9-30f6-48ef-b2df-ffedd27dcb4a', '850532eb-766b-4ea7-bfa2-bad1781a09f1', '85252eee-6a4b-4f3f-9ff3-239676f89756',
    '8532f8d8-e86e-4efe-a493-a2411ff06495', '86aa2008-a8ad-4d5e-ad5a-05b062b1d27d', '891fd9ba-4e5e-4018-914f-02734cef9593', '89f4f15d-53c2-47ec-87aa-1f42f2b5213d',
    '8d1f1afd-96e1-44b3-bc61-a4dc42f54536', '8e0a502e-7b81-47de-b172-dcf0cf93c4d2', '9168baee-d01d-45ca-a355-88d22ec9ec93', '91faf178-7174-4c58-bf6f-b93041083689',
    '96b1b8aa-7ec1-470a-832c-d169332eda2a', '98610bb2-1c02-49cf-a7ce-0d4ab8fc137f', '9975e97b-dbd9-40ff-ae7d-3478f4db060f', '9baedf50-69c3-40db-b904-f3152040d0bc',
    '9c620ea6-0c2c-4609-b788-f001feab973c', '9cb5ca66-1f07-4425-bccc-56702a299495', 'a13f2aa0-a6b4-4a9e-ae15-0b4b00158dce', 'a289ef1d-cb47-42fb-ba33-d61dd5dfb4cd',
    'a2ce6fdb-dfb3-4832-b7ac-cdca5d2bd9e8', 'a4331124-0098-4b91-ba0a-05ec75e11bf0', 'a5f8448c-d5b2-4ca8-afbe-b471c407dd4e', 'a675c149-e11c-4cc4-9e3c-251e725ed00c',
    'a8b22ec1-373a-4ad7-a3c0-5fe4f352cd1c', 'a943d353-7121-4427-8fbd-33b4f59bfcf0', 'aa948937-8653-4992-b820-87c82d31d02c', 'aa9edc03-ba77-4f0a-a668-1e75019557bc',
    'ab254bfa-a3fc-414e-b70b-b2dd98c58204', 'ad154e70-d0aa-45e8-a2f3-76f84d5c2902', 'b1b6df03-b445-43ed-bc6f-9b37e3f9602d', 'b2780da7-255b-447c-a1d7-5effc2738006',
    'b4f6a2c3-b5c2-43ad-bd1c-2ee942ee4f34', 'b6b4bfc1-bc55-4141-a5d1-be3b617d2b90', 'b735f3d7-7d12-4c78-97ca-1636927ce6b0', 'b74ba39c-593c-43c2-b851-e052972918b2',
    'b7dc6d45-24a6-40cf-8396-62f81064be2e', 'bbdc4a40-5920-4e5d-b2b5-e71021ba31ee', 'bbebbde2-9b55-4eae-8ca3-8b122f0a7428', 'c00edbe1-823e-4586-99dc-4cf2f123701c',
    'c0c35720-8ff4-4751-90a4-961a826ec582', 'c47ac320-41d0-42e9-9bc6-3fd3f211653c', 'c4ba6132-1c64-4ffe-8e87-e75e190e7aaf', 'c4e2ebd4-e7a0-40f8-ac6d-fac1f05d183d',
    'c562cc8a-2604-4996-a2a6-3cbf852a02c7', 'c5e4cea4-0243-494a-8e3e-3a50d0623ada', 'c73ee0da-dc2c-4883-b48b-f8c1a93d2ab6', 'c94105f0-0cb6-406e-b6d5-40a1c22022c0',
    'cd7e435c-0ad7-49ee-875d-fccf6fb613ab', 'cf8be5ef-5bec-4f02-8b9a-ed4135376ac3', 'd0562d2d-0738-4576-ab58-2893cb90d457', 'd0869c14-7843-4a31-b99d-56754a099ed8',
    'd122606b-fe48-4a1a-b030-c9b84ea11ec1', 'd3fcdad9-1ee1-49be-9a36-fb145b45b83a', 'd5c19cda-0789-45da-a5e2-855d1a2290f5', 'd5dcff8a-73fe-4752-a3af-18285386c5a8',
    'd63f9498-bf65-4b26-9efa-11a52cf89526', 'd66a95af-02cf-4901-bc66-6f96728440c8', 'd68f7294-7de0-44e8-9f55-891d77ff7a87', 'd9735d19-1b6d-4b56-8620-f9e29dc3505d',
    'da0667c1-9818-4ab3-bbf7-c047f5de404d', 'dd728c78-af4f-4f4d-bf16-33777bb25948', 'dda824aa-b45b-4275-a639-ff196df336e8', 'de0e3d48-5f5e-49fe-a1ef-7e1bdee67149',
    'de3428d4-e0b8-4d60-9735-c4e41dc75c12', 'de51e486-162e-4ff4-8375-8024f52f9c1a', 'dfa98ff3-650c-4194-b4e4-418ff4430e2e', 'e01a5c16-5a54-4e24-a3ec-cadae17ba8a1',
    'e229d249-5694-49f5-bc9c-23190a7c5e42', 'e533f502-53b9-44e9-aa6d-5f272825716a', 'e66ea247-7ccf-4551-a6e0-3d63c9ec26f0', 'e6c958c1-6629-41f7-87c8-c44cf845fdf6',
    'e6d0e1c3-32eb-4673-a67e-ef4a6625f9ea', 'e87ae579-e345-4edf-9b4a-6a07b6b23c48', 'e97e9d98-d205-4f2d-b6b2-6b1bbed8871f', 'eb688c83-903e-4239-9ead-95688a85a790',
    'ee1b19c6-a2fa-4ca0-8da7-4678167ca7fc', 'ee49e88a-e819-45ba-ab8b-45491f5dfd95', 'ef22551f-5e7e-4d70-ad01-a32cf614ca61', 'f60ce116-ad75-4357-9845-bc4f954eb141',
    'f6b6cd10-3168-497d-ac02-b64dcdea2f9b', 'f6df76b5-a9bc-4475-9847-23f40c7fe62e', 'f77d1933-0493-4f27-8962-95d9904c22e4', 'fe25cb7d-857d-4fe2-92c5-9265ddf4c193'
  ]) x(c) join catalogue.courses k on k.id = x.c::uuid;
  if (select count(*) from s1154_w1) <> 172 or (select count(distinct provider_id) from s1154_w1) <> 20 then  -- fixed: the approved window's size
    raise exception 'guard: the Window 1 list is not 172 courses at 20 providers';
  end if;
  if exists (select 1 from pipeline.field_enrich_items f join s1154_w1 w on w.course_id = f.course_id where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'guard: a Window 1 course already has an open entry read';
  end if;
  -- 2. the two qualification jobs pause
  for r in select j.jobid, j.jobname from cron.job j where j.jobname in ('lean-qualify', 'lean-sections-eval') and j.active loop
    perform cron.alter_job(r.jobid, active => false);
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('automations', 'pause', r.jobname, jsonb_build_object('reason', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT): qualification complete; pause lean-qualify and lean-sections-eval',
            'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT)', 'by', 'migration CF-247 s1154'), null);
  end loop;
  -- 3. the route: gpt-4.1-mini, on, US$0 daily cap (public.admin_ai_route_set_v1's checks and log)
  select * into rt from pipeline.ai_service_routes where service_code = 'course_entry_requirements' for update;
  if not exists (select 1 from pipeline.ai_model_catalogue m where m.code = 'gpt-4.1-mini' and m.status = 'allowed') then raise exception 'guard: gpt-4.1-mini is not an allowed model'; end if;
  update pipeline.ai_service_routes set cascade = array['gpt-4.1-mini'], daily_usd_cap = 0, enabled = true, reason = v_reason, changed_at = now(), changed_by = null
   where service_code = 'course_entry_requirements';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', 'course_entry_requirements', jsonb_build_object(
          'before', jsonb_build_object('cascade', to_jsonb(rt.cascade), 'daily_usd_cap', rt.daily_usd_cap, 'daily_calls_cap', rt.daily_calls_cap, 'enabled', rt.enabled),
          'after', jsonb_build_object('cascade', to_jsonb(array['gpt-4.1-mini']), 'daily_usd_cap', 0, 'daily_calls_cap', rt.daily_calls_cap, 'enabled', true),
          'resolver', rt.resolver, 'reason', v_reason, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT)', 'via', 'CF-247 s1154 migration'), null);
  -- 3b. course entry reads send the whole page (the preprocessing exception), through the settings pattern
  declare s record; begin
    select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reading.course_entry_sections_on' for update;
    if s.key is null then raise exception 'guard: reading.course_entry_sections_on is missing'; end if;
    update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = v_reason, updated_at = now() where toolset_key = 'pipeline' and key = 'reading.course_entry_sections_on';
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('toolsets', 'setting', 'pipeline.reading.course_entry_sections_on', jsonb_build_object('before', s.value, 'after', to_jsonb(0), 'reason', v_reason,
            'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT)', 'via', 'CF-247 s1154 migration'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end;
  -- 4. the qualification request closes; one request opens for the 20 providers
  if exists (select 1 from pipeline.on_demand_requests where id = '0de69556-171f-485d-9c81-e4a2b26f7455' and state = 'open') then
    v_close := security.on_demand_close_v1('0de69556-171f-485d-9c81-e4a2b26f7455');
  end if;
  select array_agg(distinct provider_id) into v_prov from s1154_w1;
  v_od := security.on_demand_open_v1('claude_session', v_reason, v_prov,
          jsonb_build_object('openrouter_usd', 0.35, 'calls', 360, 'firecrawl_credits', 0, 'courses', 172, 'model', 'gpt-4.1-mini', 'input', 'whole page'), null, array['openrouter']);  -- fixed: the approved window's estimate
  -- 5. the 172 courses through the entry Read now
  for r in select course_id from s1154_w1 order by provider_id, course_id loop
    v_job := security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_reason);
    v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'window_open', 'course_entry_requirements', jsonb_build_object('reason', v_reason, 'window', 1, 'courses', v_n, 'providers', cardinality(v_prov),
          'on_demand', v_od->'id', 'closed', '0de69556-171f-485d-9c81-e4a2b26f7455', 'close', v_close, 'approved_by', 'Platform Admin (chat, 25 Nov 2026 18:26 AEDT)', 'by', 'migration CF-247 s1154'), null);
  raise notice 's1151 window 1: % courses queued, request %', v_n, v_od->'id';
end $act$;

do $c$
declare v_api jsonb; v_r jsonb; v_od uuid[]; v_out int;
begin
  if (select count(*) from cron.job where active) <> (select n - q from s1154_cron) then
    raise exception 'post-check: the number of active cron jobs changed beyond the two paused jobs';
  end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  if exists (select 1 from cron.job where jobname in ('lean-qualify', 'lean-sections-eval') and active) then raise exception 'post-check: a qualification job is still active'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1154_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.field_enrich_items f join s1154_w1 w on w.course_id = f.course_id where f.field = 'entry_requirements' and f.state = 'queued') <> 172 then
    raise exception 'post-check: the 172 courses are not all queued';
  end if;
  -- containment: the worker hands out capped fields only for providers in open on-demand requests; no other entry item may be among them
  v_r := security.ai_enrich_routes_v1();
  if not coalesce(v_r->'limit_fields' ? 'entry_requirements', false) then raise exception 'post-check: the entry field is not held by the US$0 cap: %', v_r; end if;
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  select count(*) into v_out from pipeline.field_enrich_items f
   where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') and f.provider_id = any(v_od)
     and not exists (select 1 from s1154_w1 w where w.course_id = f.course_id);
  if v_out > 0 then raise exception 'post-check: % entry items outside the 172 could be read under an open request', v_out; end if;
  if security.ai_route_v1('course_entry_requirements')->>'held' is distinct from 'true' then raise exception 'post-check: the scheduled reader is not held by the cap'; end if;
  if security.pipeline_num_v1('reading.course_entry_sections_on', 1) <> 0 then raise exception 'post-check: course entry reads still send the selection'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
