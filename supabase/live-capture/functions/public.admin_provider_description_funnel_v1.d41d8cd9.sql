CREATE OR REPLACE FUNCTION public.admin_provider_description_funnel_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_out jsonb; v_job jsonb; v_last jsonb := null; v_sel jsonb; v_elig int; v_pending int; v_pmax numeric := security.pipeline_num_v1('pdesc.pending_max', 10);
        v_size int := least(security.pipeline_num_v1('pdesc.queue_per_run', 10), security.pipeline_num_v1('pdesc.pending_max', 10), security.pipeline_num_v1('run_now.pilot_cap', 20))::int;
        v_stall text; v_policy int; v_run int; v_spent numeric; v_fc numeric; v_big boolean; v_pat text[];
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
  -- many providers in scope (QA B2): identity and the stored page are counted from the register in one pass instead of provider by provider, so the screen stays inside its time-out
  select count(*) > security.pipeline_num_v1('pdesc.funnel_detail_max', 400) into v_big from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
   where p.lifecycle_status = 'active' and coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text and security.pdesc_type_in_scope_v1(t.code);
  v_pat := security.pdesc_about_like_patterns_v1();
  with base as (
    select p.id, p.stable_key, p.website, nullif(btrim(p.description), '') is not null has_desc, nullif(btrim(p.website), '') is not null has_site,
           p.lifecycle_status = 'active' and p.publication_status = 'published' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) live,
           coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text
             and security.pdesc_type_in_scope_v1(t.code) policy_scope
      from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where p.lifecycle_status = 'active'),
  st as (
    select b.*, case when b.live and b.policy_scope then case when v_big and jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)) = 0 then true else security.provider_description_scope_v1(b.id) end end run_scope,
           case when b.live and b.policy_scope then case when v_big then b.has_site and not exists (select 1 from pipeline.provider_identity_findings f where f.provider_id = b.id and f.state = 'open')
                                                                           and not exists (select 1 from catalogue.providers o where o.id <> b.id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = security.site_host_v1(b.website))
                                                 else coalesce((security.provider_description_identity_v1(b.id, b.website)->>'ok')::boolean, false) end end identity_ok,
           case when b.live and b.policy_scope then case when v_big then security.provider_description_stored_candidate_v1(b.id, v_pat) else security.provider_description_stored_v1(b.id) is not null end end stored_page,
           lr.state, lr.rule, lr.published_at, lr.consumer_checked_at, lr.created_at read_created
      from base b left join lateral (select x.state, x.rule, x.published_at, x.consumer_checked_at, x.created_at from pipeline.provider_description_reads x where x.provider_id = b.id order by x.created_at desc, x.id desc limit 1) lr on true)
  select jsonb_build_object(
    'contract', 'provider-description-funnel-v1', 'as_at', now(),
    'stages', jsonb_build_array(
      jsonb_build_object('key', 'registry', 'label', 'Active providers', 'n', count(*)),
      jsonb_build_object('key', 'live', 'label', 'Active, published, not hidden', 'n', count(*) filter (where live)),
      jsonb_build_object('key', 'website', 'label', 'With a website', 'n', count(*) filter (where live and has_site)),
      jsonb_build_object('key', 'policy_scope', 'label', 'In the set countries and institution types', 'n', count(*) filter (where live and policy_scope)),
      jsonb_build_object('key', 'run_scope', 'label', 'In the run scope (pdesc.provider_keys applied)', 'n', count(*) filter (where run_scope)),
      jsonb_build_object('key', 'identity_clear', 'label', 'Identity clear (policy scope)', 'n', count(*) filter (where identity_ok)),
      jsonb_build_object('key', 'stored_page', 'label', 'Official About page already stored (policy scope)', 'n', count(*) filter (where stored_page)),
      jsonb_build_object('key', 'read', 'label', 'Read at least once', 'n', count(*) filter (where state is not null)),
      jsonb_build_object('key', 'queued', 'label', 'Queued or reading', 'n', count(*) filter (where state in ('queued', 'reading'))),
      jsonb_build_object('key', 'proposed', 'label', 'Proposed, waiting for a person in Layer 4', 'n', count(*) filter (where state = 'proposed')),
      jsonb_build_object('key', 'held', 'label', 'Held by a rule', 'n', count(*) filter (where state in ('held', 'dead_letter'))),
      jsonb_build_object('key', 'rejected', 'label', 'Rejected by a person', 'n', count(*) filter (where state = 'rejected')),
      jsonb_build_object('key', 'admitted', 'label', 'Approved and admitted', 'n', count(*) filter (where state in ('admitted', 'verified'))),
      jsonb_build_object('key', 'published', 'label', 'Description held by the catalogue', 'n', count(*) filter (where has_desc and live)),
      jsonb_build_object('key', 'consumer_checked', 'label', 'Checked on the Website read', 'n', count(*) filter (where consumer_checked_at is not null))),
    'held_reasons', coalesce((select jsonb_agg(jsonb_build_object('rule', z.rule, 'state', z.state, 'n', z.n) order by z.n desc, z.rule) from (select s.rule, s.state, count(*) n from st s where s.state in ('held', 'dead_letter', 'rejected') group by 1, 2) z), '[]'::jsonb),
    'policy_scope_outside_run_scope', count(*) filter (where live and policy_scope and not run_scope),
    'oldest_open_read', min(read_created) filter (where state in ('queued', 'reading', 'proposed')))
    into v_out from st;
  v_policy := (select (x->>'n')::int from jsonb_array_elements(v_out->'stages') x where x->>'key' = 'policy_scope');
  v_run := (select (x->>'n')::int from jsonb_array_elements(v_out->'stages') x where x->>'key' = 'run_scope');
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  v_sel := security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'prefilter', v_big, 'size', v_size, 'mode', case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then 'approved' else 'stored' end));
  v_elig := (v_sel->>'eligible')::int;
  select jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active) into v_job from cron.job j where j.jobname = 'provider-description-read';
  if to_regclass('cron.job_run_details') is not null then
    execute $q$select jsonb_build_object('status', d.status, 'started', d.start_time, 'finished', d.end_time) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-read' order by d.start_time desc limit 1$q$ into v_last;
  end if;
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc from pipeline.provider_description_reads r;
  v_stall := case when security.pipeline_num_v1('pdesc.enabled', 0) < 1 then 'reader_off'
                  when coalesce((v_job->>'active')::boolean, false) is not true then 'job_paused'
                  when v_pending >= v_pmax and security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then 'review_full'
                  when v_elig > 0 then 'next_run_will_queue'
                  when v_policy > v_run then 'run_scope_limited_by_pdesc_provider_keys'
                  when v_pending > 0 then 'waiting_for_reviewers'
                  else 'no_eligible_provider_in_scope' end;
  return v_out || jsonb_build_object(
    'layer4', jsonb_build_object('pending', v_pending, 'pending_max', v_pmax,
       'oldest_pending', (select min(i.created_at) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending'),
       'decided', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status <> 'pending')),
    'job', coalesce(v_job, '{}'::jsonb), 'last_run', v_last,
    'settings', jsonb_build_object('enabled', security.pipeline_num_v1('pdesc.enabled', 0) >= 1, 'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1,
       'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1, 'queue_per_run', security.pipeline_num_v1('pdesc.queue_per_run', 10),
       'pinned_providers', jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)),
       'countries', coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb), 'provider_types', coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb)),
    'spend', jsonb_build_object('ai_usd', round(v_spent, 4), 'ai_usd_max', security.pipeline_num_v1('pdesc.ai_usd_max', 1), 'firecrawl_reads', v_fc, 'firecrawl_reads_max', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)),
    'next_run', jsonb_build_object('eligible', v_elig, 'size', v_size, 'exclusions', coalesce((select jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n) order by z.n desc, z.reason)
                                                                                                from (select x->>'reason' reason, count(*) n from jsonb_array_elements(coalesce(v_sel->'exclusions', '[]'::jsonb)) x group by 1) z), '[]'::jsonb)),
    'stall', v_stall);
end $function$
