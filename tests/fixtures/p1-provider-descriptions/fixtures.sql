-- P1 provider descriptions on isolated fixtures (CF-247 missing-field enrichment, Platform Admin 2 Nov 2026 10:28). Run by run.sh after the
-- migration; every block raises an exception on failure and a PASS notice on success. Nothing here is live data.
\set ON_ERROR_STOP 1
set fx.role = 'service_role';

-- providers: two Australian universities, a TAFE (out of scope), an unpublished university, a locked university
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU'), ('00000000-0000-0000-0000-0000000000a2', 'NZ');
insert into ref.provider_types(id, code, name) values ('00000000-0000-0000-0000-0000000000b1', 'university', 'University'), ('00000000-0000-0000-0000-0000000000b2', 'tafe_polytechnic', 'TAFE');
insert into catalogue.providers(id, stable_key, canonical_name, website, country_id, provider_type_id, publication_status) values
 ('10000000-0000-0000-0000-000000000001', 'provider:cricos:0000a', 'University of Alpha', 'https://www.alpha.edu.au', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'published'),
 ('10000000-0000-0000-0000-000000000002', 'provider:cricos:0000b', 'Beta University', 'https://beta.edu.au/', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'published'),
 ('10000000-0000-0000-0000-000000000003', 'provider:cricos:0000c', 'Gamma TAFE', 'https://gamma.tafe.edu.au', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2', 'published'),
 ('10000000-0000-0000-0000-000000000004', 'provider:cricos:0000d', 'Delta University', 'https://delta.edu.au', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'unpublished'),
 ('10000000-0000-0000-0000-000000000005', 'provider:cricos:0000e', 'Epsilon University', 'https://epsilon.edu.au', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'published'),
 ('10000000-0000-0000-0000-000000000006', 'provider:nzqa:6', 'Zeta University', 'https://zeta.ac.nz', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 'published');
insert into pipeline.manual_locks(entity, entity_id, field) values ('provider', '10000000-0000-0000-0000-000000000005', 'description');
-- a merged institution's second domain (binding.provider_host_aliases), as live
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', 'binding.provider_host_aliases', 'list', '["provider:cricos:0000a=alpha-old.edu.au"]')
on conflict (toolset_key, key) do update set value = excluded.value;

-- stored copies: Alpha's About page (own host), an About page of Beta stored under Alpha's source (refused), Alpha's fees page (not an About page)
insert into pipeline.sources(id, source_type, provider_id) values ('20000000-0000-0000-0000-000000000001', 'provider_course_page_sweep', '10000000-0000-0000-0000-000000000001');
insert into pipeline.evidence_artifacts(id, source_id, source_url, storage_path, content_hash, mime_type, captured_at) values
 ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about', 'layer2/AU/x/alpha-about.html.gz', 'h1', 'text/html', now() - interval '10 days'),
 ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'https://beta.edu.au/about', 'layer2/AU/x/beta-about.html.gz', 'h2', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/study/fees', 'layer2/AU/x/alpha-fees.html.gz', 'h3', 'text/html', now()),
 ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about-us', 'layer2/AU/x/alpha-about-old.html.gz', 'h4', 'text/html', now() - interval '800 days');

-- the answers a model could give (the worker sets on_page after checking each quote against the page)
create temp table ans(k text primary key, a jsonb);
insert into ans values
 ('good', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": true},
   {"text": "It offers undergraduate and postgraduate courses across health, engineering, business and the arts.", "quote": "We offer undergraduate and postgraduate courses across health, engineering, business and the arts.", "on_page": true},
   {"text": "Its main campus is in Crawley, close to the Swan River.", "quote": "Our main campus is in Crawley, close to the Swan River.", "on_page": true}]}'),
 ('claim', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": true},
   {"text": "It is ranked first in Australia for graduate employment and starting salaries.", "quote": "Our graduates go on to work in many fields around the world.", "on_page": true}]}'),
 ('claim_quoted', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": true},
   {"text": "Its engineering courses are accredited by Engineers Australia, as the university states.", "quote": "Our engineering courses are accredited by Engineers Australia.", "on_page": true}]}'),
 ('marketing', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a world-class public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": true},
   {"text": "It offers undergraduate and postgraduate courses across health, engineering, business and the arts.", "quote": "We offer undergraduate and postgraduate courses across health, engineering, business and the arts.", "on_page": true}]}'),
 ('unsupported', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": true},
   {"text": "It runs subsidised housing, free parking and a large sporting precinct beside the river.", "quote": "Our main campus is in Crawley, close to the Swan River.", "on_page": true}]}'),
 ('not_on_page', '{"about_page": true, "sentences": [
   {"text": "The University of Alpha is a public university in Perth, Western Australia, founded in 1911.", "quote": "The University of Alpha is a public university founded in 1911 in Perth, Western Australia.", "on_page": false},
   {"text": "It offers undergraduate and postgraduate courses across health, engineering, business and the arts.", "quote": "We offer undergraduate and postgraduate courses across health, engineering, business and the arts.", "on_page": true}]}'),
 ('not_about', '{"about_page": false, "sentences": []}');

