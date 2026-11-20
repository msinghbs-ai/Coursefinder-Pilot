-- CF-247 S831 (S1-AER, Platform Admin 20 Nov 2026 11:55 AEDT, item 4): Layer 4 AER "Why items are held" breakdown and the list behind each reason, read from the stored result of the
-- machine check (pipeline.aer_machine_admissions, the latest check of each pending item). Read only: no row is written, admitted, approved or rejected here; the completeness gate,
-- audit sample, page identity, manual locks and no-overwrite are not touched (Decision 276). Decisions stay in Layer 4 through the Inbox's own decide action.
-- Guards: Decision 276 (AER v1 frozen), G3 (no new public function, table or view: public.admin_layer4_aer_queue gains one branch; its result for every existing argument is unchanged),
--   G2 (no operational value: the page size is a fixed bound), Decision 260 (housekeeping).
-- Replaces: public.admin_layer4_aer_queue(jsonb) (same name and signature; the live definition md5 800198d6264c08f088f672adbdaa26a5 is checked before the edit)
-- Retires: nothing
--
-- New: security.layer4_aer_hold_reasons_v1(jsonb), called only by public.admin_layer4_aer_queue (Pipeline Operator or above).
--   {hold_reasons: true}                          -> {as_at, total, reasons: [{code, label, n}]} for every pending first read (course) and matrix item
--   {hold_reasons: true, reason, offset, limit}   -> {reason, total, items: [{id, course, provider, country, checked_at, why}]} (limit at most 100)

do $g$
begin
  if to_regprocedure('public.admin_layer4_aer_queue(jsonb)') is null or to_regprocedure('security.layer4_aer_queue_v1(jsonb)') is null
     or to_regclass('pipeline.aer_machine_admissions') is null then
    raise exception 'S831 needs public.admin_layer4_aer_queue, security.layer4_aer_queue_v1 and pipeline.aer_machine_admissions';
  end if;
  if md5(pg_catalog.pg_get_functiondef('public.admin_layer4_aer_queue(jsonb)'::regprocedure)) <> '800198d6264c08f088f672adbdaa26a5' then
    raise exception 'S831: public.admin_layer4_aer_queue is not the definition this change was written against; read it again';
  end if;
end $g$;

