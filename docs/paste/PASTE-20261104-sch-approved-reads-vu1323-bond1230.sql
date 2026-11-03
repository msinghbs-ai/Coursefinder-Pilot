-- CF-247 approved scholarship reads (handover 3 Nov 2026 Priority 3 item 9; approved by the Platform Admin 3 Nov 2026 19:34, Firecrawl allowance
-- 19:23 "keep on using firecrawl credit as you need it, keep storing the page as above layers does as evidence"): exactly two held items.
--   VU   ref 1323  candidate 7700  https://www.vu.edu.au/bachelor-of-it-professional-placement-scholarship-application   normal read (no stored copy is held)
--   Bond ref 1230  candidate 6712  https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship FRESH read (the 29 Sep 2026 copy is not reused)
-- Each request queues ONE row on the normal scholarship AI path (security.scholarship_read_request_v1, migration 20261104160000). The worker reads
-- the page through svc_fc_spend (1 Firecrawl credit each) and the scholarship model chain (about US$0.001 each), and stores it as evidence
-- (pipeline.evidence_artifacts, scholarship_ai_page). Nothing is admitted or published: the answer is attached to the held item in Layer 4, where
-- the decision stays. A page that cannot be read ends the request at once (one credit, no retry).
-- The allowance scholarship.single_read_daily_max is set to 2 for these two requests and returned to 0 in the same transaction.
-- PASTE FILE. Not applied by any migration. Run after migration 20261104160000 is deployed. Writes 2 requests and 2 queue rows. Nothing is deleted.
-- Rollback (before the worker takes them, within about a minute): update pipeline.scholarship_ai_queue set state = 'failed', skip_reason = 'withdrawn'
--   where read_request_id in (<the two request ids returned>) and state = 'queued'; and the requests to state 'refused'.
begin;
do $$
declare v_n int; a jsonb; b jsonb;
begin
  if to_regprocedure('security.scholarship_read_request_v1(bigint,boolean,text,text)') is null then raise exception 'migration 20261104160000 is not deployed; nothing changed'; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_ai_next(integer)'::regprocedure)) <> '709ad0f93b16e99f8962e85671f0b291'
     or md5(pg_get_functiondef('security.scholarship_ai_has_copy_v1(bigint)'::regprocedure)) <> 'ecc54cd39a4fb9fc9c4c2217f6548d30'
     or md5(pg_get_functiondef('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'::regprocedure)) <> 'b2fafccb2532afc3e0d1337588b5c43d' then
    raise exception 'guard: the read path is not the 20261104160000 release (fresh reads and the Layer 4 hand-off); nothing changed';
  end if;
  select count(*) into v_n from pipeline.scholarship_ai_reviews r
   where (r.id, r.candidate_id, r.provider_id) in ((1323, 7700, 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid), (1230, 6712, '739948f6-6338-4ee9-8d0c-a8c8e953c29d'::uuid)) and r.status = 'pending';
  if v_n <> 2 then raise exception 'guard: % of the 2 held items are pending with the expected candidate and provider; nothing changed', v_n; end if;
  select count(*) into v_n from pipeline.scholarship_owner_proposals where review_id in (1323, 1230) and state = 'proposed';
  if v_n <> 0 then raise exception 'guard: an owner proposal is open for one of the items; nothing changed'; end if;
  select count(*) into v_n from pipeline.scholarship_ai_queue where candidate_id in (7700, 6712) and state in ('queued', 'leased');
  if v_n <> 0 then raise exception 'guard: a read of one of the items is already queued; nothing changed'; end if;
  if security.pipeline_num_v1('scholarship.single_read_daily_max', 0) <> 0 then raise exception 'guard: the single-read allowance is not at its shipped value 0; nothing changed'; end if;

  update pipeline.platform_toolset_settings set value = to_jsonb(2), updated_at = now(),
         reason = 'Platform Admin 3 Nov 2026 19:34: approved reads VU 1323 and Bond 1230 only (paste PASTE-20261104-sch-approved-reads-vu1323-bond1230)'
   where toolset_key = 'pipeline' and key = 'scholarship.single_read_daily_max';
  a := security.scholarship_read_request_v1(1323, false, 'Approved read of held scholarship VU ref 1323 through the scholarship acquisition path; evidence stored as normal',
                                             'Platform Admin, 3 Nov 2026 19:34 (handover Priority 3 item 9; Firecrawl decision 19:23)');
  b := security.scholarship_read_request_v1(1230, true, 'Approved FRESH read of held scholarship Bond ref 1230 (the stored copy of 29 Sep 2026 is not reused); round applicability to be checked by a person',
                                             'Platform Admin, 3 Nov 2026 19:34 (handover Priority 3 item 9; Firecrawl decision 19:23)');
  if coalesce(a->>'ok', '') <> 'true' or coalesce(b->>'ok', '') <> 'true' then raise exception 'guard: a request was refused (VU %, Bond %); rolled back', a, b; end if;
  select count(*) into v_n from pipeline.scholarship_ai_queue q join pipeline.scholarship_read_requests r on r.id = q.read_request_id and r.queue_id = q.id
   where r.id in ((a->>'request')::bigint, (b->>'request')::bigint) and q.state = 'queued';
  if v_n <> 2 then raise exception 'guard: % queue rows bound to the 2 requests, expected 2; rolled back', v_n; end if;
  if not (select fresh_read from pipeline.scholarship_ai_queue where id = (b->>'queue_id')::bigint) then raise exception 'guard: the Bond row is not fresh; rolled back'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(0), updated_at = now(),
         reason = 'Returned to 0 after the two approved reads were queued (PASTE-20261104-sch-approved-reads-vu1323-bond1230)'
   where toolset_key = 'pipeline' and key = 'scholarship.single_read_daily_max';
  raise notice 'queued: VU request % (queue %), Bond request % (queue %, fresh)', a->>'request', a->>'queue_id', b->>'request', b->>'queue_id';
end $$;
commit;

-- After about 5 minutes (read only): the outcome of each request, the evidence and the held items
select r.id, r.review_id, r.fresh, r.state, r.queue_id, r.outcome->>'storage_path' copy, r.outcome->>'evidence_id' evidence, r.outcome->>'error' error,
       r.outcome->>'audience' audience, r.outcome->>'audience_quote' audience_quote, r.outcome->>'offered' offered, r.outcome->>'offered_quote' offered_quote,
       r.outcome->>'dates_quote' dates_quote, r.outcome->>'open_date' open_date, r.outcome->>'close_date' close_date, r.outcome->'value' value
  from pipeline.scholarship_read_requests r where r.review_id in (1323, 1230) order by r.id;
select id, status, reason, storage_path, extraction_ids from pipeline.scholarship_ai_reviews where id in (1323, 1230);
select purpose, provider_id, units, url, at from pipeline.coverage_vendor_usage where url in
  ('https://www.vu.edu.au/bachelor-of-it-professional-placement-scholarship-application', 'https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship')
   and at > now() - interval '1 hour';