-- 1 off by default: the setting, the job, the fire function, the lease and the queue
do $t$ declare v jsonb; begin
  if security.pipeline_num_v1('pdesc.enabled', 1) <> 0 then raise exception 'reader not off by default'; end if;
  if security.pipeline_num_v1('pdesc.acquire_direct', 1) <> 0 or security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0 then raise exception 'acquisition not off by default'; end if;
  if (select active from cron.job where jobname = 'provider-description-read') then raise exception 'job active by default'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'provider-description-read') then raise exception 'job not catalogued'; end if;
  if (select command from cron.job where jobname = 'provider-description-read') ~ '\(\s*\d|,\s*\d' then raise exception 'a number in the job command'; end if;
  v := security.provider_description_fire_v1(); if v->>'enabled' <> 'false' then raise exception 'fire ran while off: %', v; end if;
  v := public.svc_provider_description_next(3); if v->>'reason' <> 'off' then raise exception 'lease while off: %', v; end if;
  if security.provider_description_enqueue_v1() <> 0 or exists (select 1 from pipeline.provider_description_reads) then raise exception 'queued while off'; end if;
  raise notice 'PASS job off by default';
end $t$;

update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'pdesc.enabled';

-- 2 scope and bounded queue: universities of the countries only; unpublished and hand-locked providers are never queued; queue_per_run bounds it
do $t$ declare n int; begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'pdesc.queue_per_run';
  n := security.provider_description_enqueue_v1(); if n <> 1 then raise exception 'queue_per_run not honoured: %', n; end if;
  update pipeline.platform_toolset_settings set value = '10' where key = 'pdesc.queue_per_run';
  n := security.provider_description_enqueue_v1(); if n <> 1 then raise exception 'second run queued %', n; end if;
  if (select array_agg(provider_id order by provider_id) from pipeline.provider_description_reads) <> array['10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002']::uuid[] then
    raise exception 'wrong scope: %', (select array_agg(provider_id) from pipeline.provider_description_reads);
  end if;
  if security.provider_description_enqueue_v1() <> 0 then raise exception 'duplicate open read'; end if;
  raise notice 'PASS scope and bounded queue (type, country, unpublished, locked, one open read a provider)';
end $t$;

