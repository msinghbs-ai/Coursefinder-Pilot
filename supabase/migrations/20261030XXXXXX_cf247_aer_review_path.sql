-- CF-247 decisions A1-A3 (Platform Admin, 30 Oct 2026 06:53; admin docs/platform/ui-audit/2026-10-30-platform-admin-decision-paper.md Part A):
-- the evidence-aware AER review path for the three AER Layer 4 kinds (entry_matrix_first_run, entry_matrix_change, course_entry_first_read).
--   A1 "Approve except": the reviewer ticks the rows to leave out and gives one reason. The ticked rows stay unadmitted and visibly identifiable
--      (existing row status inactive; status_reason "excluded by approve except (Layer 4 item <id>, reviewer <id>): <reason>"; provenance
--      aer_exclusion). Every other row is admitted only through the existing apply functions, after the same identity, completeness and
--      table checks (scale and basis are table constraints re-checked on the status change). Lineage (item, run, source, stored copy hash,
--      rows) is kept on the decision (pipeline.layer4_decisions.final_value) and in pipeline.admin_control_events (area layer4, action aer_*).
--      An AER item is never edited inline: edit_and_approve on an AER kind accepts only the Approve except shape.
--      The completeness admission rule of 26 Oct ("a read is admitted whole or rejected") becomes "every row of a complete read is admitted
--      or explicitly excluded": the read must still be complete and fully waiting; only the reviewer's ticked rows are left out.
--   A2 the generic bulk decide (l4_api.layer4_review_bulk_decide) and the generic batch decide (security.layer4_batch_decide_v1_impl) skip
--      AER kinds, decide nothing and report how many they skipped (skipped_aer).
--   A3 AER admission and rejection are the Platform Admin's (rank 6), enforced in security.layer4_review_decide_impl for AER kinds only.
--      Curators keep their operational editing in Catalogue > Entry requirements (public.admin_aer is not changed).
-- Layer 4 > Inbox shows AER items as their own kind (aer_review) with their rows (public.layer4_aer_review_read); they were shown as course links.
-- W28 (security.aer_reread_v1) is not changed: it supersedes only proposed rows, so excluded rows (inactive) are never touched by a re-read.
-- Replaces: security.layer4_review_decide_impl, security.entry_matrix_review_apply_v1, security.course_entry_review_apply_v1, l4_api.layer4_review_bulk_decide, security.layer4_batch_decide_v1_impl, security.layer4_inbox_kinds_v1, security.layer4_inbox_items_v1, public.admin_layer4_inbox (same names, md5-guarded edits)
-- Retires: nothing (the inline edit-and-approve route for AER items is switched off here: it accepts only the Approve except shape; AER items no longer show as course links in the Inbox)
-- Nothing dropped, deleted or renamed. No new table, job, setting, row status or Layer 4 action. Consumer API untouched (G3).

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1. The AER kinds, named once.
create or replace function security.aer_review_kinds_v1() returns text[]
language sql immutable set search_path to ''
as $function$
  select array['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read']::text[]
$function$;
revoke all on function security.aer_review_kinds_v1() from public, anon;
grant execute on function security.aer_review_kinds_v1() to authenticated;
comment on function security.aer_review_kinds_v1() is 'CF-247 A1-A3 (30 Oct 2026): the Layer 4 kinds that take the AER review path only (Platform Admin, one at a time, never in bulk).';

