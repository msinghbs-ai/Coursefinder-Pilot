-- CF-247 SS-021 audit F2 (IQ-00077): provider-identity-check fails every run (4 of 4 since v2.15.433) because its own integration-issue write
-- passes root_cause_class 'data' and workstream 'G', which pipeline.integration_issues does not accept (integration_issues_root_cause_class_check,
-- integration_issues_workstream_check), so the run rolls back and no identity finding lands for any provider (Platform Admin overnight mandate
-- 3 Nov 2026 21:59, §2 P0 work continuity: "Release the provider-identity-check constraint fix separately").
-- What: the issue write uses the accepted values ('data_drift', 'A10', the workstream of provider identity in the ops register), and each issue
--   write runs in its own block, so a refused report write is recorded in the run's result and never rolls back the findings of the run.
-- Replaces: security.provider_identity_check_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No spend. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before -> after:
--   security.provider_identity_check_v1()                             fe1df994ada824fcd5375fd84680f5be -> ad78092b0138ca4760528c8bd7c2b8de

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

select pg_temp.edit_once('security.provider_identity_check_v1()', 'fe1df994ada824fcd5375fd84680f5be', 'ad78092b0138ca4760528c8bd7c2b8de',
  array[
    array[$o$'root_cause_class', 'data', 'workstream', 'G',$o$, $n$'root_cause_class', 'data_drift', 'workstream', 'A10',$n$],
    array[$o$      v_fp := 'provider_identity:' || r.check_code;
      v_issues := v_issues || jsonb_build_object(r.check_code, (security.integration_issue_upsert_v1(jsonb_build_object($o$,
          $n$      v_fp := 'provider_identity:' || r.check_code;
      begin  -- one refused issue write is recorded in the result and never rolls back the run's findings (SS-021 F2)
      v_issues := v_issues || jsonb_build_object(r.check_code, (security.integration_issue_upsert_v1(jsonb_build_object($n$],
    array[$o$        'provider-identity-check'))->>'action');
    end loop;$o$,
          $n$        'provider-identity-check'))->>'action');
      exception when others then
        v_issues := v_issues || jsonb_build_object(r.check_code, 'issue not written: ' || sqlerrm);
      end;
    end loop;$n$]
  ], array[1, 1, 1]);
