-- CF-247 AER throughput fixtures (migration 20261104470000): assertions on the production-shaped seed. Run by run.sh after the migration.
\set ON_ERROR_STOP on
create or replace function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
create or replace function fx.held_ready() returns int language sql as $f$
  select count(*)::int from pipeline.layer4_item_readiness x join fx.gate f on f.item_id = x.item_id
   where x.field_code = 'course_entry_first_read' and x.readiness = 'judgement_ready' and fx.cls(f.g) <> 'complete' $f$;

-- 1 readiness gates never-gated entry reads first, within layer4.gate_batch a run, until no held read is reported judgement_ready
do $$
declare v_runs int := 0; v_g int; v_first int;
begin
  perform fx.ok(fx.held_ready() = 376, 'before the first run after the change: 376 held course reads are reported judgement_ready (as live)');
  truncate fx.gate_calls;
  perform security.layer4_readiness_tick_v1();
  select count(*) into v_g from fx.gate_calls;
  select count(*) into v_first from fx.gate_calls c join pipeline.layer4_item_readiness x on x.item_id = c.item_id join fx.gate f on f.item_id = c.item_id
   where fx.cls(f.g) <> 'complete' and f.g->>'rule' = 'E13';
  perform fx.ok(v_g = 20 and v_first = 20, 'one run gates 20 (layer4.gate_batch), all of them never-gated held reads, not the already-gated items');
  perform fx.ok(fx.held_ready() = 356, 'after one run 356 remain judgement_ready (20 now technical_blocked)');
  v_runs := 1;
  while fx.held_ready() > 0 and v_runs < 40 loop perform security.layer4_readiness_tick_v1(); v_runs := v_runs + 1; end loop;
  perform fx.ok(v_runs = 19, format('every held course read is gated after 19 runs (%s; 376 / 20; about 10 hours at :22 and :52)', v_runs));
  perform fx.ok((select count(*) from pipeline.layer4_item_readiness x where x.field_code = 'course_entry_first_read' and x.readiness = 'technical_blocked') = 395,
                '395 course reads are technical_blocked (completeness gate), as the gate holds them');
  perform fx.ok((select count(*) from pipeline.layer4_item_readiness x where x.field_code = 'course_entry_first_read' and x.readiness = 'judgement_ready') = 169,
                '169 complete course reads stay judgement_ready (review-ready for a person)');
  perform fx.ok((select count(*) from pipeline.layer4_review_items where status <> 'pending') = 0, 'no Layer 4 item changed status');
  -- once all are gated the run gates by due time again (nothing is starved the other way)
  truncate fx.gate_calls; update pipeline.layer4_item_readiness set classified_at = now() - interval '3 hours', gate_checked_at = now() - interval '3 hours';
  perform security.layer4_readiness_tick_v1();
  perform fx.ok((select count(*) from fx.gate_calls) = 20, 'with every item gated, a run re-gates 20 due items (layer4.gate_batch unchanged)');
end $$;