-- 2. Lineage of an AER item as it waits: item, run, source, stored copy hash and the waiting rows.
create or replace function security.aer_review_lineage_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare i pipeline.layer4_review_items%rowtype; r pipeline.entry_matrix_runs%rowtype;
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or not (i.field_code = any (security.aer_review_kinds_v1())) then raise exception 'not an AER review item' using errcode = '22023'; end if;
  if i.field_code = 'course_entry_first_read' then
    return jsonb_build_object('review_item_id', i.id, 'kind', i.field_code, 'course_id', i.entity_id, 'enrich_item_id', i.proposed_value->'item_id',
      'source_url', i.proposed_value->>'url', 'evidence_id', i.evidence_id,
      'proposed_row_ids', (select coalesce(jsonb_agg(x.id order by x.id), '[]'::jsonb) from catalogue.course_entry_requirements x
                            where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed'),
      'row_evidence_ids', (select coalesce(jsonb_agg(distinct x.evidence_id), '[]'::jsonb) from catalogue.course_entry_requirements x
                            where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and x.evidence_id is not null),
      'row_content_hashes', (select coalesce(jsonb_agg(distinct e.content_hash), '[]'::jsonb) from catalogue.course_entry_requirements x
                              join pipeline.evidence_artifacts e on e.id = x.evidence_id
                              where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and e.content_hash is not null));
  end if;
  select * into r from pipeline.entry_matrix_runs where review_item_id = p_item;
  return jsonb_build_object('review_item_id', i.id, 'kind', i.field_code, 'provider_id', i.entity_id, 'run_id', r.id, 'source_id', r.source_id,
    'source_url', coalesce((select s.url from pipeline.entry_matrix_sources s where s.id = r.source_id), i.proposed_value->>'url'),
    'content_hash', r.content_hash, 'model', r.model_code, 'run_done_at', r.done_at, 'rows_dropped', r.rows_dropped,
    'completeness', jsonb_build_object('status', r.result->'completeness'->>'status', 'matched', r.result->'completeness'->'matched',
                                       'required', case when r.id is not null then security.entry_completeness_required_v1(r.provider_id) end),
    'proposed_row_ids', (select coalesce(jsonb_agg(m.id order by m.id), '[]'::jsonb) from catalogue.provider_entry_matrix m
                          where r.id is not null and m.run_id = r.id and m.status = 'proposed'),
    'row_evidence_ids', (select coalesce(jsonb_agg(distinct m.evidence_id), '[]'::jsonb) from catalogue.provider_entry_matrix m
                          where r.id is not null and m.run_id = r.id and m.status = 'proposed' and m.evidence_id is not null),
    'row_content_hashes', (select coalesce(jsonb_agg(distinct m.content_hash), '[]'::jsonb) from catalogue.provider_entry_matrix m
                            where r.id is not null and m.run_id = r.id and m.status = 'proposed' and m.content_hash is not null));
end $function$;
revoke all on function security.aer_review_lineage_v1(uuid) from public, anon, authenticated;
comment on function security.aer_review_lineage_v1(uuid) is 'CF-247 A1 (30 Oct 2026): the lineage of a waiting AER item (item, run, source, stored copy hash, waiting row ids), recorded with every AER decision. Owner only.';

-- 3. "Approve except": checks the reviewer's explicit exclusion and returns the decision's final value (rows, reviewer, reason, lineage).
create or replace function security.aer_approve_except_v1(p_item uuid, p_final jsonb, p_reason text, p_actor uuid, p_lineage jsonb) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare v_ex uuid[]; v_prop uuid[]; v_bad int;
begin
  if jsonb_typeof(p_final) is distinct from 'object' or coalesce(p_final->>'mode', '') <> 'approve_except' then
    raise exception 'AER items are not edited inline: use Approve except (tick the rows to leave out, with one reason) or Reject (decision A1)' using errcode = '22023';
  end if;
  if jsonb_typeof(p_final->'exclude_row_ids') is distinct from 'array' then
    raise exception 'Approve except needs the rows to leave out (exclude_row_ids)' using errcode = '22023';
  end if;
  begin
    v_ex := array(select distinct x::uuid from jsonb_array_elements_text(p_final->'exclude_row_ids') x);
  exception when invalid_text_representation then
    raise exception 'Approve except: a row to leave out is not a row id' using errcode = '22023';
  end;
  v_prop := array(select x::uuid from jsonb_array_elements_text(coalesce(p_lineage->'proposed_row_ids', '[]'::jsonb)) x);
  if cardinality(v_ex) = 0 then raise exception 'Approve except: tick at least one row to leave out, or use Approve' using errcode = '22023'; end if;
  select count(*) into v_bad from unnest(v_ex) e where not (e = any (v_prop));
  if v_bad > 0 then raise exception 'Approve except: % ticked row(s) are not waiting rows of this item; reload it', v_bad using errcode = '22023'; end if;
  if cardinality(v_ex) >= cardinality(v_prop) then raise exception 'Approve except: every row is left out; use Reject instead' using errcode = '22023'; end if;
  return jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ex), 'reviewer', p_actor, 'reason', p_reason, 'decided_at', now(),
    'excluded', coalesce(
      (select jsonb_agg(jsonb_build_object('id', m.id, 'row_hash', m.row_hash, 'country', m.country_code, 'level', m.level_label, 'qualification', m.qualification_name,
                                           'band', m.benchmark_band, 'min_grade', m.min_grade, 'scale', m.grade_scale, 'quote', m.quote) order by m.id)
         from catalogue.provider_entry_matrix m where m.id = any (v_ex)),
      (select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'description', x.description, 'min_grade', x.min_grade, 'scale', x.grade_scale,
                                           'score', x.min_entry_score, 'basis', x.min_entry_score_basis, 'quote', x.quote) order by x.id)
         from catalogue.course_entry_requirements x where x.id = any (v_ex)), '[]'::jsonb),
    'lineage', p_lineage);
