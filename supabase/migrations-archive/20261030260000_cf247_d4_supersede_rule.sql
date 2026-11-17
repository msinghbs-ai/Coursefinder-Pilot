-- CF-247 decision D4 (Platform Admin, 30 Oct 2026 08:45; implementation decision lodged as admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md
-- §11.1, commit aef0490f, before code): what an AER "Approve except" may supersede. It closes the open point of §10 (A1).
--   Rule: only an active row with an explicitly approved replacement may be superseded; an active row whose proposed replacement was excluded
--   stays active and unchanged; exclusion never implicitly withdraws, stales or supersedes the existing active value; the retained active row,
--   the excluded proposal and the decision stay linked; conflicting approved replacements hold the decision rather than guess.
--   Provider tables (entry_matrix_first_run / entry_matrix_change):
--     - A replacement is matched on row_hash, the table's existing row identity (unique among active rows), within the scope W15 already uses
--       (same provider, same source, an earlier run). Under Approve except an earlier active row is superseded only when an approved waiting
--       row has its identity; it is kept untouched when its new reading was excluded, or when the new read does not carry it (literal reading).
--     - Approve all rows, the automatic changed-page path (p_final null) and the quarantine branch keep W15 exactly as before.
--     - Holds (both paths), with the whole decision refused and nothing changed (the item stays pending):
--       C1 two approved rows of the run share one identity (the existing RMIT band check, reworded);
--       C2 an approved row's identity is already active on a row this decision does not replace (another source of the provider).
--     - Audit: the excluded row's provenance.aer_exclusion gains retains_active_row_id / retains_active_row_hash; each replaced row gains
--       provenance.aer_supersede (item, run, replaced_by_row_id); the apply result carries retained and supersede_map, which
--       security.layer4_review_decide_impl already records as "result" in the aer_approve_except control event (not edited here).
--   Course pages (course_entry_first_read): course rows have no identity key, so Approve except on a course that already has active
--   AI-read rows is held (nothing changed); with no active rows it works as before. Approve all rows keeps W15.
--   Layer 4 > Inbox: the Approve except choice says that an active row whose replacement is left out stays active.
-- Replaces: security.entry_matrix_review_apply_v1, security.course_entry_review_apply_v1, security.layer4_inbox_kinds_v1 (same names, md5-guarded edits)
-- Retires: nothing (the implicit supersede of an excluded row's active counterpart under Approve except is switched off here)
-- Nothing dropped, deleted or renamed. No new table, column, job, setting, row status or Layer 4 action. Consumer API untouched (G3).

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

-- 1. Provider entry matrix: identity-matched supersede under Approve except, holds C1 and C2, audit links.
select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '7c718987b496cad38352f8dfa1f727b7', array[
  array[$o$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0;$o$,
        $n$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0;$n$],
  array[$o$      raise exception 'entry matrix run %: proposed rows share an identity; nothing admitted', r.id using errcode = '23505';$o$,
        $n$      -- D4 C1 (Platform Admin 30 Oct 2026 08:45): conflicting approved replacements hold the whole decision
      raise exception 'Held (decision D4): entry matrix run %: approved rows % share one identity, so it is not clear which replaces the active value; nothing was changed. Leave out all but one of them, or Reject the read', r.id,
        (select string_agg(g.ids, '; ') from (select '[' || string_agg(m.id::text, ', ' order by m.id) || ']' ids from catalogue.provider_entry_matrix m
                                                where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex)) group by m.row_hash having count(*) > 1) g)
        using errcode = '23505';$n$],
  array[$o$    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;
    get diagnostics v_sup = row_count;$o$,
        $n$    -- D4 C2: an approved row whose identity is already active on a row this decision does not replace holds the whole decision
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
    end if;$n$],
  array[$o$'run_id', r.id, 'content_hash', m.content_hash, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)')),$o$,
        $n$'run_id', r.id, 'content_hash', m.content_hash, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)',
             -- D4: the active row this excluded proposal would have replaced, kept active and unchanged (null when an approved row replaced it)
             'retains_active_row_id', (select a.id from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'
                                         and a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id),
             'retains_active_row_hash', (select a.row_hash from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'
                                         and a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id))),$n$],
  array[$o$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup);$o$,
        $n$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)
         || case when v_map is not null then jsonb_build_object('retained', v_ret, 'supersede_map', v_map) else '{}'::jsonb end;  -- D4 audit$n$]
], array[1, 1, 1, 1, 1]);

