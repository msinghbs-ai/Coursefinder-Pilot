-- CF-247 s1114 (S2-AER, Platform Admin 25 Nov 2026 06:56 AEDT, Admin #1054: AER wave 1 steps 3-5, 30 named AU providers).
-- Measured live 25 Nov 2026 (rolled-back read-back): the 26 providers with stored course pages have 478 eligible courses; every one already has an entry-requirements read
--   (292 filled, 159 skipped, 39 failed). 39 reads failed with held_partial (slice not read whole) or "no answer could be recorded after 3 tries". This change reads those courses
--   once more through the existing course-level reader (security.course_entry_read_enqueue_v1: stored page only, no Firecrawl, model reader course-entry-v1). Every output goes to Layer 4
--   for a person or the unchanged machine rule; nothing is admitted here. Course-level requirements stay course-level (catalogue.course_entry_requirements), not country matrices.
-- Only a course of the 30 named providers that is eligible, has a bound page with evidence, and whose entry-requirements items are all failed is read again. Size is the
--   existing setting entry.course_batch_size; the estimate must leave the OpenRouter balance above its floor (Toolsets & limits).
-- G1: no job. G2: no operational number written into the run. G3: no consumer object (75/48). Manual locks untouched. Nothing dropped or deleted.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the course rows

create temp table s1114_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $r$
declare
  v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
  v_providers constant uuid[] := array[
    '8cc6fece-de98-424d-8033-0fdd92cdee00',
    '981b9811-9f4e-4825-b7af-cc47b5ebf6f5',
    'bba5dcf0-c9dc-4fa3-bd00-bc0638c78c22',
    'bd32bbd0-d59f-4201-bb23-8eadd2a4afb7',
    '0cca4a32-4649-4d79-bb46-49cfecf161b9',
    '5d21e4d4-73b4-4ad6-b100-199264540e72',
    '6c79c82b-5cde-49b7-9998-13af66d28b47',
    '8e7141b4-d366-4860-819e-86c54586dc12',
    'ad99fbcf-e690-499b-bbae-bc81ef892fc8',
    'e6396c9e-c655-47b5-b2a1-820f48910206',
    '15e47a21-94a7-4984-aca8-cbbbecbfaab6',
    '5d0e3147-4dcb-4152-8f21-6a2a5ce51bc6',
    '70b6688c-2ca3-49cd-8eb8-9f35297d6c35',
    '98f6df2b-f06c-4963-8aa1-7375e4b367d4',
    'f7281274-2d50-49d2-98db-a68d3467a86b',
    '03f447ae-f200-44f1-b58a-6581c00b9743',
    '1241fe08-1fff-45c7-9c76-2857ec5a53dc',
    '159328df-fb4b-4bb8-a6b8-5f24546437a3',
    '4790a6ab-7e93-42d6-b0ac-757d68040f7d',
    '9edc07c5-fc46-407e-8432-6ac240f34da8',
    '28828d80-3ce9-47af-b2b2-b9b08ee5d514',
    '449f1b2d-5f7f-4ef3-9fe1-a89c2f8bbe49',
    '823d398f-5e99-47c9-96a8-eff642853fa8',
    'a7499e11-54b6-4edf-a301-390b0d4f39ad',
    'ae1a5efb-620e-4690-849b-155ff6390d3b',
    'aead951c-991f-4bd6-b969-ac047a083276',
    'bb0e5aed-a647-48f0-b625-80038c3a2cdf',
    'd446e6a4-14a8-4e15-8646-5b8e2906adf3',
    'ef15a84d-4edf-4d20-9eef-3cee7b315f10',
    '36db369a-8c74-440f-b561-455262867050'
  ]::uuid[];
  v_max int := security.pipeline_num_v1('entry.course_batch_size', 50)::int;
  v_ids uuid[]; v_c uuid; v_job uuid; v_n int := 0; v_est numeric; v_bal numeric; v_floor numeric;
begin
  select array_agg(e.course_id order by e.course_id) into v_ids
    from security.course_entry_eligible_v1() e
   where e.provider_id = any (v_providers)
     and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = e.course_id and g.status = 'bound' and g.evidence_id is not null)
     and exists (select 1 from pipeline.field_enrich_items f where f.course_id = e.course_id and f.field = 'entry_requirements' and f.state = 'failed')
     and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = e.course_id and f.field = 'entry_requirements' and f.state <> 'failed')
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = e.course_id);
  if v_ids is null then raise notice 's1114: no failed course read to read again'; return; end if;
  if cardinality(v_ids) > v_max then raise exception 'guard: % courses exceed the batch size setting %', cardinality(v_ids), v_max; end if;
  if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'AI reading is stopped (AI limits)'; end if;
  v_est := cardinality(v_ids) * security.course_entry_cost_v1();
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is null or v_bal - v_est < v_floor then raise exception 'the estimate would take the OpenRouter balance below its floor'; end if;
  foreach v_c in array v_ids loop
    v_job := security.course_entry_read_enqueue_v1(v_c, v_pa, 'S2-AER s1114 (Admin #1054): earlier course read failed (held_partial or no answer recorded); read again from the stored page');
    v_n := v_n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'course_reread', 'migration s1114', jsonb_build_object('courses', v_n, 'estimate_usd', round(v_est, 4), 'balance_usd', v_bal, 'floor_usd', v_floor), v_pa);
  raise notice 's1114: % courses queued, estimate US$%', v_n, round(v_est, 4);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1114_locks) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