end $function$;
revoke all on function security.aer_approve_except_v1(uuid, jsonb, text, uuid, jsonb) from public, anon, authenticated;
comment on function security.aer_approve_except_v1(uuid, jsonb, text, uuid, jsonb) is 'CF-247 A1 (30 Oct 2026): checks an Approve except on an AER item (explicit waiting rows, at least one admitted) and returns the decision''s final value with the excluded rows, reviewer, reason and lineage. Owner only.';

-- 4. What the reviewer reads: the item's rows with their quotes, its source, stored copy and completeness (Layer 4 > Inbox, AER items).
create or replace function security.aer_review_read_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare v_rank int := coalesce(security.current_role_rank(), 0); i pipeline.layer4_review_items%rowtype; r pipeline.entry_matrix_runs%rowtype; v_rows jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or not (i.field_code = any (security.aer_review_kinds_v1())) then raise exception 'not an AER review item' using errcode = '22023'; end if;
  if i.field_code = 'course_entry_first_read' then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'status', x.status, 'status_reason', x.status_reason, 'kind', x.kind, 'audience', x.audience,
             'description', x.description, 'min_grade', x.min_grade, 'scale', x.grade_scale, 'score', x.min_entry_score, 'basis', x.min_entry_score_basis,
             'band', x.benchmark_band, 'quote', x.quote, 'evidence_id', x.evidence_id) order by x.kind, x.created_at, x.id), '[]'::jsonb)
      into v_rows from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = p_item::text;
  else
    select * into r from pipeline.entry_matrix_runs where review_item_id = p_item;
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'status', m.status, 'status_reason', m.status_reason, 'country', m.country_code,
             'level', m.level_label, 'qualification', m.qualification_name, 'band', m.benchmark_band, 'min_grade', m.min_grade, 'scale', m.grade_scale,
             'quote', m.quote, 'evidence_id', m.evidence_id, 'content_hash', m.content_hash) order by m.country_code, m.level_label, m.qualification_name, m.id), '[]'::jsonb)
      into v_rows from catalogue.provider_entry_matrix m
     where (r.id is not null and m.run_id = r.id) or m.provenance->'aer_exclusion'->>'review_item_id' = p_item::text;
  end if;
  return jsonb_build_object('review_item_id', i.id, 'kind', i.field_code, 'status', i.status, 'can_decide', v_rank >= 6,
    'lineage', security.aer_review_lineage_v1(p_item), 'rows', v_rows,
    'evidence_id', coalesce(i.evidence_id, (select (v->>'evidence_id')::uuid from jsonb_array_elements(v_rows) v where v->>'evidence_id' is not null limit 1)),
    'decision', (select jsonb_build_object('action', d.action, 'reason', d.reason, 'at', d.created_at, 'exclude_row_ids', d.final_value->'exclude_row_ids')
                   from pipeline.layer4_decisions d where d.review_item_id = i.id order by d.created_at desc limit 1));
