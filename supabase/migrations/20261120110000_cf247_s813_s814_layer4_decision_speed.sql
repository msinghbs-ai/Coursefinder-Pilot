-- CF-247 s813/s814 (Platform Admin 20 Nov 2026 09:55 AEDT, chat S1-Build): Layer 4 decisions timed out (Held scholarship › Not for international
-- students on UTS Jumbunna Postgraduate Research Scholarship). Every decision of every kind was timed live in a rolled-back run on 20 Nov 2026
-- 10:05 AEDT (as the Platform Admin, one item per kind, each choice); the slow ones and their cause, by function time:
--   Held scholarship (Publish, Not for international students, Not a scholarship): 1.8 to 5.8 s. The decision itself
--     (security.scholarship_ai_review_apply_v1) takes about 35 ms; public.admin_scholarship_ai('review_decide') then rebuilds the whole
--     AI screen (scores, sample answers, queue, costs, recent runs) and the Inbox stored that reply in its audit row. The Inbox now applies
--     the decision and writes the same audit row itself, without the screen.
--   Adapter has nothing ready › Rebuild (2.5 s) and Course pages not found › Release (0.7 s): security.layer4_decide_guard_v1 read every
--     Layer 4 decision (21,526) for "already tried at this university". A partial index answers it from the index.
--   Course link (fee check) › Use (0.8 s): security.layer4_decision_outcome_v1 found the fee by a LIKE on every fee's notes (185,209 rows).
--     It now compares the fixed-length head of the note against an index (same rows: the note head is the review item's id).
--   University and Course description › Approve (0.6 s): security.course_description_promote_held_v1 scanned the reading items; a partial
--     index on the held first readings serves it.
-- Parity before writing (read live 20 Nov 2026 10:02 AEDT): head 20261120103000, 2,206 rows, 58 = 58 files on main; no open pull request.
-- G3: no consumer object changes (indexes only on catalogue.course_fees; no column, type or function of the consumer API). No spend.
-- Replaces: the dashboard rebuild inside Held scholarship decisions; the full scans in the decision guard, the fee outcome read and the held description promotion.
-- Retires: nothing.

create index if not exists admin_control_events_l4_guard_idx on pipeline.admin_control_events ((detail->>'provider_id'), (detail->>'kind'), (detail->>'choice'), id desc)
  where area = 'layer4' and action = 'inbox_decide';
create index if not exists field_enrich_items_desc_held_idx on pipeline.field_enrich_items (provider_id, id) where field = 'description' and state = 'skipped';
create index if not exists course_fees_layer4_decision_note_idx on catalogue.course_fees (substr(notes, 1, 80))  -- fixed: 80 = the note head "…review item <uuid>;"
  where notes like 'CF-247 Layer 4 human decision;%' and status = 'active';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[], p_counts int[] default null)
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> coalesce(p_counts[i], 1) then raise exception 'pre-check: %: fragment % must occur % time(s) (found %)', p_sig, i, coalesce(p_counts[i], 1), v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- Held scholarship: the decision and its audit row, as public.admin_scholarship_ai('review_decide') wrote them, without rebuilding that screen
select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, 'c179c26dca4107946ab57e5191143c51',
  array[$o$  elsif v_kind = 'held_scholarship' then
    v_r := public.admin_scholarship_ai('review_decide', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                         'extraction_id', v_det->'extraction_id', 'reason', v_reason));$o$],
  array[$n$  elsif v_kind = 'held_scholarship' then
    -- s813 (20 Nov 2026): the decision itself and the AI screen's audit row; admin_scholarship_ai('review_decide') also rebuilt that screen (2 to 5 s)
    v_r := jsonb_build_object('applied', security.scholarship_ai_review_apply_v1(v_ref::bigint, case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                                 nullif(v_det->>'extraction_id', '')::bigint, nullif(v_reason, ''), auth.uid()));
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarship_ai', 'review_decide', '', jsonb_build_object('review_id', v_ref::bigint, 'decision', case when v_choice = 'publish' then 'admit' else 'refuse' end,
                                                                     'extraction_id', v_det->'extraction_id', 'reason', v_reason, 'via', 'layer4_inbox'), auth.uid());$n$]);

select pg_temp.cf_edit_def('security.layer4_decision_outcome_v1(text,text,jsonb)'::regprocedure, 'c40ee758b2d5888deeb5a101fd036cb6',
  array[$o$       where f.notes like 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';%' and f.status = 'active'$o$],
  array[$n$       where f.notes like 'CF-247 Layer 4 human decision;%' and f.status = 'active'  -- s814: the note head (indexed) names the review item
         and substr(f.notes, 1, 80) = 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';'$n$]);


