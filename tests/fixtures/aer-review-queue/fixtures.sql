-- CF-247 AER review queue fixtures (migration 20261104530000): assertions on the production-shaped seed. Run by run.sh after the migration.
\set ON_ERROR_STOP on
create or replace function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
create or replace function fx.item(p_provider text, p_cls text, p_n int default 1) returns uuid language sql as $f$
  select i.id from pipeline.layer4_review_items i join fx.gate f on f.item_id = i.id join catalogue.courses c on c.id = i.entity_id join catalogue.providers p on p.id = c.provider_id
   where p.canonical_name = p_provider and fx.cls(f.g) = p_cls and f.g->>'rule' = 'E13' order by i.created_at, i.id offset p_n - 1 limit 1 $f$;
create temp table before_state as select (select count(*) from pipeline.layer4_review_items where status = 'pending') pending,
  (select count(*) from catalogue.course_entry_requirements where status = 'active') active, (select count(*) from pipeline.layer4_decisions) decisions;

-- 1 settlement classes and the reviewer-ready queue: from stored records, followed universities first, one university's items oldest first
create or replace function fx.expect_ready() returns bigint language sql as $f$
  select count(*) from pipeline.layer4_review_items i join fx.gate f on f.item_id = i.id
    left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id left join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
   where i.status = 'pending' and (i.field_code = 'entry_matrix_first_run' and ((f.g->>'complete')::boolean or f.g::text like '%Approve except%')
         or i.field_code = 'course_entry_first_read' and fx.cls(f.g) in ('complete', 'row_level') and pg.url = i.proposed_value->>'url'
            and not exists (select 1 from pipeline.manual_locks l where l.entity_id = i.entity_id)) $f$;
do $$
declare v jsonb; v_first jsonb; v_rmit jsonb; s jsonb;
begin
  v := public.admin_layer4_aer_queue('{}');
  perform fx.ok((v->>'ready')::bigint = fx.expect_ready() and fx.expect_ready() between 205 and 218,
                format('ready = complete and rows-to-leave-out reads on their bound page and not locked, plus ready matrix runs (%s)', v->>'ready'));
  perform fx.ok((select sum(value::int) from jsonb_each_text(v->'by_settlement')) = 605 and v->'by_settlement' ?& array['ready', 'recoverable', 'needs_input', 'stale'],
                format('every one of the 605 items is in one of the four classes (%s)', v->'by_settlement'));
  perform fx.ok((v->'by_settlement'->>'stale')::int = (select count(*) from pipeline.layer4_review_items i join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
                   where i.status = 'pending' and pg.url is distinct from i.proposed_value->>'url'), 'stale: every read whose course is now bound to another page');
  v_first := v->'universities'->0;
  perform fx.ok((v_first->>'followed')::boolean and not exists (select 1 from jsonb_array_elements(v->'universities') with ordinality u(x, n)
                  where not (x->>'followed')::boolean and n < (select max(n2) from jsonb_array_elements(v->'universities') with ordinality u2(x2, n2) where (x2->>'followed')::boolean)),
                'followed universities (coverage.aer_priority_providers) come first');
  v_rmit := public.admin_layer4_aer_queue('{"provider_id": "8e1adb6c-e069-43db-9584-bd054255e702"}');
  perform fx.ok(jsonb_array_length(v_rmit->'items') = 25 and (select bool_and(x->>'kind' = 'aer_review' and (x->>'ready')::boolean and x ? 'why' and x->'detail' ? 'field_code')
                  from jsonb_array_elements(v_rmit->'items') x), 'RMIT''s ready page: 25 Inbox items (kind aer_review) ready first, each decidable by the Inbox''s own decide');
  perform fx.ok((select bool_and((a->>'created_at')::timestamptz <= (b->>'created_at')::timestamptz) from jsonb_array_elements(v_rmit->'items') with ordinality a1(a, n)
                  join jsonb_array_elements(v_rmit->'items') with ordinality b1(b, m) on m = n + 1), 'items in order, oldest first');
  s := public.admin_layer4_aer_queue('{"summary_provider_id": "8e1adb6c-e069-43db-9584-bd054255e702"}');
  perform fx.ok((s->>'pending')::int = 303 and (s->>'review_ready')::int + (s->>'technically_held')::int + (s->>'human_input_required')::int + (s->>'stale')::int = 303
                and (s->>'unresolved')::int = 303 - (s->>'review_ready')::int, format('RMIT summary: 303 pending, the four classes add up (%s)', s - 'by_route'));
  update fx.caller set rank = 3;
  begin perform public.admin_layer4_aer_queue('{}'); raise exception 'FAILED: rank 3 read the queue';
  exception when insufficient_privilege then perform fx.ok(true, 'below Pipeline Operator: refused'); end;
  update fx.caller set rank = 4;
