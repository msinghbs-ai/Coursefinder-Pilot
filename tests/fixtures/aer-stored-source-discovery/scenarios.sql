-- AER source discovery from stored evidence, after migration 20261107150000 (applied twice). Each block raises 'FAIL: ...' on the first broken expectation.

-- S1 the circular gate is open: a suggested first page is attached; the enabled rule itself is unchanged; the other refusals still hold
do $$
declare v int;
begin
  perform fx.ok(not security.entry_matrix_enabled_v1('d1000000-0000-4000-8000-0000000000b3'), 'S1 enabled_v1 is untouched: it still needs a recorded page');
  perform fx.ok(security.entry_matrix_attach_allowed_v1('d1000000-0000-4000-8000-0000000000b3'), 'S1 the new rule allows a first page');
  v := security.entry_matrix_attach_v1();
  perform fx.ok(v = 1, 'S1 the central-find suggestion became the provider''s first page (attached ' || v || ')');
  perform fx.ok((select found_via || '/' || status from pipeline.entry_matrix_sources where provider_id = 'd1000000-0000-4000-8000-0000000000b3') = 'search/found', 'S1 attached as found_via search, status found');
  perform fx.ok(security.entry_matrix_attach_v1() = 0, 'S1 a second attach adds nothing');
  perform fx.ok(security.entry_matrix_enabled_v1('d1000000-0000-4000-8000-0000000000b3'), 'S1 once the page is recorded the provider is enabled for reading, as before');
  perform fx.ok(not security.entry_matrix_attach_allowed_v1('d1000000-0000-4000-8000-0000000000a7'), 'S1 a hidden provider is still refused');
  perform fx.ok(not security.entry_matrix_attach_allowed_v1('d1000000-0000-4000-8000-0000000000a9'), 'S1 a country switched off for scheduled reading is still refused');
  perform fx.ok(not security.entry_matrix_attach_allowed_v1('d1000000-0000-4000-8000-0000000000a0'), 'S1 a provider outside the entry countries is still refused');
  update pipeline.platform_toolset_settings set value = '0' where key = 'entry.matrix_enabled';
  perform fx.ok(not security.entry_matrix_attach_allowed_v1('d1000000-0000-4000-8000-0000000000a1'), 'S1 the reader switch off refuses everything');
  update pipeline.platform_toolset_settings set value = '1' where key = 'entry.matrix_enabled';
  raise notice 'S1 the gate: a suggested first page is attached; hidden, country-off, other-country and reader-off still refused; enabled_v1 untouched';
end $$;

-- S2 the page rules (the same patterns, noise list and score as the worker's central.ts)
do $$
begin
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/international/academic-entry-requirements', null) = 8.6, 'S2 strong address, international, short: 8.6');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/international/entry-requirements', 'Entry requirements') = 4.1, 'S2 weak address with international, depth 2: 4.1');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/study/international/entry-requirements', null) = 3.9, 'S2 the same one level deeper: 3.9, below the attach score');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/entry-requirements', null) = 2.3, 'S2 a plain entry-requirements page: 2.3');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/study/apply', 'International and overseas qualifications') = 6.6, 'S2 strong in the link text only: 4 + 2 + 0.6');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/files/international-entry-requirements.pdf', null) = 8.1, 'S2 a PDF costs 0.5');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/english-language-requirements', null) is null, 'S2 an English page is not the academic matrix');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/international/entry-requirements', 'IELTS entry') is null, 'S2 IELTS in the text excludes it');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/news/entry-requirements-change', null) is null, 'S2 news is noise');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/courses/bachelor-of-arts', 'Bachelor of Arts') is null, 'S2 a course page has no entry wording');
  perform fx.ok(security.entry_source_score_v1('https://x.edu.au/entry-requirements?page=2', null) is null, 'S2 a paging address is noise');
  perform fx.ok(security.entry_source_score_v1(null, null) is null, 'S2 null in, null out');
  raise notice 'S2 page rules: 12 scores as the worker gives them';
end $$;

