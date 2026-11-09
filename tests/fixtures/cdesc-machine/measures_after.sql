-- Guards: F-CDESC (Platform Admin decision 10 Nov 2026): with no machine decision the four edited measures answer exactly as before, apart from the new machine keys (see measures_before.sql).
\set ON_ERROR_STOP 1
do $$ declare b record; a jsonb; bad text := '';
begin
  if (select count(*) from pipeline.layer4_decisions where layer2_state->>'actor_kind' = 'machine') <> 0 then raise exception 'a machine decision exists; this comparison needs none'; end if;
  for b in select * from public.g_measure_before loop
    a := case b.fn when 'summary' then security.course_description_summary_v1(null, false) when 'capacity' then security.course_description_capacity_v1()
                   when 'sample' then security.course_description_sample_report_v1() else security.layer4_pace_v1() end;
    -- the new keys, with their value while there is no machine decision
    if b.fn = 'summary' then if (a->>'admitted_by_machine')::int <> 0 then bad := bad || ' summary.admitted_by_machine'; end if; if a->>'note' not like '%admitted_by_machine%' then bad := bad || ' summary.note'; end if; a := a - 'admitted_by_machine'; a := jsonb_set(a, '{note}', b.answer->'note'); end if; -- the note names the new key; nothing else in the answer moves
    if b.fn = 'capacity' then if (a->>'approved_by_machine')::int <> 0 then bad := bad || ' capacity.approved_by_machine'; end if; a := a - 'approved_by_machine'; end if;
    if b.fn = 'sample' then if (a->>'approved_by_machine')::int <> 0 then bad := bad || ' sample.approved_by_machine'; end if; a := a - 'approved_by_machine'; end if;
    if a is distinct from b.answer then bad := bad || ' ' || b.fn || ' (before ' || left(b.answer::text, 200) || ' after ' || left(a::text, 200) || ')'; end if;
  end loop;
  if bad <> '' then raise exception 'a measure answers differently with no machine decision:%', bad; end if;
  raise notice 'measures: summary, capacity, sample report and pace answer as before with no machine decision (one new key beside the old ones in the first three; pace unchanged)';
end $$;
drop table public.g_measure_before;
