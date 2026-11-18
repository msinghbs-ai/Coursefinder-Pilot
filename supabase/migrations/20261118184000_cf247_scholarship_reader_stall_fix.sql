-- CF-247 Scholarship detail reader: the idle fill restarts (S2-Build; Platform Admin 18 Nov 2026 13:02 and 15:32: "use the existing reader to
-- write verified, verbatim-quoted award values and closing dates straight to the scholarship record (no-overwrite enforced) across the unread
-- scholarships - do not create a new Layer 4 review kind").
--
-- What was read live (18 Nov 2026 15:40 AEDT)
--   * 138 active scholarships with a stored official page have no good v3 reading; 122 of them were never queued. The last detail reading was
--     14 Nov 2026 03:17 UTC.
--   * security.scholarship_ai_fire_v1 fills existing records from their stored page (security.scholarship_detail_backfill_v1) only when nothing
--     else is due. Its due count includes leased items whose lease has run out at any attempt count, but the picker (svc_scholarship_ai_next)
--     takes only items under three attempts. Two items (one admit, one detail) have been leased at the third attempt since 14 Nov 2026, so
--     the due count has been 2 every minute, the picker found nothing and the fill never ran.
--
-- What it changes
--   * The due count uses the picker's own rule (attempts under three), so a dead lease no longer blocks the fill.
--   * The two dead items are settled as failed with the reason (an update; nothing is deleted).
--   * An on-demand window (security.on_demand_open_v1, via claude_session, toolset openrouter) is opened for the providers of the unread
--     scholarships, with its estimate, so the fill is not held by the scheduled toolset limits while it catches up.
-- Nothing else changes. The reader, the prompt (v3), the pinned model and the apply path stay as they are: security.scholarship_detail_apply_v1
-- fills only empty fields whose checks pass (the award value and closing date need their verbatim quote on the page), respects manual locks and
-- never overwrites. A reading whose quote is missing or whose answer is cut off stays in the existing held buckets (held_partial, recovery);
-- no new review kind. G3 untouched.
-- Replaces: the due count in security.scholarship_ai_fire_v1.
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. the due count follows the picker
select pg_temp.cf_edit('security.scholarship_ai_fire_v1()'::regprocedure, '127e679f0a07e2d97814e5d4e94a0b14',
  $o$where (q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now());$o$,
  $n$where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;  -- fixed: the picker's attempt cap (svc_scholarship_ai_next); 20261118184000: a dead lease no longer blocks the idle fill$n$,
  '20261118184000: a dead lease no longer blocks the idle fill');

-- 2. settle the dead leases (update only)
update pipeline.scholarship_ai_queue
   set state = 'failed', done_at = now(), leased_until = null,
       skip_reason = 'Lease ran out at the attempt cap; settled 18 Nov 2026 (20261118184000) because it kept the idle fill from running'
 where state = 'leased' and attempts >= 3 and leased_until < now();  -- fixed: the picker's attempt cap

-- 3. the on-demand window for the catch-up (estimate from the last 14 days of detail readings)
do $d$
declare v_prov uuid[]; v_n int; v_avg numeric; v_max numeric; v_res jsonb;
begin
  select array_agg(distinct s.provider_id), count(*) into v_prov, v_n
    from scholarship.scholarships s
   where s.lifecycle_status = 'active'
     and exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id)
     and not exists (select 1 from pipeline.scholarship_ai_extractions x where x.scholarship_id = s.id and x.prompt_version >= 3 and x.error is null)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id);
  if coalesce(cardinality(v_prov), 0) = 0 then raise notice 'nothing unread; no on-demand window opened'; return; end if;
  select avg(cost_usd), max(cost_usd) into v_avg, v_max from pipeline.scholarship_ai_extractions
   where run_kind = 'detail' and cost_usd is not null and at > now() - interval '14 days';  -- fixed: the estimate's look-back
  v_res := security.on_demand_open_v1('claude_session',
    'Scholarship detail fill catch-up after the reader stall (Platform Admin 18 Nov 2026 15:32): award values and closing dates from the stored official pages, existing reader, no overwrite',
    v_prov,
    jsonb_build_object('scholarships', v_n, 'providers', cardinality(v_prov), 'model', 'qwen3-30b', 'prompt_version', 3,
                       'usd_per_reading_avg', round(coalesce(v_avg, 0), 5), 'usd_estimate', round(coalesce(v_avg, 0) * v_n * 2, 2),  -- fixed: long pages are read in two parts
                       'usd_ceiling', round(coalesce(v_max, 0) * v_n * 2, 2), 'firecrawl_credits', 0),  -- fixed: long pages are read in two parts
    null, '{openrouter}');
  raise notice 'on-demand window: %', v_res;
end $d$;

-- 4. post-checks
do $$
declare v_src text := (select prosrc from pg_proc where oid = 'security.scholarship_ai_fire_v1()'::regprocedure);
begin
  if position('and q.attempts < 3;' in v_src) = 0 then raise exception 'post-check: the due count must follow the picker'; end if;
  if exists (select 1 from pipeline.scholarship_ai_queue where state = 'leased' and attempts >= 3 and leased_until < now()) then raise exception 'post-check: dead leases remain'; end if; -- fixed: the picker's attempt cap
  if (select count(*) from cron.job where jobname = 'scholarship-ai-extract' and active) <> 1 then raise exception 'post-check: the reader job must stay active'; end if;
  if security.pipeline_num_v1('sch_detail.on', 1) < 1 then raise exception 'post-check: the detail fill is switched off'; end if;
end $$;
