-- CF-247 S1-UI-Parity (Platform Admin 20 Nov 2026 14:40 and 14:41, chat S1-RM-Design): the database side of the Dashboard and Layer 4 Review parity
-- with the approved s820-s827 mockup.
--   s836 Dashboard spend card. The stored ops pulse took the daily AI cap from the budgets check's openrouter_daily_ceiling_usd, which the check no
--        longer writes; it writes ai_daily_ceiling_usd (US$14.00 today). The card therefore said "cap not set". The pulse now takes
--        ai_daily_ceiling_usd first and the older key second (one fragment of security.ops_pulse_refresh_v1, md5-guarded).
--   s837 Layer 4 Review, "Waiting, grouped by rule" across the whole queue of a kind, not only the cards on the loaded page. Two new read-only actions
--        of public.admin_layer4_inbox (md5-guarded: one inserted branch, signature unchanged), answered by the new security.layer4_rule_groups_v1:
--        rule_groups  every waiting item of one built-in kind (optionally one university), grouped by the rule that holds it: course and university
--                     descriptions by their hold code (a refused word is its own group, "Contains a banned word"), AER items by the machine rule's
--                     hold code with S1-AER's plain label (security.layer4_aer_hold_reasons_v1), every other kind by the first sentence of its reason.
--                     Each group lists its oldest refs, up to layer4.rule_group_refs_max.
--        rule_group_items  the full cards of up to layer4.rule_batch_max of those refs, by key (the keyed read of security.layer4_inbox_items_v2),
--                     for the focused card and Preview the batch.
--        Nothing is decided here: every decision still goes through the Inbox's own decide action, one record at a time, with its reason.
--   s838 Platform Health rate meters. The stored pulse gains rates (security.ops_pulse_rates_v1): pages captured in the last
--        pulse.rate_window_hours against the normal rate of the pulse.baseline_days before it, and the auto-clean pass rate (machine admissions of
--        course and university descriptions and AER, admitted against all decided) in the same window against the same baseline. It is built in the
--        5-minute ops-pulse-refresh job, so the screens make no extra read.
-- Objects (no new public function, table or view): functions security.layer4_rule_groups_v1(text,jsonb,jsonb,int), security.ops_pulse_rates_v1();
-- two in-place edits: public.admin_layer4_inbox(text,jsonb) (md5-guarded, one inserted branch) and security.ops_pulse_refresh_v1() (md5-guarded, two
-- fragments); four settings. G1: no new job (the rates ride the existing ops-pulse-refresh job). G2: the windows and limits are settings.
-- G3: no consumer API object; security.consumer_api_check_v1() is read before and after (75 functions, 48 relations, no drift).
-- Spend: none (no AI, no Firecrawl). Manual locks: untouched.
-- Replaces: the client-side rule groups of the loaded page (src/Layer4RuleGroups.jsx, s826) as the Inbox's default rail; the pulse's old cap key.
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: remove the inserted branch and the two pulse fragments with the same helper; the two new functions are then unused.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'layer4.rule_group_refs_max', 'Layer 4 rule groups: items listed per group',
   'Waiting, grouped by rule lists the oldest items of each group up to this many, so a reviewer can work through a group card by card. The group''s count is always the full count.',
   'number', to_jsonb(500), 50, 5000, 'items', 890, 'Layer 4', 'security.layer4_rule_groups_v1 (rule_groups)', 'CF-247 s837 (Platform Admin 20 Nov 2026 14:40)'),
  ('pipeline', 'layer4.rule_batch_max', 'Layer 4 rule groups: records in one batch preview',
   'Preview the batch shows at most this many records, and a batch decision acts on exactly the records shown, one decision each.',
   'number', to_jsonb(50), 5, 200, 'records', 891, 'Layer 4', 'security.layer4_rule_groups_v1 (rule_group_items)', 'CF-247 s837 (Platform Admin 20 Nov 2026 14:40)'),
  ('pipeline', 'pulse.rate_window_hours', 'Ops pulse rates: window measured',
   'Platform Health compares what happened in this many recent hours (pages captured, auto-clean pass rate) with the normal rate before it.',
   'number', to_jsonb(24), 1, 168, 'hours', 982, 'Platform health', 'security.ops_pulse_rates_v1 (job ops-pulse-refresh)', 'CF-247 s838 (Platform Admin 20 Nov 2026 14:41)'),
  ('pipeline', 'pulse.baseline_days', 'Ops pulse rates: days that set the normal rate',
   'The normal rate is the average over this many days before the measured window.',
   'number', to_jsonb(7), 1, 60, 'days', 983, 'Platform health', 'security.ops_pulse_rates_v1 (job ops-pulse-refresh)', 'CF-247 s838 (Platform Admin 20 Nov 2026 14:41)')