-- 3 stored copy reuse: Alpha's own About copy (not Beta's page under Alpha's source, not a fees page, not a copy older than the set age)
do $t$ declare v jsonb; it jsonb; r jsonb; begin
  if security.provider_description_stored_v1('10000000-0000-0000-0000-000000000001') <> '30000000-0000-0000-0000-000000000001' then raise exception 'stored copy not chosen'; end if;
  if security.provider_description_stored_v1('10000000-0000-0000-0000-000000000002') is not null then raise exception 'Beta has no copy of its own'; end if;
  -- acquisition off: only the provider with a stored copy is read; Beta waits
  v := public.svc_provider_description_next(50);
  if jsonb_array_length(v->'items') <> 1 or (v->>'acquire_direct')::boolean or (v->>'acquire_firecrawl')::boolean then raise exception 'lease with acquisition off: %', v; end if;
  if v->>'model' <> 'fixture/pinned-model' then raise exception 'not the pinned model'; end if;
  -- the central page finder's About suggestions are given to the worker, own hosts only, best first
  insert into pipeline.provider_central_search values ('10000000-0000-0000-0000-000000000002', '[
    {"kind": "about_page", "url": "https://beta.edu.au/about-us", "score": 6.6},
    {"kind": "about_page", "url": "https://www.alpha.edu.au/about", "score": 7},
    {"kind": "about_page", "url": "https://beta.edu.au/about-the-university/overview", "score": 2},
    {"kind": "fee_schedule", "url": "https://beta.edu.au/fees", "score": 6}]');
  update pipeline.platform_toolset_settings set value = '1' where key = 'pdesc.acquire_direct';
  v := jsonb_build_object('items', (v->'items') || (public.svc_provider_description_next(50)->'items'));
  if jsonb_array_length(v->'items') <> 2 then raise exception 'lease: %', v; end if;
  if (select x->'candidates' from jsonb_array_elements(v->'items') x where x->>'provider_id' = '10000000-0000-0000-0000-000000000002') <> '["https://beta.edu.au/about-us"]'::jsonb then
    raise exception 'candidates: %', v;
  end if;
  select x into it from jsonb_array_elements(v->'items') x where x->>'provider_id' = '10000000-0000-0000-0000-000000000001';
  if it->'stored'->>'evidence_id' <> '30000000-0000-0000-0000-000000000001' then raise exception 'stored copy not given to the worker: %', it; end if;
  if not (it->'hosts' ? 'alpha.edu.au' and it->'hosts' ? 'alpha-old.edu.au') then raise exception 'hosts: %', it->'hosts'; end if;
  r := public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', it->>'item_id', 'stored_evidence_id', '30000000-0000-0000-0000-000000000001',
         'answer', (select a from ans where k = 'good'), 'model', 'fixture/pinned-model', 'prompt_version', 'provider-description-v1', 'worker', 'fx', 'cost', 0.0021)));
  if r->>'proposed' <> '1' then raise exception 'not proposed: %', r; end if;
  if (select read_via || '|' || evidence_id || '|' || source_url from pipeline.provider_description_reads where provider_id = '10000000-0000-0000-0000-000000000001')
     <> 'stored|30000000-0000-0000-0000-000000000001|https://www.alpha.edu.au/about' then raise exception 'provenance not kept'; end if;
  if (select count(*) from pipeline.evidence_artifacts) <> 4 then raise exception 'a stored copy was registered again'; end if;
  raise notice 'PASS stored copy reuse (own host, About page, set age; provenance kept); acquisition off by default; About suggestions';
end $t$;

-- 4 proposal into Layer 4 without auto-admission; the projection shows nothing until a person approves
do $t$ declare i pipeline.layer4_review_items%rowtype; begin
  select * into i from pipeline.layer4_review_items where field_code = 'provider_description' and entity_id = '10000000-0000-0000-0000-000000000001';
  if i.id is null or i.status <> 'pending' or i.entity_type <> 'provider' or i.evidence_id <> '30000000-0000-0000-0000-000000000001' then raise exception 'item: %', to_jsonb(i); end if;
  if jsonb_array_length(i.proposed_value->'sentences') <> 3 or i.proposed_value->>'source_url' <> 'https://www.alpha.edu.au/about' or i.layer3_state->>'model' <> 'fixture/pinned-model' then raise exception 'item lineage: %', to_jsonb(i); end if;
  if (select description from catalogue.providers where id = i.entity_id) is not null then raise exception 'written before admission'; end if;
  if public.website_v2_provider('provider:cricos:0000a')->'item'->>'description' is not null then raise exception 'projection shows a proposal'; end if;
  if exists (select 1 from pipeline.layer4_decisions) then raise exception 'decided by itself'; end if;
  raise notice 'PASS proposal into Layer 4 without auto-admission';
end $t$;

-- 5 unsupported claims and marketing words are held; a quoted claim passes the claim check; an unsupported sentence and a quote not on the page are held
do $t$ declare v jsonb; begin
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'claim'));
  if v->>'rule' <> 'unsupported_claim' or (v->>'ok')::boolean then raise exception 'claim: %', v; end if;
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'marketing'));
  if v->>'rule' <> 'unsupported_marketing' then raise exception 'marketing: %', v; end if;
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'unsupported'));
  if v->>'rule' <> 'unsupported_sentence' then raise exception 'unsupported: %', v; end if;
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'not_on_page'));
  if v->>'rule' <> 'quote_not_on_page' then raise exception 'not on page: %', v; end if;
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'not_about'));
  if v->>'rule' <> 'not_stated' then raise exception 'not about: %', v; end if;
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'claim_quoted'));
  if v->>'rule' = 'unsupported_claim' or v->>'rule' = 'unsupported_marketing' then raise exception 'a quoted claim refused: %', v; end if;
  raise notice 'PASS unsupported claim, marketing word, unsupported sentence and missing quote held';