end $$;

-- 1b E13 deterministic repeats: the Diploma of Commerce shape is waiting for a row boundary, not another re-read or a rows request
do $$
declare st record; st2 record;
begin
  select * into st from security.aer_settlement_v1('8e1adb6c-e069-43db-9584-bd054255e702') z where z.item_id = (select id from fx.dc where n = 1);
  perform fx.ok(st.settlement = 'needs_input' and st.route = 'row_limit_stored' and st.tries = 2 and st.rows_read = 9
                and st.why like 'the corrected read kept every printed requirement (9 rows) but is over the row limit%' and st.next_action like 'a row boundary for the university%',
                'two refusals for the row limit on the same copy: a row boundary is the next action (9 stored rows; no new read)');
  select * into st2 from security.aer_settlement_v1('8e1adb6c-e069-43db-9584-bd054255e702') z where z.item_id = (select id from fx.dc where n = 2);
  perform fx.ok(st2.route = 'identity' and st2.settlement = 'needs_input', 'refused because the page''s proof does not admit entry requirements: an identity case');
  perform fx.ok((select count(*) from jsonb_array_elements(security.aer_e13_recover_v1(true)->'items') x where (x->>'item_id')::uuid in (select id from fx.dc)) = 0, 'the E13 pilot never picks them');
end $$;

-- 2 the review packet: provider, course, qualification, country, audience, evidence, rows, active rows, locks, checks, decision, consequences
do $$
declare p jsonb; v_calls int;
begin
  truncate fx.gate_calls;
  p := security.aer_review_packet_v1(fx.item('RMIT University (RMIT)', 'complete', 1));
  perform fx.ok((select count(*) from fx.gate_calls) = 0, 'a current stored gate is used: no gate is run for the packet');
  perform fx.ok(p->>'provider' = 'RMIT University (RMIT)' and p->'course'->>'qualification' in ('Bachelor', 'Masters (Coursework)') and p->'course'->>'country' = 'AU'
                and p->'course'->>'code' like 'C%' and (p->'proposed'->>'count')::int = 3 and p->'audiences' @> '["international"]'
                and p->'evidence'->>'url' like 'https://uni9.example/c/%' and p->'evidence'->>'captured_at' is not null,
                'packet: exact university, course, code, qualification, country, audiences, stored copy and the three proposed rows with quotations');
  perform fx.ok((p->'active'->>'count')::int = 2 and p->>'recommended' = 'Approve all rows (every check passes)'
                and p->'consequences'->>'approve' like '3 waiting row(s) become active; 2 active row(s) from earlier reads are superseded%'
                and p->'consequences'->>'reject' like '3 waiting row(s) are quarantined%', 'complete read: Approve all, with its exact consequences (2 active rows superseded)');
  perform fx.ok((p->'queue'->>'ready_at_university')::int = (select count(*) from security.aer_settlement_v1('8e1adb6c-e069-43db-9584-bd054255e702') z
                   where z.settlement = 'ready' and z.field_code = 'course_entry_first_read') and (p->'queue'->>'position')::int >= 1 and (p->'queue'->>'next_ready') is not null
                and p->'settlement'->>'settlement' = 'ready',
                format('queue: position %s of %s ready at RMIT, with the next ready item', p->'queue'->>'position', p->'queue'->>'ready_at_university'));
  p := security.aer_review_packet_v1(fx.item('RMIT University (RMIT)', 'complete', 2));
  perform fx.ok(p->>'recommended' like 'Reject the read or leave it: the course has a manual lock%' and jsonb_array_length(p->'locks') = 1, 'a manual lock is shown and changes the recommendation');
  p := security.aer_review_packet_v1(fx.item('Auckland University of Technology', 'row_level', 1));
  perform fx.ok(p->>'recommended' like 'Approve except: leave out 1 row(s)%' and jsonb_array_length(p->'exclude_row_ids') = 1
                and p->'consequences'->>'approve' like '2 waiting row(s) become active and 1 are kept inactive%', 'rows to leave out: Approve except with the row named, and its consequence');
  p := security.aer_review_packet_v1(fx.item('Monash University', 'complete', 1));
  perform fx.ok(p->'owner'->0->>'owner' = 'chatgpt', 'ownership: Monash is shown as the ChatGPT browser reviewer''s');
  p := security.aer_review_packet_v1(fx.item('RMIT University (RMIT)', 'drops_uncovered', 1));
  perform fx.ok(p->>'recommended' like 'Do not approve: technical recovery (%' and p->'consequences'->>'approve' like 'refused: the completeness gate (E13)%'
                and (p->'queue'->>'position') is null, 'a held read is never offered for approval and is not in the reviewer-ready queue');
  update pipeline.layer4_item_readiness set gate_checked_at = now() - interval '5 hours' where item_id = fx.item('RMIT University (RMIT)', 'complete', 3);
  truncate fx.gate_calls;
  p := security.aer_review_packet_v1(fx.item('RMIT University (RMIT)', 'complete', 3));
  perform fx.ok((select count(*) from fx.gate_calls) = 1 and p->'gate'->>'source' = 'checked now', 'a stale stored gate: exactly one live gate, for this item only');
  p := security.aer_review_packet_v1((select i.id from pipeline.layer4_review_items i join fx.gate f on f.item_id = i.id where i.field_code = 'entry_matrix_first_run' and (f.g->>'complete')::boolean limit 1));
  perform fx.ok(p->>'recommended' = 'Approve the run (every check passes)' and (p->'proposed'->>'count')::int = 3 and p->'source'->>'url' like 'https://matrix.example/%',
                'matrix run: source, proposed rows by country, and the recommendation');
  truncate fx.gate_calls;
  perform security.aer_review_packet_v1(fx.item('RMIT University (RMIT)', 'complete', 5));
  perform fx.ok((select count(*) from fx.gate_calls) = 0, 'the queue position of a university with 303 items is read from stored classes: no gate per row');