create or replace function security.layer4_aer_hold_base_v1()
returns table (id uuid, entity_id uuid, field_code text, code text, reason text, checked_at timestamptz)
language sql stable security definer set search_path to '' as $f$
-- S831 (20 Nov 2026): every pending AER item with the class of its latest stored machine check; read only
  with p as (select i.id, i.field_code, i.entity_id from pipeline.layer4_review_items i
              where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')),
  l as (select distinct on (a.review_item_id) a.review_item_id, a.reason_code, a.outcome, a.reason, a.created_at
          from pipeline.aer_machine_admissions a join p on p.id = a.review_item_id order by a.review_item_id, a.created_at desc)
  select p.id, p.entity_id, p.field_code,
         case when p.field_code = 'entry_matrix_first_run' then 'matrix_first_run'
              when p.field_code = 'entry_matrix_change' then 'matrix_change'
              when l.review_item_id is null then 'not_checked'
              when l.outcome = 'audit_sample' then 'audit_sample'
              when l.reason_code in ('gate_incomplete', 'all_rows_held', 'identity_not_admitted', 'no_bound_page') then l.reason_code
              else 'other' end,
         l.reason, l.created_at
    from p left join l on l.review_item_id = p.id
$f$;
revoke all on function security.layer4_aer_hold_base_v1() from public, anon, authenticated;
comment on function security.layer4_aer_hold_base_v1() is 'S831: every pending AER item with the class of its latest stored machine check; read only; used by security.layer4_aer_hold_reasons_v1';

create or replace function security.layer4_aer_hold_reasons_v1(p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
-- S831 (20 Nov 2026): why each pending AER item waits, from the stored result of its latest machine check; read only
declare
  v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
  v_off int := greatest(0, coalesce(nullif(p_args->>'offset', '')::int, 0));
  v_lim int := least(100, greatest(1, coalesce(nullif(p_args->>'limit', '')::int, 25))); -- fixed: bound on one page
begin
  if v_reason is null then
    return jsonb_build_object('as_at', now(), 'total', (select count(*) from security.layer4_aer_hold_base_v1()),
      'reasons', coalesce((select jsonb_agg(jsonb_build_object('code', z.code, 'n', z.n, 'label', case z.code
          when 'gate_incomplete' then 'Completeness gate (partial table read)'
          when 'audit_sample' then 'Audit sample (a person checks it)'
          when 'all_rows_held' then 'All rows held (every row fails a row rule)'
          when 'identity_not_admitted' then 'Page identity (the stored page is not proven to be this course''s)'
          when 'no_bound_page' then 'No stored page bound'
          when 'matrix_first_run' then 'Provider matrix, first run'
          when 'matrix_change' then 'Provider matrix, change of an admitted table'
          when 'not_checked' then 'Not checked yet'
          else 'Other' end) order by z.n desc) from (select b.code, count(*) n from security.layer4_aer_hold_base_v1() b group by 1) z), '[]'::jsonb));
  end if;
  return jsonb_build_object('reason', v_reason, 'offset', v_off, 'total', (select count(*) from security.layer4_aer_hold_base_v1() h where h.code = v_reason),
    'items', coalesce((select jsonb_agg(q.x order by q.pn nulls last, q.ct nulls last, q.hid) from (
       select jsonb_build_object('id', h.id, 'course', coalesce(c.display_title, c.canonical_title, '—'), 'provider', coalesce(pr.name, '—'), 'country', co.iso_alpha2,
                                 'checked_at', h.checked_at, 'why', left(coalesce(h.reason, ''), 300)) x, pr.name pn, coalesce(c.display_title, c.canonical_title) ct, h.id hid
         from security.layer4_aer_hold_base_v1() h
         left join catalogue.courses c on c.id = h.entity_id and h.field_code = 'course_entry_first_read'
         left join catalogue.providers pr on pr.id = coalesce(c.provider_id, case when h.field_code <> 'course_entry_first_read' then h.entity_id end)
         left join ref.countries co on co.id = pr.country_id
        where h.code = v_reason order by pr.name nulls last, coalesce(c.display_title, c.canonical_title) nulls last, h.id offset v_off limit v_lim) q), '[]'::jsonb));
end $f$;
revoke all on function security.layer4_aer_hold_reasons_v1(jsonb) from public, anon, authenticated;
comment on function security.layer4_aer_hold_reasons_v1(jsonb) is 'S831: why each pending AER item waits (latest stored machine check), and the items behind one reason; read only; called by public.admin_layer4_aer_queue';

create or replace function public.admin_layer4_aer_queue(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 directions 10:00 §3 and 12:16 §5, §8: the reviewer-ready AER queue and one university's summary (Pipeline Operator and above; read
-- only). Decisions are made in Layer 4 › Inbox, one item at a time. S831 (20 Nov 2026): {hold_reasons: true} answers why items wait.
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then
    raise exception 'Pipeline Operator or above required' using errcode = '42501';
  end if;
  if coalesce(p_args, '{}'::jsonb) ? 'hold_reasons' then
    return security.layer4_aer_hold_reasons_v1(p_args);
  end if;
  if coalesce(p_args, '{}'::jsonb) ? 'summary_provider_id' then
    return security.layer4_aer_university_summary_v1((p_args->>'summary_provider_id')::uuid);
  end if;
  return security.layer4_aer_queue_v1(coalesce(p_args, '{}'::jsonb));
end $function$;

do $p$
begin
  if pg_catalog.pg_get_functiondef('public.admin_layer4_aer_queue(jsonb)'::regprocedure) not like '%hold_reasons%' then raise exception 'post-check: S831 edit missing'; end if;
  if has_function_privilege('anon', 'security.layer4_aer_hold_reasons_v1(jsonb)', 'execute') or has_function_privilege('authenticated', 'security.layer4_aer_hold_reasons_v1(jsonb)', 'execute') then
    raise exception 'post-check: the hold reasons function must not be callable by anon or authenticated';
  end if;
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'post-check: G3 must stay 75 functions and 48 relations';
  end if;
end $p$;