end $function$;
revoke all on function security.aer_review_read_v1(uuid) from public, anon;
grant execute on function security.aer_review_read_v1(uuid) to authenticated;
comment on function security.aer_review_read_v1(uuid) is 'CF-247 A1 (30 Oct 2026): one AER Layer 4 item for the reviewer: its rows with quotes and statuses, lineage, stored copy and whether the reader may decide (Platform Admin, A3). Curator and above.';

create or replace function public.layer4_aer_review_read(p_review_item_id uuid) returns jsonb
language sql stable set search_path to 'pg_catalog', 'security'
as $function$ select security.aer_review_read_v1(p_review_item_id) $function$;
revoke all on function public.layer4_aer_review_read(uuid) from public, anon;
grant execute on function public.layer4_aer_review_read(uuid) to authenticated;
comment on function public.layer4_aer_review_read(uuid) is 'CF-247 A1 (30 Oct 2026): Layer 4 > Inbox reads one AER item (rows, quotes, lineage). Curator and above; deciding is the Platform Admin''s (A3).';

-- 5. The single-item decide: A3 role check, A1 Approve except (and no other inline edit), lineage audited, for AER kinds only.
select pg_temp.edit_n('security.layer4_review_decide_impl(uuid,text,text,jsonb)', '22f17fa1cc5e9a3644b18c199a6c5518', array[
  array[$o$  v_refresh_id uuid; v_search_signal_id uuid; v_evidence pipeline.evidence_artifacts%rowtype;$o$,
        $n$  v_refresh_id uuid; v_search_signal_id uuid; v_evidence pipeline.evidence_artifacts%rowtype; v_aer jsonb;$n$],
  array[$o$  if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;
$o$,
        $n$  if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;
  -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): AER items take the evidence-aware review path only
  if v_item.field_code = any (security.aer_review_kinds_v1()) then
    -- A3: AER admission and rejection are the Platform Admin's; Curators keep their operational editing in the workspace
    if v_rank<6 then raise exception 'Platform Admin role required: AER items are admitted or rejected by the Platform Admin (decision A3)' using errcode='42501'; end if;
    v_aer:=security.aer_review_lineage_v1(v_item.id);
    if p_action='approve' then
      v_final:=v_item.proposed_value-'exclude_row_ids';  -- A1: a plain approval never carries an exclusion
    elsif p_action='edit_and_approve' then
      -- A1: the only edit of an AER item is Approve except: explicit waiting rows, one reason, the reviewer and the lineage recorded
      v_final:=security.aer_approve_except_v1(v_item.id,p_final_value,trim(p_reason),v_actor,v_aer);
    end if;
  end if;
$n$],
  array[$o$  ) returning id into v_decision;
$o$,
        $n$  ) returning id into v_decision;
  if v_aer is not null then
    -- A1: every AER inclusion and exclusion is audited with its lineage (item, run, source, stored copy hash, rows)
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', case when p_action='edit_and_approve' then 'aer_approve_except' else 'aer_'||p_action end, 'pipeline.layer4_review_items',
            jsonb_build_object('review_item_id', v_item.id, 'decision_id', v_decision, 'kind', v_item.field_code, 'reason', trim(p_reason),
                               'lineage', v_aer, 'excluded_row_ids', coalesce(v_final->'exclude_row_ids', '[]'::jsonb), 'result', v_scalar), v_actor);
  end if;
