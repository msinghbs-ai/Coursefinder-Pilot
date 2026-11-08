-- CF-247 AER: one definition of "ready to decide" (Platform Admin directive 8 Nov 2026: "Reconcile the 184-item verified review pack against the live
-- Layer 4 Inbox. Resolve the discrepancy between review-pack readiness and Inbox readiness, including Approve except and stale items."; "Run readiness
-- assessment for newly replayed RMIT items").
--
-- Finding (live read 8 Nov 2026, project fxcwkweaxjtknorudmwp): two definitions of "ready" were in use for the same waiting AER items.
--   Inbox (Layer 4 Review > Inbox > Entry requirements (AER) > Ready to decide; security.aer_settlement_v1 -> layer4_aer_university_summary_v1,
--   layer4_aer_queue_v1): a person can decide the item now: the gate passes (route review) or names the rows to leave out (review_except,
--   matrix_except), and the read is not stale (course inactive or bound to another page) or held by a lock on entry requirements.
--   Scheduling count (security.work_review_ready_v1 / aer_provider_load_v1, from pipeline.layer4_item_readiness): judgement_ready only, one item per
--   entity and kind. Against live this was wrong in three ways: (1) it counted the Approve except items (24 courses, 14 matrix runs) as technically
--   held although a person, not a repair, settles them (security.aer_fair_projection_v1 already states the intent: routes review, review_except,
--   matrix_except are reviewer-ready); (2) it called 22 matrix runs duplicates although each is a different source page and run (24 runs, 24 urls,
--   24 run ids for Australian National University and The University of Melbourne); (3) it counted 4 stale reads as ready (Lincoln University 3,
--   Victoria University of Wellington 1: the course is bound to an archive record, not the page read).
-- Change: security.aer_review_ready_v1 is the single place the definition is stated; it reads security.aer_settlement_v1 (the Inbox's own source, not
--   changed) and adds the class, the listed exception rows, the URL lock flag and the true-duplicate rule (same course; for matrix runs the same
--   source page). security.work_review_ready_v1 and security.aer_provider_load_v1 now read it, so the scheduling counts equal the Inbox's "Ready to
--   decide" except for true duplicates (none live). The 600 limit (aer.schedule_layer4_max) and the share and reserve settings are unchanged.
-- Readiness for new items: security.layer4_readiness_item_v1 classifies one waiting item exactly as the readiness run does (the run now calls it);
--   security.layer4_readiness_items_v1 classifies a list of items, so the items a replay creates are assessed in the same minute instead of at the
--   next :22 or :52 run. Nothing is decided, approved, admitted or published by either.
-- Not changed (decisions for the Platform Admin, see the review pack of 8 Nov 2026): which locks hold a first read (url_locked is reported, membership
--   of "ready" is not changed), and the normalisation of a trailing slash in the bound page (reported).
-- Consumer API: untouched (no public.website_v2_*, website_edge_*, zoho_edge_*, api.* function or table is read or changed).
--
-- Live definitions this change replaces or edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.layer4_readiness_tick_v1() 06e5f4394b0c2831404fc7a766d669c4 -> 150baa35976f7a77a2b5dbba9bce4d79
--   security.work_review_ready_v1(text) 6d90b76b58f0593f7a8d6af038c8c916 -> 0067ab8da7ab36f0b6359ee1a87f39c7
--   security.aer_provider_load_v1() 3f0aede5f6f670fa75aeeb8640f4dc63 -> 7378cc5415cd84ce6b9e1282ae779e2e
-- Called, not edited: security.aer_settlement_v1(uuid) 49fb7e5071453b7eff4cf343d80b5737, security.aer_route_v1(text,jsonb) 5763be109e7cdafd5d5d4b7603b87d78.
-- Replaces: the readiness-table count of "ready" inside security.work_review_ready_v1 and security.aer_provider_load_v1 (replaced in place by security.aer_review_ready_v1); the copy of the classification steps inside the readiness run (replaced in place by security.layer4_readiness_item_v1)
-- Retires: nothing
-- Nothing is dropped or deleted. No Layer 4 item is changed; no setting or flag is changed.

-- 0 the definitions this change calls, edits or replaces, as read live --------------------------------------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_settlement_v1(uuid)', '49fb7e5071453b7eff4cf343d80b5737'),
                                 ('security.aer_route_v1(text,jsonb)', '5763be109e7cdafd5d5d4b7603b87d78')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  for r in select * from (values ('security.layer4_resolution_v1(uuid)'), ('security.layer4_blockers_v1(uuid,boolean)'), ('security.layer4_pace_v1()'),
                                 ('security.pipeline_list_v1(text,jsonb)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

create or replace function pg_temp.replace_def(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 one waiting item classified (the steps of the readiness run, unchanged) ---------------------------------------------------------------------
create or replace function security.layer4_readiness_item_v1(p_item uuid, p_use_gate boolean, p_pace jsonb default null, p_kinds text[] default null)
returns boolean language plpgsql security definer set search_path to '' as $function$
-- CF-247 Layer 4 readiness for ONE waiting item: resolvable / technical_blocked / judgement_ready, with blockers, route and the kind's measured reviewer
-- minutes, written to pipeline.layer4_item_readiness. These are the steps security.layer4_readiness_tick_v1 ran for every item (the run now calls this).
-- p_use_gate evaluates the completeness gate (E13, D-R3) for an entry-requirement item; otherwise the earlier gate result is kept and, if it held the
-- read, still holds it. Returns whether the gate was evaluated; false when the item is not waiting. Records only; no item is decided.
declare r record; v_res jsonb; v_blk jsonb; v_gate jsonb; v_gate_at timestamptz; v_ready text; v_reasons text[]; v_route text;
        v_pace jsonb := coalesce(p_pace, security.layer4_pace_v1());
        v_kinds text[] := coalesce(p_kinds, security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb));
        v_use_gate boolean := coalesce(p_use_gate, false) and exists (select 1 from pipeline.layer4_review_items z where z.id = p_item and z.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change'));
begin
  select i.id, i.entity_type, i.entity_id, i.field_code, i.created_at, x.gate, x.gate_checked_at into r
    from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id where i.id = p_item and i.status = 'pending';
  if not found then return false; end if;
  v_res := security.layer4_resolution_v1(r.id);
  v_blk := security.layer4_blockers_v1(r.id, v_use_gate);
  if v_use_gate then v_gate := v_blk->'gate'; v_gate_at := now();
  else
    v_gate := r.gate; v_gate_at := r.gate_checked_at;
    -- an earlier gate result that held the read still holds it until it is evaluated again
    if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
      v_blk := jsonb_set(v_blk, '{blockers}', (v_blk->'blockers') || jsonb_build_object('code', 'completeness_gate', 'why', coalesce(v_gate->'reasons'->>0, 'the completeness gate holds this read'),
                         'repair', 'the reader of this kind (D-R2 replacement read)', 'rule', v_gate->>'rule', 'as_at', r.gate_checked_at));
      v_blk := jsonb_set(v_blk, '{route}', to_jsonb('repair:' || (v_blk->'blockers'->0->>'code')));
    end if;
  end if;
  if v_res is not null and r.field_code = any (v_kinds) then
    v_ready := 'resolvable'; v_reasons := array[v_res->>'reason']; v_route := 'platform:' || (v_res->>'reason');
  elsif jsonb_array_length(v_blk->'blockers') > 0 then
    v_ready := 'technical_blocked'; v_reasons := (select array_agg(distinct b->>'code') from jsonb_array_elements(v_blk->'blockers') b); v_route := v_blk->>'route';
  else
    v_ready := 'judgement_ready'; v_reasons := '{}'; v_route := v_blk->>'route';
  end if;
  insert into pipeline.layer4_item_readiness as x(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, resolution, blockers,
                                                  est_minutes, gate, gate_checked_at, classified_at)
  values (r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, 'pending', v_ready, v_reasons, v_route, v_res, v_blk->'blockers',
          coalesce((v_pace->r.field_code->>'minutes')::numeric, security.pipeline_num_v1('layer4.pace_default_minutes', 3)), v_gate, v_gate_at, now())
  on conflict (item_id) do update set item_status = 'pending', readiness = excluded.readiness, reasons = excluded.reasons, route = excluded.route,
     resolution = excluded.resolution, blockers = excluded.blockers, est_minutes = excluded.est_minutes, gate = excluded.gate, gate_checked_at = excluded.gate_checked_at,
     classified_at = now();
  return v_use_gate;
end $function$;
revoke all on function security.layer4_readiness_item_v1(uuid, boolean, jsonb, text[]) from public, anon, authenticated;

create or replace function security.layer4_readiness_items_v1(p_items uuid[]) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 Layer 4 readiness for the listed waiting items now (the items an AER replay has just created), instead of at the next run of job
-- layer4-readiness: never-gated entry items first, at most layer4.gate_batch completeness gates in one call (the rest keep the run's turn). Items that
-- are not waiting are skipped. Honours layer4.readiness_on. Records only; no item is decided, approved, admitted or published.
declare r record; v_pace jsonb := security.layer4_pace_v1(); v_kinds text[] := security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb);
        v_gates int := security.pipeline_num_v1('layer4.gate_batch', 20)::int; v_g int := 0; v_n int := 0; v_use boolean;
begin
  if security.pipeline_num_v1('layer4.readiness_on', 1) < 1 then return jsonb_build_object('classified', 0, 'gates', 0, 'switch', 'off'); end if;
  for r in select i.id, i.field_code, x.gate_checked_at from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
            where i.id = any (coalesce(p_items, '{}'::uuid[])) and i.status = 'pending'
            order by (x.gate_checked_at is null and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')) desc, i.created_at, i.id loop
    v_use := r.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') and v_g < v_gates
             and (r.gate_checked_at is null or r.gate_checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int));
    perform security.layer4_readiness_item_v1(r.id, v_use, v_pace, v_kinds);
    if v_use then v_g := v_g + 1; end if;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('classified', v_n, 'gates', v_g);
end $function$;
revoke all on function security.layer4_readiness_items_v1(uuid[]) from public, anon, authenticated;

-- 2 the readiness run calls it ---------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.layer4_readiness_tick_v1()', '06e5f4394b0c2831404fc7a766d669c4', '150baa35976f7a77a2b5dbba9bce4d79',
  array[array[$o$      v_res := security.layer4_resolution_v1(r.id);
      v_use_gate := r.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') and v_g < v_gates
                    and (r.gate_checked_at is null or r.gate_checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int));
      v_blk := security.layer4_blockers_v1(r.id, v_use_gate);
      if v_use_gate then v_g := v_g + 1; v_gate := v_blk->'gate'; v_gate_at := now();
      else
        v_gate := r.gate; v_gate_at := r.gate_checked_at;
        -- an earlier gate result that held the read still holds it until it is evaluated again
        if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
          v_blk := jsonb_set(v_blk, '{blockers}', (v_blk->'blockers') || jsonb_build_object('code', 'completeness_gate', 'why', coalesce(v_gate->'reasons'->>0, 'the completeness gate holds this read'),
                             'repair', 'the reader of this kind (D-R2 replacement read)', 'rule', v_gate->>'rule', 'as_at', r.gate_checked_at));
          v_blk := jsonb_set(v_blk, '{route}', to_jsonb('repair:' || (v_blk->'blockers'->0->>'code')));
        end if;
      end if;
      if v_res is not null and r.field_code = any (v_kinds) then
        v_ready := 'resolvable'; v_reasons := array[v_res->>'reason']; v_route := 'platform:' || (v_res->>'reason');
      elsif jsonb_array_length(v_blk->'blockers') > 0 then
        v_ready := 'technical_blocked'; v_reasons := (select array_agg(distinct b->>'code') from jsonb_array_elements(v_blk->'blockers') b); v_route := v_blk->>'route';
      else
        v_ready := 'judgement_ready'; v_reasons := '{}'; v_route := v_blk->>'route';
      end if;
      insert into pipeline.layer4_item_readiness as x(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, resolution, blockers,
                                                      est_minutes, gate, gate_checked_at, classified_at)
      values (r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, 'pending', v_ready, v_reasons, v_route, v_res, v_blk->'blockers',
              coalesce((v_pace->r.field_code->>'minutes')::numeric, security.pipeline_num_v1('layer4.pace_default_minutes', 3)), v_gate, v_gate_at, now())
      on conflict (item_id) do update set item_status = 'pending', readiness = excluded.readiness, reasons = excluded.reasons, route = excluded.route,
         resolution = excluded.resolution, blockers = excluded.blockers, est_minutes = excluded.est_minutes, gate = excluded.gate, gate_checked_at = excluded.gate_checked_at,
         classified_at = now();
      v_cls := v_cls + 1;
$o$, $n$      v_use_gate := r.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') and v_g < v_gates
                    and (r.gate_checked_at is null or r.gate_checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int));
      -- 8 Nov 2026: one item is classified by security.layer4_readiness_item_v1 (also called for the items a replay creates), not by a copy of its steps here
      perform security.layer4_readiness_item_v1(r.id, v_use_gate, v_pace, v_kinds);
      if v_use_gate then v_g := v_g + 1; end if;
      v_cls := v_cls + 1;
$n$]], array[1]);

-- 3 the single definition of "ready to decide" ------------------------------------------------------------------------------------------------
create or replace function security.aer_review_ready_v1(p_provider uuid default null)
returns table(item_id uuid, field_code text, provider_id uuid, created_at timestamptz, settlement text, route text, review_class text, ready boolean,
              exception_rows integer, url_locked boolean, duplicate_of uuid, readiness text)
language sql stable security definer set search_path to '' as $function$
-- CF-247 AER (8 Nov 2026): every waiting entry-requirement item (one university, or all when null) with the one definition of "ready to decide".
-- ready = security.aer_settlement_v1 says ready (the Inbox's own source): the completeness gate passes (review_class complete), or it names the rows
-- to leave out (approve_except; exception_rows counts the rows it lists), and the read is not stale (course inactive or bound to another page), not
-- held by a lock on entry requirements, and gated. Held: recoverable (an automatic step remains, or not yet gated) and needs_input.
-- url_locked: the course has a manual lock on a field of entry.supersede_lock_fields (reported, not part of "ready"; the Platform Admin rules on it).
-- duplicate_of: the older waiting item for the same course (for a matrix run: the same source page); a matrix run from another page is not a duplicate.
  with s as (select * from security.aer_settlement_v1(p_provider)),
       lf as (select security.pipeline_list_v1('entry.supersede_lock_fields', '["entry_requirements", "course_url", "official_url"]'::jsonb) f),
       w as (select s.item_id, s.field_code, s.provider_id, s.created_at, s.settlement, s.route, i.entity_type, i.entity_id, x.readiness, x.gate,
                    first_value(i.id) over (partition by i.entity_id, i.field_code, case when i.field_code = 'course_entry_first_read' then null else i.proposed_value->>'url' end
                                            order by i.created_at, i.id) first_id
               from s join pipeline.layer4_review_items i on i.id = s.item_id left join pipeline.layer4_item_readiness x on x.item_id = i.id)
  select w.item_id, w.field_code, w.provider_id, w.created_at, w.settlement, w.route,
         case w.settlement when 'ready' then (case when w.route = 'review' then 'complete' else 'approve_except' end) else w.settlement end,
         w.settlement = 'ready',
         coalesce((select sum(jsonb_array_length(g.v))::int from jsonb_each(coalesce(w.gate, '{}'::jsonb)) g(k, v)
                    where jsonb_typeof(g.v) = 'array' and g.k = any (case when w.route = 'matrix_except' then array['flagged', 'same_identity']
                                                                          else array['audience', 'not_requirement', 'other_programme', 'joined'] end)), 0),
         w.entity_type = 'course' and exists (select 1 from pipeline.manual_locks l, lf where l.entity = 'course' and l.entity_id = w.entity_id and l.field = any (lf.f)),
         case when w.first_id <> w.item_id then w.first_id end,
         w.readiness
    from w
$function$;
revoke all on function security.aer_review_ready_v1(uuid) from public, anon, authenticated;

-- 4 the scheduling counts read it ---------------------------------------------------------------------------------------------------------------
select pg_temp.replace_def('security.work_review_ready_v1(text)', '6d90b76b58f0593f7a8d6af038c8c916', '0067ab8da7ab36f0b6359ee1a87f39c7',
$d$create or replace function security.work_review_ready_v1(p_category text) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F4, 8 Nov 2026: a review category's waiting items by state. Category aer reads security.aer_review_ready_v1, the one definition of
-- "ready to decide" (the Inbox's): ready_waiting = complete or Approve except, not stale, not a true duplicate (approve_except is the part of it that
-- needs rows left out); technical = held (an automatic step remains, or a person must supply something); stale; duplicates = a second read of the same
-- course, or of the same source page; resolvable = settled by the platform. Each waiting item is in exactly one of them (duplicate, resolvable, stale,
-- ready, then held). Other categories count by pipeline.layer4_item_readiness as before. Read only.
  with c as (select * from pipeline.work_review_categories where category = p_category),
       q as (select r.item_id, r.review_class, r.settlement, r.duplicate_of, r.readiness, r.ready
               from security.aer_review_ready_v1(null) r, c where p_category = 'aer' and r.field_code = any (c.field_codes)),
       qb as (select q.*, case when q.duplicate_of is not null then 'duplicate' when q.readiness = 'resolvable' then 'resolvable' when q.settlement = 'stale' then 'stale'
                               when q.ready and coalesce(q.readiness, '') <> 'closed' then 'ready' else 'held' end bucket from q),
       w as (select i.id, i.entity_id, i.field_code, x.readiness,
                    row_number() over (partition by i.entity_id, i.field_code order by i.created_at, i.id) rn
               from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id, c
              where p_category <> 'aer' and i.status = 'pending' and i.field_code = any (c.field_codes))
  select jsonb_build_object('category', p_category,
    'raw_waiting', case when p_category = 'aer' then (select count(*) from qb) else (select count(*) from w) end,
    'ready_waiting', case when p_category = 'aer' then (select count(*) from qb where bucket = 'ready')
                          else (select count(*) from w where w.rn = 1 and coalesce(w.readiness, 'judgement_ready') not in ('technical_blocked', 'resolvable', 'closed')) end,
    'approve_except', case when p_category = 'aer' then (select count(*) from qb where bucket = 'ready' and review_class = 'approve_except') else 0 end,
    'technical', case when p_category = 'aer' then (select count(*) from qb where bucket = 'held') else (select count(*) from w where w.readiness = 'technical_blocked') end,
    'stale', case when p_category = 'aer' then (select count(*) from qb where bucket = 'stale') else 0 end,
    'resolvable', case when p_category = 'aer' then (select count(*) from qb where bucket = 'resolvable') else (select count(*) from w where w.readiness = 'resolvable') end,
    'duplicates', case when p_category = 'aer' then (select count(*) from qb where bucket = 'duplicate') else (select count(*) from w where w.rn > 1) end,
    'in_progress', (select count(distinct coalesce(f.course_id, f.provider_id)) from pipeline.field_enrich_items f, c
                     where cardinality(c.in_progress_fields) > 0 and f.field = any (c.in_progress_fields) and f.state in ('queued', 'waiting', 'ai', 'leased')))
$function$$d$);

select pg_temp.replace_def('security.aer_provider_load_v1()', '3f0aede5f6f670fa75aeeb8640f4dc63', '7378cc5415cd84ce6b9e1282ae779e2e',
$d$create or replace function security.aer_provider_load_v1() returns table(provider_id uuid, waiting bigint)
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F4, 8 Nov 2026: each university's review-ready AER decisions waiting (security.aer_review_ready_v1, the one definition: complete or
-- Approve except, not stale, not a true duplicate) plus distinct entry reads in progress (the share check).
  select z.pid, count(distinct z.k) from (
    select q.provider_id pid, q.item_id::text k
      from security.aer_review_ready_v1(null) q join pipeline.work_review_categories rc on rc.category = 'aer'
     where q.field_code = any (rc.field_codes) and q.ready and q.duplicate_of is null and coalesce(q.readiness, '') not in ('resolvable', 'closed')
    union all
    select f.provider_id, 'read:' || coalesce(f.course_id, f.provider_id)
      from pipeline.field_enrich_items f join pipeline.work_review_categories rc on rc.category = 'aer'
     where f.field = any (rc.in_progress_fields) and f.state in ('queued', 'waiting', 'ai', 'leased')) z
   where z.pid is not null group by z.pid
$function$$d$);

-- 5 component register ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_review_ready_v1', 'Layer 4', 'CF-247 AER: the one definition of ready to decide (the Inbox''s), with class, listed exception rows, URL lock and true duplicates', 'active', '{}', '20261108040000'),
 ('function', 'security.layer4_readiness_item_v1', 'Layer 4', 'CF-247 readiness: one waiting item classified (the steps the readiness run took per item)', 'active', '{}', '20261108040000'),
 ('function', 'security.layer4_readiness_items_v1', 'Layer 4', 'CF-247 readiness: the listed waiting items classified now (items an AER replay has just created)', 'active', '{}', '20261108040000')
on conflict do nothing;

-- 6 post-check -------------------------------------------------------------------------------------------------------------------------------
do $p$
declare v jsonb := security.work_review_ready_v1('aer');
begin
  if (v->>'ready_waiting')::int + (v->>'technical')::int + (v->>'stale')::int + (v->>'resolvable')::int + (v->>'duplicates')::int <> (v->>'raw_waiting')::int then
    raise exception 'post-check: the waiting AER items are not each in exactly one state: %', v; end if;
  if (select count(*) from security.aer_review_ready_v1(null) q where q.ready) <> (select count(*) from security.aer_settlement_v1(null) s where s.settlement = 'ready') then
    raise exception 'post-check: ready differs from the Inbox settlement'; end if;
end $p$;