-- 2 technical recovery records the gate class; E13 recovery is off and asks nothing
do $$
declare v jsonb; v_sup int := (select count(*) from pipeline.aer_read_supersessions); v_jobs int := (select count(*) from pipeline.admin_jobs);
begin
  v := security.aer_technical_recovery_v1();
  perform fx.ok((v->>'technical_checked')::int = 376, format('technical recovery now sees the 376 held reads readiness had hidden (the 37 gated before were recorded by the run before the change) (%s)', v->>'technical_checked'));
  perform fx.ok((select count(*) from pipeline.layer4_item_readiness x where x.readiness = 'technical_blocked'
                   and exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = x.item_id::text)) = 413,
                'every held item (395 course reads, 18 matrix runs) has a technical recovery record');
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'duplicate' and w.stage = 'parked') = 5,
                'the repeated keys (three universities with two waiting matrix runs, one with three) stay parked as duplicates, as before');
  perform fx.ok(v->'e13_recover'->>'refusal' = 'aer.e13_recover_on is 0' and (v->'e13_recover'->>'asked')::int = 0, 'E13 recovery ships off and asks nothing');
  perform fx.ok((select count(*) from pipeline.aer_read_supersessions) = v_sup and (select count(*) from pipeline.admin_jobs) = v_jobs, 'off: no corrected read and no job');
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'technical_hold' and w.evidence::text like '%"gate_class": "shared_page"%')
                = (select count(*) from pipeline.work_items w join fx.gate f on f.item_id::text = w.entity where w.lane = 'aer_technical' and w.evidence::text like '%gate_class%' and fx.cls(f.g) = 'shared_page')
                and (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.evidence::text like '%gate_class%') = 376,
                'every hold recorded after the change carries its gate class; shared-page holds carry shared_page (Human-assisted recovery''s aer_course_identity pattern finds them)');
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'technical_hold' and w.evidence::text like '%"reread_can_fix": true%')
                = (select count(*) from pipeline.work_items w join fx.gate f on f.item_id::text = w.entity where w.lane = 'aer_technical' and w.evidence::text like '%gate_class%' and fx.cls(f.g) = 'drops_uncovered'),
                'holds for dropped minimums (and only they) are marked as fixable by a re-read; row-limit, shared-page and row-level holds are not');
end $$;

-- 3 the preview: readiness-aware, stored copy of the same page only, tries and spacing, fair by university, within the run size; writes nothing
do $$
declare v jsonb; v_sup int := (select count(*) from pipeline.aer_read_supersessions); e jsonb;
begin
  v := security.aer_e13_recover_v1(true);
  perform fx.ok((v->>'asked')::int = 10 and v->>'refusal' is null, format('preview: 10 reads a run (batch.aer_e13_recover) while off (%s)', v->>'asked'));
  perform fx.ok((select count(*) from pipeline.aer_read_supersessions) = v_sup, 'preview writes nothing');
  for e in select * from jsonb_array_elements(v->'items') loop
    perform 1 from pipeline.coverage_course_pages pg join pipeline.layer4_review_items i on i.entity_id = pg.course_id
     where i.id = (e->>'item_id')::uuid and pg.evidence_id is not null and pg.url = i.proposed_value->>'url';
    if not found then raise exception 'FAILED: preview picked % without a stored copy of the same page', e->>'item_id'; end if;
    if fx.cls((select g from fx.gate where item_id = (e->>'item_id')::uuid)) <> 'drops_uncovered' then raise exception 'FAILED: preview picked a hold a re-read cannot fix'; end if;
    if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = (e->>'item_id')::uuid) then raise exception 'FAILED: preview picked an item tried within the spacing'; end if;
  end loop;
  perform fx.ok(true, 'preview picks only dropped-minimum holds with a stored copy of the same page, none tried within aer.schedule_held_retry_days');
  perform fx.ok((select max(n) from (select count(*) n from jsonb_array_elements(v->'items') it group by it->>'provider_id') z) <= 2
                and (select count(*) from jsonb_array_elements(v->'items') it where (it->>'provider_id')::uuid = '8e1adb6c-e069-43db-9584-bd054255e702') <= 2,
                'fair by university: at most 2 a university a run (RMIT, with 91 such holds, takes 2 of 10)');
end $$;