end $$;

-- 3 the AER card: the packet first, then Human-assisted recovery's detail and actions, through the extend hook
do $$
declare d jsonb;
begin
  perform fx.ok((select detail_fn from pipeline.layer4_inbox_kind_hooks where kind = 'aer_review' and mode = 'extend') = 'security.layer4_aer_review_detail_v1(text)',
                'the aer_review extend hook reads the review card');
  d := security.layer4_aer_review_detail_v1(fx.item('RMIT University (RMIT)', 'drops_uncovered', 2)::text);
  perform fx.ok((select array_agg(s->>'key' order by n) from jsonb_array_elements(d->'sections') with ordinality z(s, n)) @> array['review', 'checks', 'rows', 'active', 'recovery']
                and d->'sections'->0->>'key' = 'summary' and d->'sections'->0->'body' ? 'Next action', 'sections: a readable summary (class, failure, next action), review, checks, rows, active rows, then the recovery detail');
  perform fx.ok(jsonb_array_length(d->'actions') = 4 and d->'sections'->2->'body'->>'Route' is not null, 'Human-assisted recovery''s four actions are kept; the route is shown');
end $$;
begin;
create or replace function security.layer4_aer_recovery_detail_v1(p_ref text) returns jsonb language plpgsql as $f$ begin raise exception 'canceling statement due to statement timeout'; end $f$;
select fx.ok((security.layer4_aer_review_detail_v1(fx.item('RMIT University (RMIT)', 'complete', 1)::text)->'sections'->1->>'key') = 'review',
             'the recovery detail failing (time-out) leaves the review card');
rollback;

-- 4 ownership: one owner a university; a claim is refused while another owner holds it
do $$
declare v jsonb;
begin
  v := security.layer4_aer_owner_claim_v1((select id from catalogue.providers where canonical_name = 'Monash University'), 'claude', 'Integration Controller AER queue');
  perform fx.ok(not (v->>'claimed')::boolean and v->>'reason' = 'held by chatgpt', 'claim of a ChatGPT-owned university refused');
  v := security.layer4_aer_owner_claim_v1('8e1adb6c-e069-43db-9584-bd054255e702', 'claude', 'Integration Controller AER queue');
  perform security.layer4_aer_owner_claim_v1('8e1adb6c-e069-43db-9584-bd054255e702', 'claude', 'again');
  perform fx.ok((v->>'claimed')::boolean and (select count(*) from pipeline.layer4_review_owners where provider_id = '8e1adb6c-e069-43db-9584-bd054255e702' and closed_at is null) = 3,
                'RMIT claimed for the three AER kinds, once');