-- every decision reads its item twice through security.layer4_inbox_items_v2 (the detail, then whether it still waits): about 110 ms. The item's
-- own id is now also matched as its type, so each source finds it by its key instead of reading every waiting row (the text match stays).
create or replace function security.l4_key_uuids_v1(p_keys text[]) returns uuid[] language sql immutable parallel safe set search_path to '' as $f$
  select coalesce(array_agg(split_part(k, ':', 2)::uuid), '{}') from unnest(p_keys) k
   where split_part(k, ':', 2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$f$;
create or replace function security.l4_key_bigints_v1(p_keys text[]) returns bigint[] language sql immutable parallel safe set search_path to '' as $f$
  select coalesce(array_agg(split_part(k, ':', 2)::bigint), '{}') from unnest(p_keys) k where split_part(k, ':', 2) ~ '^[0-9]{1,18}$'
$f$;
revoke all on function security.l4_key_uuids_v1(text[]) from public, anon, authenticated;
revoke all on function security.l4_key_bigints_v1(text[]) from public, anon, authenticated;
comment on function security.l4_key_uuids_v1(text[]) is 'CF-247 s814: the uuid refs of Layer 4 item keys (kind:ref), so an item source can find its rows by id.';
comment on function security.l4_key_bigints_v1(text[]) is 'CF-247 s814: the numeric refs of Layer 4 item keys (kind:ref), so an item source can find its rows by id.';
select pg_temp.cf_edit_def('security.layer4_inbox_items_v2(uuid,text,text[],boolean)'::regprocedure, '26283b7b330d74a86122307e2ab8b7f7',
  array[$o$(p_keys is null or z.k || ':' || r.id::text = any (p_keys))$o$,
        $o$(p_keys is null or 'held_scholarship:' || r.id::text = any (p_keys))$o$,
        $o$(p_keys is null or z.k || ':' || f.id::text = any (p_keys))$o$,
        $o$(p_keys is null or 'course_page_needed:' || n.course_id::text = any (p_keys))$o$],
  array[$n$(p_keys is null or (r.id = any (security.l4_key_uuids_v1(p_keys)) and z.k || ':' || r.id::text = any (p_keys)))$n$,
        $n$(p_keys is null or (r.id = any (security.l4_key_bigints_v1(p_keys)) and 'held_scholarship:' || r.id::text = any (p_keys)))$n$,
        $n$(p_keys is null or (f.id = any (security.l4_key_bigints_v1(p_keys)) and z.k || ':' || f.id::text = any (p_keys)))$n$,
        $n$(p_keys is null or (n.course_id = any (security.l4_key_uuids_v1(p_keys)) and 'course_page_needed:' || n.course_id::text = any (p_keys)))$n$],
  array[1, 1, 2, 1]);

-- post-checks, as a signed-in Platform Admin, on real items, each decision rolled back; the times are reported (cf.diag)
do $$
declare v_admin uuid; v_o text := ''; v_ks text[]; s jsonb; r jsonb; it jsonb; pr text[]; t0 timestamptz; ms int; v_hs int; v_val text;
begin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  foreach pr slice 1 in array array[['held_scholarship', 'not_international'], ['held_scholarship', 'not_scholarship'], ['held_scholarship', 'publish'],
                                    ['nothing_ready', 'rebuild'], ['pages_not_found', 'release'], ['course_link', 'use'], ['provider_description', 'approve'],
                                    ['aer_review', 'approve'], ['site_down', 'wait']] loop
    r := public.admin_layer4_inbox('items', jsonb_build_object('kind', pr[1], 'limit', 1)); it := r->'items'->0;
    continue when it is null;
    t0 := clock_timestamp();
    begin
      r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', pr[1], 'ref', it->>'ref', 'choice', pr[2], 'reason', 'post-check (rolled back)'));
      ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
      if pr[1] = 'held_scholarship' then
        if not coalesce((r->>'ok')::boolean, false) then raise exception 'post-check: held scholarship % did not apply: %', pr[2], left(r::text, 300); end if;
        if not exists (select 1 from pipeline.scholarship_ai_reviews ar where ar.id = (it->>'ref')::bigint and ar.status in ('admitted', 'refused')) then
          raise exception 'post-check: held scholarship % left the review pending', pr[2]; end if;
        if not exists (select 1 from pipeline.admin_control_events e where e.area = 'scholarship_ai' and e.action = 'review_decide' and e.detail->>'review_id' = it->>'ref' and e.detail->>'via' = 'layer4_inbox') then
          raise exception 'post-check: no audit row for the held scholarship decision'; end if;
        v_hs := greatest(coalesce(v_hs, 0), ms);
      end if;
      v_o := v_o || pr[1] || '/' || pr[2] || ' ' || ms || 'ms; ';
      raise exception 'cf-s813-undo';
    exception when others then
      if sqlerrm like 'post-check:%' then raise; end if;
      if sqlerrm <> 'cf-s813-undo' then v_o := v_o || pr[1] || '/' || pr[2] || ' refused by its own rule (' || left(sqlerrm, 60) || '); '; end if;
    end;
  end loop;
  -- the keyed read finds exactly what the full read finds, for a page of items of every kind
  select array_agg(x.kind || ':' || x.ref) into v_ks from (select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, null, false) i order by i.kind, i.created_at limit 400) x;
  if exists ((select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, v_ks, false) i
              except select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, null, false) i where i.kind || ':' || i.ref = any (v_ks))
             union all
             (select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, null, false) i where i.kind || ':' || i.ref = any (v_ks)
              except select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, v_ks, false) i)) then
    raise exception 'post-check: the keyed read differs from the full read'; end if;
  t0 := clock_timestamp();
  perform 1 from security.layer4_inbox_items_v2(null, 'course_link', array['course_link:' || (select r2.id::text from pipeline.layer4_review_items r2 where r2.status = 'pending' limit 1)], true);
  v_o := v_o || 'keyed read ' || round(extract(epoch from clock_timestamp() - t0) * 1000) || 'ms; ';
  perform set_config('request.jwt.claims', '', true);
  if v_hs is null then raise exception 'post-check: no held scholarship was decided'; end if;
  if v_hs > 1000 then raise exception 'post-check: a held scholarship decision took % ms', v_hs; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
