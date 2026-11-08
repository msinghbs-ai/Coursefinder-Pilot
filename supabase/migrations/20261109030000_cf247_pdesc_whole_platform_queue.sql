-- CF-247 F-PDESC (Platform Admin decision 9 Nov 2026, "All-Provider Autonomous Description Delivery": partitioned AU/NZ/CA queues, fair rotation, throughput sized from the remaining providers and the
-- observed rate, bounded concurrency, and the machine admission route inside the reader). Follows 20261109020000 (the machine admission functions, settings and tables).
--
-- With pdesc.machine_admit_on = 0 (the default, and what this migration leaves) every edited function behaves exactly as before: each edit is behind that setting. With it at 1:
--   security.provider_description_selection_v1   the size limit is pdesc.queue_cap (60) instead of min(queue_per_run, pending_max, run_now.pilot_cap) = 10; with the new argument prefilter it looks at a bounded slice
--                                                (pdesc.scan_factor x the size, at most pdesc.scan_max) of the providers that can still be read, least recently looked at first, and works out the stored page and identity
--                                                for those only (QA B2: the whole catalogue was evaluated, 10 to 12 seconds on live and 130 ms more for each stored page)
--   security.provider_description_enqueue_v1     queues each country in pdesc.countries separately (selection called per country), sized by security.provider_description_throughput_v1:
--                                                remaining providers / runs in pdesc.target_hours, limited by what the observed rate can drain (pdesc.backlog_hours); a share per country;
--                                                it remembers which providers it looked at (pipeline.provider_description_scan_marks) so none is looked at twice before the rest
--   public.svc_provider_description_next         work in progress is bounded by pdesc.concurrency_max and by the AI spend still available (pdesc.read_cost_floor_usd), not by the Layer 4
--                                                waiting cap; the country read least recently is leased first (fair rotation, one count for the whole queue); a provider the rule must not describe
--                                                (locked, earlier rejection, withdrawn, cleared by hand, open finding, unusable name) is held before any AI call; only a provider with no description is read;
--                                                the Firecrawl reads other calls hold in flight are taken off what a call may start (pdesc.firecrawl_per_call), so parallel calls cannot pass pdesc.firecrawl_reads_max
--   public.svc_provider_description_record       a proposal the text rule refuses waits for a person in Layer 4 while fewer than pdesc.machine_pending_max such items wait (the old waiting cap, pdesc.pending_max, no longer
--                                                stops the reader); any other refusal, or no room, is HELD with the whole proposal and the exact reason (never dropped); one that passes is created as a
--                                                Layer 4 item and admitted by security.provider_description_machine_admit_v1 under the system automation account (never the human decision path)
--   security.provider_description_fire_v1        runs the machine step (settle waiting items, tier 4) each run, does not stop for the Layer 4 waiting cap, and sends up to pdesc.dispatch_max
--                                                worker calls (sized from the due reads) instead of one; the hourly floor (pdesc.every_minutes), AI ceiling, Firecrawl ceiling and fire guards are unchanged
-- The AI ceiling (pdesc.ai_usd_max), the Firecrawl ceiling (pdesc.firecrawl_reads_max) and the waiting cap (pdesc.pending_max) are NOT changed. No schedule, job or setting value changes.
--
-- Live definitions this change edits (read 9 Nov 2026, project fxcwkweaxjtknorudmwp), md5 of the function body (pg_proc.prosrc) before -> after. The body md5 is the same on PostgreSQL 16 (the test database)
-- and 17 (live); the live bodies were compared to the test database's. The selection function's "before" is its body after 20261109010000 (live today it is still the body from before that migration):
--   security.provider_description_selection_v1(jsonb) 1fa6c1c9fa9200eb644fcabf8c85dcf0 -> c8dd7882a5a6c5b174a829972d475d40
--   security.provider_description_enqueue_v1() c25746895368b9320a1e5fc4222b14d1 -> 803478538da3dd9594ba08be38284c3e
--   public.svc_provider_description_next(integer) 3d6eb1eb35b80f54c72eb160c63aac82 -> cb83dc4e3502d6cc16450c2126368ec9
--   public.svc_provider_description_record(jsonb) 1b7fec4fb287277e31fa4fbcc2a101ef -> 3114f845b25fc31ed97eaab0f56ee297
--   security.provider_description_fire_v1() 92e445408c50883e301088b9ba0d8b9c -> fc835699c88759e4a0b12c6d95e47965
-- Replaces: the single-batch, Layer 4 capacity-bound queue and dispatch of the provider-description reader when automatic admission is on (edited in place behind pdesc.machine_admit_on; the functions are not replaced)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_selection_v1(jsonb)'), ('security.provider_description_enqueue_v1()'), ('public.svc_provider_description_next(integer)'),
                                 ('public.svc_provider_description_record(jsonb)'), ('security.provider_description_fire_v1()'), ('security.provider_description_machine_admit_v1(uuid)'),
                                 ('security.provider_description_machine_gate_v1(uuid,text,jsonb)'), ('security.provider_description_machine_step_v1()'), ('security.provider_description_throughput_v1()'),
                                 ('security.provider_description_machine_blocked_v1(uuid)'), ('security.provider_description_stored_candidate_v1(uuid,text[])')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261109020000 first)', r.sig; end if;
  end loop;
  if to_regclass('pipeline.provider_description_scan_marks') is null then raise exception 'required pipeline.provider_description_scan_marks is missing (apply 20261109020000 first)'; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17; the header lines pg_get_functiondef prints can differ between versions
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then
    raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ------------------------------------------------------------------------------------------------------------------ selection: the size limit in automatic mode, and the bounded slice
