-- Forward recovery for migration 20261112040000_cf247_aer_discovery_campaign (F-AER.04). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Restores public.svc_fc_spend and security.aer_source_discover_v1 to their bodies before the change (md5 39075b66... and f818e6bb...), byte for byte (the same guarded
-- edits, reversed), and switches the campaign off. The campaign table, its column, the settings and the read functions are kept (nothing is dropped or deleted).
-- A quicker reversal without code: aer.discovery_campaign_on 0 on Settings > Pipeline settings.

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('public.svc_fc_spend(numeric,text,uuid,text)', 'c9d616fa35a278103121416ce73e0295', '39075b66a1d8ff15246b8c82ffa0c590',
     array[$o$    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then$o$],
     array[$n$    -- 12 Nov 2026 (F-AER.04 discovery campaign): a central spend for a provider the running campaign asked about stops at the campaign ceiling
    -- (aer.discovery_campaign_credit_cap); it is checked after the monthly limit, the cost breakers, the daily total and the central share above
    elsif p_provider_id is not null and v_grp = 'central' and security.aer_discovery_campaign_over_v1(p_provider_id, p_units) then
      v_why := 'campaign_cap';
    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then$n$]),
    ('security.aer_source_discover_v1(boolean)', '16e04c3ffe38a38f3b6f23df7bd0e0a1', 'f818e6bb2500c5cc63c361970c73d1e3',
     array[$o$  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found$o$,
           $o$                  when r.s_req is null and r.evidence ? 'refusal' then 'refused'
                  when r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null) then 'failed'$o$,
           $o$  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap);$o$],
     array[$n$  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found, s.updated_at s_upd$n$,
           $n$                  -- 12 Nov 2026 (F-AER.04): a refusal or an error settles the request only when it was recorded after the request (never the 22 Oct evidence)
                  when r.s_req is null and r.evidence ? 'refusal' and r.s_upd >= r.requested_at then 'refused'
                  when (r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null)) and r.s_upd >= r.requested_at then 'failed'$n$,
           $n$  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap)
         || jsonb_build_object('campaign', security.aer_discovery_campaign_ask_v1(p_preview));$n$])
  ) v(sig, md5_before, md5_after, news, olds) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = 'F-AER.04 forward recovery: campaign off', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.discovery_campaign_on';
update pipeline.aer_discovery_campaigns set state = 'stopped', completed_at = now() where state = 'running';