on conflict do nothing;

-- s837: whole-queue rule groups and keyed cards (read only)
create or replace function security.layer4_rule_groups_v1(p_action text, p_args jsonb, p_kinds jsonb, p_target int)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_kind text := nullif(p_args->>'kind', ''); v_prov uuid := nullif(p_args->>'provider_id', '')::uuid;
        v_max int := security.pipeline_num_v1('layer4.rule_group_refs_max', 500)::int;
        v_batch int := security.pipeline_num_v1('layer4.rule_batch_max', 50)::int;
        v_refs text[]; v_aer jsonb := '[]'::jsonb; t0 timestamptz := clock_timestamp(); v_out jsonb;
begin
  if p_action not in ('rule_groups', 'rule_group_items') then raise exception 'INVALID_INPUT: unknown action' using errcode = '22023'; end if;
  if v_kind is null then raise exception 'INVALID_INPUT: choose a kind' using errcode = '22023'; end if;
  -- a registered (hook) kind has its own page reader: the screen shows its list as before
  if not (security.layer4_inbox_kinds_v1() ? v_kind) then
    return jsonb_build_object('kind', v_kind, 'built_in', false, 'total', null, 'groups', '[]'::jsonb, 'items', '[]'::jsonb);
  end if;

  if p_action = 'rule_group_items' then
    v_refs := array(select y.x from jsonb_array_elements_text(case when jsonb_typeof(p_args->'refs') = 'array' then p_args->'refs' else '[]'::jsonb end) with ordinality y(x, n)
                     order by y.n limit v_batch);
    return (with b as (select i.kind, i.ref, i.provider_id, coalesce(p.display_name, p.canonical_name) provider, i.subject, i.why, i.suggestion, i.created_at, i.detail
                         from security.layer4_inbox_items_v2(null, v_kind, array(select v_kind || ':' || r from unnest(v_refs) r), true) i
                         left join catalogue.providers p on p.id = i.provider_id
                        where coalesce(array_length(v_refs, 1), 0) > 0)
      select jsonb_build_object('kind', v_kind, 'built_in', true, 'asked', coalesce(array_length(v_refs, 1), 0), 'batch_max', v_batch,
               'items', coalesce(jsonb_agg(jsonb_build_object('kind', b.kind, 'ref', b.ref, 'provider_id', b.provider_id, 'provider', b.provider, 'subject', b.subject,
                          'why', b.why, 'suggestion', b.suggestion, 'created_at', b.created_at, 'late', b.created_at < now() - make_interval(days => p_target),
                          'detail', b.detail, 'o', (p_kinds->b.kind->>'order')::int) order by array_position(v_refs, b.ref)), '[]'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
        from b);
  end if;

  if v_kind = 'aer_review' then v_aer := coalesce(security.layer4_aer_hold_reasons_v1('{}'::jsonb)->'reasons', '[]'::jsonb); end if;
  with i as (
         select r.ref, r.created_at, r.why,
                case when v_kind = 'provider_description' then coalesce(r.detail->'machine'->>'reason_code', r.detail->'proposed'->>'held_rule', '') end code,
                regexp_replace(regexp_replace(btrim(coalesce(r.why, '')), '([.;])\s.*$', '\1'), '[.;:]+$', '') clause
           from security.layer4_inbox_items_v2(v_prov, v_kind, null, v_kind = 'provider_description') r),
       k as (
         select i.*,
                case when v_kind = 'provider_description' then 'cd:' || (case
                       when i.code = '' then 'first_provider_sample'
                       when i.code = 'policy_refused_word' then 'banned_word'
                       when i.code in ('identity_margin_thin', 'identity_not_allowed') then 'identity_margin_thin'
                       when i.code = 'binding_ambiguous' then 'binding_ambiguous'
                       when i.code = 'check_sentence_count' then 'sentence_count_over_2'
                       when i.code = 'check_length' then 'length'
                       when i.code like 'policy\_%' or i.code in ('check_unsupported_claim', 'check_unsupported_marketing') then 'boilerplate_detected'
                       when i.code in ('check_quote_not_on_page', 'check_unsupported_sentence', 'check_copied_sentence', 'source_recheck_failed') then 'quote_mismatch'
                       when i.code in ('evidence_moved', 'page_url_changed', 'reading_other_evidence') then 'evidence_moved'
                       when i.code = 'wrong_page_kind' then 'wrong_page_kind'
                       when i.code like 'duplicate\_%' or i.code = 'check_duplicate_other_course' then 'duplicate'
                       when i.code like 'rejected\_before%' or i.code = 'withdrawn_awaiting_person' then 'rejected_before'
                       else 'other' end)
                     when v_kind = 'aer_review' then 'aer:' || coalesce(substring(i.why from 'did not admit this: ([a-z_]+)'), 'other')
                     else v_kind || ':' || lower(i.clause) end gkey
           from i),
       g as (
         select k.gkey, count(*) n, min(k.created_at) oldest, count(*) filter (where k.created_at < now() - make_interval(days => p_target)) late,
                (array_agg(k.clause order by k.created_at, k.ref))[1] clause,
                (array_agg(k.ref order by k.created_at, k.ref))[1:v_max] refs
           from k group by k.gkey)
  select jsonb_build_object('kind', v_kind, 'built_in', true, 'provider_id', v_prov, 'total', coalesce(sum(g.n), 0), 'refs_max', v_max, 'batch_max', v_batch,
           'groups', coalesce(jsonb_agg(jsonb_build_object('key', g.gkey, 'n', g.n, 'oldest', g.oldest, 'late', g.late,
                       'label', case when v_kind = 'aer_review' then coalesce((select r->>'label' from jsonb_array_elements(v_aer) r where 'aer:' || (r->>'code') = g.gkey limit 1),
                                                   upper(substr(g.gkey, 5, 1)) || replace(substr(g.gkey, 6), '_', ' '))
                                     when v_kind = 'provider_description' then null else nullif(g.clause, '') end,
                       'refs', to_jsonb(g.refs)) order by g.n desc, g.gkey), '[]'::jsonb),
           'as_at', now(), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::int)
    into v_out from g;
  return v_out;
end $function$;
revoke all on function security.layer4_rule_groups_v1(text, jsonb, jsonb, int) from public, anon, authenticated;
comment on function security.layer4_rule_groups_v1(text, jsonb, jsonb, int) is 'CF-247 s837: Layer 4 Review, Waiting grouped by rule across the whole queue of one built-in kind (rule_groups) and the cards of up to layer4.rule_batch_max refs (rule_group_items). Read only; reached through public.admin_layer4_inbox (Curator or above).';

-- s838: capture and auto-clean rates against their normal rate, for the stored pulse
create or replace function security.ops_pulse_rates_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_h int := security.pipeline_num_v1('pulse.rate_window_hours', 24)::int; v_d int := security.pipeline_num_v1('pulse.baseline_days', 7)::int;
        v_w timestamptz; v_b timestamptz; v_c1 bigint; v_cb bigint; v_a1 bigint; v_t1 bigint; v_ab bigint; v_tb bigint;
        v_cap jsonb; v_ac jsonb; v_err jsonb := '{}'::jsonb; v_per numeric;
begin
  v_w := now() - make_interval(hours => v_h); v_b := v_w - make_interval(days => v_d); v_per := v_h::numeric / (v_d * 24);
  begin
    select count(*) filter (where created_at >= v_w), count(*) filter (where created_at < v_w) into v_c1, v_cb
      from pipeline.evidence_artifacts where created_at >= v_b;
    v_cap := jsonb_build_object('window', v_c1, 'normal', round(v_cb * v_per, 1),
                                'ratio', case when v_cb > 0 then round(v_c1 / (v_cb * v_per), 2) end);
  exception when others then v_cap := null; v_err := v_err || jsonb_build_object('capture', left(sqlerrm, 200)); end;
  begin
    with m as (select outcome, created_at from pipeline.course_description_machine_admissions where created_at >= v_b
               union all select outcome, created_at from pipeline.provider_description_machine_admissions where created_at >= v_b
               union all select outcome, created_at from pipeline.aer_machine_admissions where created_at >= v_b
               union all select outcome, created_at from pipeline.aer_matrix_machine_admissions where created_at >= v_b)
    select count(*) filter (where created_at >= v_w and outcome = 'admitted'), count(*) filter (where created_at >= v_w),
           count(*) filter (where created_at < v_w and outcome = 'admitted'), count(*) filter (where created_at < v_w)
      into v_a1, v_t1, v_ab, v_tb from m where outcome is not null;
    v_ac := jsonb_build_object('passed', v_a1, 'decided', v_t1, 'rate', case when v_t1 > 0 then round(v_a1 * 100.0 / v_t1, 1) end,
                               'normal_rate', case when v_tb > 0 then round(v_ab * 100.0 / v_tb, 1) end, 'normal_decided', v_tb);
  exception when others then v_ac := null; v_err := v_err || jsonb_build_object('autoclean', left(sqlerrm, 200)); end;
  return jsonb_build_object('window_hours', v_h, 'baseline_days', v_d, 'capture', v_cap, 'autoclean', v_ac, 'errors', v_err);
end $function$;
revoke all on function security.ops_pulse_rates_v1() from public, anon, authenticated;
comment on function security.ops_pulse_rates_v1() is 'CF-247 s838: pages captured and the auto-clean pass rate in the last pulse.rate_window_hours against the normal rate of the pulse.baseline_days before it. Built into the stored ops pulse by security.ops_pulse_refresh_v1; a part that fails is null and named in errors.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if p_md5 is not null and md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- s836 and s838: security.ops_pulse_refresh_v1 (md5 read live 20 Nov 2026 14:42, after s823): the cap key and the rates
select pg_temp.cf_edit_def('security.ops_pulse_refresh_v1()'::regprocedure, '8aa5a729fc1f07f06543a6ab057c1a72',
  array[$o$'cap_usd', h.detail->'openrouter_daily_ceiling_usd',$o$,
        $o$'stages', v_stages, 'checks', v_checks),$o$],
  array[$n$'cap_usd', coalesce(h.detail->'ai_daily_ceiling_usd', h.detail->'openrouter_daily_ceiling_usd'),$n$,
        $n$'stages', v_stages, 'checks', v_checks, 'rates', security.ops_pulse_rates_v1()),$n$]);

