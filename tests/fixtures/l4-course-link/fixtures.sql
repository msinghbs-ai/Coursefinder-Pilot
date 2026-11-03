-- CF-247 Layer 4 course link: every case after the migration (seed.sql). Each block raises on failure and prints "<id> ok".
create temporary table fx_before as
  select (select md5(string_agg(entity || entity_id || field || coalesce(mode, ''), '|' order by entity, entity_id, field)) from pipeline.manual_locks) locks;

-- K1 the kinds: course link keeps its three choices word for word and gains Refuse this proposal; held scholarship gains the duplicate route;
-- Course page needed is a kind with its three choices
do $f$
declare k jsonb := security.layer4_inbox_kinds_v1();
begin
  if (select string_agg(c->>'key' || '=' || (c->>'label'), '|' order by n) from jsonb_array_elements(k->'course_link'->'choices') with ordinality x(c, n))
     <> 'keep=Keep the page we hold|use=Use the new page|enter=Enter another address|refuse=Refuse this proposal' then raise exception 'K1: course link choices %', k->'course_link'; end if;
  if (select string_agg(c->>'key', ',' order by n) from jsonb_array_elements(k->'held_scholarship'->'choices') with ordinality x(c, n)) <> 'publish,not_international,not_scholarship,duplicate'
     or (select c->>'input' from jsonb_array_elements(k->'held_scholarship'->'choices') c where c->>'key' = 'duplicate') <> 'scholarship' then raise exception 'K1: scholarship choices'; end if;
  if k->'course_page_needed'->>'label' <> 'Course page needed'
     or (select string_agg(c->>'key', ',' order by n) from jsonb_array_elements(k->'course_page_needed'->'choices') with ordinality x(c, n)) <> 'add_page,search_again,no_page' then raise exception 'K1: page needed'; end if;
  if (select count(*) from jsonb_object_keys(k)) <> 19 then raise exception 'K1: % kinds', (select count(*) from jsonb_object_keys(k)); end if;
  raise notice 'K1 ok: course link keeps keep/use/enter word for word and adds Refuse this proposal; held scholarship adds the duplicate route; Course page needed has its three choices';
end $f$;