end $t$;

-- 6 wrong host: a page on another provider's website is refused and never stored as this provider's evidence
do $t$ declare r jsonb; v_item uuid; begin
  if security.provider_page_host_v1('10000000-0000-0000-0000-000000000002', 'https://www.alpha.edu.au/about') <> 'other_provider' then raise exception 'other provider host'; end if;
  if security.provider_page_host_v1('10000000-0000-0000-0000-000000000001', 'https://news.alpha-old.edu.au/about') <> 'own' then raise exception 'alias host'; end if;
  if security.provider_page_host_v1('10000000-0000-0000-0000-000000000002', 'https://www.unknown.com/about') <> 'unknown_host' then raise exception 'unknown host'; end if;
  select id into v_item from pipeline.provider_description_reads where provider_id = '10000000-0000-0000-0000-000000000002';
  r := public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', v_item,
         'fetch', jsonb_build_object('status', 'read', 'via', 'direct', 'url', 'https://www.alpha.edu.au/about', 'http', 200, 'storage_path', 'layer2/AU/provider-description/b/x.html.gz',
                                     'sha256', repeat('a', 64), 'mime', 'text/html'),
         'answer', (select a from ans where k = 'good'), 'model', 'fixture/pinned-model', 'cost', 0.002)));
  if (select state || '|' || rule from pipeline.provider_description_reads where id = v_item) <> 'held|wrong_host' then raise exception 'wrong host not refused: %', r; end if;
  if exists (select 1 from pipeline.evidence_artifacts where content_hash = repeat('a', 64)) then raise exception 'another provider''s page stored as evidence'; end if;
  if exists (select 1 from pipeline.layer4_review_items where entity_id = '10000000-0000-0000-0000-000000000002') then raise exception 'wrong host proposed'; end if;
  raise notice 'PASS wrong-host page refused';
end $t$;

-- 7 duplicate and outdated detection
do $t$ declare v jsonb; begin
  -- the same text as another provider's waiting proposal (Alpha's): held as a duplicate
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'good'));
  if v->>'rule' <> 'duplicate_other_provider' or v->'checks'->>'duplicate_of' <> '10000000-0000-0000-0000-000000000001' then raise exception 'duplicate: %', v; end if;
  -- the same as the description held: verified, not proposed again
  update catalogue.providers set description = (select string_agg(x->>'text', ' ') from ans, jsonb_array_elements(a->'sentences') x where k = 'claim_quoted') where id = '10000000-0000-0000-0000-000000000006';
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now(), (select a from ans where k = 'claim_quoted'));
  if v->>'outcome' <> 'verified' or v->>'rule' <> 'same_as_current' then raise exception 'same as current: %', v; end if;
  update catalogue.providers set description = null where id = '10000000-0000-0000-0000-000000000006';
  -- a copy older than pdesc.source_max_age_days is held as outdated
  v := security.provider_description_validate_v1('10000000-0000-0000-0000-000000000006', 'https://zeta.ac.nz/about', now() - interval '800 days', (select a from ans where k = 'claim_quoted'));
  if v->>'rule' <> 'source_outdated' then raise exception 'outdated: %', v; end if;
  raise notice 'PASS duplicate and outdated detection';
end $t$;

