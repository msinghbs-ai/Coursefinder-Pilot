-- CF-247 s1173 (S1-RM-Design; SS-Programme-Control P0, 26 Nov 2026 12:10 AEDT: reconcile PIM monitoring figures).
-- Demonstrated defect: security.pim_progress_v1 counted canonical and published gains only from field-enrich items in state filled, keyed by the enrich field name. Academic entry
-- rows are admitted by the AER lanes (deterministic reader, Layer 4, course entry windows), which do not write field-enrich items, and the enrich field is entry_requirements while the
-- register field is academic_entry, so academic entry gains were always 0 (S1-Build counted 1,305 rows and 278 newly populated AU courses in 24 h).
--   1. academic_entry gains now come from the canonical table: a course is newly populated in the window when its earliest active catalogue.course_entry_requirements row was created in
--      the window (data_delivery.net_short_hours); published when its provider is published. Other fields keep the enrich basis, and every field row says its basis (gain_basis).
--   2. security.pim_refresh_v1: blocked and robots_disallowed pages are protected holds, never counted as due for an executable re-read.
--   Read-only closing checks (standing rule, 26 Nov 08:30: production migration checks never start processing).
-- G1: no job. G2: no new value. G3: no consumer API object touched (checked). No lock removed; cron ceiling checked.
-- Replaces: security.pim_progress_v1 and security.pim_refresh_v1 (anchored edits).
-- Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the read-only checks

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
end $g$;
create temp table s1173_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $p$
declare d text := pg_get_functiondef('security.pim_progress_v1()'::regprocedure);
        a1 constant text := 'from ap left join q on q.cc = ap.cc and q.field = ap.field;';
        b1 constant text := E'from ap left join q on q.cc = ap.cc and q.field = ap.field\n'
          || E'    left join (select k2.iso_alpha2 cc, count(*) gain, count(*) filter (where pr2.publication_status = ''published'') pub\n'
          || E'                 from (select x.course_id, min(x.created_at) first_at from catalogue.course_entry_requirements x where x.status = ''active'' group by x.course_id) fx\n'
          || E'                 join catalogue.courses co2 on co2.id = fx.course_id join catalogue.providers pr2 on pr2.id = co2.provider_id join ref.countries k2 on k2.id = pr2.country_id\n'
          || E'                where fx.first_at >= v_since group by k2.iso_alpha2) ae on ae.cc = ap.cc and ap.field = ''academic_entry'';';
        a2 constant text := E'''canonical_gain_window'', coalesce(q.filled_window, 0), ''published_gain_window'', coalesce(q.filled_published_window, 0), ''throughput_per_hour'', round(coalesce(q.filled_window, 0)::numeric / v_hours, 2), ''clearance_hours'', case when coalesce(q.filled_window, 0) > 0 then round((ap.applicable - ap.held)::numeric / (q.filled_window::numeric / v_hours), 1) end,';
        b2 constant text := E'''canonical_gain_window'', case when ap.field = ''academic_entry'' then coalesce(ae.gain, 0) else coalesce(q.filled_window, 0) end,\n'
          || E'      ''published_gain_window'', case when ap.field = ''academic_entry'' then coalesce(ae.pub, 0) else coalesce(q.filled_published_window, 0) end,\n'
          || E'      ''gain_basis'', case when ap.field = ''academic_entry'' then ''canonical: courses whose first active entry row was created in the window'' else ''enrich items filled in the window'' end,\n'
          || E'      ''throughput_per_hour'', round((case when ap.field = ''academic_entry'' then coalesce(ae.gain, 0) else coalesce(q.filled_window, 0) end)::numeric / v_hours, 2),\n'
          || E'      ''clearance_hours'', case when (case when ap.field = ''academic_entry'' then coalesce(ae.gain, 0) else coalesce(q.filled_window, 0) end) > 0\n'
          || E'        then round((ap.applicable - ap.held)::numeric / ((case when ap.field = ''academic_entry'' then coalesce(ae.gain, 0) else coalesce(q.filled_window, 0) end)::numeric / v_hours), 1) end,';
        dn text := regexp_replace(d, '\s+', ' ', 'g');
begin
  -- the live text is matched with its whitespace normalised; the function is rebuilt from the normalised text (SQL is whitespace-insensitive outside literals; no literal in it holds runs of spaces)
  if (length(dn) - length(replace(dn, a1, ''))) / length(a1) <> 1 or (length(dn) - length(replace(dn, a2, ''))) / length(a2) <> 1 then raise exception 'guard: progress anchors not found exactly once'; end if;
  if position('--' in dn) > 0 then raise exception 'guard: the normalised text would carry a line comment'; end if;
  execute replace(replace(dn, a1, b1), a2, b2);
end $p$;

do $r$
declare d text := pg_get_functiondef('security.pim_refresh_v1()'::regprocedure);
        a constant text := 'count(*) pages, count(*) filter (where g.next_read_at <= now()) due_for_reread';
        b constant text := 'count(*) pages, count(*) filter (where g.next_read_at <= now() and coalesce(g.read_status, '''') not in (''blocked'', ''robots_disallowed'')) due_for_reread, bool_or(g.read_status in (''blocked'', ''robots_disallowed'')) protected_hold';
        a2 constant text := E'''due_for_reread'', due_for_reread)';
        b2 constant text := E'''due_for_reread'', due_for_reread, ''protected_hold'', coalesce(protected_hold, false))';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then raise exception 'guard: refresh anchors not found exactly once'; end if;
  execute replace(replace(d, a, b), a2, b2);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); p jsonb; x jsonb; v_gain bigint;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1173_locks) then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  p := security.pim_progress_v1();
  select coalesce(sum((f->>'canonical_gain_window')::bigint), 0) into v_gain from jsonb_array_elements(p->'fields') f where f->>'field' = 'academic_entry';
  if v_gain <> (select count(*) from (select x.course_id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where x.status = 'active' group by x.course_id
                 having min(x.created_at) >= now() - make_interval(hours => security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int)) z) then
    raise exception 'guard: academic entry gain % does not match the canonical table', v_gain;
  end if;
  x := security.pim_refresh_v1();
  if exists (select 1 from jsonb_array_elements(x->'sources') s where s->>'outcome' in ('blocked', 'robots_disallowed') and (s->>'due_for_reread')::int > 0) then raise exception 'guard: a protected hold is counted as due'; end if;
  raise notice 'academic entry newly populated courses in the window: %', v_gain;
end $c$;
