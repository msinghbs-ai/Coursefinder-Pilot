-- CF-247 / R5 (rankings clean-up): THE "2015".
-- After THE 2016–2024 were applied (28 Sep 2026: 800, 981, 1,103, 1,258, 1,397, 1,526, 2,112, 2,345, 2,671 rows),
-- the "2015" edition was compared with 2021: all 1,526 rows are identical in institution, rank and overall score,
-- and the files have the same size. "2015" is the 2021 file registered under the wrong year, so the edition and
-- its upload are withdrawn (kept, not deleted) and 2015 is removed from the supported years. Guarded by the proof.
do $r5$
declare v_sys uuid; v_e15 uuid; v_e21 uuid; v_same int; v_n15 int; v_before jsonb;
begin
  select id into v_sys from ranking.systems where code='the_wur';
  select id into v_e15 from ranking.editions where system_id=v_sys and edition_year=2015 and status='accepted';
  select id into v_e21 from ranking.editions where system_id=v_sys and edition_year=2021 and status='accepted';
  if v_e15 is null or v_e21 is null then raise exception 'THE 2015/2021 editions not in the reviewed state; nothing changed'; end if;
  select count(*) into v_n15 from ranking.observations where edition_id=v_e15;
  select count(*) into v_same from ranking.observations a join ranking.observations b on b.edition_id=v_e21 and a.publisher_institution_id=b.publisher_institution_id
     and a.rank_display is not distinct from b.rank_display and a.overall_score is not distinct from b.overall_score where a.edition_id=v_e15;
  if v_n15=0 or v_same<>v_n15 then raise exception 'THE 2015 is not identical to 2021 (% of %); nothing changed', v_same, v_n15; end if;
  v_before:=security.consumer_api_snapshot_v1();
  update ranking.editions set status='rejected', updated_at=now(),
         licensing_note=coalesce(licensing_note,'')||' | Withdrawn 28 Sep 2026 (R5): identical to the 2021 edition (1,526 of 1,526 rows); the file was registered under the wrong year.'
   where id=v_e15;
  update ranking.manual_imports set status='rejected', updated_at=now(),
         validation_summary=coalesce(validation_summary,'{}'::jsonb)||jsonb_build_object('rejected_reason','Identical to THE 2021 (1,526 of 1,526 rows, same file size); registered under the wrong year. Withdrawn in R5, 28 Sep 2026.','rejected_at',now())
   where system_id=v_sys and edition_year=2015;
  update pipeline.sources set metadata=jsonb_set(metadata,'{supported_edition_years}',
         coalesce((select jsonb_agg(y) from jsonb_array_elements(metadata->'supported_edition_years') y where y::text<>'2015'),'[]'::jsonb)), updated_at=now()
   where metadata->>'ranking_system_code'='the_wur';
  insert into pipeline.consumer_api_baselines(label, snapshot) values
    ('before R5 THE 2015 withdrawn', v_before), ('after R5 THE 2015 withdrawn', security.consumer_api_snapshot_v1());
end $r5$;