-- 8 batch and retry bounds: at most 10 a lease and never past the Layer 4 cap; a failed read retries then goes to the dead letter list
do $t$ declare r jsonb; v jsonb; v_id uuid; begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'pdesc.pending_max';
  v := public.svc_provider_description_next(5); if v->>'reason' <> 'review_full' then raise exception 'Layer 4 cap not honoured: %', v; end if;
  v := security.provider_description_fire_v1(); if v->>'review' <> 'full' then raise exception 'fire past the cap: %', v; end if;
  update pipeline.platform_toolset_settings set value = '10' where key = 'pdesc.pending_max';
  insert into pipeline.provider_description_reads(provider_id, state, tries) values ('10000000-0000-0000-0000-000000000006', 'queued', 0) returning id into v_id;
  update pipeline.platform_toolset_settings set value = '["AU","NZ"]' where key = 'pdesc.countries';
  update pipeline.platform_toolset_settings set value = '2' where key = 'pdesc.tries';
  v := public.svc_provider_description_next(50);
  if jsonb_array_length(v->'items') <> 1 then raise exception 'lease: %', v; end if;
  r := public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', v_id, 'error', 'held_partial: output_truncated', 'cost', 0.001)));
  if (select state || '|' || tries from pipeline.provider_description_reads where id = v_id) <> 'queued|1' then raise exception 'retry: %', r; end if;
  if (select next_try_at from pipeline.provider_description_reads where id = v_id) < now() + interval '5 hours' then raise exception 'retry wait not set'; end if;
  if jsonb_array_length(public.svc_provider_description_next(5)->'items') <> 0 then raise exception 'retried before its wait'; end if;
  update pipeline.provider_description_reads set next_try_at = now() where id = v_id;
  v := public.svc_provider_description_next(5);
  r := public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', v_id, 'error', 'HTTP 502', 'cost', 0.001)));
  if (select state from pipeline.provider_description_reads where id = v_id) <> 'dead_letter' then raise exception 'not dead-lettered: %', r; end if;
  if (select cost_usd from pipeline.provider_description_reads where id = v_id) <> 0.002 then raise exception 'cost of failed calls not kept'; end if;
  update pipeline.provider_description_reads set state = 'queued', tries = 2, next_try_at = now() where id = v_id;
  if jsonb_array_length(public.svc_provider_description_next(5)->'items') <> 0 then raise exception 'leased past its tries'; end if;
  update pipeline.provider_description_reads set state = 'dead_letter' where id = v_id;
  if security.provider_description_enqueue_v1() <> 0 then raise exception 'a dead letter re-queued by itself'; end if;
  -- recovery: a PIM Admin (rank 5) sends it back with a reason; a curator cannot
  perform set_config('fx.uid', '90000000-0000-0000-0000-000000000001', false); perform set_config('fx.rank', '3', false);
  begin perform public.admin_provider_descriptions('retry', jsonb_build_object('provider_ids', jsonb_build_array('10000000-0000-0000-0000-000000000006'), 'reason', 'site back up'));
        raise exception 'curator retried'; exception when insufficient_privilege then null; end;
  perform set_config('fx.rank', '5', false);
  r := public.admin_provider_descriptions('retry', jsonb_build_object('provider_ids', jsonb_build_array('10000000-0000-0000-0000-000000000006'), 'reason', 'site back up'));
  if r->>'requeued' <> '1' or (select state || '|' || tries from pipeline.provider_description_reads where id = v_id) <> 'queued|0' then raise exception 'recovery: %', r; end if;
  if not exists (select 1 from pipeline.admin_control_events where area = 'provider_descriptions' and action = 'retry') then raise exception 'retry not logged'; end if;
  update pipeline.provider_description_reads set state = 'held' where id = v_id;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  update pipeline.platform_toolset_settings set value = '3' where key = 'pdesc.tries';
  update pipeline.platform_toolset_settings set value = '["AU"]' where key = 'pdesc.countries';
  raise notice 'PASS batch and retry bounds (lease cap, Layer 4 cap, retry wait, tries, dead letter, recovery)';
end $t$;

-- 9 fire: sends one worker call at most once every pdesc.every_minutes, with the batch from its setting
do $t$ declare v jsonb; begin
  update pipeline.provider_description_reads set state = 'queued', next_try_at = now(), tries = 0, review_item_id = null where provider_id = '10000000-0000-0000-0000-000000000002';
  v := security.provider_description_fire_v1();
  if v->>'sent' <> '1' or not exists (select 1 from pipeline.edge_request_log where mode = 'provider_description') then raise exception 'not sent: %', v; end if;
  v := security.provider_description_fire_v1();
  if v->>'sent' <> '0' then raise exception 'sent twice within the interval: %', v; end if;
  raise notice 'PASS fire: once a run interval, batch from its setting';
end $t$;