select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', '1fa6c1c9fa9200eb644fcabf8c85dcf0', 'c8dd7882a5a6c5b174a829972d475d40',
array[
$old$ v_max int := least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int;
$old$,
$old$ v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb;
$old$,
$old$ with candidates as materialized (
$old$,
$old$  and security.provider_description_scope_v1(p.id)
 ), rows as (
$old$,
$old$  when p.lifecycle_status<>'active' then 'provider_inactive'
$old$,
$old$'[]'::jsonb) into v_rows
 from (select * from shaped order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm limit v_size) b;
$old$,
$old$'bounded',true,'size',v_size,'as_at',now(),
$old$],
array[
$new$ v_max int := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then security.pipeline_num_v1('pdesc.queue_cap',60)::int else least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int end;
$new$,
$new$ v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb; v_scanned jsonb; v_pat text[]:=security.pdesc_about_like_patterns_v1();
 -- QA B2: with prefilter (automatic mode only; the default there for the missing-description list of every caller, and always for the reader) the stored page and identity are worked out for a bounded slice of the providers that can still be read, not for the whole catalogue
 v_pre boolean := security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'prefilter')::boolean,v_filter='missing' and v_provider is null);
 v_slice int := least(security.pipeline_num_v1('pdesc.scan_max',150)::int, greatest(coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int),1)*security.pipeline_num_v1('pdesc.scan_factor',3)::int);
$new$,
$new$ with pre as materialized (
  select q.id from (select p.id,coalesce(m.scanned_at,'-infinity'::timestamptz) sc,(select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') ac,coalesce(p.display_name,p.canonical_name) nm
   from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id left join pipeline.provider_description_scan_marks m on m.provider_id=p.id
   where v_pre and (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
    and security.provider_description_scope_v1(p.id) and nullif(btrim(p.description),'') is null and p.publication_status='published'
    and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))
    and (v_mode<>'stored' or security.provider_description_stored_candidate_v1(p.id,v_pat))
   order by sc,ac desc,nm limit v_slice) q
 ), candidates as materialized (
$new$,
$new$  and security.provider_description_scope_v1(p.id)
  and (not v_pre or p.id in (select pre.id from pre))
 ), rows as (
$new$,
$new$  when v_pre and security.provider_description_machine_blocked_v1(p.id) is not null then 'machine_'||(security.provider_description_machine_blocked_v1(p.id)->>'rule')
  when p.lifecycle_status<>'active' then 'provider_inactive'
$new$,
$new$'[]'::jsonb),(select coalesce(jsonb_agg(z.row->>'provider_id'),'[]'::jsonb) from shaped z where z.eligibility_reason not in ('eligible','invalid_description','description_lost')) into v_rows,v_scanned
 from (select * from shaped order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm limit v_size) b;