$n$]
], array[1, 1, 1]);

-- 6. Provider entry matrix: an excluded row names the item and reviewer; the complete read is accounted for (admitted or explicitly excluded).
select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '5531f0198f89c1246587118ccb8344a6', array[
  array[$o$    -- complete admission (26 Oct 2026): under the guard, what is admitted is the whole complete read, never a part of it
    if security.entry_completeness_required_v1(r.provider_id)
       and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex)))
           is distinct from nullif(r.result->'completeness'->>'matched', '')::int then
      raise exception 'entry matrix run %: % of the % rows the complete read matched would be admitted; a read is admitted whole or rejected', r.id,
        (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex))),
        coalesce(r.result->'completeness'->>'matched', '?') using errcode = '23514';
    end if;$o$,
        $n$    -- complete admission (26 Oct 2026), with A1 (Platform Admin 30 Oct 2026 06:53): under the guard the whole complete read is accounted for;
    -- every row it matched still waits, and is admitted or explicitly excluded by the reviewer (Approve except), never silently lost
    if security.entry_completeness_required_v1(r.provider_id)
       and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed')
           is distinct from nullif(r.result->'completeness'->>'matched', '')::int then
      raise exception 'entry matrix run %: % rows wait but the complete read matched %; every row of a complete read is admitted or explicitly excluded', r.id,
        (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed'),
        coalesce(r.result->'completeness'->>'matched', '?') using errcode = '23514';
    end if;$n$],
  array[$o$    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'excluded by the reviewer: ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed' and m.id = any(v_ex);$o$,
        $n$    -- A1: an excluded row stays unadmitted and identifiable: inactive, its reason names the item and the reviewer, provenance keeps the record
    update catalogue.provider_entry_matrix m set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || coalesce(p_item, r.review_item_id)::text || ', reviewer ' || coalesce(p_final->>'reviewer', 'unknown') || '): ' || coalesce(p_reason, ''),
           provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('aer_exclusion', jsonb_build_object('review_item_id', coalesce(p_item, r.review_item_id),
             'run_id', r.id, 'content_hash', m.content_hash, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)')),
           updated_at = now()
     where m.run_id = r.id and m.status = 'proposed' and m.id = any(v_ex);$n$]
], array[1, 1]);

-- 7. Course entry requirements: the same exclusion record.
select pg_temp.edit_n('security.course_entry_review_apply_v1(uuid,text,jsonb,text)', 'e2ae70b0077bf458d505b430f77fdebd', array[
  array[$o$    update catalogue.course_entry_requirements x set status = 'inactive', status_reason = 'excluded by the reviewer: ' || coalesce(p_reason, ''), updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and x.id = any (v_ex);$o$,
        $n$    -- A1: an excluded row stays unadmitted and identifiable: inactive, its reason names the item and the reviewer, provenance keeps the record
    update catalogue.course_entry_requirements x set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || p_item::text || ', reviewer ' || coalesce(p_final->>'reviewer', 'unknown') || '): ' || coalesce(p_reason, ''),
           provenance = coalesce(x.provenance, '{}'::jsonb) || jsonb_build_object('aer_exclusion', jsonb_build_object('review_item_id', p_item,
             'enrich_item_id', v_enrich, 'evidence_id', x.evidence_id, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)')),
           updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and x.id = any (v_ex);$n$]
], array[1]);

-- 8. A2: the generic bulk decide skips AER kinds, decides nothing and says how many it skipped.
select pg_temp.edit_n('l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)', 'e6a2ffddff142a81d9a6d6a050661b2d', array[
  array[$o$if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
$o$,
        $n$if length(trim(coalesce(p_reason,'')))<8 then raise exception 'decision reason must be at least 8 characters';end if;
 -- CF-247 A2 (Platform Admin 30 Oct 2026 06:53): AER items are never decided in bulk; the group is skipped and counted, nothing is decided
 if p_field_code = any (security.aer_review_kinds_v1()) then
  select count(*) into v_count from pipeline.layer4_review_items where status='pending' and entity_type=p_entity_type and field_code=p_field_code and coalesce(escalation_reason,'')=coalesce(p_escalation_reason,'');
  return jsonb_build_object('ok',false,'action',p_action,'processed',0,'failed',0,'skipped_aer',v_count,'remaining_in_group',v_count,'reason','aer_review_path_only',
   'message',v_count||' AER item(s) skipped: AER items are decided one at a time in the AER review path (decision A2)','publication_changed',false);
 end if;
$n$],
  array[$o$,'sample_errors',v_err,'publication_changed',false);$o$,
        $n$,'sample_errors',v_err,'publication_changed',false,'skipped_aer',0);$n$]
], array[1, 1]);