-- 10 admission by a person through the live Layer 4 decide (edited here): an edit is refused, approval writes the description and the
--    Website API v2 payload shows it; a rejected proposal never reaches the projection
do $t$ declare i uuid; r jsonb; v_text text; begin
  select id into i from pipeline.layer4_review_items where field_code = 'provider_description' and entity_id = '10000000-0000-0000-0000-000000000001';
  perform set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false); perform set_config('fx.rank', '2', false);
  begin perform security.layer4_review_decide_impl(i, 'approve', 'reads well, quotes checked'); raise exception 'below curator approved'; exception when insufficient_privilege then null; end;
  perform set_config('fx.rank', '3', false);
  begin perform security.layer4_review_decide_impl(i, 'edit_and_approve', 'shorter wording', '{"description": "A university in Perth."}'); raise exception 'edited description admitted';
  exception when invalid_parameter_value then null; end;
  if (select status from pipeline.layer4_review_items where id = i) <> 'pending' or (select description from catalogue.providers where id = '10000000-0000-0000-0000-000000000001') is not null then
    raise exception 'a refused edit changed something';
  end if;
  -- through Layer 4 › Inbox, as a person does it (the live admin_layer4_inbox, edited here)
  perform set_config('fx.rank', '4', false);
  if not exists (select 1 from security.layer4_inbox_items_v1() x where x.kind = 'provider_description' and x.ref = i::text
                   and x.provider_id = '10000000-0000-0000-0000-000000000001' and x.subject = 'University description from the official page'
                   and jsonb_array_length(x.detail->'proposed'->'sentences') = 3 and x.detail->>'source_url' = 'https://www.alpha.edu.au/about') then
    raise exception 'not in the Inbox as its own kind: %', (select jsonb_agg(to_jsonb(x)) from security.layer4_inbox_items_v1() x);
  end if;
  if (select jsonb_agg(c->>'key') from jsonb_array_elements(security.layer4_inbox_kinds_v1()->'provider_description'->'choices') c) <> '["approve", "reject"]'::jsonb then raise exception 'choices'; end if;
  if (security.layer4_inbox_kinds_v1()->'course_link'->>'order') <> '1' then raise exception 'other kinds changed'; end if;
  r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'provider_description', 'ref', i, 'choice', 'approve', 'reason', 'every sentence matches the official About page'));
  if not (r->>'ok')::boolean then raise exception 'inbox decide: %', r; end if;
  raise notice 'PASS Layer 4 Inbox: its own kind and choices';
  v_text := (select proposed_value->>'description' from pipeline.layer4_review_items where id = i);
  if (select description from catalogue.providers where id = '10000000-0000-0000-0000-000000000001') is distinct from v_text then raise exception 'not admitted: %', r; end if;
  if public.website_v2_provider('provider:cricos:0000a')->'item'->>'description' is distinct from v_text then raise exception 'projection does not show the admitted value'; end if;
  if (select state || '|' || (published_at is not null) from pipeline.provider_description_reads where review_item_id = i) <> 'admitted|true' then raise exception 'read not admitted and published'; end if;
  if not exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = i and d.action = 'approve' and d.actor_id = '90000000-0000-0000-0000-000000000002') then raise exception 'decision not recorded'; end if;
  if not exists (select 1 from pipeline.search_refresh_signals s where s.entity_type = 'provider' and s.entity_id = '10000000-0000-0000-0000-000000000001') then raise exception 'no search refresh signal'; end if;
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  raise notice 'PASS admission by a person only; projection shows only admitted values';
end $t$;

