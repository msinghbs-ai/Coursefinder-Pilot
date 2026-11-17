-- CF-247 F-CDESC visible results (Platform Admin, 10 Nov 2026): "I should not have to rely on your chat messages to know whether descriptions are being processed, admitted and published."
-- Data Delivery shows the course description STAGES, counted live and exactly (no estimate, no forecast): source -> AI proposal -> validation -> admitted -> Website and Zoho.
--   security.data_delivery_cdesc_stages_v1() (read only) is called by the existing security.data_delivery_v1 for the stream 'cdesc' only, as one new key 'stages'. Nothing else in that
--   function changes: it stays the one Data Delivery read, and the existing Data Delivery component draws the new key. No new panel, table or setting; the number of reasons shown is the
--   existing setting data_delivery.reasons_shown. Machine and person counts are kept apart: admitted by the machine rule (live), admitted by a person (a Layer 4 approval whose decision is not
--   marked actor_kind machine), withdrawn, declined by the machine rule with the top reasons. Publication is the Website's own published status of the course; "unpublished course" is counted
--   apart (an unpublished course is not served to the Website listing). The Zoho course feed carries no description field, so Zoho is "not counted" with that reason, never 0.
--   The machine's own read-back at admission (consumer_check) is shown as recorded: it is the Website detail function answering by identifier, which is not the same as listed and published.
--   A failure to count returns known false with the error: the rest of Data Delivery is not affected. Cost (live, 10 Nov 2026): the counts read the Layer 4 items, the ledger, the held readings and
--   the catalogue's described courses, about 0.1 s warm; the page and feed tables are not scanned.
-- Live definition (pg_proc.prosrc md5, read 10 Nov 2026, project fxcwkweaxjtknorudmwp), original -> edited:
--   security.data_delivery_v1()  916e015e0cce905c97e17786b4c2ada1 -> b67bd181c58546076da48e7b5f00a2a4
-- Forward recovery (the original body, byte for byte): supabase/held/cdesc_visible_results_forward_recovery.sql. The new function is dropped by a paste file only if the Platform Admin asks.
-- The consumer API (G3) is not touched: no public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* object, table column or edge function changes;
-- the consumer tables and the feed are only read. No setting value changes. Nothing is dropped or deleted.
-- Replaces: security.data_delivery_v1 is edited in place (md5-guarded, one new key); otherwise nothing
-- Retires: nothing

do $g$ declare s text; begin
  foreach s in array array['security.data_delivery_v1()', 'security.pipeline_num_v1(text,numeric)'] loop
    if to_regprocedure(s) is null then raise exception 'required % is missing (apply 20261110000100 first)', s; end if;
  end loop;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the stage counts (read only)