-- 2. Course entry requirements: no identity to match on, so Approve except on a course with active rows is held.
select pg_temp.edit_n('security.course_entry_review_apply_v1(uuid,text,jsonb,text)', '25899209725990622fea50e533316f49', array[
  array[$o$    update catalogue.course_entry_requirements x set status = 'superseded', status_reason = 'replaced by Layer 4 item ' || p_item, updated_at = now()$o$,
        $n$    -- D4 (Platform Admin 30 Oct 2026 08:45): course rows have no identity key, so an excluded row cannot be matched to the active row it would
    -- replace; Approve except on a course that already has active rows holds the whole decision rather than guess
    if cardinality(v_ex) > 0 and exists (select 1 from catalogue.course_entry_requirements x
                                         where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai') then
      raise exception 'Held (decision D4): course % has % active entry requirement rows and course rows have no identity to match an excluded row to the row it would replace; nothing was changed. Use Approve all rows if every waiting row is right, or Reject the read',
        r.entity_id, (select count(*) from catalogue.course_entry_requirements x where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai')
        using errcode = '55000';
    end if;
    update catalogue.course_entry_requirements x set status = 'superseded', status_reason = 'replaced by Layer 4 item ' || p_item, updated_at = now()$n$]
], array[1]);

-- 3. Layer 4 > Inbox: the Approve except choice says what happens to the rows the website shows today.
select pg_temp.edit_n('security.layer4_inbox_kinds_v1()', '08e7999c3f4639f02b9607e1fd9ac506', array[
  array[$o$"The ticked rows stay unadmitted, marked excluded with your reason; every other row becomes active once the same checks pass"$o$,
        $n$"The ticked rows stay unadmitted, marked excluded with your reason; every other row becomes active once the same checks pass. An earlier active row is replaced only by an approved row with its identity; one whose replacement you leave out stays active (D4)"$n$]
], array[1]);

-- post-check: every edited definition carries its change, and Approve all keeps W15 unchanged
do $g$ declare v_m text := pg_get_functiondef('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'::regprocedure);
               v_c text := pg_get_functiondef('security.course_entry_review_apply_v1(uuid,text,jsonb,text)'::regprocedure); v jsonb;
begin
  if v_m !~ 'Held \(decision D4\): entry matrix run %: approved rows % share one identity' or v_m !~ 'approved row\(s\) have the identity of an active row this decision does not replace'
     or v_m !~ '''retains_active_row_id''' or v_m !~ '''aer_supersede''' or v_m !~ '''supersede_map''' or v_m ~ 'proposed rows share an identity; nothing admitted' then
    raise exception 'D4 post-check: entry_matrix_review_apply_v1 not edited'; end if;
  if strpos(v_m, $w$    if cardinality(v_ex) = 0 then
    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;$w$) = 0 then
    raise exception 'D4 post-check: Approve all rows no longer keeps W15'; end if;
  if v_c !~ 'Held \(decision D4\): course %' then raise exception 'D4 post-check: course_entry_review_apply_v1 not edited'; end if;
  v := security.layer4_inbox_kinds_v1();
  if (select c->>'returns' from jsonb_array_elements(v->'aer_review'->'choices') c where c->>'key' = 'approve_except') !~ 'stays active \(D4\)$' then
    raise exception 'D4 post-check: Inbox Approve except wording'; end if;
end $g$;

select 'D4: Approve except supersedes only rows with an approved replacement; conflicts hold the decision' ok;
