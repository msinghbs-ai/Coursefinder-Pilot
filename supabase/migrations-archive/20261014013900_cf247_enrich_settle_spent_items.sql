-- CF-247 v2.15.275 hotfix (scheduled check of the NZ and Canada Enrich fields run, 14 Oct 2026 15:24 Melbourne; the Platform Admin asked at
-- 12:04 to "maintain stats and telemetry" and run the batches)
--   An AI reply that held a null character could not be recorded; its 30 items used their three tries while still "leased", and an
--   item left like that was never settled. Batch 1 could not finish (and batch 2, queued behind it, could not start); the campus
--   lists of the universities those items belong to waited for them.
--   1 Each pass now settles an item that has used its tries and is no longer being worked on, as failed, with the reason.
--   2 Worker v0.23.1 removes null characters before recording (supabase/functions/coverage-sweep).
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"security.enrich_fields_slice_v1(uuid,integer)": "e2e2447103b9c4ef9ae15689dc8d989c"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.enrich_fields_slice_v1(p_id uuid, p_items integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j pipeline.admin_jobs%rowtype; it record; v_src text; v_srcs text[]; v_ai boolean; v_scr boolean; v_x jsonb; v_txt text; v_val jsonb;
        v_done int := 0; v_batch int := greatest(coalesce(p_items, 0), 1) * security.pipeline_num_v1('batch.enrich_fields', 400)::int / 10;
        v_cc text; v_path text; v_ev uuid; v_settled boolean; v_left int;
begin
  select * into j from pipeline.admin_jobs where id = p_id for update;
  v_ai := coalesce((j.args->>'ai')::boolean, true); v_scr := coalesce((j.args->>'scraper')::boolean, false);
  -- v2.15.275 hotfix: an item that has used its AI tries and is no longer being worked on is settled as failed, so the task can finish
  update pipeline.field_enrich_items e set state = 'failed', leased_until = null, updated_at = now(),
         reason = coalesce(e.reason, 'no answer could be recorded after ' || e.attempts || ' tries')
   where e.job_id = p_id and e.attempts >= 3 and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now()));
  -- items waiting for a requested page: move on when the page arrived, skip when the wait is over
  update pipeline.field_enrich_items e set state = 'queued', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = e.course_id and g.evidence_id is not null and g.read_at >= e.updated_at);
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'the requested page read did not arrive in time', updated_at = now()
   where e.job_id = p_id and e.state = 'waiting' and e.field <> 'campus'
     and e.updated_at < now() - make_interval(hours => security.pipeline_num_v1('enrich.wait_page_hours', 6)::int);
  for it in select e.*, k.iso_alpha2::text cc from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id join ref.countries k on k.id = p.country_id
             where e.job_id = p_id and e.state = 'queued' order by e.id limit v_batch for update of e skip locked loop
    v_settled := false; v_srcs := security.field_sources_for_v1(it.cc, case when it.field = 'campus_list' then 'campus' else it.field end);
    foreach v_src in array v_srcs loop
      continue when v_src = any (it.tried);
      continue when v_src in ('ai_stored', 'ai_title') and not v_ai;
      continue when v_src = 'scraper' and not v_scr;
      update pipeline.field_enrich_items set tried = tried || v_src where id = it.id;
      if v_src = 'adapter' and it.course_id is not null then
        select r.fields->'extra' into v_x from pipeline.uni_adapter_results r where r.course_id = it.course_id order by r.at desc limit 1;
        v_txt := nullif(btrim(case it.field when 'campus' then coalesce(v_x->>'campus', v_x->>'location') when 'duration' then v_x->>'duration'
                                            when 'level' then v_x->>'study_level' when 'delivery' then v_x->>'mode' when 'international' then v_x->>'student_type' end), '');
        if v_txt is null then continue; end if;
        v_ev := (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = it.course_id);
        v_val := case it.field when 'duration' then security.enrich_parse_duration_v1(v_txt)
                               when 'level' then (select jsonb_build_object('level_id', l) from (select security.enrich_parse_level_v1(v_txt) l) z where l is not null)
                               when 'delivery' then (select jsonb_build_object('mode', m) from (select security.enrich_parse_delivery_v1(left(v_txt, 120)) m) z where m is not null)
                               when 'international' then case when v_txt ~* 'international' then jsonb_build_object('open', true) end
                               else null end;
        if it.field = 'campus' then
          -- the campus text waits for the university's campus list
          update pipeline.field_enrich_items set state = 'waiting', source = 'adapter', quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
        if v_val is null then continue; end if;
        update pipeline.field_enrich_items set source = 'adapter', value = v_val, quote = left(v_txt, 300), evidence_id = v_ev, updated_at = now() where id = it.id;
        perform security.enrich_apply_v1(it.id); v_settled := true; exit;
      elsif v_src = 'institution_rule' and it.field = 'international' then
        if it.cc = 'CA' and exists (select 1 from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli') then
          update pipeline.field_enrich_items set source = 'institution_rule', value = jsonb_build_object('open', true),
                 quote = 'Listed by IRCC as a designated learning institution (DLI ' || (select i.identifier from catalogue.provider_identifiers i where i.provider_id = it.provider_id and i.scheme = 'ircc_dli' limit 1) || ')', updated_at = now()
           where id = it.id;
          perform security.enrich_apply_v1(it.id); v_settled := true; exit;
        end if;
      elsif v_src = 'ai_stored' then
        if it.field = 'provider_address' then
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
        elsif it.field = 'campus_list' then
          v_path := null; v_ev := null;  -- the list is made from the campus names, with the contact page when one is stored
          select e.storage_path, e.id into v_path, v_ev from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
           where s.provider_id = it.provider_id and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page') and e.storage_path is not null order by e.created_at desc limit 1;
          update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
          v_settled := true; exit;
        else
          select e.storage_path, e.id into v_path, v_ev from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id where g.course_id = it.course_id;
        end if;
        if v_path is null then continue; end if;
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_stored', storage_path = v_path, evidence_id = v_ev, updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'ai_title' and it.course_id is not null then
        update pipeline.field_enrich_items set state = 'ai', source = 'ai_title', updated_at = now() where id = it.id;
        v_settled := true; exit;
      elsif v_src = 'scraper' then
        if it.field = 'provider_address' then
          if exists (select 1 from catalogue.providers p where p.id = it.provider_id and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)) then
            update pipeline.field_enrich_items set state = 'ai', source = 'scraper', storage_path = null, updated_at = now() where id = it.id;
            v_settled := true; exit;
          end if;
        elsif it.course_id is not null and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.url ~* '^https?://') then
          update pipeline.coverage_course_pages set next_read_at = now() where course_id = it.course_id and coalesce(next_read_at, 'infinity') > now();
          update pipeline.field_enrich_items set state = 'waiting', reason = 'course page asked to be read', updated_at = now() where id = it.id;
          v_settled := true; exit;
        end if;
      end if;
    end loop;
    if not v_settled then
      update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(reason, 'no allowed source had a value'), updated_at = now() where id = it.id and state = 'queued';
    end if;
    v_done := v_done + 1;
  end loop;
  -- a university's campus list goes to the AI once its course campus items have all been read
  update pipeline.field_enrich_items l set state = 'queued', updated_at = now()
   where l.job_id = p_id and l.field = 'campus_list' and l.state = 'waiting'
     and not exists (select 1 from pipeline.field_enrich_items c where c.job_id = p_id and c.provider_id = l.provider_id and c.field = 'campus' and c.state in ('queued', 'ai', 'leased'));
  perform security.enrich_campus_link_v1(p_id);
  -- course campus items whose page named no campus: nothing to link
  update pipeline.field_enrich_items c set state = 'skipped', reason = 'no campus named on the page', updated_at = now()
   where c.job_id = p_id and c.field = 'campus' and c.state = 'waiting' and c.quote is null;
  if exists (select 1 from pipeline.field_enrich_items where job_id = p_id and state = 'ai') then perform security.enrich_ai_fire_v1(); end if;
  select count(*) into v_left from pipeline.field_enrich_items where job_id = p_id and state in ('queued', 'waiting', 'ai', 'leased');
  update pipeline.admin_jobs set progress = (select jsonb_build_object('done', count(*) filter (where state in ('filled', 'review', 'skipped', 'failed')), 'total', count(*),
                                                   'phase', case when v_left = 0 then 'finishing' when count(*) filter (where state in ('ai', 'leased')) > 0 then 'reading with AI' else 'settling stored values' end)
                                               from pipeline.field_enrich_items where job_id = p_id),
         result = (select jsonb_build_object('by_field', jsonb_object_agg(f, s), 'cost_usd', (select round(coalesce(sum(cost_usd), 0), 4) from pipeline.field_enrich_items where job_id = p_id))
                     from (select field f, jsonb_object_agg(state, n) s from (select field, state, count(*) n from pipeline.field_enrich_items where job_id = p_id group by 1, 2) z group by field) y),
         updated_at = now()
   where id = p_id;
  return v_left = 0;
end $function$;

do $post$
declare v_expected jsonb := '{"security.enrich_fields_slice_v1(uuid,integer)": "aa68e9a80a65f4e513b51ef1453b2751"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.275 hotfix post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