-- S3 the step ships off; a measurement writes nothing and says what it would attach
do $$
declare v jsonb;
begin
  perform fx.ok((security.entry_source_stored_find_v1()->>'on')::boolean = false, 'S3 off by default');
  v := security.entry_source_stored_find_v1(100, false);
  perform fx.ok((v->>'on')::boolean and not (v->>'apply')::boolean, 'S3 the measurement runs while the step is off: ' || v::text);
  perform fx.ok((select count(*) from pipeline.aer_source_stored_find) = 0 and (select count(*) from pipeline.entry_matrix_sources where found_via = 'search') = 1, 'S3 the measurement wrote nothing');
  perform fx.ok(v->'outcomes' = '{"attached": 2, "host_shared": 2, "no_link_material": 1, "no_entry_candidate": 1}'::jsonb, 'S3 outcomes: ' || (v->'outcomes')::text);
  perform fx.ok(jsonb_array_length(v->'would_attach') = 2 and (v->>'looked_at')::int = 6, 'S3 six providers looked at, two would be given pages: ' || v::text);
  raise notice 'S3 off by default; the measurement writes nothing: %', v->'outcomes';
end $$;

-- S4 switched on: own host only, best first, capped, recorded with the reason; ineligible providers are not looked at
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'aer.source_stored_find_on';
do $$
declare v jsonb; a uuid := 'd1000000-0000-4000-8000-0000000000a1';
begin
  v := security.entry_source_stored_find_v1();
  perform fx.ok((v->>'looked_at')::int = 6 and (v->>'sources_attached')::int = 4, 'S4 six providers looked at, four sources attached: ' || v::text);
  perform fx.ok((select array_agg(url order by rank) from pipeline.entry_matrix_sources where provider_id = a) =
                array['https://www.alpha.edu.au/admissions/overseas-qualifications', 'https://www.alpha.edu.au/international/academic-entry-requirements', 'https://study.alpha.edu.au/international/entry-requirements-by-country'],
                'S4 alpha: best three by score on its own host only (a sub-host is own host; no English, news, other-host, look-alike host or 3.9 page; the 4.1 fourth candidate is cut by the cap): '
                || (select array_agg(url order by rank)::text from pipeline.entry_matrix_sources where provider_id = a));
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id = a and found_via = 'search' and status = 'found') = 3, 'S4 attached for the existing reader: found_via search, status found');
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id = 'd1000000-0000-4000-8000-0000000000b1') = 1, 'S4 a PDF page on the own host is attached (the reader holds it until PDFs are on)');
  perform fx.ok((select outcome || '/' || links || '/' || candidates || '/' || attached || '/' || (detail->>'below_threshold') from pipeline.aer_source_stored_find where provider_id = a) = 'attached/10/4/3/1',
                'S4 alpha recorded: 10 addresses (a duplicate is one), 4 candidates, 3 attached, 1 own-host page below the score: ' || (select outcome || '/' || links || '/' || candidates || '/' || attached || '/' || (detail->>'below_threshold') from pipeline.aer_source_stored_find where provider_id = a));
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id in ('d1000000-0000-4000-8000-0000000000b2', 'd1000000-0000-4000-8000-0000000000c3')) = 0
                and (select outcome from pipeline.aer_source_stored_find where provider_id = 'd1000000-0000-4000-8000-0000000000b2') = 'host_shared', 'S4 two providers on one website: recorded host_shared, nothing attached (identity needs a person)');
  perform fx.ok((select outcome || '/' || candidates || '/' || (detail->>'below_threshold') from pipeline.aer_source_stored_find where provider_id = 'd1000000-0000-4000-8000-0000000000d4') = 'no_entry_candidate/0/1', 'S4 delta: only a plain entry-requirements link (2.3): no_entry_candidate');
  perform fx.ok((select outcome from pipeline.aer_source_stored_find where provider_id = 'd1000000-0000-4000-8000-0000000000e5') = 'no_link_material', 'S4 epsilon: no stored links: no_link_material');
  perform fx.ok(not exists (select 1 from pipeline.aer_source_stored_find where provider_id in ('d1000000-0000-4000-8000-0000000000f6', 'd1000000-0000-4000-8000-0000000000a7', 'd1000000-0000-4000-8000-0000000000a8',
                'd1000000-0000-4000-8000-0000000000a9', 'd1000000-0000-4000-8000-0000000000a0', 'd1000000-0000-4000-8000-0000000000b3')), 'S4 providers with a page, hidden, on a third-party host, country off, not AER-eligible are not looked at');
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id = 'd1000000-0000-4000-8000-0000000000f6') = 1, 'S4 a provider with a page keeps exactly its page');
  raise notice 'S4 stored find: alpha three best own-host pages, lambda one, shared hosts and no-candidate providers recorded with the reason, ineligible providers untouched';
