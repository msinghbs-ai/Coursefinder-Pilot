-- CF-247, 7 Oct 2026: automatic adapter build, part 4 of 6: the step function, run by the schedule as the Platform Admin who asked.
-- See 20261007001900 for the decisions; qualifying is part 3, admitting is part 5 (by a Platform Admin).

create or replace function security.adapter_autobuild_tick_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare b record; v_read int; v_stored int; v_run pipeline.firecrawl_runs%rowtype; v_d pipeline.uni_adapter_drafts%rowtype; v_p jsonb; v_r jsonb;
        v_adapter jsonb; v_n int := 0; v_budget jsonb;
begin
  for b in select * from pipeline.adapter_autobuilds where status in ('queued', 'finding_pages', 'capturing', 'proposing', 'applying', 'qualifying') order by created_at limit 10 loop
    begin
      perform set_config('request.jwt.claims', jsonb_build_object('sub', b.requested_by::text, 'role', 'authenticated')::text, true);
      select count(*) filter (where pg.read_status = 'read'), count(*) into v_read, v_stored from pipeline.coverage_course_pages pg where pg.provider_id = b.provider_id;
      if b.status = 'queued' then
        if v_read >= 3 then
          v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', b.provider_id, 'reason', 'Automatic build: ' || b.reason));
          update pipeline.adapter_autobuilds set status = 'capturing', draft_id = (v_r->>'draft_id')::uuid, step_started_at = now(), note = 'Capturing sample pages with Firecrawl.', updated_at = now() where id = b.id;
        elsif v_stored = 0 then
          perform public.admin_firecrawl_write('target', jsonb_build_object('provider_id', b.provider_id, 'included', true, 'reason', 'Automatic build: no course pages known yet'));
          update pipeline.adapter_autobuilds set status = 'failed', error = 'No course pages are known for this provider yet. It is now a Firecrawl target, so the course-page search will look for its pages; build again once pages are found.', updated_at = now() where id = b.id;
        elsif exists (select 1 from pipeline.firecrawl_runs r where r.use_case = 'find_page' and r.status = 'running') then
          update pipeline.adapter_autobuilds set note = 'Waiting for another Find pages run to finish.', updated_at = now() where id = b.id;
        else
          v_r := security.firecrawl_upgrade_run_v1(b.provider_id, coalesce(security.firecrawl_setting('find_query') #>> '{}', '{course} site:{domain}'), '^$', greatest(b.credits_cap - 5, 5), 'Automatic adapter build: ' || b.reason, b.requested_by);
          update pipeline.adapter_autobuilds set status = 'finding_pages', fc_run_id = (v_r->>'run_id')::uuid, step_started_at = now(),
                 note = format('Finding and reading course pages with Firecrawl (%s pages, up to %s credits).', v_r->>'items', greatest(b.credits_cap - 5, 5)), updated_at = now() where id = b.id;
        end if;
      elsif b.status = 'finding_pages' then
        select * into v_run from pipeline.firecrawl_runs where id = b.fc_run_id;
        if v_run.status = 'running' and now() - b.step_started_at < interval '3 hours' then
          update pipeline.adapter_autobuilds set note = format('Finding pages: %s of %s done, %s credits used.', coalesce(v_run.done, 0), coalesce(v_run.items, 0), coalesce(v_run.credits_used, 0)), updated_at = now() where id = b.id;
        elsif v_read >= 3 then
          v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', b.provider_id, 'reason', 'Automatic build: ' || b.reason));
          update pipeline.adapter_autobuilds set status = 'capturing', draft_id = (v_r->>'draft_id')::uuid, step_started_at = now(),
                 result = result || jsonb_build_object('find_credits', v_run.credits_used), note = 'Capturing sample pages with Firecrawl.', updated_at = now() where id = b.id;
        elsif now() - b.step_started_at > interval '4 hours' then
          update pipeline.adapter_autobuilds set status = 'failed', error = format('Only %s course pages could be read after the Firecrawl run (3 are needed).', v_read), updated_at = now() where id = b.id;
        end if;
      elsif b.status = 'capturing' then
        select * into v_d from pipeline.uni_adapter_drafts where id = b.draft_id;
        if v_d.status = 'captured' then
          if not exists (select 1 from jsonb_array_elements(coalesce(v_d.captures, '[]'::jsonb)) c where not (c ? 'error')) then
            update pipeline.adapter_autobuilds set status = 'failed', error = 'None of the sample pages could be captured.', updated_at = now() where id = b.id;
          else
            v_budget := security.adapter_builder_budget();
            if (v_budget->>'used_usd')::numeric >= (v_budget->>'limit_usd')::numeric or (v_budget->>'proposals')::int >= (v_budget->>'limit_proposals')::int then
              update pipeline.adapter_autobuilds set note = 'Waiting for the AI allowance (it renews at midnight, Melbourne time).', updated_at = now() where id = b.id;
            else
              perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', b.provider_id, 'draft_id', b.draft_id, 'marks', '[]'::jsonb,
                       'comments', 'Automatic build: propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Automatic build'));
              update pipeline.adapter_autobuilds set status = 'proposing', step_started_at = now(), note = format('The pinned model (%s) is proposing the settings.', v_d.model), updated_at = now() where id = b.id;
            end if;
          end if;
        elsif v_d.status = 'error' or now() - b.step_started_at > interval '30 minutes' then
          update pipeline.adapter_autobuilds set status = 'failed', error = 'Capturing the sample pages did not finish (' || coalesce(v_d.status, 'no draft') || ').', updated_at = now() where id = b.id;
        end if;
      elsif b.status = 'proposing' then
        select * into v_d from pipeline.uni_adapter_drafts where id = b.draft_id;
        v_p := v_d.proposals -> -1;
        if v_d.status = 'proposed' and v_p is not null then
          if v_p->>'kind' = 'error' or v_p->'adapter' is null then
            update pipeline.adapter_autobuilds set status = 'failed', error = 'The model could not propose settings: ' || left(coalesce(v_p->>'error', 'no settings returned'), 300), updated_at = now() where id = b.id;
          else
            v_adapter := coalesce(security.uni_adapter_json(b.provider_id), '{}'::jsonb) - 'updated_at' - 'reason'
                         || jsonb_strip_nulls(jsonb_build_object('json_source', v_p->'adapter'->'json_source', 'json_paths', v_p->'adapter'->'json_paths', 'patterns', v_p->'adapter'->'patterns', 'pick', v_p->'adapter'->'pick'))
                         || jsonb_build_object('enabled', true, 'notes', left('Automatic build ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') || ': ' || coalesce(v_p->>'reason', ''), 1500));
            perform public.admin_uni_adapter_write('save', jsonb_build_object('provider_id', b.provider_id, 'adapter', v_adapter, 'reason', 'Automatic build: settings proposed by the pinned model'));
            perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', b.provider_id, 'reason', 'Automatic build: apply to the stored pages'));
            update pipeline.adapter_autobuilds set status = 'applying', step_started_at = now(), result = result || jsonb_build_object('proposal', v_p - 'output', 'proposal_cost', v_p->'cost'),
                   note = 'Saved (switched on, testing) and applying to the stored pages.', updated_at = now() where id = b.id;
          end if;
        elsif v_d.status = 'error' or now() - b.step_started_at > interval '30 minutes' then
          update pipeline.adapter_autobuilds set status = 'failed', error = 'The proposal did not finish.', updated_at = now() where id = b.id;
        end if;
      elsif b.status = 'applying' then
        if now() - b.step_started_at > interval '90 minutes'
           or (now() - b.step_started_at > interval '10 minutes' and not exists (select 1 from pipeline.uni_adapter_results r where r.provider_id = b.provider_id and r.at > now() - interval '5 minutes')) then
          update pipeline.adapter_autobuilds set status = 'qualifying', step_started_at = now(), note = 'Qualifying each field against the admit rule.', updated_at = now() where id = b.id;
        end if;
      elsif b.status = 'qualifying' then
        perform security.adapter_autobuild_qualify_v1(b.id);
      end if;
      v_n := v_n + 1;
    exception when others then
      update pipeline.adapter_autobuilds set status = 'failed', error = left(sqlerrm, 500), updated_at = now() where id = b.id;
    end;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  return jsonb_build_object('advanced', v_n);
end $f$;
revoke all on function security.adapter_autobuild_tick_v1() from public, anon, authenticated;