end $$;

-- 5 technical routing: one deduplicated intervention per held read no automatic remedy can fix; fair; resumable
do $$
declare v jsonb; v2 jsonb; v_n int;
begin
  perform fx.ok((select generate_fn::text from pipeline.layer4_intervention_handlers where lane = 'aer_item') = 'security.har_aer_item_generate_v1(integer)', 'lane aer_item has its generator');
  v := security.har_aer_item_generate_v1(40);
  v_n := (v->>'raised_or_changed')::int;
  perform fx.ok(v_n > 0 and v_n <= 40, format('one run raises %s (at most batch.har_generate)', v_n));
  perform fx.ok((select max(n) from (select provider_id, count(*) n from pipeline.layer4_interventions group by 1) z) <= 2, 'at most 2 a university a run (har.generate_per_provider_max)');
  perform fx.ok(not exists (select 1 from pipeline.layer4_interventions x join fx.gate f on f.item_id::text = x.entity
                             where not (x.missing_fact = 'aer_course_identity' and fx.cls(f.g) = 'shared_page' or x.missing_fact = 'aer_read_rows_missing' and fx.cls(f.g) = 'drops_uncovered')),
                'shared pages ask for the course identity; dropped minimums ask for the rows; nothing else is raised (row limit, complete, matrix)');
  perform fx.ok(not exists (select 1 from pipeline.layer4_interventions x join pipeline.layer4_review_items i on i.id::text = x.entity
                              join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
                             where x.missing_fact = 'aer_read_rows_missing' and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'
                               and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id)),
                'no rows request while an untried corrected read from the stored copy could still fix it');
  perform fx.ok((select bool_and(x.work_item_id is not null and x.resume_target->>'review_item' = x.entity and x.status = 'awaiting_input') from pipeline.layer4_interventions x),
                'each is linked to its work item, waits for a person, and names the read it resumes');
  v2 := security.har_aer_item_generate_v1(40);
  perform fx.ok((select count(*) from pipeline.layer4_interventions) = v_n + (v2->>'raised_or_changed')::int
                and not exists (select 1 from pipeline.layer4_interventions group by entity, missing_fact having count(*) > 1), 'the next run raises others; never a second item for the same read');
  for v_n in 1 .. 10 loop perform security.har_aer_item_generate_v1(40); end loop;
  perform fx.ok(not exists (select 1 from pipeline.layer4_interventions x where x.entity in (select id::text from fx.dc where n = 1)),
                'the row-limit repeat (Diploma of Commerce shape) raises no rows request: a person''s rows would only resume the same refused read');
end $$;

-- 6 the E13 recovery pilot: listed universities, the pilot total, never a read refused on the same stored copy; yield measured
do $$
declare v jsonb; e jsonb;
begin
  v := security.aer_e13_recover_v1(true);
  perform fx.ok((v->>'asked')::int > 0, format('preview while off: %s candidates in the pilot universities', v->>'asked'));
  for e in select * from jsonb_array_elements(v->'items') loop
    if not ((e->>'provider_id') = any (security.pipeline_list_v1('aer.e13_recover_providers', '[]'::jsonb))) then raise exception 'FAILED: a university outside the pilot'; end if;
    if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = (e->>'item_id')::uuid and s.state = 'refused') then raise exception 'FAILED: a read refused on the same copy'; end if;
  end loop;
  perform fx.ok(true, 'only pilot universities; no read whose corrected read was refused on the same stored copy');
  update pipeline.platform_toolset_settings set value = '1' where key = 'aer.e13_recover_on';
  update pipeline.platform_toolset_settings set value = '3' where key = 'aer.e13_recover_total_max';
  update pipeline.platform_toolset_settings set value = '5' where key = 'aer.e13_recover_per_provider';
  v := security.aer_e13_recover_v1(false);
  perform fx.ok((v->>'asked')::int = 3, format('on: the pilot total (aer.e13_recover_total_max 3) bounds it (%s)', v->>'asked'));
  v := security.aer_e13_recover_v1(false);
  perform fx.ok(v->>'refusal' = 'the pilot total is used (aer.e13_recover_total_max)', 'then it stops and says why');
  update pipeline.aer_read_supersessions set state = 'superseded', closed_at = now() where id = (select id from pipeline.aer_read_supersessions where reason like 'AER technical recovery (E13)%' limit 1);
  update pipeline.aer_read_supersessions set state = 'refused', outcome = 'the corrected read still drops 1 printed requirement(s)', closed_at = now()
   where id = (select id from pipeline.aer_read_supersessions where reason like 'AER technical recovery (E13)%' and state = 'requested' limit 1);
  v := security.aer_e13_pilot_report_v1();
  perform fx.ok((v->>'asked')::int = 3 and (v->>'replaced')::int = 1 and (v->>'refused')::int = 1 and (v->>'waiting')::int = 1 and (v->>'yield_pct')::numeric = 50,
                format('pilot report: asked 3, replaced 1, refused 1, waiting 1, yield 50%% (%s)', v));
  update pipeline.platform_toolset_settings set value = '[]' where key = 'aer.e13_recover_providers';
  update pipeline.platform_toolset_settings set value = '40' where key = 'aer.e13_recover_total_max';
  v := security.aer_e13_recover_v1(false);
  perform fx.ok(v->>'refusal' = 'no university is in the pilot (aer.e13_recover_providers)', 'an empty pilot list asks nothing');
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.e13_recover_on';
end $$;