-- E1 evidence on arrival: a new official-link item gets the newest stored copy of its page however written; a kind not listed does not; off: none
do $f$
begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, layer2_state, status)
  values ('20000000-0000-0000-0000-000000000001', 'course', 'c0000000-0000-0000-0000-000000000003', 'official_course_url', '{"course_url": "http://www.canberra.edu.au/course/c3/"}', '{}', 'pending'),
         ('20000000-0000-0000-0000-000000000002', 'course', 'c0000000-0000-0000-0000-000000000003', 'course_english', '{"url": "https://canberra.edu.au/course/c3"}', '{}', 'pending');
  if (select evidence_id from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000001') is distinct from 'e0000000-0000-0000-0000-000000000003'::uuid then raise exception 'E1: not linked'; end if;
  if (select evidence_id from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000002') is not null then raise exception 'E1: a kind not listed was linked'; end if;
  update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, layer2_state, status)
  values ('20000000-0000-0000-0000-000000000003', 'course', 'c0000000-0000-0000-0000-000000000003', 'official_course_url', '{"course_url": "https://canberra.edu.au/course/c3"}', '{}', 'superseded');
  if (select evidence_id from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000003') is not null then raise exception 'E1: off'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';
  if security.layer4_stored_copy_v1('https://canberra.edu.au/course/c1/') <> 'e0000000-0000-0000-0000-000000000002' then raise exception 'E1: newest copy'; end if;
  raise notice 'E1 ok: linked on arrival (http/www/slash written differently; newest copy); a kind not listed and the switch off link nothing';
end $f$;

-- E2 the backfill: counts first, then links only items without a copy (audited); a second call links nothing
do $f$
declare r jsonb;
begin
  r := security.layer4_evidence_backfill_v1(100, false);
  if (r->>'linkable')::int <> 5 or (r->>'linked')::int <> 0 or exists (select 1 from pipeline.admin_control_events where action = 'evidence_backfill') then raise exception 'E2: dry run %', r; end if;
  r := security.layer4_evidence_backfill_v1(100, true);
  if (r->>'linked')::int <> 5 or (select evidence_id from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000001') <> 'e0000000-0000-0000-0000-000000000002'
     or (select evidence_id from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000010') <> 'e0000000-0000-0000-0000-000000000010' then raise exception 'E2: apply %', r; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000010') <> 'pending' then raise exception 'E2: status changed'; end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'evidence_backfill') then raise exception 'E2: audit'; end if;
  if (security.layer4_evidence_backfill_v1(100, true)->>'linked')::int <> 0 then raise exception 'E2: second call'; end if;
  raise notice 'E2 ok: dry run counts 5 (3 have no stored copy); apply links 5 (items stay waiting; audited); a second call links nothing';
end $f$;

-- E3 a fee hold card shows the stored copy of the course's bound page; W1 wording: no CRICOS for a Canadian provider, unchanged for Australia
do $f$
declare d jsonb; w text;
begin
  select i.detail into d from security.layer4_inbox_items_v1() i where i.kind = 'fee_check' and i.ref = '9001';
  if d->>'evidence_id' <> 'e0000000-0000-0000-0000-000000000030' or d->>'source_url' <> 'https://canberra.edu.au/course/c30' then raise exception 'E3: %', d; end if;
  select i.why, i.detail into w, d from security.layer4_inbox_items_v1() i where i.ref = '10000000-0000-0000-0000-000000000020';
  if w ilike '%CRICOS%' or w <> 'The course page that shows this course''s code is a different address from the official page we hold. Please check which page is current.' or d->>'code_label' <> 'Course code' then
    raise exception 'W1: %', w; end if;
  select i.why, i.detail into w, d from security.layer4_inbox_items_v1() i where i.ref = '10000000-0000-0000-0000-000000000010';
  if w not like '%this course''s CRICOS code%' or d->>'code_label' <> 'CRICOS' then raise exception 'W1: AU %', w; end if;
  raise notice 'E3 ok: the fee hold card carries the stored copy of the bound page';
  raise notice 'W1 ok: Canadian reason says "this course''s code" (label Course code); Australian reason unchanged (label CRICOS)';
end $f$;

-- P1 the refusal route: no held page -> Course page needed, no review item; a held page -> review item as before; switch off -> as before
do $f$
declare r text; n int := (select count(*) from pipeline.layer4_review_items);
begin
  r := security.binding_refusal_route_v1('c0000000-0000-0000-0000-000000000006', 'https://canberra.edu.au/course/c6-flyer.pdf', '{"reason": "it is a flyer", "rule": "not_page"}', 'firecrawl_search', null);
  if r <> 'page_needed' or (select count(*) from pipeline.layer4_review_items) <> n then raise exception 'P1: %', r; end if;
  if not exists (select 1 from pipeline.page_rejections where course_id = 'c0000000-0000-0000-0000-000000000006' and url = 'https://canberra.edu.au/course/c6-flyer.pdf') then raise exception 'P1: refusal not recorded'; end if;
  if (select state || ':' || refused || ':' || last_refused_lane from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'open:1:firecrawl_search' then raise exception 'P1: list'; end if;
  r := security.binding_refusal_route_v1('c0000000-0000-0000-0000-000000000011', 'https://canberra.edu.au/course/c11-other', '{"reason": "another level"}', 'title_search', null);
  if r <> 'pending_item_kept' then raise exception 'P1: pending first %', r; end if;
  insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values ('c0000000-0000-0000-0000-000000000007', 'official_course', 'https://canberra.edu.au/course/c7-held', true, 'active');
  r := security.binding_refusal_route_v1('c0000000-0000-0000-0000-000000000007', 'https://canberra.edu.au/course/c7-other', '{"reason": "another level"}', 'title_search', null);
  if r <> 'item_created' then raise exception 'P1: held page %', r; end if;
  update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.page_needed_on';
  r := security.binding_refusal_route_v1('c0000000-0000-0000-0000-000000000008', 'https://canberra.edu.au/course/c8-x', '{"reason": "another level"}', 'title_search', null);
  if r <> 'item_created' or exists (select 1 from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000008') then raise exception 'P1: off %', r; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.page_needed_on';
  raise notice 'P1 ok: no held page -> Course page needed (refusal recorded, no item); a waiting item is kept; a held page -> item; off -> item';
end $f$;

-- P2 converting a university: only refusals with no held page and a recorded refusal move (item superseded with the reason, history kept);
-- a claimed item and a held-page dispute stay; counts first; a curator cannot run it
do $f$
declare r jsonb; v_n int := (select count(*) from pipeline.layer4_review_items);
begin
  perform set_config('fx.uid', '90000000-0000-0000-0000-0000000000bb', false); perform set_config('fx.rank', '3', false);
  begin perform security.course_page_needed_convert_v1('0e1532b8-de30-4761-87fe-460684608633', 100, true); raise exception 'P2: a curator converted';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  r := security.course_page_needed_convert_v1('0e1532b8-de30-4761-87fe-460684608633', 100, false);
  -- the refusal raised while the switch was off (P1, course 8) is a refusal with no held page too
  if (r->>'moved')::int <> 2 or exists (select 1 from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000001' and status <> 'pending') then raise exception 'P2: dry %', r; end if;
  r := security.course_page_needed_convert_v1('0e1532b8-de30-4761-87fe-460684608633', 100, true);
  raise notice 'P2 %', r;
  if (r->>'moved')::int <> 2 or r->'kept_in_layer4'->>'claimed_by_reviewer' <> '1' or r->'kept_in_layer4'->>'held_page_when_raised' is null then raise exception 'P2: %', r; end if;
  if (select status || ':' || change_control_ref from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000001') not like 'superseded:%moved to Course page needed%' then raise exception 'P2: item'; end if;
  if (select converted_items from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000001') <> array['10000000-0000-0000-0000-000000000001'::uuid] then raise exception 'P2: list'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000005') <> 'pending'
     or (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000004') <> 'pending' then raise exception 'P2: a claimed item or a dispute moved'; end if;
  if (select count(*) from pipeline.layer4_review_items) <> v_n then raise exception 'P2: rows deleted or added'; end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'page_needed_convert') then raise exception 'P2: audit'; end if;
  raise notice 'P2 ok: two refusals moved (superseded with the reason; listed with its item); claimed and held-page items stay; curator refused; audited';
end $f$;

-- P3 the list in Layer 4: grouped by university like every kind; Add the page, Search again (bounded), No page exists (evidence required)
do $f$
declare r jsonb; v_n int;
begin
  perform set_config('fx.uid', '90000000-0000-0000-0000-0000000000aa', false); perform set_config('fx.rank', '6', false);
  r := public.admin_layer4_inbox('universities', jsonb_build_object('kind', 'course_page_needed'));
  if (r->>'total')::int <> 1 or (r->'items'->0->'by_kind'->>'course_page_needed')::int <> 3 then raise exception 'P3: grouping %', r; end if;
  r := public.admin_layer4_inbox('items', jsonb_build_object('kind', 'course_page_needed'));
  if (r->>'total')::int <> 3 or (select count(*) from jsonb_array_elements(r->'items') x where x->'detail'->>'evidence_id' = 'e0000000-0000-0000-0000-000000000002') <> 1 then raise exception 'P3: items %', r; end if;
  -- search again, bounded by layer4.page_needed_search_max
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.page_needed_search_max';
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_page_needed', 'ref', 'c0000000-0000-0000-0000-000000000006', 'choice', 'search_again', 'reason', 'try the handbook'));
  if (select stage || ':' || state from pipeline.course_link_search where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'cricos:queued'
     or (select state from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'search_requested' then raise exception 'P3: search %', r; end if;
  -- the next refusal brings it back; a second search is refused at the limit
  perform security.binding_refusal_route_v1('c0000000-0000-0000-0000-000000000006', 'https://canberra.edu.au/course/c6-other', '{"reason": "another level"}', 'cricos_search', null);
  if (select state || ':' || refused from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'open:2' then raise exception 'P3: reopen'; end if;
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_page_needed', 'ref', 'c0000000-0000-0000-0000-000000000006', 'choice', 'search_again', 'reason', 'again please'));
    raise exception 'P3: the search limit was passed';
  exception when raise_exception then if sqlerrm not like 'another search was already asked for 1 times%' then raise; end if;
  end;
  -- no page exists: evidence address and a reason are required
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_page_needed', 'ref', 'c0000000-0000-0000-0000-000000000006', 'choice', 'no_page', 'reason', 'none', 'value', 'https://canberra.edu.au/courses'));
    raise exception 'P3: a short reason passed';
  exception when raise_exception then if sqlerrm not like 'say what that page shows%' then raise; end if;
  end;
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_page_needed', 'ref', 'c0000000-0000-0000-0000-000000000006', 'choice', 'no_page',
         'reason', 'The course list shows it only as a major inside another degree', 'value', 'https://canberra.edu.au/courses'));
  if (select state || ':' || (basis->>'evidence_url') from pipeline.course_no_page where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'confirmed:https://canberra.edu.au/courses'
     or (select state from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'no_page_exists' then raise exception 'P3: no page'; end if;
  -- add the page: the course edit sets it as a person's value; the course leaves the list
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_page_needed', 'ref', 'c0000000-0000-0000-0000-000000000001', 'choice', 'add_page',
         'reason', 'Checked on the university site', 'value', 'https://canberra.edu.au/course/c1-own'));
  if not exists (select 1 from catalogue.course_links where course_id = 'c0000000-0000-0000-0000-000000000001' and url = 'https://canberra.edu.au/course/c1-own' and status = 'active')
     or (select state from pipeline.course_page_needed where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'page_added' then raise exception 'P3: add page'; end if;
  select count(*) into v_n from security.layer4_inbox_items_v1() i where i.kind = 'course_page_needed';
  if v_n <> 1 then raise exception 'P3: % listed (course 8 waits)', v_n; end if;
  if (select count(*) from pipeline.admin_control_events where action = 'inbox_decide' and detail->>'kind' = 'course_page_needed') <> 3 then raise exception 'P3: audit'; end if;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  raise notice 'P3 ok: grouped by university with the stored copy; search again queues the existing search (bounded; reopens on the next refusal); no page needs evidence; add page sets a person''s value';
end $f$;

-- R1 Refuse this proposal: the page is recorded as refused and the item closes as rejected; a fee item cannot be refused this way
do $f$
declare r jsonb;
begin
  perform set_config('fx.uid', '90000000-0000-0000-0000-0000000000aa', false); perform set_config('fx.rank', '4', false);
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_link', 'ref', '10000000-0000-0000-0000-000000000011', 'choice', 'refuse', 'reason', 'A scholarship page, not the course'));
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000011') <> 'rejected'
     or not exists (select 1 from pipeline.page_rejections where course_id = 'c0000000-0000-0000-0000-000000000011' and url = 'https://www.canberra.edu.au/scholarship/x' and source = 'layer4_refuse')
     or (select action from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000011') <> 'reject' then raise exception 'R1: %', r; end if;
  if not exists (select 1 from catalogue.course_links where course_id = 'c0000000-0000-0000-0000-000000000011' and status = 'active') then raise exception 'R1: the held page changed'; end if;
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'course_link', 'ref', '10000000-0000-0000-0000-000000000030', 'choice', 'refuse', 'reason', 'not the fee'));
    raise exception 'R1: a fee item was refused as a page';
  exception when raise_exception then if sqlerrm not like 'this item is a fee%' then raise; end if;
  end;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  raise notice 'R1 ok: refused page recorded (layer4_refuse), item rejected through the existing decision, held page untouched; a fee item is refused';
end $f$;

-- D1 duplicate route: only a published, active scholarship of the same provider; the held review is refused naming it; the link recorded
do $f$
declare r jsonb;
begin
  perform set_config('fx.uid', '90000000-0000-0000-0000-0000000000aa', false); perform set_config('fx.rank', '4', false);
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'held_scholarship', 'ref', '1184', 'choice', 'duplicate', 'reason', 'same scholarship', 'value', 'a3470000-0000-0000-0000-000000000003'));
    raise exception 'D1: another provider''s scholarship was accepted';
  exception when raise_exception then if sqlerrm not like 'that is not a published, active scholarship of the same provider%' then raise; end if;
  end;
  begin
    perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'held_scholarship', 'ref', '1184', 'choice', 'duplicate', 'reason', 'same scholarship', 'value', 'a3470000-0000-0000-0000-000000000002'));
    raise exception 'D1: the held one itself was accepted';
  exception when raise_exception then if sqlerrm not like 'that is not a published%' then raise; end if;
  end;
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'held_scholarship', 'ref', '1184', 'choice', 'duplicate', 'reason', 'Same title, provider and value; official page one-off', 'value', 'a3470000-0000-0000-0000-000000000001'));
  if (select status || ':' || note from pipeline.scholarship_ai_reviews where id = 1184) not like 'refused:Duplicate of published scholarship a3470000-0000-0000-0000-000000000001 (%'
     or (select duplicate_of from pipeline.scholarship_duplicate_closures where review_id = 1184) <> 'a3470000-0000-0000-0000-000000000001' then raise exception 'D1: %', r; end if;
  if (select publication_status from scholarship.scholarships where id = 'a3470000-0000-0000-0000-000000000001') <> 'published' then raise exception 'D1: the published one changed'; end if;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  raise notice 'D1 ok: wrong provider and the held record refused; the duplicate closes the review naming the published one; nothing on it changes';
end $f$;

-- V1 rule validation: pass or fail per item with reasons (Canberra shape); nothing is decided
do $f$
declare v text; n_pending int := (select count(*) from pipeline.layer4_review_items where status = 'pending');
begin
  for v in select x.item_id || ' ' || x.pass || ' ' || array_to_string(x.reasons, '; ') from security.layer4_course_link_rule_validate_v1('canberra_no_year') x order by x.item_id loop raise notice 'V1 %', v; end loop;
  if (select pass from security.layer4_course_link_rule_validate_v1('canberra_no_year') where item_id = '10000000-0000-0000-0000-000000000010') is not true then raise exception 'V1: c10 should pass'; end if;
  if (select array_to_string(reasons, '; ') from security.layer4_course_link_rule_validate_v1('canberra_no_year') where item_id = '10000000-0000-0000-0000-000000000012')
     <> 'stored copy identity basis exact_title is not an exact-course basis' then raise exception 'V1: c12'; end if;
  if (select array_to_string(reasons, '; ') from security.layer4_course_link_rule_validate_v1('canberra_no_year') where item_id = '10000000-0000-0000-0000-000000000013')
     <> 'no stored copy of the proposed page; manual lock on the official page' then raise exception 'V1: c13 %', (select reasons from security.layer4_course_link_rule_validate_v1('canberra_no_year') where item_id = '10000000-0000-0000-0000-000000000013'); end if;
  if exists (select 1 from security.layer4_course_link_rule_validate_v1('canberra_no_year') where item_id = '10000000-0000-0000-0000-000000000011') then raise exception 'V1: a decided item validated'; end if;
  if (select count(*) from pipeline.layer4_review_items where status = 'pending') <> n_pending then raise exception 'V1: something was decided'; end if;
  if (select count(*) from pipeline.layer4_course_link_rules) <> 3 then raise exception 'V1: rules'; end if;
  raise notice 'V1 ok: the rule validates per item (pass; identity basis; no copy and manual lock); decided items are left out; nothing decided';
end $f$;

-- C1 search spend against refusals, by lane
do $f$
declare r jsonb := security.layer4_refusal_search_cost_v1(7);
begin
  raise notice 'C1 %', r;
  if (select (l->>'purpose_credits')::numeric from jsonb_array_elements(r->'lanes') l where l->>'lane' = 'firecrawl_search') <> 4
     or (select (l->>'refusals')::int from jsonb_array_elements(r->'lanes') l where l->>'lane' = 'firecrawl_search') < 1 then raise exception 'C1'; end if;
  raise notice 'C1 ok: Firecrawl credits of the lanes that feed refusals, beside the refusals they raised';
end $f$;

-- the rule executor's cases (Simon Fraser, Adelaide and a refused-decision item), raised as they were before this change
-- rule executor cases: Simon Fraser (strict: level and current copy) and Adelaide (keep the held page); a Canberra item whose decision the
-- existing apply refuses (a social-site address), so it must stay waiting
update catalogue.courses set provider_id = 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0', course_code = '115900H' where id = 'c0000000-0000-0000-0000-000000000023';
insert into pipeline.evidence_artifacts(id, source_id, source_url, content_hash, captured_at, metadata) values
 ('e0000000-0000-0000-0000-000000000021', 'b0000000-0000-0000-0000-000000000001', 'https://www.sfu.ca/students/calendar/programs/c21/ma.html', 'h21', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000021", "identity_basis": "field_award"}'),
 ('e0000000-0000-0000-0000-000000000022', 'b0000000-0000-0000-0000-000000000001', 'https://www.sfu.ca/students/calendar/programs/c22/ba.html', 'h22', now() - interval '200 days', '{"course_id": "c0000000-0000-0000-0000-000000000022", "identity_basis": "field_award"}'),
 ('e0000000-0000-0000-0000-000000000023', 'b0000000-0000-0000-0000-000000000001', 'https://adelaide.edu.au/study/degrees/c23/', 'h23', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000023", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000014', 'b0000000-0000-0000-0000-000000000001', 'https://www.facebook.com/c14/7', 'h14', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000014", "identity_basis": "cricos_code"}');
insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values
 ('c0000000-0000-0000-0000-000000000021', 'official_course', 'https://www.sfu.ca/students/calendar/2026/fall/programs/c21/ma.html', true, 'active'),
 ('c0000000-0000-0000-0000-000000000022', 'official_course', 'https://www.sfu.ca/students/calendar/2026/fall/programs/c22/ba.html', true, 'active'),
 ('c0000000-0000-0000-0000-000000000023', 'official_course', 'https://adelaide.edu.au/study/degrees/c23/', true, 'active'),
 ('c0000000-0000-0000-0000-000000000014', 'official_course', 'https://www.facebook.com/c14/7/2027', true, 'active');
insert into fx.reference_hosts values ('www.facebook.com', 'not_course_page') on conflict do nothing;
insert into fx.page_levels values
 ('c0000000-0000-0000-0000-000000000020', 'https://www.sfu.ca/students/calendar/programs/c20/ba.html', '["bachelor"]', '["bachelor"]'),
 ('c0000000-0000-0000-0000-000000000021', 'https://www.sfu.ca/students/calendar/programs/c21/ma.html', '["bachelor"]', '["master"]'),
 ('c0000000-0000-0000-0000-000000000022', 'https://www.sfu.ca/students/calendar/programs/c22/ba.html', '["bachelor"]', '["bachelor"]');
update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, status, escalation_reason, created_at) values
 ('10000000-0000-0000-0000-000000000021', 'course', 'c0000000-0000-0000-0000-000000000021', 'official_course_url', '["https://www.sfu.ca/students/calendar/2026/fall/programs/c21/ma.html"]',
  '{"course_url": "https://www.sfu.ca/students/calendar/programs/c21/ma.html"}', '{"source": "coverage sweep"}', 'pending',
  'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days'),
 ('10000000-0000-0000-0000-000000000022', 'course', 'c0000000-0000-0000-0000-000000000022', 'official_course_url', '["https://www.sfu.ca/students/calendar/2026/fall/programs/c22/ba.html"]',
  '{"course_url": "https://www.sfu.ca/students/calendar/programs/c22/ba.html"}', '{"source": "coverage sweep"}', 'pending',
  'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days'),
 ('10000000-0000-0000-0000-000000000023', 'course', 'c0000000-0000-0000-0000-000000000023', 'official_course_url', '["https://adelaide.edu.au/study/degrees/c23/"]',
  '{"course_url": "https://adelaideuni.edu.au/study/degrees/c23/"}', '{"source": "coverage sweep"}', 'pending',
  'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days'),
 ('10000000-0000-0000-0000-000000000014', 'course', 'c0000000-0000-0000-0000-000000000014', 'official_course_url', '["https://www.facebook.com/c14/7/2027"]',
  '{"course_url": "https://www.facebook.com/c14/7"}', '{"source": "coverage sweep"}', 'pending',
  'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days');
update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';

-- X0 the ownership register in data: the migration opened the Integration Controller's rows for the three approved rules
do $f$
begin
  if (select count(*) from pipeline.layer4_review_owners where owner = 'claude' and closed_at is null) <> 3 then raise exception 'X0: owners'; end if;
  if (select string_agg(code || ':' || strict, ',' order by code) from pipeline.layer4_course_link_rules) <> 'adelaide_keep_held:false,canberra_no_year:false,sfu_no_term:true'
     or (select identity_bases from pipeline.layer4_course_link_rules where code = 'sfu_no_term') <> array['field_award'] then raise exception 'X0: rules'; end if;
  raise notice 'X0 ok: ownership rows for the three rules; Simon Fraser strict, field-and-award only';
end $f$;

-- X1 counting decides nothing: one Canberra item would be decided; title-only, lock and no-copy items fail with reasons
do $f$
declare r jsonb; n_dec int := (select count(*) from pipeline.layer4_decisions);
begin
  r := security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, false);
  raise notice 'X1 %', r;
  if (r->>'would_decide')::int <> 2 or (r->>'decided')::int <> 0 then raise exception 'X1: %', r; end if;
  if (select count(*) from pipeline.layer4_decisions) <> n_dec or exists (select 1 from pipeline.layer4_review_items where id in ('10000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000014') and status <> 'pending') then
    raise exception 'X1: something was decided'; end if;
  if (select outcome from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000012') <> 'failed' then raise exception 'X1: title-only'; end if;
  raise notice 'X1 ok: a count decides nothing; the title-only, locked and no-copy items fail with their reasons';
end $f$;

-- X2 the parallel reviewer's university, a claimed item and a curator are all refused at execution time
do $f$
declare r jsonb;
begin
  insert into pipeline.layer4_review_owners(provider_id, field_code, owner, scope, basis) values ('0e1532b8-de30-4761-87fe-460684608633', 'official_course_url', 'chatgpt', 'declared university', 'ownership register');
  r := security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, true);
  if (r->>'decided')::int <> 0 or (r->'failed_by_reason')::text not like '%university owned by the parallel reviewer%' then raise exception 'X2: owner %', r; end if;
  update pipeline.layer4_review_owners set closed_at = now() where owner = 'chatgpt';
  update pipeline.layer4_review_items set claimed_at = now() where id = '10000000-0000-0000-0000-000000000010';
  r := security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, true);
  if (select reasons from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000010') <> array['claimed by a reviewer'] then raise exception 'X2: claimed %', r; end if;
  update pipeline.layer4_review_items set claimed_at = null where id = '10000000-0000-0000-0000-000000000010';
  perform set_config('fx.uid', '90000000-0000-0000-0000-0000000000bb', false); perform set_config('fx.rank', '3', false);
  begin perform security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, false); raise exception 'X2: a curator ran it';
  exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  raise notice 'X2 ok: the parallel reviewer''s university, a claimed item and a curator are refused; nothing decided';
