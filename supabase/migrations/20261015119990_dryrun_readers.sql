-- DRY RUN ONLY (rolled back by the raise at the end)
do $purge$
declare v_n bigint; v_h text; v_refs text; t text; v_wi_before bigint; v_tuition_before jsonb; v_li_before bigint; v_fh bigint; v_wi bigint; v_li bigint;
begin
  -- 1 the export is in Storage
  select string_agg(x.name, ', ') into v_refs
    from (values
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_fact_handoffs/part-000.jsonl.gz', 2031664),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_fact_handoffs/part-001.jsonl.gz', 2031960),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_fact_handoffs/part-002.jsonl.gz', 1403489),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_work_items_purged/part-000.jsonl.gz', 4325549),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_work_items_purged/part-001.jsonl.gz', 4321346),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_work_items_purged/part-002.jsonl.gz', 1610263),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_interpretations_purged/part-000.jsonl.gz', 8789704),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_interpretations_purged/part-001.jsonl.gz', 8754392),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_interpretations_purged/part-002.jsonl.gz', 8783949),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_interpretations_purged/part-003.jsonl.gz', 1921639),
      ('cf247-usage-audit-2026-10-15/38729659914/layer2_scope_wave_items/part-000.jsonl.gz', 20),
      ('cf247-usage-audit-2026-10-15/38729659914/layer2_provider_benchmark_observations/part-000.jsonl.gz', 3925),
      ('cf247-usage-audit-2026-10-15/38729659914/pilot_edge_execution_queue/part-000.jsonl.gz', 7071),
      ('cf247-usage-audit-2026-10-15/38729659914/intent_aliases/part-000.jsonl.gz', 1020),
      ('cf247-usage-audit-2026-10-15/38729659914/evidence_links/part-000.jsonl.gz', 20),
      ('cf247-usage-audit-2026-10-15/38729659914/layer2_domain_refresh_policies/part-000.jsonl.gz', 459),
      ('cf247-usage-audit-2026-10-15/38729659914/layer3_work_item_rebinds/part-000.jsonl.gz', 445),
      ('cf247-usage-audit-2026-10-15/38729659914/zz_qualify_scratch_v1/part-000.jsonl.gz', 9328),
      ('cf247-usage-audit-2026-10-15/38729659914/reading_restores_20261005/part-000.jsonl.gz', 10236),
      ('cf247-usage-audit-2026-10-15/38729659914/_layer1_depth_uat_control/part-000.jsonl.gz', 137),
      ('cf247-usage-audit-2026-10-15/38729659914/layer2_fanout_tasks/part-000.jsonl.gz', 19497),
      ('cf247-usage-audit-2026-10-15/38729659914/night_run_queue/part-000.jsonl.gz', 51947),
      ('cf247-usage-audit-2026-10-15/38729659914/night_run_rebatch/part-000.jsonl.gz', 16014),
      ('cf247-usage-audit-2026-10-15/38729659914/refused_host_changes/part-000.jsonl.gz', 30059),
      ('cf247-usage-audit-2026-10-15/38729659914/scholarship_reread_snapshots/part-000.jsonl.gz', 10945),
      ('cf247-usage-audit-2026-10-15/38729659914/manifest.json', null)) x(name, bytes)
   where not exists (select 1 from storage.objects o where o.bucket_id = 'archive' and o.name = x.name
                       and (x.bytes is null or (o.metadata->>'size')::bigint = x.bytes));
  if v_refs is not null then raise exception 'export not found in Storage (or a different size): %; nothing removed', v_refs; end if;

  -- 2 every row set is exactly what was exported
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select h.* from pipeline.layer3_fact_handoffs h) z) y;
  if v_n <> 53805 or v_h <> '40e8121fb73b0fa58ece37966051e2f8' then raise exception 'layer3_fact_handoffs: % rows now, 53805 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select w.* from pipeline.layer3_work_items w where w.task_class <> 'provider_current_tuition_validation' and w.status in ('admitted', 'no_candidate', 'superseded') and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id)) z) y;
  if v_n <> 47454 or v_h <> '2d4919796238c34f7dff3ddf5e875174' then raise exception 'layer3_work_items_purged: % rows now, 47454 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select i.* from pipeline.layer3_interpretations i where not exists (select 1 from pipeline.layer3_work_items w where w.interpretation_id = i.id and not (w.task_class <> 'provider_current_tuition_validation' and w.status in ('admitted', 'no_candidate', 'superseded') and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id))) and not exists (select 1 from pipeline.layer4_review_items r where r.layer3_interpretation_id = i.id) and not exists (select 1 from pipeline.scholarship_ai_run_items s where s.interpretation_id = i.id)) z) y;
  if v_n <> 64395 or v_h <> 'eb0ecd97d0e3a89d2e0445f679603ac9' then raise exception 'layer3_interpretations_purged: % rows now, 64395 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.layer2_scope_wave_items t) z) y;
  if v_n <> 0 or v_h <> 'd41d8cd98f00b204e9800998ecf8427e' then raise exception 'layer2_scope_wave_items: % rows now, 0 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.layer2_provider_benchmark_observations t) z) y;
  if v_n <> 40 or v_h <> '47ea65d03602a7435c519a3f66df7e5b' then raise exception 'layer2_provider_benchmark_observations: % rows now, 40 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.pilot_edge_execution_queue t) z) y;
  if v_n <> 113 or v_h <> 'cbdb8ca3ce8eec0a92467bc8d49939d9' then raise exception 'pilot_edge_execution_queue: % rows now, 113 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from search.intent_aliases t) z) y;
  if v_n <> 22 or v_h <> '3aa717625de6f1a69df6250729530b84' then raise exception 'intent_aliases: % rows now, 22 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.evidence_links t) z) y;
  if v_n <> 0 or v_h <> 'd41d8cd98f00b204e9800998ecf8427e' then raise exception 'evidence_links: % rows now, 0 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.domain)::text k from (select t.* from pipeline.layer2_domain_refresh_policies t) z) y;
  if v_n <> 4 or v_h <> '8148731758d342a42a4d596b2b0a7a51' then raise exception 'layer2_domain_refresh_policies: % rows now, 4 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.layer3_work_item_rebinds t) z) y;
  if v_n <> 5 or v_h <> 'afe805e5a3c3ec7fa05645a6a2a6e607' then raise exception 'layer3_work_item_rebinds: % rows now, 5 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.provider_id)::text k from (select t.* from pipeline.zz_qualify_scratch_v1 t) z) y;
  if v_n <> 218 or v_h <> '616cec1ab481e0e7c9820bf2694afd88' then raise exception 'zz_qualify_scratch_v1: % rows now, 218 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select md5(to_jsonb(z)::text) k from (select t.* from pipeline.reading_restores_20261005 t) z) y;
  if v_n <> 193 or v_h <> '3f9f55863dbb201921321351fd301994' then raise exception 'reading_restores_20261005: % rows now, 193 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from public._layer1_depth_uat_control t) z) y;
  if v_n <> 1 or v_h <> 'b326b5062b2f0e69046810717534cb09' then raise exception '_layer1_depth_uat_control: % rows now, 1 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.layer2_fanout_tasks t) z) y;
  if v_n <> 157 or v_h <> 'a625a309a27d51b36d09879883d2dcdf' then raise exception 'layer2_fanout_tasks: % rows now, 157 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.provider_id)::text k from (select t.* from pipeline.night_run_queue t) z) y;
  if v_n <> 1769 or v_h <> '44b6a0b84062bdd52201c1908c6a09a3' then raise exception 'night_run_queue: % rows now, 1769 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.provider_id)::text k from (select t.* from pipeline.night_run_rebatch t) z) y;
  if v_n <> 582 or v_h <> 'e3abfbd2199fb68cd6147a0ad539a32c' then raise exception 'night_run_rebatch: % rows now, 582 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select (z.id)::text k from (select t.* from pipeline.refused_host_changes t) z) y;
  if v_n <> 835 or v_h <> 'd646b25faf123515a6b2c9dfdeff5a6b' then raise exception 'refused_host_changes: % rows now, 835 exported (or different rows); nothing removed', v_n; end if;
  select count(*), md5(coalesce(string_agg(k, ',' order by k collate "C"), '')) into v_n, v_h from (select md5(to_jsonb(z)::text) k from (select t.* from pipeline.scholarship_reread_snapshots t) z) y;
  if v_n <> 373 or v_h <> '6a16e625234330c79d5a2d41d2526074' then raise exception 'scholarship_reread_snapshots: % rows now, 373 exported (or different rows); nothing removed', v_n; end if;

  -- 3 nothing names the 15 tables any more
  foreach t in array array['pipeline.layer2_scope_wave_items', 'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links', 'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control', 'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots'] loop
    select string_agg(n.nspname || '.' || p.proname, ', ') into v_refs
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname not in ('pg_catalog', 'information_schema') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* ('\m' || split_part(t, '.', 2) || '\M');  -- comments do not count
    if v_refs is not null then raise exception '% is still named by %; nothing removed', t, v_refs; end if;
    select string_agg(c.oid::regclass::text, ', ') into v_refs from pg_class c
     where c.relkind in ('v', 'm') and pg_get_viewdef(c.oid) ~* ('\m' || split_part(t, '.', 2) || '\M');
    if v_refs is not null then raise exception '% is used by view %; nothing removed', t, v_refs; end if;
    select string_agg(conrelid::regclass::text, ', ') into v_refs from pg_constraint
     where contype = 'f' and confrelid = t::regclass and conrelid::regclass::text <> all (array['pipeline.layer2_scope_wave_items', 'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links', 'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control', 'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots']);
    if v_refs is not null then raise exception '% is referenced by %; nothing removed', t, v_refs; end if;
    if exists (select 1 from cron.job where command ~* ('\m' || split_part(t, '.', 2) || '\M')) then raise exception 'a scheduled job names %; nothing removed', t; end if;
  end loop;

  -- 4 drop the 15 tables (the work item rebinds first: they cascade from work items)
  foreach t in array array['pipeline.layer2_scope_wave_items', 'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links', 'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control', 'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots'] loop
    execute format('drop table %s', t);
  end loop;

  -- 5 purge the Layer 3 rows nothing live uses
  select count(*) into v_wi_before from pipeline.layer3_work_items;
  select count(*) into v_li_before from pipeline.layer3_interpretations;
  select jsonb_object_agg(status, n) into v_tuition_before from (select status, count(*) n from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' group by 1) z;
  delete from pipeline.layer3_fact_handoffs;
  get diagnostics v_fh = row_count;
  delete from pipeline.layer3_work_items w where w.task_class <> 'provider_current_tuition_validation' and w.status in ('admitted', 'no_candidate', 'superseded')
     and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id);
  get diagnostics v_wi = row_count;
  delete from pipeline.layer3_interpretations i
   where not exists (select 1 from pipeline.layer3_work_items w where w.interpretation_id = i.id)
     and not exists (select 1 from pipeline.layer4_review_items r where r.layer3_interpretation_id = i.id)
     and not exists (select 1 from pipeline.scholarship_ai_run_items s where s.interpretation_id = i.id);
  get diagnostics v_li = row_count;

  -- 6 check the result
  if v_fh <> 53805 or v_wi <> 47454 or v_li <> 64395 then
    raise exception 'removed % handoffs, % work items, % interpretations; expected 53805, 47454, 64395; nothing removed', v_fh, v_wi, v_li;
  end if;
  if (select count(*) from pipeline.layer3_work_items) <> v_wi_before - 47454 or (select count(*) from pipeline.layer3_interpretations) <> v_li_before - 64395 then
    raise exception 'row counts after the purge are not as expected; nothing removed';
  end if;
  if (select jsonb_object_agg(status, n) from (select status, count(*) n from pipeline.layer3_work_items where task_class = 'provider_current_tuition_validation' group by 1) z) <> v_tuition_before then
    raise exception 'tuition work items changed; nothing removed';
  end if;
  if exists (select 1 from pipeline.layer3_work_items w where w.interpretation_id is not null and not exists (select 1 from pipeline.layer3_interpretations i where i.id = w.interpretation_id)) then
    raise exception 'a kept work item lost its interpretation; nothing removed';
  end if;
  if (select count(*) from pipeline.layer3_validated_readings) <> 15852 then raise exception 'validated readings copy changed; nothing removed'; end if;

  update pipeline.component_register set status = 'retired', updated_at = now(),
         note = coalesce(note, '') || '; dropped 15 Oct 2026 by paste file (rows in Storage: archive/cf247-usage-audit-2026-10-15/38729659914)'
   where kind = 'table' and name in ('pipeline.layer2_scope_wave_items', 'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links', 'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control', 'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots');
  update pipeline.component_register set updated_at = now(),
         note = 'Usage audit 15 Oct 2026, D6 and D7: rows nothing live uses purged by paste file; exported first to Storage archive/cf247-usage-audit-2026-10-15/38729659914'
   where kind = 'table' and name in ('pipeline.layer3_interpretations', 'pipeline.layer3_work_items', 'pipeline.layer3_fact_handoffs');
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values
   ('retention', 'purge', 'Layer 3 retired tables and 15 unused tables',
    jsonb_build_object('decision', 'Platform Admin 15 Oct 2026 22:12: "Proceed with D6, D7, D9 and D10"', 'export', 'archive/cf247-usage-audit-2026-10-15/38729659914',
                       'fact_handoffs', v_fh, 'work_items', v_wi, 'interpretations', v_li, 'tables_dropped', array['pipeline.layer2_scope_wave_items', 'pipeline.layer2_provider_benchmark_observations', 'pipeline.pilot_edge_execution_queue', 'search.intent_aliases', 'pipeline.evidence_links', 'pipeline.layer2_domain_refresh_policies', 'pipeline.layer3_work_item_rebinds', 'pipeline.zz_qualify_scratch_v1', 'pipeline.reading_restores_20261005', 'public._layer1_depth_uat_control', 'pipeline.layer2_fanout_tasks', 'pipeline.night_run_queue', 'pipeline.night_run_rebatch', 'pipeline.refused_host_changes', 'pipeline.scholarship_reread_snapshots']), null);
  raise exception 'DRYRUN %', jsonb_build_object('handoffs', v_fh, 'work_items', v_wi, 'interpretations', v_li,
    'tables_left', (select count(*) from pg_class where oid::regclass::text in ('pipeline.layer2_scope_wave_items', 'pipeline.night_run_queue', 'search.intent_aliases')),
    'kept_work_items', (select count(*) from pipeline.layer3_work_items), 'kept_interpretations', (select count(*) from pipeline.layer3_interpretations),
    'english_plan_ok', (select count(*) from pipeline.provider_policy_proposals p cross join lateral security.provider_english_plan_v1(p.id) e where p.kind = 'english_policy' and p.status = 'approved' limit 1) >= 0,
    'retired', (select count(*) from pipeline.component_register where status = 'retired' and note like '%dropped 15 Oct 2026 by paste file%'));
end $purge$;