create or replace function security.data_delivery_cdesc_stages_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare v_top int := security.pipeline_num_v1('data_delivery.reasons_shown', 3)::int; -- derived: the existing Data Delivery setting, how many exact reasons a stream lists
begin
  return (
  with l4 as (select i.id, i.status, i.entity_id from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read'),
       led as (select a.course_id, a.review_item_id, a.outcome, a.reason_code, a.reason, a.created_at, a.withdrawn_at, a.consumer_check from pipeline.course_description_machine_admissions a),
       live_m as (select l.course_id, coalesce(l.consumer_check, 'not_checked') chk from led l where l.outcome = 'admitted' and l.withdrawn_at is null),
       declined as (select l.reason_code, l.reason, l.created_at from led l join l4 on l4.id = l.review_item_id where l.outcome = 'declined' and l4.status = 'pending'),
       top as (select d.reason_code code, count(*) n, (array_agg(d.reason order by d.created_at desc))[1] example from declined d group by 1 order by 2 desc, 1 limit v_top),
       described as (select c.id from catalogue.courses c where nullif(btrim(c.description), '') is not null),
       shown as (select d.course_id from search.course_documents d where d.publication_status = 'published' and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)),
       held as (select count(*) filter (where f.reason like 'held\_first\_admission:%') behind_cap, count(*) filter (where f.reason like 'held: %') by_check
                  from pipeline.field_enrich_items f where f.field = 'description' and f.state = 'skipped'),
       zl as (select z.item ? 'description' has_key from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null order by z.seq desc limit 1)
  select jsonb_build_object(
    'known', true, 'counted_at', now(), 'unit', 'courses',
    'source', jsonb_build_object('proposals_from_a_stored_page', (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.evidence_id is not null)),
    'proposal', jsonb_build_object('waiting_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
                                   'held_behind_provider_cap', (select behind_cap from held), 'held_by_a_check', (select by_check from held)),
    'validation', jsonb_build_object('not_yet_checked_by_machine', (select count(*) from l4 where l4.status = 'pending' and not exists (select 1 from led l where l.review_item_id = l4.id)),
                                     'declined_by_machine', (select count(*) from declined),
                                     'top_decline_reasons', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'n', t.n, 'example', t.example) order by t.n desc, t.code) from top t), '[]'::jsonb)),
    'admitted', jsonb_build_object('by_machine', (select count(*) from live_m),
                                   'by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved')
                                                    and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = l4.id and md.layer2_state->>'actor_kind' = 'machine')),
                                   'withdrawn', (select count(*) from led where outcome = 'admitted' and withdrawn_at is not null),
                                   'described_courses', (select count(*) from described),
                                   'described_other_route', (select count(*) from described d where d.id not in (select course_id from live_m) and d.id not in (select l4.entity_id from l4 where l4.status in ('approved', 'edited_approved')))),
    'consumers', jsonb_build_object('website_published', (select count(*) from described d where d.id in (select course_id from shown)),
                                    'unpublished_course', (select count(*) from described d where d.id not in (select course_id from shown)),
                                    'machine_readback', jsonb_build_object('matched', (select count(*) from live_m where chk = 'matched'), 'lag', (select count(*) from live_m where chk = 'lag'),
                                                                           'not_in_feed', (select count(*) from live_m where chk = 'not_in_feed'), 'error', (select count(*) from live_m where chk = 'error'),
                                                                           'not_checked', (select count(*) from live_m where chk not in ('matched', 'lag', 'not_in_feed', 'error'))),
                                    'zoho', coalesce((select case when zl.has_key then jsonb_build_object('known', false, 'reason', 'The Zoho course feed now carries a description field, but how many reach Zoho is not counted yet.')
                                                         else jsonb_build_object('known', false, 'reason', 'The latest course item in the Zoho course feed has no description field, so a course description does not reach Zoho. Nothing is counted for it.') end from zl),
                                                    jsonb_build_object('known', false, 'reason', 'The Zoho course feed holds no course item, so nothing is counted for it.'))))
  );
exception when others then
  -- a count that cannot be made is shown as such, never as 0, and does not stop the rest of Data Delivery
  return jsonb_build_object('known', false, 'reason', 'The stage counts could not be read: ' || sqlerrm);
end $f$;
comment on function security.data_delivery_cdesc_stages_v1() is 'CF-247 F-CDESC visible results (Platform Admin 10 Nov 2026): the course description stages counted live and exactly for Data Delivery (read only): stored-page proposals, waiting and held readings, the machine rule''s declines with the top reasons, admitted by the machine rule and by a person kept apart, withdrawn, described courses, the Website published status, unpublished courses and the machine read-back. Called by security.data_delivery_v1 for the stream cdesc.';
revoke all on function security.data_delivery_cdesc_stages_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the md5-guarded edit
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.data_delivery_v1()', '916e015e0cce905c97e17786b4c2ada1', 'b67bd181c58546076da48e7b5f00a2a4',
     array[$o$'jobs', v_job_sum || jsonb_build_object('list', v_jobs), 'recovery', v_rec, 'flags', v_flags,$o$],
     array[$n$'jobs', v_job_sum || jsonb_build_object('list', v_jobs), 'recovery', v_rec, 'flags', v_flags,
      'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then continue; end if; -- already applied
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
  end loop;
end $m$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- register, post-check
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.data_delivery_cdesc_stages_v1', 'Platform', 'F-CDESC: the course description stage counts for Data Delivery (read only, live)', 'active', '{}', '20261110100000')
on conflict do nothing;

do $post$ begin
  if to_regprocedure('security.data_delivery_cdesc_stages_v1()') is null then raise exception 'post-check: the stage counts function is missing'; end if;
  if position('data_delivery_cdesc_stages_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: Data Delivery does not call the stage counts'; end if;
end $post$;
