-- CF-247 s1343 (S1-Build; SS-Programme-Control 28 Nov 2026 08:39 "Integrate qualified workload routing into the existing dispatcher, using the
-- smallest authorised change ... Begin processing eligible production workloads", 09:03 and 10:11 AEDT).
-- The Cloudflare reader (s1320, s1324) is deployed on Techm and qualified on stored entry PDFs (28 Nov 2026: Western Sydney 11 tables / 86 rows,
-- VU 6 / 153, Le Cordon Bleu 18 / 239; Newcastle, Sydney and UNSW correctly held; about US$0.02 a run). It runs the same pdf.ts and scope retry.
-- This change lets the existing entry reader (coverage-sweep v1.0.63, storedText) use it: the gate finds a stored copy by its storage path when no
-- evidence id is given, and a routing switch (cloudflare_reader.route_entry_pdf) decides whether the entry route may start a run. Every other
-- gate rule is unchanged: the kill switch, one free slot, the daily and monthly compute caps, a stored public layer2 source copy.
-- G1: no job. G2: the switch is a setting with a label, range, unit and used_by. G3: not the consumer API; 75/48 checked. Locks, Layer 4 and cron
-- checked. Nothing dropped or deleted.
-- Replaces: public.svc_cloudflare_reader_v1 (md5 c7c20af099c61eff6dd6843c6df4a42f; the gate's stored-copy lookup and the routing switch).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

create temp table s1343_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'cloudflare_reader.route_entry_pdf', 'Cloudflare burst reader: entry PDFs',
   'Whether the entry reader may send a stored entry PDF to the Cloudflare reader (inside the same switch, slot and compute caps). 0: entry PDFs are parsed in Supabase only.',
   'number', to_jsonb(1), 0, 1, 'switch', 1587, 'Services & limits', 'public.svc_cloudflare_reader_v1; coverage-sweep entry reader (storedText)', 'CF-247 s1343 (SS-Programme-Control 28 Nov 2026 08:39)')
on conflict do nothing;

do $e$
declare v jsonb := security.consumer_api_check_v1(); d text; d2 text; n int;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  d := pg_get_functiondef('public.svc_cloudflare_reader_v1(text,jsonb,text)'::regprocedure);
  if position('s1343' in d) > 0 then raise notice 's1343: already applied'; return; end if;
  if md5(d) <> 'c7c20af099c61eff6dd6843c6df4a42f' then raise exception 'guard: svc_cloudflare_reader_v1 differs from the definition this change edits (live md5 %)', md5(d); end if;
  n := (length(d) - length(replace(d, 'select * into e from pipeline.evidence_artifacts where id = (p_args->>''evidence_id'')::uuid;', ''))) / length('select * into e from pipeline.evidence_artifacts where id = (p_args->>''evidence_id'')::uuid;');
  if n <> 1 then raise exception 'guard: stored-copy lookup found % times', n; end if;
  n := (length(d) - length(replace(d, 'return jsonb_build_object(''ok'', false, ''held'', ''HELD:SWITCHED_OFF''); end if;', ''))) / length('return jsonb_build_object(''ok'', false, ''held'', ''HELD:SWITCHED_OFF''); end if;');
  if n <> 1 then raise exception 'guard: switch check found % times', n; end if;
  d2 := replace(d, 'select * into e from pipeline.evidence_artifacts where id = (p_args->>''evidence_id'')::uuid;',
    'if p_args ? ''evidence_id'' then select * into e from pipeline.evidence_artifacts where id = (p_args->>''evidence_id'')::uuid; else select * into e from pipeline.evidence_artifacts where storage_path = p_args->>''storage_path'' and evidence_type = ''source_snapshot'' order by created_at desc limit 1; end if; /* s1343: or by its storage path (entry reader route) */');
  d2 := replace(d2, 'return jsonb_build_object(''ok'', false, ''held'', ''HELD:SWITCHED_OFF''); end if;',
    'return jsonb_build_object(''ok'', false, ''held'', ''HELD:SWITCHED_OFF''); end if; if p_args->>''route'' = ''entry_matrix'' and security.pipeline_num_v1(''cloudflare_reader.route_entry_pdf'', 1) < 1 then return jsonb_build_object(''ok'', false, ''held'', ''HELD:ROUTE_OFF''); end if; /* s1343 */');
  execute d2;
end $e$;

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record; d text;
begin
  select * into g from s1343_guard;
  d := pg_get_functiondef('public.svc_cloudflare_reader_v1(text,jsonb,text)'::regprocedure);
  if position('HELD:ROUTE_OFF' in d) = 0 or position('storage_path = p_args->>''storage_path''' in d) = 0 then raise exception 'post-check: gate edit not in place'; end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'cloudflare\_reader.%') <> 8 then raise exception 'post-check: cloudflare_reader settings'; end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> g.decided_before then raise exception 'post-check: Layer 4 decisions changed'; end if;
end $e$;
