CREATE OR REPLACE FUNCTION security.course_entry_correction_check_v1(p_item uuid, p_course uuid, p_url text, p_rows jsonb DEFAULT NULL::jsonb, p_dropped jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.layer4_review_items%rowtype; v_why text[] := '{}'; v_chk jsonb; v_shared jsonb; v_diff jsonb;
begin
  select * into o from pipeline.layer4_review_items where id = p_item;
  if o.id is null or o.field_code <> 'course_entry_first_read' then return jsonb_build_object('ok', false, 'why', 'not a course entry read'); end if;
  if o.status <> 'pending' then v_why := v_why || format('the read no longer waits (%s)', o.status); end if;
  if o.entity_id is distinct from p_course then v_why := v_why || 'another course'::text; end if;
  if exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = o.id) then v_why := v_why || 'a person has decided it'::text; end if;
  if o.claimed_at is not null and o.claimed_at > now() - make_interval(mins => security.pipeline_num_v1('entry.supersede_claim_minutes', 60)::int) then
    v_why := v_why || 'a reviewer claimed it'::text;
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p_course
               and l.field in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.supersede_lock_fields'), '[]'::jsonb)))) then
    v_why := v_why || 'the course has a manual lock'::text;
  end if;
  if p_url is null or p_url is distinct from o.proposed_value->>'url' then
    v_why := v_why || format('the course''s bound page (%s) is not the page of the waiting read (%s): a new first read, not a correction', coalesce(p_url, 'none'), coalesce(o.proposed_value->>'url', 'none'));
  end if;
  if p_rows is not null then
    v_chk := security.course_entry_read_check_v1(p_rows, p_dropped);
    v_shared := security.course_entry_shared_page_v1(p_course);
    if jsonb_array_length(p_rows) = 0 then v_why := v_why || 'the corrected read has no row'::text; end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_dropped, '[]'::jsonb)) d where d->>'reason' in ('over_row_limit', 'other_programme')) then
      v_why := v_why || 'the corrected read cut or set aside rows'::text;
    end if;
    if jsonb_array_length(v_chk->'drops_uncovered') > 0 then v_why := v_why || format('the corrected read still drops %s printed requirement(s)', jsonb_array_length(v_chk->'drops_uncovered')); end if;
    if jsonb_array_length(v_chk->'not_requirement') > 0 then v_why := v_why || format('%s row(s) are not entry requirements', jsonb_array_length(v_chk->'not_requirement')); end if;
    if jsonb_array_length(v_chk->'audience') > 0 then v_why := v_why || format('%s domestic row(s) stored for everyone', jsonb_array_length(v_chk->'audience')); end if;
    if jsonb_array_length(v_shared) > 0 then v_why := v_why || 'the page is shared with another programme'::text; end if;
    -- the reviewer's diff: a row is the same when kind, audience, quote (letters and digits), score and basis are the same
    with oldr as (select x.kind, x.audience, x.quote, x.min_entry_score sc, x.min_entry_score_basis b,
                         x.kind || '|' || x.audience || '|' || lower(regexp_replace(coalesce(x.quote, ''), '[^[:alnum:]]', '', 'g')) || '|' || coalesce(x.min_entry_score::text, '') || '|' || lower(coalesce(x.min_entry_score_basis, '')) k
                    from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = o.id::text),
         newr as (select y->>'kind' kind, y->>'audience' audience, y->>'quote' quote, y->>'min_entry_score' sc, y->>'min_entry_score_basis' b,
                         (y->>'kind') || '|' || (y->>'audience') || '|' || lower(regexp_replace(coalesce(y->>'quote', ''), '[^[:alnum:]]', '', 'g')) || '|' || coalesce((y->>'min_entry_score')::numeric::text, '') || '|' || lower(coalesce(y->>'min_entry_score_basis', '')) k
                    from jsonb_array_elements(p_rows) y)
    select jsonb_build_object(
      'added', (select coalesce(jsonb_agg(jsonb_build_object('kind', n.kind, 'audience', n.audience, 'score', n.sc, 'basis', n.b, 'quote', left(n.quote, 200))), '[]'::jsonb) from newr n where not exists (select 1 from oldr x where x.k = n.k)),
      'removed', (select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'audience', x.audience, 'score', x.sc, 'basis', x.b, 'quote', left(x.quote, 200))), '[]'::jsonb) from oldr x where not exists (select 1 from newr n where n.k = x.k)),
      'unchanged', (select count(*) from newr n where exists (select 1 from oldr x where x.k = n.k)),
      'dropped_before', (select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) from (select d->>'reason' k, count(*) c from jsonb_array_elements(coalesce(o.proposed_value->'dropped', '[]'::jsonb)) d group by 1) z),
      'dropped_after', (select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) from (select d->>'reason' k, count(*) c from jsonb_array_elements(coalesce(p_dropped, '[]'::jsonb)) d group by 1) z),
      'old_evidence_id', o.evidence_id)
      into v_diff;
  end if;
  return jsonb_build_object('ok', cardinality(v_why) = 0, 'why', array_to_string(v_why, '; '), 'reasons', to_jsonb(v_why), 'check', v_chk, 'diff', v_diff);
end $function$
