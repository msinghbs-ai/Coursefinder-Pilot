-- CF-247 intake selection: an explicit pilot share beside fairness and focus priority (Platform Admin 5 Nov 2026 18:00: "reconcile the
-- distinction between enrich_focus_providers and the approved top-10 Australian university intake pilot ... Keep the global scheduler
-- eligible to process other providers. Do not hard-code a permanent top-10 restriction"; direction 15:50 §3; decision 16:36 §2).
-- Why (production, 18:00-18:17): the scheduled intake-dates job processes the global catalogue (every provider with an approved calendar). The
--   approved pilot is security.intake_ui_scopes_v1() (the top Australian universities by active courses, sized by run_now.cohort_top_au_universities,
--   10). v2.15.484 ordered rounds by the 50-provider enrichment focus list, so non-pilot focus providers served at 09:26 (Torrens, James Cook,
--   La Trobe, Australian Pacific College, Sunshine Coast, TAFE SA) took the first slots and most of the pilot waited, although the pilot has
--   genuinely eligible work (Newcastle: 34 of 120 sampled rows would be admitted under the current evidence and admission rules).
-- What (security.intake_dates_plan_v3, md5-guarded edit of 886876cd; the same job, batch, share, fingerprints, revisits, holds and locks):
--   * the pilot universities take up to intake_dates.pilot_batch_share per cent of each batch (60), round by round, the one waiting longest
--     first, then focus rank; the rest of the batch goes to every other provider as before (focus first, longest waiting first); unused room on
--     either side is taken by the other, so a pilot with no eligible work blocks nobody and the global catalogue keeps moving;
--   * the pilot is the existing run_now.cohort_top_au_universities scope (not a list in code); pilot_batch_share 0 restores the v2.15.484 order.
-- Consumer API: unchanged (G3).
-- Replaces: md5-guarded edit of security.intake_dates_plan_v3 (886876cd)
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.pilot_batch_share', 'Intake dates: share of each run for the pilot universities',
  'The pilot universities (the top Australian universities by active courses, Run now: Australian universities a cohort is picked from) take up to this share of each intake-dates run, round by round and longest waiting first; every other provider takes the rest. Unused room on either side goes to the other. 0 gives the pilot no reserved share.',
  'number', to_jsonb(60), 0, 100, 'per cent', 1012, 'Intake dates', 'security.intake_dates_plan_v3; job intake-dates-apply',
  'Platform Admin 5 Nov 2026 18:00: the approved top-10 pilot is processed every run without a permanent top-10 restriction')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit('security.intake_dates_plan_v3(uuid[],integer)', '886876cde3afdd3e55fa04a9459c6f95', 'intake_dates.pilot_batch_share',
  array[$o$  v_share int := greatest(1, security.pipeline_num_v1('intake_dates.provider_share', 25)::int);$o$,
        $o$    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id, c.course_url, sets.s cal_set,
           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id$o$,
        $o$     order by ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share),
              (f.rank is null), sets.served nulls first, f.rank nulls last, c.provider_id, i.course_id, i.id  -- focus universities first within a round (direction 5 Nov 2026 15:50 §3), longest waiting first among them
     limit v_limit$o$],
  array[$n$  v_share int := greatest(1, security.pipeline_num_v1('intake_dates.provider_share', 25)::int);
  -- Platform Admin 5 Nov 2026 18:00: the approved pilot (run_now.cohort_top_au_universities) takes up to this many rows of each batch
  v_pilot uuid[] := case when p_course_ids is null then (select coalesce(array_agg((e->>'id')::uuid), '{}') from jsonb_array_elements(security.intake_ui_scopes_v1()) e) else '{}' end;
  v_pilot_rows int := floor(coalesce(p_limit, security.pipeline_num_v1('batch.intake_dates_apply', 200)::int) * least(100, greatest(0, security.pipeline_num_v1('intake_dates.pilot_batch_share', 60))) / 100.0)::int;$n$,
        $n$    select q.id, q.course_id, q.provider_id, q.intake_label, q.intake_year, q.start_date, q.application_deadline, q.evidence_id, q.course_url, q.cal_set, q.fp from (
    select q0.*, row_number() over (partition by q0.pilot order by q0.rnd, q0.served nulls first, q0.frank nulls last, q0.provider_id, q0.course_id, q0.id) pilot_seq from (
    select i.id, i.course_id, c.provider_id, i.intake_label, i.intake_year, i.start_date, i.application_deadline, i.evidence_id, c.course_url, sets.s cal_set,
           security.intake_inputs_fp_v1(sets.s, i.evidence_id, c.course_url, v_settings) fp,
           ceil(row_number() over (partition by c.provider_id order by i.course_id, i.id)::numeric / v_share) rnd, sets.served, f.rank frank, c.provider_id = any (v_pilot) pilot
      from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join sets on sets.provider_id = c.provider_id$n$,
        $n$    ) q0) q
     -- the pilot's reserved rows first, then every other provider (focus first, longest waiting first), then any pilot rows beyond its share
     order by case when q.pilot and q.pilot_seq <= v_pilot_rows then 0 when not q.pilot then 1 else 2 end,
              q.rnd, (q.frank is null), q.served nulls first, q.frank nulls last, q.provider_id, q.course_id, q.id  -- focus universities first within a round (direction 5 Nov 2026 15:50 §3)
     limit v_limit$n$],
  array[1, 1, 1]);
