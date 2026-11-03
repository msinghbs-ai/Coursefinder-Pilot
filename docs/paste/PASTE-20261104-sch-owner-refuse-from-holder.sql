-- CF-247 ownership of held scholarships on directory pages (handover 3 Nov 2026 Priority 3 item 10). APPROVED: Platform Admin decision D4,
-- overnight mandate 3 Nov 2026 21:59 ("refuse the 21 held scholarships from their incorrect current providers, preserving evidence and history;
-- do not declare the underlying scholarships invalid or silently reassign them"). Submitted by the Integration Controller.
-- Evidence (pipeline.scholarship_owner_proposals, recorded by the auto remedy sch_owner_proposals of migration 20261104210000): each page is a
-- state-government listing page (coursesearch.studymelbourne.vic.gov.au 12, search.studyqueensland.qld.gov.au 9), now listed as a directory site;
-- every candidate of the five holders (Lexis TESOL 9, Marriott Academy 5, Kangaroo International College 3, Prime Education Group 3, Victorian
-- Skills College 1) is on a portal host, found by site search (map_search), not on the holder's own site. No page names the holder.
-- Effect: each held item is refused from its current holder in Layer 4 (security.scholarship_ai_review_apply_v1, 'refuse'): its candidate is marked rejected, refused_by_person,
-- with the proposal as the reason. The scholarship is not declared invalid; its page copies, extractions, evidence and the proposal stay as
-- history. Nothing is reassigned to another provider and nothing is admitted or published. Where the page names an
-- institution, that institution's own page is the source; RMIT University already holds "RMIT UP General English Bursary for Asia" and Bond
-- University holds "Bond University Postgraduate Research Scholarship". Unresolved names (ACU, MACC, VU, QUT College, NTG and generic titles) are
-- for the scholarship coverage owner (workstream C), not this file.
-- PASTE FILE. Not applied by any migration. Run after migration 20261104210000 is deployed and its owner check has run. Decides exactly 21 held items.
-- Nothing is deleted. Rollback: none by paste (a refusal is a Layer 4 decision; a person may re-open an item by reading it again).
begin;
do $$
declare v_n int; r record;
  v_by uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin account (decided_by of 2,004 held-item decisions)
  v_refs bigint[] := array[1172, 1173, 1174, 1175, 1851, 1854, 1855, 1859, 1867, 1176, 1177, 1287, 1889, 1893, 1894, 1861, 1868, 1869, 1881, 1882, 1897];
begin
  if to_regclass('pipeline.scholarship_owner_proposals') is null then raise exception 'migration 20261104210000 is not deployed; nothing changed'; end if;
  perform security.scholarship_owner_check_v1(security.pipeline_num_v1('batch.scholarship_owner_check', 200)::int);
  select count(*) into v_n from pipeline.scholarship_owner_proposals o join pipeline.scholarship_ai_reviews rv on rv.id = o.review_id
   where o.review_id = any (v_refs) and o.state = 'proposed' and o.proposed_action = 'refuse_from_holder' and rv.status = 'pending' and security.third_party_host_v1(rv.url)
     and rv.provider_id in ('159328df-fb4b-4bb8-a6b8-5f24546437a3', '23d6f63d-c91b-4652-bb81-e853a27cdbf0', '65fee2d5-61b7-4383-aeda-ac27fb87f99b',
                            '1bdef519-6927-4765-8a06-632d396fa2ae', '38c8fb5a-6c00-4073-940d-4bcb8e4b7b33');
  if v_n <> 21 then raise exception 'guard: % of the 21 held items have an open proposal, are pending, on a directory page and under the five holders; nothing changed', v_n; end if;
  if (select count(*) from pipeline.scholarship_owner_proposals where state = 'proposed') <> 21 then raise exception 'guard: the open proposals are not exactly these 21; nothing changed'; end if;
  for r in select o.review_id, o.host, o.named, o.owner_candidates, o.evidence->>'holder' holder from pipeline.scholarship_owner_proposals o where o.review_id = any (v_refs) order by o.review_id loop
    perform security.scholarship_ai_review_apply_v1(r.review_id, 'refuse', null,
      'Not this provider''s scholarship: a state-government listing page (' || r.host || ') held under ' || r.holder || ', which the page does not name'
      || case when jsonb_array_length(r.owner_candidates) > 0 then '; the page names ' || (r.owner_candidates->0->>'name') || ', whose own page is the source' else '' end
      || '. Platform Admin decision D4, overnight mandate 3 Nov 2026 21:59; submitted by the Integration Controller.', v_by);
  end loop;
  perform security.scholarship_owner_check_v1(security.pipeline_num_v1('batch.scholarship_owner_check', 200)::int);
  select count(*) into v_n from pipeline.scholarship_ai_reviews where id = any (v_refs) and status = 'refused' and decided_by = v_by;
  if v_n <> 21 then raise exception 'guard: % of 21 refused; rolled back', v_n; end if;
  select count(*) into v_n from pipeline.scholarship_owner_proposals where review_id = any (v_refs) and state = 'decided';
  if v_n <> 21 then raise exception 'guard: % of 21 proposals closed; rolled back', v_n; end if;
  raise notice 'refused 21 held items from their holders; 21 proposals closed';
end $$;
commit;