-- 9. A2: the generic batch decide (it could approve course reads) skips AER kinds the same way.
select pg_temp.edit_n('security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)', 'f8e9e97314096ff24cea8e8c7d5641ce', array[
  array[$o$  if v_kinds<>1 then raise exception 'a batch must contain one kind of item'; end if;
$o$,
        $n$  if v_kinds<>1 then raise exception 'a batch must contain one kind of item'; end if;
  -- CF-247 A2 (Platform Admin 30 Oct 2026 06:53): AER items are never decided in a batch; the batch is skipped and counted, nothing is decided
  if v_field = any (security.aer_review_kinds_v1()) then
    return jsonb_build_object('ok',false,'decided',0,'skipped_aer',v_n,'action',p_action,'reason','aer_review_path_only',
      'message',v_n||' AER item(s) skipped: AER items are decided one at a time in the AER review path (decision A2)');
  end if;
$n$],
  array[$o$'decided',jsonb_array_length(v_results),'action',p_action);$o$,
        $n$'decided',jsonb_array_length(v_results),'action',p_action,'skipped_aer',0);$n$]
], array[1, 1]);

-- 10. Layer 4 > Inbox: AER items are their own kind, decided by the Platform Admin one at a time (they showed as course links).
select pg_temp.edit_n('security.layer4_inbox_kinds_v1()', '3f1fddbe89ed4e5c18262cade82e817a', array[
  array[$o$   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$o$,
        $n$   "aer_review": {"label": "Entry requirements (AER)", "order": 17, "choices": [
     {"key": "approve", "label": "Approve all rows", "rank": 6, "returns": "Every waiting row becomes active once the identity, completeness, scale and basis checks pass; the source''s earlier rows are superseded"},
     {"key": "approve_except", "label": "Approve except…", "rank": 6, "input": "rows", "returns": "The ticked rows stay unadmitted, marked excluded with your reason; every other row becomes active once the same checks pass"},
     {"key": "reject", "label": "Reject the read", "rank": 6, "returns": "No row is admitted; every waiting row is withdrawn with your reason"}]},
   "provider_departure": {"label": "Provider left the register", "order": 14, "choices": [$n$]
], array[1]);

select pg_temp.edit_n('security.layer4_inbox_items_v1()', 'cc42a3d524545fb518186d81971da56f', array[
  array[$o$              else 'course_link' end::text,$o$,
        $n$              when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'  -- CF-247 A1-A3 (30 Oct 2026): the AER review path
              else 'course_link' end::text,$n$],
  array[$o$r.field_code),$o$,
        $n$case r.field_code when 'entry_matrix_first_run' then 'Entry requirements: first read of the provider table'
                                       when 'entry_matrix_change' then 'Entry requirements: the provider table changed' end,
                  r.field_code),$n$]
], array[1, 1]);

