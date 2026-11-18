-- CF-247 gate hotfix (Platform Admin 26 Oct 2026 19:27: "QUARANTINE NOW. Then trace how the university adapter bypassed the write-time
-- identity check — this is a gate hole, same class as Hotfix 2; the fix is the check covering the adapter path, not just this row. Add a
-- contract test: adapter-written fees pass through the same tuition identity check as every other path.")
-- Record: admin docs/platform/ui-audit/2026-10-26-au-wave-checkins.md (19:3x).
-- Cause:
--   1 security.adapter_overwrite_v1 checks tuition identity for nothing: its intakes and English branches call
--     coverage_identity_allowed(.., 'intakes' / 'english'); its fee branch does not.
--   2 for AU courses with both CRICOS codes it writes through public.svc_coursefacts_apply_record, not security.coverage_apply_course_v1,
--     where R1's write-time check lives. 23 functions write catalogue.course_fees; only 2 checked tuition identity.
-- Fix:
--   1 One write-time gate at the table for every writer: trigger course_fee_identity_gate (BEFORE INSERT OR UPDATE) on catalogue.course_fees.
--     An international provider fee written or changed to 'active' for a course whose bound page (not a manual binding) carries a proof the
--     country's tuition list does not accept is stored 'unverified' with one Layer 4 item (source identity_basis_reverify; the R1 shape).
--     Exempt: a person's own write (signed-in call, auth.uid() set) and the manual-edit flag (cf.manual_edit). Setting fees.identity_gate_on.
--   2 security.adapter_overwrite_v1 (md5-guarded): its fee branch checks tuition identity before it supersedes anything, so a refused
--     reading never leaves a course without its current fee.
-- Replaces: nothing (security.adapter_overwrite_v1 edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API's shape is not touched (a trigger beside the table; values only become unverified as the
-- R1 gate already designed).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'fees.identity_gate_on', 'Fees: identity gate at the write', '1: every write of an international provider fee goes through the country''s tuition identity check at the table, whatever wrote it; a fee for a course whose page proof the country does not accept is stored unverified with a Layer 4 item. 0: only the callers'' own checks apply.', 'number', '1'::jsonb, 0, 1, 'on/off', 723, 'Admission checks', 'security.course_fee_identity_gate_tg', 'CF-247 gate hotfix, Platform Admin 26 Oct 2026 19:27')
on conflict (toolset_key, key) do nothing;

create or replace function security.course_fee_identity_gate_tg()
returns trigger language plpgsql security definer set search_path = '' as $f$
declare v_ident text; v_url text; v_cc text; v_pid uuid;
begin
  if new.fee_type is distinct from 'provider_current_tuition' or new.status is distinct from 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' and old.amount is not distinct from new.amount and old.fee_year is not distinct from new.fee_year then return new; end if;
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;
  if security.pipeline_num_v1('fees.identity_gate_on', 1) < 1 then return new; end if;
  select p.identity_basis, p.url, k.iso_alpha2, c.provider_id into v_ident, v_url, v_cc, v_pid
    from pipeline.coverage_course_pages p
    join catalogue.courses c on c.id = p.course_id
    join catalogue.providers pr on pr.id = c.provider_id join ref.countries k on k.id = pr.country_id
   where p.course_id = new.course_id and p.status = 'bound' and coalesce(p.basis, '') <> 'manual' and p.identity_basis is not null
     and p.identity_basis <> 'manual' and not security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'tuition') limit 1;
  if v_ident is null then return new; end if;
  new.status := 'unverified';
  if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = new.course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', new.course_id, 'provider_current_tuition', new.evidence_id, null,
            jsonb_build_object('amount', new.amount, 'currency', new.currency_code, 'basis', new.basis, 'fee_year', new.fee_year, 'page', v_url),
            jsonb_build_object('source', 'identity_basis_reverify', 'state', 'quarantined', 'country', v_cc, 'identity_basis', v_ident, 'page', v_url, 'gate', 'table'),
            '{}'::jsonb, 'pending',
            'quarantined at the write: the course page was bound with a ' || v_ident || ' proof, which the ' || v_cc || ' tuition policy does not accept; re-binding the page under the country''s rule re-admits the fee',
            'CF-CHG-20260915-247 gate hotfix 26 Oct 2026 (identity gate at the table)');
  end if;
  return new;
end $f$;
comment on function security.course_fee_identity_gate_tg() is 'CF-247 gate hotfix (Platform Admin 26 Oct 2026 19:27): every writer of an international provider fee passes the country tuition identity check at the table; a person''s own write and the manual-edit flag are exempt';
revoke all on function security.course_fee_identity_gate_tg() from public, anon, authenticated;

create trigger course_fee_identity_gate before insert or update on catalogue.course_fees
  for each row execute function security.course_fee_identity_gate_tg();

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

select pg_temp.edit_n('security.adapter_overwrite_v1(integer)', 'c96ca02c38878da034758b637abf60a8', array[
  array[$o$       and (('fee' = any (r.af) and r.adm) or coalesce(r.r5_fee, false)) and not security.uni_adapter_excluded(r.course_id, 'fee')$o$,
        $n$       -- gate hotfix 26 Oct 2026: the fee branch checks tuition identity like the intakes and English branches, before anything is superseded
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'tuition')
       and (('fee' = any (r.af) and r.adm) or coalesce(r.r5_fee, false)) and not security.uni_adapter_excluded(r.course_id, 'fee')$n$]], array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_fee_identity_gate_tg', 'Admission', 'Gate hotfix: tuition identity check at the table for every fee writer (trigger course_fee_identity_gate)', 'active', '{}', '20261026006000')
on conflict do nothing;
