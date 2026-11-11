-- Forward recovery for migration 20261112103900_cf247_aer_discovery_spare (F-AER.04 D2). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Takes the three edited bodies back to their live definitions before the change, byte for byte (md5-guarded), and switches the spare room off
-- (aer.discovery_spare_daily_max 0). Nothing is dropped: the table, settings and new functions stay (a drop goes to the Platform Admin as a paste file).
update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = 'forward recovery of 20261112103900', updated_at = now()
 where toolset_key = 'pipeline' and key = 'aer.discovery_spare_daily_max';
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_discovery_campaign_used_v1(bigint)', 'a1635da2b5eb53b4539518cb65ba7198', '2b1e2ec802e29f873fe0a77c85fe7150',
     array[$o$  -- 12 Nov 2026 (D2): from each provider's first request of the campaign, through the (provider_id, at) index; the same total as any request before the spend
  with f as (select q.provider_id, min(q.requested_at) t from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign group by 1)
  select coalesce(sum(u.units), 0) from f join pipeline.coverage_vendor_usage u on u.provider_id = f.provider_id and u.at >= f.t
   where security.fc_purpose_group_v1(u.purpose) = 'central'$o$],
     array[$n$  select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u
   where security.fc_purpose_group_v1(u.purpose) = 'central'
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.campaign_id = p_campaign and q.provider_id = u.provider_id and u.at >= q.requested_at)$n$]),
    ('public.svc_fc_spend(numeric,text,uuid,text)', '07972f712be389e84d49f33a0852f534', 'c9d616fa35a278103121416ce73e0295',
     array[$o$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url); v_spare boolean := false;$o$,
           $o$    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    -- 12 Nov 2026 (Platform Admin decision D2): a central spend for a provider with an open discovery campaign request that the central share would refuse may use
    -- verified unused capacity (security.aer_discovery_spare_room_v1: inside the daily total, after every other group's projected need, above the vendor floor, at most
    -- aer.discovery_spare_daily_max a day); the campaign ceiling and not_due below still apply
    v_spare := v_grp = 'central' and p_provider_id is not null and security.fc_budget_left_v1(p_purpose) < p_units
               and security.aer_discovery_spare_ok_v1(p_provider_id, p_units);
    if security.fc_budget_left_v1(p_purpose) < p_units and not v_spare then$o$,
           $o$  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  if v_spare then
    insert into pipeline.aer_discovery_spare_spends(campaign_id, provider_id, purpose, units, room)
    select c.id, p_provider_id, p_purpose, p_units, coalesce((security.aer_discovery_spare_room_v1()->>'room')::numeric, 0) + p_units
      from pipeline.aer_discovery_campaigns c where c.state = 'running' order by c.id desc limit 1;
  end if;
  return true;$o$],
     array[$n$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);$n$,
           $n$    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    if security.fc_budget_left_v1(p_purpose) < p_units then$n$,
           $n$  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;$n$]),
    ('public.admin_aer_discovery(jsonb)', '8a84d58d70e1c7f31606af2b4199363b', '2f26aa2679d98904bb310bc97857857c',
     array[$o$      'metrics', security.aer_discovery_metrics_v1(),  -- 12 Nov 2026 (D2)
      'rows', (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.courses desc, pg.provider), '[]'::jsonb) from pg)));$o$],
     array[$n$      'rows', (select coalesce(jsonb_agg(to_jsonb(pg) order by pg.courses desc, pg.provider), '[]'::jsonb) from pg)));$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition migration 20261112103900 left (body md5 %)', r.sig, md5(v_src); end if;
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