$new$,
$new$'bounded',true,'size',v_size,'scanned',case when v_pre then v_scanned end,'as_at',now(),
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ enqueue: one partition a country in automatic mode, a bounded slice each
select pg_temp.edit_all('security.provider_description_enqueue_v1()', 'c25746895368b9320a1e5fc4222b14d1', '803478538da3dd9594ba08be38284c3e',
array[
$old$ declare v_n int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 insert into pipeline.provider_description_reads(provider_id)
$old$,
$old$ get diagnostics v_n=row_count; return v_n;
end $function$
$old$],
array[
$new$ declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
  -- automatic mode: each country is its own bounded queue, sized from the providers still to do and the observed rate; each looks at a bounded slice (QA B2)
  v_n:=0; v_t:=security.provider_description_throughput_v1();
  for v_cc,v_share in select e.key,e.value::int from jsonb_each_text(coalesce(v_t->'share','{}'::jsonb)) e order by e.key loop
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',v_share,'country',v_cc,'prefilter',true,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end));
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(v_sel->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
   -- the providers looked at that cannot be read yet, and those returned, go to the back of the rotation
   insert into pipeline.provider_description_scan_marks(provider_id,scanned_at,last_reason)
   select u.pid::uuid,now(),'looked at' from (select jsonb_array_elements_text(coalesce(v_sel->'scanned','[]'::jsonb)) pid union select y->>'provider_id' from jsonb_array_elements(coalesce(v_sel->'providers','[]'::jsonb)) y) u
   on conflict (provider_id) do update set scanned_at=excluded.scanned_at,last_reason=excluded.last_reason;
  end loop;
  return v_n;
 end if;
 insert into pipeline.provider_description_reads(provider_id)
$new$,
$new$ get diagnostics v_n=row_count; return v_n;
end $function$
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ lease: work in progress bounded by concurrency and spend, fair rotation, first description only
select pg_temp.edit_all('public.svc_provider_description_next(integer)', '3d6eb1eb35b80f54c72eb160c63aac82', 'cb83dc4e3502d6cc16450c2126368ec9',
array[
$old$declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int;
$old$,
$old$  select (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')
$old$,
$old$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
$old$,
$old$  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
$old$,
$old$  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
$old$,
$old$  with pick as (select r.id from pipeline.provider_description_reads r
$old$,
$old$                     or exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified')))
$old$,
$old$                 order by r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(security.pipeline_num_v1('pdesc.pending_max', 10) - v_pending)::int))
$old$,
$old$'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id)),
$old$,
$old$    'firecrawl_left', greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used),
$old$],
array[
$new$declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric; v_fc_res int; v_fc_left int;
$new$,
$new$  v_cap := case when v_mach then security.pipeline_num_v1('pdesc.concurrency_max', 12) else security.pipeline_num_v1('pdesc.pending_max', 10) end;
  select (case when v_mach then 0 else (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending') end)
$new$,
$new$  if v_pending >= v_cap then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
$new$,
$new$  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  if v_mach then
    -- automatic mode: no more reads in progress than the AI spend still available covers, at the dearer of the set cost and the observed cost of a read
    v_afford := floor((security.pipeline_num_v1('pdesc.ai_usd_max', 1) - v_spent - coalesce((select sum(x.reserved_usd) from pipeline.provider_description_reads x where x.state = 'reading'), 0))
                      / greatest(security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003), coalesce((select sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0) from pipeline.provider_description_reads x), 0)))
                - (select count(*) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now());
    if v_afford < 1 then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  end if;
  -- QA N4: Firecrawl reads held by worker calls still in flight are not available again; with automatic admission on, this call is granted at most pdesc.firecrawl_per_call of what the ceiling still allows after them
  v_fc_res := coalesce((select sum(coalesce((x.checks->>'firecrawl_reserved')::int, 0)) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now()), 0);
  v_fc_left := case when v_mach then least(greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used - v_fc_res), security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int)
                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;
$new$,
$new$  if v_mach then
    -- QA N6/N7/N11: a provider the automatic rule must not describe now (locked, earlier rejection, withdrawn, cleared by hand, open finding, unusable name, already described) is held here, before any AI call
    update pipeline.provider_description_reads r set state='held',rule='machine_declined_'||(b.blk->>'rule'),reason=left(b.blk->>'reason',400),leased_until=null,updated_at=now() -- fixed: the stored reason shows its first 400 characters
      from (select x.id,security.provider_description_machine_blocked_v1(x.provider_id) blk from pipeline.provider_description_reads x where (x.state='queued' and x.next_try_at<=now()) or (x.state='reading' and x.leased_until<now())) b
     where r.id=b.id and b.blk is not null;
  end if;
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
$new$,
$new$  with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id),
  pick as (select r.id from pipeline.provider_description_reads r
$new$,
$new$                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
$new$,
$new$                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))
$new$,
$new$'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id),'firecrawl_reserved',case when v_mach and r.id=(select pk.id from pick pk order by pk.id limit 1) then v_fc_left else 0 end),
$new$,
$new$    'firecrawl_left', v_fc_left,
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ record: the machine rule decides a proposal when automatic admission is on
select pg_temp.edit_all('public.svc_provider_description_record(jsonb)', '1b7fec4fb287277e31fa4fbcc2a101ef', '3114f845b25fc31ed97eaab0f56ee297',
array[
$old$v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text;
$old$,
$old$    if v_chk->>'outcome'='propose' and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
$old$,
$old$      v_out := 'proposed';
    elsif v_chk->>'outcome' = 'verified' then
$old$],
array[
$new$v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text; v_m jsonb;
$new$,
$new$    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
      -- machine rule pdesc-machine-v1. A description the TEXT rule refuses waits for a person in Layer 4 while there is room (pdesc.machine_pending_max); any other refusal (a lock, an earlier
      -- rejection, a withdrawal, an open finding ...) or no room: HELD with the whole proposal and the exact reason. Nothing is dropped.
      v_m:=security.provider_description_machine_gate_v1(r.provider_id,v_chk->>'text',jsonb_build_object('tier',r.read_via));
      if not (v_m->>'ok')::boolean and (v_m->>'rule' not like 'machine_text%' or (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.machine_pending_max',200)) then
        update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='machine_declined_'||(v_m->>'rule'),
          reason=left(v_m->>'reason'||case when v_m->>'rule' like 'machine_text%' then ' Held with the full proposal: the places for a person to decide in Layer 4 are taken (pdesc.machine_pending_max).' else '' end,400),last_verified_at=now(),updated_at=now() where id=r.id; -- fixed: the stored reason shows its first 400 characters
        v_tally:=v_tally||jsonb_build_object('machine_declined',coalesce((v_tally->>'machine_declined')::int,0)+1); continue;
      end if;
    end if;
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
$new$,
$new$      v_out := 'proposed';
      if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
        -- admitted here under the machine rule, or left waiting for a person with the reason on the item; a failure never undoes the proposal
        begin
          v_m:=security.provider_description_machine_admit_v1(v_item);
          if (v_m->>'ok')::boolean then v_out:='admitted'; end if;
        exception when others then null;
        end;
      end if;
    elsif v_chk->>'outcome' = 'verified' then
$new$]);

-- ------------------------------------------------------------------------------------------------------------------ fire: machine step, no Layer 4 stop, several worker calls
select pg_temp.edit_all('security.provider_description_fire_v1()', '92e445408c50883e301088b9ba0d8b9c', 'fc835699c88759e4a0b12c6d95e47965',
array[
$old$declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int;
$old$,
$old$  v_q := security.provider_description_enqueue_v1();
  else v_q:=0; v_resumed:=0; end if;
$old$,
$old$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
$old$,
$old$    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 1, 'dead_letter', v_dead);
$old$],
array[
$new$declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int; v_sent int; v_i int;
$new$,
$new$  v_q := security.provider_description_enqueue_v1();
  if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then perform security.provider_description_machine_step_v1(); end if;
  else v_q:=0; v_resumed:=0; end if;
$new$,
$new$  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
$new$,
$new$    -- automatic mode: as many worker calls as the due reads need, up to pdesc.dispatch_max (each lease is bounded by the concurrency and spend limits); otherwise one call, as before
    v_sent := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and v_cohort is null then least(security.pipeline_num_v1('pdesc.dispatch_max',3)::int, greatest(1, ceil(v_due::numeric / greatest(1, security.pipeline_num_v1('batch.provider_description', 3)))::int)) else 1 end;
    for v_i in 1 .. v_sent loop
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    end loop;
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', v_sent, 'dead_letter', v_dead);
$new$]);
