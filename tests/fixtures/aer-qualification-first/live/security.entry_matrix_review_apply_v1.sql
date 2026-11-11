CREATE OR REPLACE FUNCTION security.entry_matrix_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text, p_run uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;
begin
  if p_item is not null then select * into r from pipeline.entry_matrix_runs where review_item_id = p_item;
  else select * into r from pipeline.entry_matrix_runs where id = p_run; end if;
  if r.id is null then raise exception 'no entry matrix run for this review item'; end if;
  -- D-R3 (Platform Admin 2 Nov 2026 23:24): a person's approval (Approve, Approve except, or confirming "no matrix published here") is refused,
  -- with nothing changed, while the whole read cannot be shown complete (security.entry_matrix_gate_v1); Reject and the automatic path are unchanged
  if p_action = 'approve' and p_item is not null then
    v_gate := security.entry_matrix_gate_v1(r.id, coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}'));
    if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
      raise exception 'Held (D-R3, incomplete read): %. Nothing was changed',
        (select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w) using errcode = '55000';
    end if;
  end if;
  -- Step C (29 Oct 2026): a rendered page with no requirements table; approval confirms "no matrix published here" and changes no row
  if r.rows_admitted = 0 and r.result->>'outcome' = 'no_requirements_table' then
    return jsonb_build_object('entry_matrix_run', r.id, 'admitted', 0, 'quarantined', 0, 'superseded', 0, 'outcome', 'no_requirements_table', 'decision', p_action);
  end if;
  if p_action = 'approve' then
    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    -- RMIT band fix (26 Oct 2026): rows of one run that share an identity (a lost band or level) are never admitted
    if exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex))
                group by m.row_hash having count(*) > 1) then
      -- D4 C1 (Platform Admin 30 Oct 2026 08:45): conflicting approved replacements hold the whole decision
      raise exception 'Held (decision D4): entry matrix run %: approved rows % share one identity, so it is not clear which replaces the active value; nothing was changed. Leave out all but one of them, or Reject the read', r.id,
        (select string_agg(g.ids, '; ') from (select '[' || string_agg(m.id::text, ', ' order by m.id) || ']' ids from catalogue.provider_entry_matrix m
                                                where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex)) group by m.row_hash having count(*) > 1) g)
        using errcode = '23505';
    end if;
    -- completeness guard (26 Oct 2026): a read that has not passed it is never admitted
    if coalesce(r.result->'completeness'->>'status', 'missing') in ('incomplete', 'unparsed')
       or (security.entry_completeness_required_v1(r.provider_id) and coalesce(r.result->'completeness'->>'status', 'missing') <> 'complete') then
      raise exception 'entry matrix run %: the read has not passed the completeness guard (%); nothing admitted', r.id,
        coalesce(r.result->'completeness'->>'status', 'no verdict') using errcode = '23514';
    end if;
    -- complete admission (26 Oct 2026), with A1 (Platform Admin 30 Oct 2026 06:53): under the guard the whole complete read is accounted for;
    -- every row it matched still waits, and is admitted or explicitly excluded by the reviewer (Approve except), never silently lost
    if security.entry_completeness_required_v1(r.provider_id)
       and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed')
           is distinct from nullif(r.result->'completeness'->>'matched', '')::int then
      raise exception 'entry matrix run %: % rows wait but the complete read matched %; every row of a complete read is admitted or explicitly excluded', r.id,
        (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed'),
        coalesce(r.result->'completeness'->>'matched', '?') using errcode = '23514';
    end if;
    -- D4 C2: an approved row whose identity is already active on a row this decision does not replace holds the whole decision
    if exists (select 1 from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash and a.status = 'active' and a.id <> p.id
                where p.run_id = r.id and p.status = 'proposed' and not (p.id = any(v_ex))
                  and not coalesce(a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id, false)) then
      raise exception 'Held (decision D4): entry matrix run %: approved row(s) have the identity of an active row this decision does not replace (%); nothing was changed. Leave the row(s) out, or Reject the read and escalate', r.id,
        (select string_agg('approved ' || p.id || ' = active ' || a.id || ' (source ' || coalesce(a.source_id::text, 'none') || ')', '; ' order by p.id)
           from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash and a.status = 'active' and a.id <> p.id
          where p.run_id = r.id and p.status = 'proposed' and not (p.id = any(v_ex))
            and not coalesce(a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id, false))
        using errcode = '23505';
    end if;
    if cardinality(v_ex) = 0 then
    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;
    get diagnostics v_sup = row_count;
    else
      -- D4 (Platform Admin 30 Oct 2026 08:45): under Approve except an earlier active row of this source is superseded only when an approved
      -- waiting row has its identity (row_hash); an active row whose replacement was excluded, or that the new read does not carry, stays
      -- active and is not written to. The map is taken before anything changes and is returned for the decision's event.
      v_map := jsonb_build_object(
        'replaced', (select coalesce(jsonb_agg(jsonb_build_object('active_row_id', a.id, 'replaced_by_row_id', p.id) order by a.id), '[]'::jsonb)
                       from catalogue.provider_entry_matrix a join catalogue.provider_entry_matrix p
                         on p.run_id = r.id and p.status = 'proposed' and not (p.id = any(v_ex)) and p.row_hash = a.row_hash
                      where a.provider_id = r.provider_id and a.source_id = r.source_id and a.status = 'active' and a.run_id is distinct from r.id),
        'retained_excluded', (select coalesce(jsonb_agg(jsonb_build_object('active_row_id', a.id, 'excluded_row_id', x.id) order by a.id, x.id), '[]'::jsonb)
                       from catalogue.provider_entry_matrix a join catalogue.provider_entry_matrix x
                         on x.run_id = r.id and x.status = 'proposed' and x.id = any(v_ex) and x.row_hash = a.row_hash
                      where a.provider_id = r.provider_id and a.source_id = r.source_id and a.status = 'active' and a.run_id is distinct from r.id
                        and not exists (select 1 from catalogue.provider_entry_matrix p where p.run_id = r.id and p.status = 'proposed'
                                          and not (p.id = any(v_ex)) and p.row_hash = a.row_hash)),
        'retained_not_in_read', (select coalesce(jsonb_agg(a.id order by a.id), '[]'::jsonb)
                       from catalogue.provider_entry_matrix a
                      where a.provider_id = r.provider_id and a.source_id = r.source_id and a.status = 'active' and a.run_id is distinct from r.id
                        and not exists (select 1 from catalogue.provider_entry_matrix p where p.run_id = r.id and p.status = 'proposed' and p.row_hash = a.row_hash)));
      v_ret := (select count(distinct v->>'active_row_id') from jsonb_array_elements(v_map->'retained_excluded') v)
             + jsonb_array_length(v_map->'retained_not_in_read');
      update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id,
             provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('aer_supersede', jsonb_build_object('review_item_id', coalesce(p_item, r.review_item_id),
               'run_id', r.id, 'replaced_by_row_id', p.id, 'decision', 'approve_except (D4)', 'at', now())),
             updated_at = now()
        from catalogue.provider_entry_matrix p
       where p.run_id = r.id and p.status = 'proposed' and not (p.id = any(v_ex)) and p.row_hash = m.row_hash
         and m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;
      get diagnostics v_sup = row_count;
    end if;
    -- A1: an excluded row stays unadmitted and identifiable: inactive, its reason names the item and the reviewer, provenance keeps the record
    update catalogue.provider_entry_matrix m set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || coalesce(p_item, r.review_item_id)::text || ', reviewer ' || coalesce(p_final->>'reviewer', 'unknown') || '): ' || coalesce(p_reason, ''),
           provenance = coalesce(m.provenance, '{}'::jsonb) || jsonb_build_object('aer_exclusion', jsonb_build_object('review_item_id', coalesce(p_item, r.review_item_id),
             'run_id', r.id, 'content_hash', m.content_hash, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)',
             -- D4: the active row this excluded proposal would have replaced, kept active and unchanged (null when an approved row replaced it)
             'retains_active_row_id', (select a.id from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'
                                         and a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id),
             'retains_active_row_hash', (select a.row_hash from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'
                                         and a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id))),
           updated_at = now()
     where m.run_id = r.id and m.status = 'proposed' and m.id = any(v_ex);
    get diagnostics v_off = row_count;
    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;
  else
    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;
  end if;
  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)
         || case when v_map is not null then jsonb_build_object('retained', v_ret, 'supersede_map', v_map) else '{}'::jsonb end;  -- D4 audit
end $function$