-- 7 what wc.aer_fair_on would do: the room and each university's share from stored classes
do $$
declare v jsonb; r jsonb;
begin
  v := security.aer_fair_projection_v1();
  perform fx.ok((v->>'ready')::int = 213 and (v->>'unchecked')::int = 0 and (v->>'share')::int = 60 and (v->>'room_when_gated')::int = 600 - 213 - (v->>'in_progress')::int, format('projection: 213 distinct ready decisions (218 items less 5 repeated matrix keys), share 60, room 600 less ready and in progress (%s)', v - 'universities'));
  select x into r from jsonb_array_elements(v->'universities') x where x->>'provider_id' = '8e1adb6c-e069-43db-9584-bd054255e702';
  perform fx.ok((r->>'at_share')::boolean and (r->>'new_reads_allowed')::int = 0, format('RMIT (%s ready) is at its share: no new reads for it', r->>'ready'));
end $$;

-- 7b submitted, saved, admitted and published counts (direction 12:16 §10): a decision as the Inbox records it, then the counts
do $$
declare v_item uuid := fx.item('RMIT University (RMIT)', 'complete', 4); v_course uuid; v jsonb; v_t0 timestamptz := now() - interval '1 second';
begin
  select entity_id into v_course from pipeline.layer4_review_items where id = v_item;
  v := security.aer_progress_counts_v1(v_t0, '8e1adb6c-e069-43db-9584-bd054255e702');
  perform fx.ok((v->>'submitted')::int = 0 and (v->>'saved')::int = 0 and (v->>'admitted_rows')::int = 0, 'before: nothing submitted, saved or admitted');
  insert into pipeline.admin_control_events(area, action, target, detail) values ('layer4', 'inbox_decide', 'aer_review:' || v_item, jsonb_build_object('provider_id', '8e1adb6c-e069-43db-9584-bd054255e702'));
  insert into pipeline.layer4_decisions(review_item_id, action) values (v_item, 'approve');
  update catalogue.course_entry_requirements set status = 'active' where provenance->>'review_item_id' = v_item::text and status = 'proposed';
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status)
  select v_course, c.provider_id, p.country_id, p.canonical_name, c.canonical_title, c.canonical_title, to_tsvector(c.canonical_title), 'published' from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = v_course;
  v := security.aer_progress_counts_v1(v_t0, '8e1adb6c-e069-43db-9584-bd054255e702');
  perform fx.ok((v->>'submitted')::int = 1 and (v->>'saved')::int = 1 and (v->>'admitted_rows')::int = 3 and (v->>'admitted_courses')::int = 1 and (v->>'published_courses')::int = 1,
                format('after one approval: submitted 1, saved 1, admitted 3 rows of 1 course, published 1 (%s)', v));
  delete from search.course_documents where course_id = v_course; delete from pipeline.layer4_decisions where review_item_id = v_item;
  update catalogue.course_entry_requirements set status = 'proposed' where provenance->>'review_item_id' = v_item::text and status = 'active';
end $$;

-- 8 nothing decided, admitted or opened by this change
select fx.ok((select count(*) from pipeline.layer4_review_items where status = 'pending') = (select pending from before_state)
             and (select count(*) from catalogue.course_entry_requirements where status = 'active') = (select active from before_state)
             and (select count(*) from pipeline.layer4_decisions) = (select decisions from before_state), 'no item decided, no row admitted, no Layer 4 item opened or closed');