select pg_temp.edit_n('public.admin_layer4_inbox(text,jsonb)', '272438c275c6707280d5d29cdfbd8729', array[
  array[$o$
  elsif v_kind = 'course_link' then
$o$,
        $n$
  elsif v_kind = 'aer_review' then
    -- CF-247 A1-A3 (Platform Admin 30 Oct 2026 06:53): one AER item at a time; Approve except sends the ticked rows to leave out
    if v_choice = 'approve_except' then
      begin
        v_ids := array(select jsonb_array_elements_text(v_value::jsonb)::uuid);
      exception when others then raise exception 'tick the rows to leave out';
      end;
      if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'tick the rows to leave out'; end if;
    end if;
    v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end, v_reason,
             case when v_choice = 'approve_except' then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ids)) end);
  elsif v_kind = 'course_link' then
$n$]
], array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_review_kinds_v1', 'Layer 4', 'AER A1-A3: the Layer 4 kinds that take the AER review path only', 'active', '{}', '20261030XXXXXX'),
 ('function', 'security.aer_review_lineage_v1', 'Layer 4', 'AER A1: lineage of a waiting AER item (item, run, source, stored copy hash, rows), recorded with each AER decision', 'active', '{}', '20261030XXXXXX'),
 ('function', 'security.aer_approve_except_v1', 'Layer 4', 'AER A1: checks an Approve except and builds the decision''s final value', 'active', '{}', '20261030XXXXXX'),
 ('function', 'security.aer_review_read_v1', 'Layer 4', 'AER A1: one AER item for the reviewer (rows, quotes, lineage)', 'active', '{}', '20261030XXXXXX'),
 ('function', 'public.layer4_aer_review_read', 'Layer 4', 'AER A1: Layer 4 > Inbox reads one AER item', 'active', '{}', '20261030XXXXXX')
on conflict do nothing;

-- post-check: every edited definition carries its change, and the Inbox kinds are still valid with the AER kind for the Platform Admin only
do $g$ declare v jsonb; begin
  if pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure) !~ 'decision A3'
     or pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure) !~ 'security\.aer_approve_except_v1\(' then
    raise exception 'A1-A3 post-check: the decide function does not carry the AER review path'; end if;
  if pg_get_functiondef('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'::regprocedure) !~ 'excluded by approve except'
     or pg_get_functiondef('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'::regprocedure) ~ 'admitted whole or rejected' then
    raise exception 'A1 post-check: entry_matrix_review_apply_v1 not edited'; end if;
  if pg_get_functiondef('security.course_entry_review_apply_v1(uuid,text,jsonb,text)'::regprocedure) !~ 'excluded by approve except' then
    raise exception 'A1 post-check: course_entry_review_apply_v1 not edited'; end if;
  if pg_get_functiondef('l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)'::regprocedure) !~ 'aer_review_path_only'
     or pg_get_functiondef('security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)'::regprocedure) !~ 'aer_review_path_only' then
    raise exception 'A2 post-check: a generic bulk or batch decide does not skip AER items'; end if;
  if pg_get_functiondef('security.layer4_inbox_items_v1()'::regprocedure) !~ 'then ''aer_review'''
     or pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure) !~ 'elsif v_kind = ''aer_review'' then' then
    raise exception 'A1 post-check: the Inbox does not route AER items'; end if;
  v := security.layer4_inbox_kinds_v1();
  if jsonb_typeof(v->'aer_review'->'choices') is distinct from 'array' or v->'provider_departure' is null
     or (select count(*) from jsonb_array_elements(v->'aer_review'->'choices') c where (c->>'rank')::int = 6) <> 3 then
    raise exception 'A3 post-check: the Inbox AER kind is missing or not Platform Admin only'; end if;
  if security.aer_review_kinds_v1() <> array['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read']::text[] then
    raise exception 'A1-A3 post-check: AER kinds'; end if;
end $g$;

select 'A1-A3: AER review path (Approve except, no AER bulk decide, Platform Admin only)' ok;