end $f$;

-- X3 applying: each item through the existing decision path under the system automation account, with the rule and approval reference; an item
-- whose decision the existing apply refuses stays waiting with that reason; a second run decides nothing more
do $f$
declare r jsonb; d record;
begin
  r := security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, true);
  raise notice 'X3 %', r;
  if (r->>'decided')::int <> 1 then raise exception 'X3: %', r; end if;
  select * into d from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000010';
  if d.action <> 'approve' or d.actor_id <> 'c0ffee00-0000-4000-8000-000000000150' or d.reason not like '[rule canberra_no_year] Use the new page.%Approved by Platform Admin (Platform Admin 3 Nov 2026 after 20:40%' then raise exception 'X3: decision %', d; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000010') <> 'approved'
     or not exists (select 1 from catalogue.course_links where course_id = 'c0000000-0000-0000-0000-000000000010' and url = 'https://www.canberra.edu.au/course/c10/7' and status = 'active' and is_primary) then raise exception 'X3: not applied'; end if;
  if (select decision_id from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000010') <> d.id then raise exception 'X3: run item'; end if;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000014') <> 'pending'
     or (select array_to_string(reasons, '; ') from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000014') not like 'decision refused: use the provider''s own course page%'
     or exists (select 1 from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000014') then raise exception 'X3: refused decision'; end if;
  if (select count(*) from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000010') <> 1 then raise exception 'X3: one decision'; end if;
  if auth.uid() is not null then raise exception 'X3: the caller identity was not restored'; end if;
  r := security.layer4_course_link_rule_execute_v1('canberra_no_year', 50, true);
  if (r->>'decided')::int <> 0 then raise exception 'X3: second run %', r; end if;
  raise notice 'X3 ok: decided through layer4_review_decide_impl (system account, rule and approval in the reason, link applied); a refused decision leaves the item waiting; second run decides nothing';
end $f$;

-- X4 Simon Fraser is strict: the course level on the page and a current stored copy; Adelaide keeps the held page (reject, link unchanged)
do $f$
declare r jsonb;
begin
  r := security.layer4_course_link_rule_execute_v1('sfu_no_term', 50, true);
  raise notice 'X4 %', r;
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000020') <> 'approved' then raise exception 'X4: c20'; end if;
  if (select array_to_string(reasons, '; ') from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000021')
     <> 'course level not verified on the page (course bachelor, page master)' then raise exception 'X4: c21'; end if;
  if (select array_to_string(reasons, '; ') from pipeline.layer4_rule_run_items where run_id = (r->>'run_id')::bigint and item_id = '10000000-0000-0000-0000-000000000022')
     <> 'stored copy is older than 90 days' then raise exception 'X4: c22'; end if;
  r := security.layer4_course_link_rule_execute_v1('adelaide_keep_held', 50, true);
  if (select status from pipeline.layer4_review_items where id = '10000000-0000-0000-0000-000000000023') <> 'rejected'
     or (select action from pipeline.layer4_decisions where review_item_id = '10000000-0000-0000-0000-000000000023') <> 'reject'
     or not exists (select 1 from catalogue.course_links where course_id = 'c0000000-0000-0000-0000-000000000023' and url = 'https://adelaide.edu.au/study/degrees/c23/' and status = 'active') then raise exception 'X4: adelaide %', r; end if;
  if (select count(*) from pipeline.layer4_rule_runs) < 6 or not exists (select 1 from pipeline.admin_control_events where action = 'rule_execute') then raise exception 'X4: audit'; end if;
  raise notice 'X4 ok: Simon Fraser decides only with the level verified and a current copy; Adelaide keeps the held page; every run audited';
end $f$;

-- Z1 no lock was removed or changed by any case except the person's own Add the page
do $f$
begin
  if exists (select 1 from pipeline.manual_locks l where l.entity_id = 'c0000000-0000-0000-0000-000000000013') is false then raise exception 'Z1: a lock went'; end if;
  if (select count(*) from pipeline.manual_locks where entity_id <> 'c0000000-0000-0000-0000-000000000001') <> 1 then raise exception 'Z1: locks changed'; end if;
  raise notice 'Z1 ok: the only lock added is the person''s own Add the page; no lock removed';
end $f$;