-- s837: public.admin_layer4_inbox (md5 read live 20 Nov 2026 14:42, after s819 #1416 and s831 #1418): the two read-only rule group actions
select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, 'f458ded21b5c91dbb92a5ac0c9e185b9',
  array[$o$    return security.s812_bulk_admin_v1(p_action, p_args);  -- s812
  end if;$o$],
  array[$n$    return security.s812_bulk_admin_v1(p_action, p_args);  -- s812
  end if;
  if p_action in ('rule_groups', 'rule_group_items') then
    return security.layer4_rule_groups_v1(p_action, p_args, v_kinds, v_target);  -- CF-247 s837: Waiting, grouped by rule (read only)
  end if;$n$]);

-- post-checks
do $c$
declare v_g jsonb; v_i jsonb; v_r jsonb; v_p jsonb; v_o text := ''; v_ref text; v_n int;
begin
  v_r := security.ops_pulse_rates_v1();
  if v_r->'capture' is null or v_r->'autoclean' is null then raise exception 'post-check: the rates did not build: %', v_r; end if;
  v_o := 'rates ' || v_r::text;
  v_g := security.layer4_rule_groups_v1('rule_groups', jsonb_build_object('kind', 'provider_description'), security.layer4_inbox_hooks_v1()->'kinds', 7);
  if (v_g->>'total')::int <> (select count(*) from security.layer4_inbox_items_v2(null, 'provider_description', null, false)) then
    raise exception 'post-check: description groups do not add up to the queue: %', v_g->>'total';
  end if;
  v_o := v_o || '; descriptions ' || (v_g->>'total') || ' in ' || jsonb_array_length(v_g->'groups') || ' groups (' || (v_g->>'ms') || ' ms): '
         || coalesce((select string_agg((x->>'key') || ' ' || (x->>'n'), ', ') from jsonb_array_elements(v_g->'groups') x), '');
  v_ref := v_g->'groups'->0->'refs'->>0;
  if v_ref is not null then
    v_i := security.layer4_rule_groups_v1('rule_group_items', jsonb_build_object('kind', 'provider_description', 'refs', jsonb_build_array(v_ref)), security.layer4_inbox_hooks_v1()->'kinds', 7);
    if jsonb_array_length(v_i->'items') <> 1 or v_i->'items'->0->>'ref' <> v_ref then raise exception 'post-check: the keyed card read did not return its ref: %', left(v_i::text, 300); end if;
    v_o := v_o || '; keyed card ' || (v_i->>'ms') || ' ms';
  end if;
  v_g := security.layer4_rule_groups_v1('rule_groups', jsonb_build_object('kind', 'aer_review'), security.layer4_inbox_hooks_v1()->'kinds', 7);
  v_o := v_o || '; AER ' || (v_g->>'total') || ' in ' || jsonb_array_length(v_g->'groups') || ' groups (' || (v_g->>'ms') || ' ms)';
  v_g := security.layer4_rule_groups_v1('rule_groups', jsonb_build_object('kind', 'course_page_needed'), security.layer4_inbox_hooks_v1()->'kinds', 7);
  v_o := v_o || '; course pages ' || (v_g->>'total') || ' in ' || jsonb_array_length(v_g->'groups') || ' groups (' || (v_g->>'ms') || ' ms)';
  -- the stored pulse, rebuilt in a block that is always undone: the cap and the rates are there
  begin
    perform security.ops_pulse_refresh_v1();
    select payload->'pulse' into v_p from pipeline.ops_pulse_snapshot;
    if (select detail ? 'ai_daily_ceiling_usd' from pipeline.platform_health_checks where key = 'budgets') and v_p->'budget'->'cap_usd' is null then
      raise exception 'post-check: the pulse still has no daily cap';
    end if;
    if v_p->'rates' is null then raise exception 'post-check: the pulse has no rates'; end if;
    raise exception 'cf-s836-undo %', coalesce(v_p->'budget'->>'cap_usd', '-');
  exception when others then
    if sqlerrm not like 'cf-s836-undo%' then raise; end if;
    v_o := v_o || '; pulse cap ' || substr(sqlerrm, 14) || ' (rolled back)';
  end;
  raise notice 'CF-247 s836-s838 post-checks: %', v_o;
end $c$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API changed: %', v;
  end if;
end $g$;
