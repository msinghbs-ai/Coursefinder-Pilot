CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('idle', true, 'reason', 'off', 'items', '[]'::jsonb); end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
  select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;
  if nullif(btrim(v_model), '') is null then return jsonb_build_object('idle', true, 'reason', 'no_model', 'items', '[]'::jsonb); end if;
  -- the shared AI rule (credit floor, daily ceiling, lane guard; v2.15.404): nothing new is claimed while AI use is refused
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if;
  -- the pilot's hard ceilings: total AI spend of this lane in the shared ledger, and total Firecrawl reads of this reader
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  with pick as (select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else security.provider_description_stored_v1(r.provider_id) is not null end
                 order by r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3), (security.pipeline_num_v1('pdesc.pending_max', 10) - v_pending)::int))
                 for update skip locked),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1,
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
           'website', p.website, 'country', k.iso_alpha2, 'hosts', to_jsonb(security.provider_hosts_v1(u.provider_id)),
           'stored', (select jsonb_build_object('evidence_id', a.id, 'storage_path', a.storage_path, 'url', a.source_url, 'captured_at', coalesce(a.captured_at, a.created_at))
                        from pipeline.evidence_artifacts a where a.id = st.stored_id),
           -- About pages the central page finder suggested (page type about_page, central.ts), on the provider's own hosts, best first
           -- IQ-00055: the page rule once per suggestion (a lateral), for the filter and the order
           'candidates', (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select y.url, y.score, g.pg from (
                              select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                                from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                               where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                                 and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                              cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g
                             where (g.pg->>'ok')::boolean) z))), '[]'::jsonb)
    into v
    -- IQ-00055: the stored copy once per claimed row
    from upd u cross join lateral (select security.provider_description_stored_v1(u.provider_id) stored_id offset 0) st
         join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return jsonb_build_object('model', v_model,
    'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1, 'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1,
    'firecrawl_left', greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used),
    'page_chars', security.pipeline_num_v1('pdesc.page_chars', 16000)::int,
    'min_quote_chars', security.pipeline_num_v1('pdesc.min_quote_chars', 20)::int,
    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb),
    -- pilot 2 Nov 2026 16:16: the page rule's lists, for the home page's links (security.provider_description_page_v1 decides the same way)
    'page_rule', jsonb_build_object('about_prefixes', coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb),
                                    'refused_path_words', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb),
                                    'refused_host_labels', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb),
                                    'about_max_segments', security.pipeline_num_v1('pdesc.about_max_segments', 2)::int),
    -- pilot 2 Nov 2026 16:16 (CDU held at 916 characters): the model is told the limits the validation applies
    'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2)::int, 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5)::int,
                                 'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150)::int, 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int),
    'items', v);
end $function$

