-- CF-247 / R5 (rankings clean-up): QS 2025.
-- The accepted QS 2025 edition came from the "2.2 (For qs.com)" workbook, whose parse put the region
-- ("Oceania", "Europe", ...) into the country column for 1,502 of 1,503 rows, so no institution could be
-- matched to a provider (0 links; 0 Australian rows). The edition it replaced (CF-218 static load, same
-- 1,503 rows, correct countries, 38 Australian rows, 66 provider links) is made current again and the
-- faulty one is marked superseded with the reason. Nothing is deleted. Guarded by the counts above.
do $r5$
declare v_bad uuid:='82fdee7e-ec9a-4f33-9dc6-b3d58c25130f'; v_good uuid:='76ad113b-8023-4d5b-87ab-a18b29f19e2e'; v_region int; v_au int; v_before jsonb;
begin
  select count(*) filter (where lower(pi.country_text) in ('oceania','europe','asia','americas','north america','latin america','africa','middle east')) into v_region
    from ranking.observations o join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id where o.edition_id=v_bad;
  select count(*) filter (where pi.country_text ilike 'australia') into v_au
    from ranking.observations o join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id where o.edition_id=v_good;
  if v_region<1500 or v_au<30 then raise exception 'QS 2025 state changed since review (region rows %, AU rows %); nothing changed', v_region, v_au; end if;
  if not exists (select 1 from ranking.editions where id=v_bad and status='accepted') or not exists (select 1 from ranking.editions where id=v_good and status='superseded') then
    raise exception 'QS 2025 edition statuses changed since review; nothing changed'; end if;
  v_before:=security.consumer_api_snapshot_v1();
  update ranking.editions set status='superseded', updated_at=now() where id=v_bad;
  update ranking.editions set status='accepted', updated_at=now() where id=v_good;
  update ranking.manual_imports set status='rejected', updated_at=now(),
         validation_summary=coalesce(validation_summary,'{}'::jsonb)||jsonb_build_object('rejected_reason','Parsed region into the country column (1,502 of 1,503 rows); no provider could be matched. Replaced by the CF-218 load of the same edition (R5, 28 Sep 2026).','rejected_at',now())
   where id='c6025e9f-290d-4779-a4fb-09792af5be06';
  update ranking.manual_imports set status='applied', updated_at=now(),
         validation_summary=coalesce(validation_summary,'{}'::jsonb)||jsonb_build_object('restored_reason','Made current again: correct countries and 66 provider links; the later workbook parse was faulty (R5, 28 Sep 2026).','restored_at',now())
   where id='47190f32-4eeb-4a3e-8d95-46507e431301';
  insert into pipeline.consumer_api_baselines(label, snapshot) values
    ('before R5 QS 2025 edition restore', v_before), ('after R5 QS 2025 edition restore', security.consumer_api_snapshot_v1());
end $r5$;
