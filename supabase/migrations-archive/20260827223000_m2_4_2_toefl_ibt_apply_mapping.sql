-- M2.4.2 — align Layer 2 Course apply contract with accepted English test reference code.
begin;

do $$
declare
  v_def text;
  v_oid oid;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='layer2_apply_course_candidate'
    and pg_get_function_identity_arguments(p.oid)='p_candidate_record_id uuid, p_apply boolean'
  limit 1;

  if v_oid is null then
    raise exception 'layer2_apply_course_candidate(uuid,boolean) not found';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  if position('''test_code'',''TOEFL''' in v_def)>0 then
    v_def:=replace(v_def,'''test_code'',''TOEFL''','''test_code'',''TOEFL_IBT''');
    execute v_def;
  elsif position('''test_code'',''TOEFL_IBT''' in v_def)=0 then
    raise exception 'expected TOEFL mapping not found';
  end if;
end $$;

revoke all on function public.layer2_apply_course_candidate(uuid,boolean) from public,anon,authenticated;
grant execute on function public.layer2_apply_course_candidate(uuid,boolean) to service_role;

commit;