do $t$ declare i uuid; v_id uuid; begin
  -- Beta: a proposal that a person rejects is never written or shown
  update pipeline.provider_description_reads set state = 'reading', rule = null where provider_id = '10000000-0000-0000-0000-000000000002' returning id into v_id;
  perform public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', v_id, 'stored_evidence_id', null,
         'fetch', jsonb_build_object('status', 'read', 'via', 'firecrawl', 'url', 'https://beta.edu.au/about-us', 'http', 200, 'storage_path', 'layer2/AU/provider-description/b/y.html.gz',
                                     'sha256', repeat('b', 64), 'mime', 'text/html'),
         'answer', '{"about_page": true, "sentences": [
            {"text": "Beta University is a public university in Brisbane, Queensland, established in 1990.", "quote": "Beta University is a public university established in 1990 in Brisbane, Queensland.", "on_page": true},
            {"text": "It teaches nursing, education, law and information technology on two campuses.", "quote": "We teach nursing, education, law and information technology across our two campuses.", "on_page": true}]}'::jsonb,
         'model', 'fixture/pinned-model', 'cost', 0.003)));
  select id into i from pipeline.layer4_review_items where field_code = 'provider_description' and entity_id = '10000000-0000-0000-0000-000000000002' and status = 'pending';
  if i is null then raise exception 'Beta not proposed: %', (select to_jsonb(r) from pipeline.provider_description_reads r where id = v_id); end if;
  if (select read_via || '|' || (evidence_id is not null) from pipeline.provider_description_reads where id = v_id) <> 'firecrawl|true' then raise exception 'acquired copy not registered'; end if;
  perform set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false); perform set_config('fx.rank', '3', false);
  perform security.layer4_review_decide_impl(i, 'reject', 'the page is the international office page');
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  if (select state from pipeline.provider_description_reads where id = v_id) <> 'rejected' then raise exception 'read not rejected'; end if;
  if (select description from catalogue.providers where id = '10000000-0000-0000-0000-000000000002') is not null
     or public.website_v2_provider('provider:cricos:0000b')->'item'->>'description' is not null then raise exception 'rejected value shown'; end if;
  if security.provider_description_enqueue_v1() <> 0 then raise exception 'rejected provider re-queued before pdesc.recheck_days'; end if;
  raise notice 'PASS rejected proposal never published; acquired page registered as evidence';
end $t$;

-- 11 the AI daily guard (live ai_use_allowed_v1 with the edited ai_spend_today_v1): the reader stops when its spend reaches the guard
do $t$ declare v jsonb; begin
  insert into pipeline.platform_toolsets values ('openrouter', 'stop');
  if (select count(*) from security.ai_spend_today_v1() x where x.use = 'provider_description' and x.spent > 0) <> 1 then raise exception 'no spend line'; end if;
  update pipeline.platform_toolset_settings set value = '0.001' where toolset_key = 'openrouter' and key = 'guard_provider_description';
  if security.ai_use_allowed_v1('provider_description') then raise exception 'guard not applied'; end if;
  v := security.provider_description_fire_v1(); if v->>'ai' <> 'stopped' then raise exception 'fire past the guard: %', v; end if;
  update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'openrouter' and key = 'guard_provider_description';
  if not security.ai_use_allowed_v1('provider_description') then raise exception 'guard wrong'; end if;
  raise notice 'PASS AI daily guard (guard_provider_description)';
end $t$;

-- 12 metrics for Coverage (curator and above)
do $t$ declare v jsonb; begin
  begin perform public.admin_provider_descriptions('metrics', '{}'); raise exception 'anonymous metrics'; exception when insufficient_privilege then null; end;
  perform set_config('fx.uid', '90000000-0000-0000-0000-000000000002', false); perform set_config('fx.rank', '3', false);
  v := public.admin_provider_descriptions('metrics', '{"country": "AU"}');
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '', false);
  if (v->>'eligible')::int <> 3 or (v->>'present')::int <> 1 or (v->>'admitted')::int <> 1 or (v->>'published')::int <> 1 or (v->>'rejected')::int <> 1
     or (v->>'stored_pages_available')::int <> 2 or (v->>'missing')::int <> 2 or (v->>'pages_reused')::int <> 1 or (v->>'pages_acquired')::int < 1 or (v->>'cost_per_admitted_usd') is null then
    raise exception 'metrics: %', v;
  end if;
  raise notice 'PASS metrics (eligible published providers, present, missing, proposed, held, admitted, cost)';
end $t$;

-- 13 privileges: the worker functions are the service role's; the screen function is signed-in users' (rank checked inside)
do $t$ begin
  if has_function_privilege('anon', 'public.svc_provider_description_next(integer)', 'execute') or has_function_privilege('authenticated', 'public.svc_provider_description_record(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.svc_provider_description_record(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.admin_provider_descriptions(text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'security.layer4_provider_description_apply_impl(uuid,uuid,jsonb,text)', 'execute') then raise exception 'privileges'; end if;
  raise notice 'PASS privileges';
end $t$;
