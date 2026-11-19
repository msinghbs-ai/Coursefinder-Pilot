-- CF-CHG-20260915-247 option A: ambiguous_basis_course_total becomes a required, gating benchmark control.
do $do$
declare
  sig regprocedure := 'public.layer3_cf245_tuition_benchmark_record_service(jsonb,jsonb,text[],integer,integer,integer,numeric,integer,uuid[],text,text,uuid)'::regprocedure;
  d text := pg_get_functiondef(sig);
  old_list text := $q$array['ambiguous_multiple_equal_rank','low_confidence_missing_basis','loan_cap_or_deposit','unsupported_currency']$q$;
  new_list text := $q$array['ambiguous_multiple_equal_rank','low_confidence_missing_basis','loan_cap_or_deposit','unsupported_currency','ambiguous_basis_course_total']$q$;
begin
  if (length(d) - length(replace(d, old_list, ''))) / length(old_list) <> 1 then
    raise exception 'required-controls anchor not found exactly once; aborting';
  end if;
  execute replace(d, old_list, new_list);
end $do$;
