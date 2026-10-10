-- CF-247, 7 Oct 2026 (Platform Admin: restore the schedule fees). Switching on the WSU fee-year setting let the sweep replace 15 approved 2027 schedule fees
-- (Decision 162) with page figures that disagree (course total versus annual rate, or another year). The 15 courses are now excluded from the adapter fee;
-- this puts the 15 schedule rows back as the active 2027 fee, only where the course has no other active 2027 international fee. One-off data fix, logged.
do $p$
declare v_ids uuid[] := string_to_array('220f8ddc-d925-41ce-b816-2017209160d0,33256c1a-7fb4-4b41-b47e-330ca04c1367,493e92db-d2b8-4c35-9588-3b93b31b7e93,64bed7e0-eaf3-496c-a12a-e7dc48945fe5,6e743c98-7d60-411d-a388-17892938074e,7050fea4-508a-4ee7-9d94-7574961d2dd6,741720ac-7e20-48f3-a656-414b794683d5,84cd2526-0740-4fc4-9d6d-05b8a8299251,87cdf010-be7f-46a1-9a7e-4576df6252af,884b1875-fe53-487d-9db2-27c8921bb513,a59ad326-1a2b-40dd-b785-c0e407b81aa4,b4b23665-2802-44e6-afeb-62e19d0cb9b8,d7388466-585f-4c19-91af-59ad4da5b8f6,da54fba1-6689-424e-82f8-fc564547a375,e470e63b-a931-4026-b411-e6bacc6339e0', ',')::uuid[]; v_n int;
begin
  if (select count(*) from catalogue.course_fees where id = any(v_ids) and status = 'superseded' and fee_year = 2027 and notes like 'Decision 162%') <> 15 then
    raise exception 'the 15 schedule rows are not in the state this fix expects'; end if;
  update catalogue.course_fees f set status = 'active', updated_at = now()
   where f.id = any(v_ids) and f.status = 'superseded'
     and not exists (select 1 from catalogue.course_fees g where g.course_id = f.course_id and g.id <> f.id and g.status = 'active' and g.fee_type = f.fee_type and g.audience = f.audience and g.fee_year = 2027);
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'schedule_fees_restored', 'wsu 2027 schedule (Decision 162)', jsonb_build_object('provider_id', '1719c3ba-1ddf-483e-935e-c750124ba99c', 'restored', v_n, 'fee_ids', to_jsonb(v_ids), 'reason', 'CF-247 7 Oct 2026: Platform Admin chose to restore the schedule fees and exclude the 15 courses from the adapter fee'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $p$;