-- 4 on: the existing corrected read (D-R2) from the stored copy; bounded a run and a day; no second request for the same item
do $$
declare v jsonb; v2 jsonb; v_held int;
begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'aer.e13_recover_on';
  v := security.aer_technical_recovery_v1()->'e13_recover';
  perform fx.ok((v->>'asked')::int = 10, format('on: one run asks 10 corrected reads (%s)', v->>'asked'));
  perform fx.ok((select count(*) from pipeline.aer_read_supersessions where state = 'requested' and reason like 'AER technical recovery (E13)%') = 10, 'each is a D-R2 request (pipeline.aer_read_supersessions)');
  perform fx.ok((select count(*) from pipeline.admin_jobs j where j.args->>'scraper' = 'false' and j.args->>'entry_read' = 'true' and j.reason like 'Corrected read (D-R2)%') = 10,
                'each read uses the stored page (scraper off: no Firecrawl)');
  perform fx.ok((select count(*) from pipeline.field_enrich_items where field = 'entry_requirements' and state = 'queued') = 10, '10 entry reads queued for the existing reader');
  perform fx.ok((select count(*) from pipeline.layer4_review_items where status <> 'pending') = 0, 'nothing approved, rejected or superseded by the request itself');
  v2 := security.aer_e13_recover_v1(false);
  perform fx.ok((v2->>'asked')::int = 10 and not exists (select 1 from jsonb_array_elements(v2->'items') a join jsonb_array_elements(v->'items') b on a->>'item_id' = b->>'item_id'),
                'the next run asks 10 others: an item with a correction requested or in progress is not asked again');
  update pipeline.platform_toolset_settings set value = '25' where key = 'aer.e13_recover_daily_max';
  v2 := security.aer_e13_recover_v1(false);
  perform fx.ok((v2->>'asked')::int = 5, format('the daily budget (aer.e13_recover_daily_max 25, 20 used) leaves 5 (%s)', v2->>'asked'));
  v2 := security.aer_e13_recover_v1(false);
  perform fx.ok((v2->>'asked')::int = 0 and v2->>'refusal' like 'the daily budget of E13 recovery is used%', 'then it stops, and says why');
  -- the scheduled held step yields while E13 recovery is on, so the daily cap of new reads is not spent on corrections
  select count(*) into v_held from security.aer_schedule_held_v1(10);
  perform fx.ok(v_held = 0, 'on: the scheduled tick''s held step returns nothing');
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.e13_recover_on';
  select count(*) into v_held from security.aer_schedule_held_v1(10) where eligible;
  perform fx.ok(v_held > 0, format('off: the held step works as before (%s eligible)', v_held));
  update pipeline.platform_toolset_settings set value = '1' where key = 'aer.e13_recover_on';
  update pipeline.platform_toolset_settings set value = '40' where key = 'aer.e13_recover_daily_max';
end $$;

-- 5 refusals: AI stopped, the run-as owner without the rank, a gate that changed since readiness
do $$
declare v jsonb; v_item uuid;
begin
  insert into fx.ai_stop values ('enrich_fields', 'the daily AI ceiling is reached');
  v := security.aer_e13_recover_v1(false);
  perform fx.ok(v->>'refusal' like 'AI reading is stopped%' and (v->>'asked')::int = 0, 'AI stopped: nothing asked');
  delete from fx.ai_stop;
  update security.roles set rank = 4;
  v := security.aer_e13_recover_v1(false);
  perform fx.ok(v->>'refusal' like 'the owner it runs as does not hold%', 'run-as owner below Platform Admin: nothing asked');
  update security.roles set rank = 6;
  select (security.aer_e13_recover_v1(true)->'items'->0->>'item_id')::uuid into v_item;
  update fx.gate set g = '{"rule": "E13", "complete": true, "rows_cut": 0, "shared_page": [], "drops_uncovered": [], "reasons": []}' where item_id = v_item;
  v := security.aer_e13_recover_v1(false);
  perform fx.ok(exists (select 1 from jsonb_array_elements(v->'skipped') s where (s->>'item_id')::uuid = v_item and s->>'why' = 'the gate now says complete')
                and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = v_item and s.state = 'requested'),
                'the gate is checked again before acting: a read that is now complete is not re-read');
end $$;

-- 6 the 600 limit, E13 and the consumer API are untouched by the change
do $$
begin
  perform fx.ok((select (value #>> '{}')::int from pipeline.platform_toolset_settings where key = 'aer.schedule_layer4_max') = 600, 'aer.schedule_layer4_max is still 600');
  perform fx.ok((select count(*) from pipeline.layer4_review_items where status = 'pending') = 605, 'still 605 waiting items: the change opens and closes none');
end $$;