end $$;

-- S5 incremental: nothing is looked at twice inside the wait; after it, new links change the answer; the cap and the reader switch hold
do $$
declare v jsonb; d uuid := 'd1000000-0000-4000-8000-0000000000d4';
begin
  v := security.entry_source_stored_find_v1();
  perform fx.ok((v->>'looked_at')::int = 0, 'S5 a second run looks at nobody (attached are done, the others wait): ' || v::text);
  update pipeline.aer_source_stored_find set checked_at = now() - interval '20 days' where provider_id = d;   -- fixture clock
  insert into pipeline.provider_discovery_links(provider_id, url, anchor_text, pages) values (d, 'https://www.delta.edu.au/international/academic-entry-requirements', 'Academic entry requirements', 2);
  v := security.entry_source_stored_find_v1();
  perform fx.ok((v->>'looked_at')::int = 1 and (select outcome from pipeline.aer_source_stored_find where provider_id = d) = 'attached', 'S5 after the wait, a newly stored link is found: ' || v::text);
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id = d) = 1, 'S5 delta now has its page');
  update pipeline.platform_toolset_settings set value = '0' where key = 'entry.matrix_enabled';
  perform fx.ok((security.entry_source_stored_find_v1()->>'on')::boolean = false and (security.entry_source_stored_find_v1(10, false)->>'on')::boolean = false, 'S5 the reader switch off stops the step and the measurement');
  update pipeline.platform_toolset_settings set value = '1' where key = 'entry.matrix_enabled';
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.source_stored_find_on';
  perform fx.ok((security.entry_source_stored_find_v1()->>'on')::boolean = false, 'S5 the step''s own switch off stops it');
  raise notice 'S5 incremental: no repeat inside the wait; a new link is picked up after it; both switches stop the step';
end $$;

-- S6 the migration ships off and paused, is catalogued (G1), its values are settings (G2), and the record is private
do $$
begin
  perform fx.ok((select value from pipeline.platform_toolset_settings where key = 'aer.source_stored_find_on') = '0'::jsonb, 'S6 the switch is 0 (set back by S5; the migration inserted 0)');
  perform fx.ok(exists (select 1 from cron.job where jobname = 'aer-source-stored-find' and not active), 'S6 the job exists and is paused');
  perform fx.ok((select command from cron.job where jobname = 'aer-source-stored-find') = 'select security.entry_source_stored_find_v1(security.pipeline_num_v1(''batch.aer_source_stored_find'', 200)::int)', 'S6 the command reads its size from a setting');
  perform fx.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-source-stored-find'), 'S6 catalogued');
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where key in ('aer.source_stored_find_on', 'batch.aer_source_stored_find', 'aer.source_stored_find_recheck_days')
                    and label is not null and min_value is not null and max_value is not null and unit is not null and used_by is not null) = 3, 'S6 three settings with label, range, unit and used_by');
  perform fx.ok((select count(*) from pipeline.component_register where introduced_in = '20261107150000') = 5, 'S6 five register rows');
  raise notice 'S6 housekeeping: off, paused, catalogued, three settings, five register rows';
end $$;
do $$ begin raise notice 'stored-source: all passed'; end $$;
