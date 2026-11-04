CREATE OR REPLACE FUNCTION public.admin_provider_descriptions(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_ids uuid[]; v_n int; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
  if p_action = 'metrics' then
    return (with el as (
              select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 cc, nullif(btrim(p.description), '') is not null present,
                     (select r.state from pipeline.provider_description_reads r where r.provider_id = p.id order by r.created_at desc limit 1) state,
                     (select r.rule from pipeline.provider_description_reads r where r.provider_id = p.id order by r.created_at desc limit 1) rule,
                     security.provider_description_stored_v1(p.id) is not null stored
                from catalogue.providers p join ref.countries k on k.id = p.country_id
               where security.provider_description_scope_v1(p.id) and (v_cc is null or k.iso_alpha2 = v_cc)
                 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)),
            rd as (select r.* from pipeline.provider_description_reads r join el on el.id = r.provider_id)
      select jsonb_build_object(
        'enabled', security.pipeline_num_v1('pdesc.enabled', 0) >= 1,
        'job_active', coalesce((select j.active from cron.job j where j.jobname = 'provider-description-read'), false),
        'by_country', coalesce((select jsonb_agg(jsonb_build_object('country', cc, 'eligible', n, 'present', pr, 'missing', n - pr, 'stored_pages', st) order by cc)
                                  from (select cc, count(*) n, count(*) filter (where present) pr, count(*) filter (where stored) st from el group by cc) c), '[]'::jsonb),
        'eligible', (select count(*) from el), 'present', (select count(*) from el where present), 'missing', (select count(*) from el where not present),
        'stored_pages_available', (select count(*) from el where stored),
        'queued', (select count(*) from el where state = 'queued'), 'reading', (select count(*) from el where state = 'reading'),
        'proposed', (select count(*) from el where state = 'proposed'), 'held', (select count(*) from el where state = 'held'),
        'dead_letter', (select count(*) from el where state = 'dead_letter'), 'admitted', (select count(*) from el where state = 'admitted'),
        'verified', (select count(*) from el where state = 'verified'), 'rejected', (select count(*) from el where state = 'rejected'),
        'published', (select count(*) from rd where rd.state = 'admitted' and rd.published_at is not null),
        'pages_acquired', (select count(*) from rd where rd.read_via in ('direct', 'firecrawl')),
        'pages_reused', (select count(*) from rd where rd.read_via = 'stored'),
        'ai_reads', (select count(*) from rd where rd.model is not null),
        'retried', (select count(*) from rd where rd.tries > 1),
        'cost_usd', (select round(coalesce(sum(rd.cost_usd), 0), 4) from rd),
        'firecrawl_reads', (select coalesce(sum(rd.firecrawl_reads), 0) from rd),
        'ai_usd_max', security.pipeline_num_v1('pdesc.ai_usd_max', 1), 'firecrawl_reads_max', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0),
        'cost_per_admitted_usd', (select case when count(*) filter (where rd.state = 'admitted') = 0 then null
                                              else round(sum(rd.cost_usd) / count(*) filter (where rd.state = 'admitted'), 4) end from rd),
        'reads_last_7_days', (select count(*) from rd where rd.updated_at > now() - make_interval(days => 7) and rd.model is not null),
        'last_run', (select max(l.created_at) from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'),
        'layer4_pending', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending'),
        'layer4_decided', (select count(*) from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status <> 'pending'),
        'rejections', coalesce((select jsonb_agg(jsonb_build_object('rule', rule, 'n', n) order by n desc)
                                  from (select rd.rule, count(*) n from rd where rd.state in ('held', 'rejected', 'dead_letter') group by rd.rule) z), '[]'::jsonb),
        'backlog', (select count(*) from el where not present and coalesce(state, 'none') not in ('proposed', 'held', 'dead_letter', 'rejected')),
        'providers', coalesce((select jsonb_agg(jsonb_build_object('provider_id', el.id, 'provider', el.name, 'country', el.cc, 'present', el.present, 'state', el.state,
                                                                  'rule', el.rule, 'stored_page', el.stored) order by el.cc, el.name) from el), '[]'::jsonb)));
  elsif p_action = 'retry' then
    -- dead letters and held reads go back to the queue (PIM Admin and above, with a reason)
    if v_rank < 5 then raise exception 'PIM Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 5 then raise exception 'reason required'; end if;
    v_ids := array(select jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb))::uuid);
    update pipeline.provider_description_reads r set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = 'retried', reason = v_reason, updated_at = now()
     where r.state in ('dead_letter', 'held') and r.provider_id = any (v_ids)
       and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = r.provider_id and o.state in ('queued', 'reading', 'proposed'))
       and r.id = (select r2.id from pipeline.provider_description_reads r2 where r2.provider_id = r.provider_id order by r2.created_at desc limit 1);
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('provider_descriptions', 'retry', 'pipeline.provider_description_reads', jsonb_build_object('providers', to_jsonb(v_ids), 'requeued', v_n, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'requeued', v_n);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$

