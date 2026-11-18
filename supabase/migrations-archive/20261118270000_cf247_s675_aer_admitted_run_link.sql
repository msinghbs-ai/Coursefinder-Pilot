-- CF-247 S675 AER consumer data finding "consumer_unadmitted": approved rows read as not admitted after a re-record re-pointed their run (session S1-AER, Platform Admin
--   18 Nov 2026 22:26 AEDT, alert batch 88e5ff5b-3fb9-4613-80db-3ff0c96a6b06: "Academic entry requirements: 5 critical consumer data finding(s)", first seen 11 Nov 19:27 AEDT).
-- Guards: G1 (no job), G2 (no value), G3 (no consumer API object; CREATE OR REPLACE through md5-guarded edits only, no new function or table: 75 functions and 48 relations
--   stay), Decision 276 (no AER v1 threshold, reader or admission rule changes), Layer 4 decisions are never rewritten.
-- Findings (live, read only, 18 Nov 2026 22:40 to 22:58 AEDT, rolled-back probes): the 5 findings are 149 active provider-table rows at five providers (Auckland University
--   of Technology 56, Whitireia and WelTec 44, Massey University 36, Flinders University 12, University of Otago 1). Each provider's 28 Oct reading was decided by a person on
--   30 Oct (approved or edited and approved, item proposed_value.run_id = the rows' run); the rows were not changed after 30 Oct (version 1). On 11 Nov at 19:15 to 19:20 AEDT
--   the qualification-first re-record of stored readings (migration 20261112070000) recorded the same five runs again: public.svc_entry_matrix_record raised an
--   entry_matrix_change item for each and set the run's review_item_id to it, so the approved item lost its run and the check (security.aer_current_findings_v1, which
--   follows run -> review_item_id) read the person-approved rows as "not admitted". Nothing bypassed Layer 4 and no defective row is served: every one of the 149 rows is
--   the value a person approved. So nothing is quarantined here (that would withdraw person-approved data from the consumer API); the link and the guard are fixed.
-- What, in one transaction, under the live md5 of each function:
--   1. security.aer_current_findings_v1 (6bfcb39c7271343abf0139081f0d9a37): a provider-table row counts as admitted when its run's current item is approved, OR when an
--      approved or edited-and-approved entry-matrix item of the provider names the row's run (proposed_value.run_id). A row no approved item names is still a P0 finding.
--   2. public.svc_entry_matrix_record (bbf3517e5eb8b40fa12ea3020a274ca4): a run whose item a person approved is never recorded again (returns already_decided and changes
--      nothing): a new reading of a decided page opens a new run, so an approval is never detached from the rows it admitted.
--   The five pending change items stay as they are: they hold the qualification rows the re-record proposed, for a person (or rule aer-matrix-machine-v1) to decide.
-- Replaces: security.aer_current_findings_v1 and public.svc_entry_matrix_record (same names, in place). Retires: nothing.

do $edit$
declare e record; v_def text; v_c int;
begin
  for e in select * from (values
    (1, 'security.aer_current_findings_v1()', '6bfcb39c7271343abf0139081f0d9a37',
        $o$             where m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')$o$,
        $n$             where m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
               -- S675 (18 Nov 2026): an approved entry-matrix item that names the row's run admitted it, even when a later re-record re-pointed the run
               and not exists (select 1 from pipeline.layer4_review_items la where la.entity_id = m.provider_id and la.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
                                  and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)$n$),
    (2, 'public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'bbf3517e5eb8b40fa12ea3020a274ca4',
        $o$  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;$o$,
        $n$  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;
  -- S675 (18 Nov 2026): a run a person approved is never recorded again (a re-record on 11 Nov detached five approvals from the rows they admitted); a new reading opens a new run
  if r.review_item_id is not null and exists (select 1 from pipeline.layer4_review_items d where d.id = r.review_item_id and d.status in ('approved', 'edited_approved')) then
    return jsonb_build_object('ok', false, 'status', 'already_decided', 'review_item_id', r.review_item_id);
  end if;$n$)
  ) v(n, sig, md5, old, new) order by n loop
    v_def := pg_catalog.pg_get_functiondef(e.sig::regprocedure);
    if position('S675 (18 Nov 2026)' in v_def) > 0 then raise notice 'S675 edit %: already applied', e.n; continue; end if;
    if md5(v_def) <> e.md5 then raise exception 'S675: % differs from the definition this change edits (md5 %, live %)', e.sig, e.md5, md5(v_def); end if;
    v_c := (length(v_def) - length(replace(v_def, e.old, ''))) / length(e.old);
    if v_c <> 1 then raise exception 'S675 edit % on %: the text to replace occurs % times; the edit must apply exactly once', e.n, e.sig, v_c; end if;
    execute replace(v_def, e.old, e.new);
  end loop;
end $edit$;

insert into pipeline.admin_control_events(area, action, target, detail)
values ('aer', 's675_admitted_run_link', 'security.aer_current_findings_v1',
        jsonb_build_object('authority', 'Platform Admin 18 Nov 2026 22:26 AEDT (S1-AER, alert batch 88e5ff5b-3fb9-4613-80db-3ff0c96a6b06)', 'migration', '20261118270000',
                           'findings', 5, 'rows', 149, 'cause', 're-record of five person-approved runs on 11 Nov re-pointed review_item_id to new change items',
                           'quarantined', 0));

do $p$
begin
  -- the edited clause, for the five providers (the whole findings function is the reconcile job's, too long for a deploy)
  if pg_catalog.pg_get_functiondef('security.aer_current_findings_v1()'::regprocedure) not like '%S675 (18 Nov 2026)%'
     or pg_catalog.pg_get_functiondef('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)'::regprocedure) not like '%S675 (18 Nov 2026)%'
     or exists (select 1 from catalogue.provider_entry_matrix m
                  left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.layer4_review_items li on li.id = r.review_item_id
                 where m.provider_id in ('39301fa8-bff2-4389-bbcd-32d8415fae04', '40f9891f-c8da-45cc-aced-154e63d41cff', 'ab12c7f8-e368-453d-9dfe-4ab8bd744829',
                                         '0a42da16-8df1-4439-a929-4dfdd04b6d83', '229dc07d-c573-44a3-b5dc-cc423cc2c300')
                   and m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
                   and not exists (select 1 from pipeline.layer4_review_items la where la.entity_id = m.provider_id and la.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
                                      and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)) then
    raise exception 'post-check: the five person-approved providers still read as not admitted';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
