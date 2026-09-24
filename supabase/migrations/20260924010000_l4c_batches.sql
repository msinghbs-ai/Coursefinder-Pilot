-- L4-C: Layer 4 batches.
-- 1. Desk read refinement (guarded substitution of the live definition): scholarship scope
--    items show the scholarship and provider names, task "Scholarship scope", a plain reason,
--    and can_approve (single-item Approve applies to course facts only).
-- 2. layer4_review_batches_v1: waiting items grouped by task and rule-based suggestion.
-- 3. layer4_batch_decide_v1: decide an explicit, previewed list of items in one step.
--    Pipeline Operator (rank 4)+, at most 100 items, all pending and of one kind, typed
--    confirmation "<ACTION> <count>", no bulk edit. Each item goes through the existing
--    security.layer4_review_decide_impl, so every item keeps its normal audit record; the
--    batch is also logged in pipeline.layer4_mass_operations. All or nothing.

do $mig$
declare d text; n int;
  subs text[][] := array[
    array['left join catalogue.providers p2 on r.entity_type=''provider'' and p2.id=r.entity_id',
          E'left join catalogue.providers p2 on r.entity_type=''provider'' and p2.id=r.entity_id\n    left join scholarship.scholarships sc on r.entity_type=''scholarship'' and sc.id=r.entity_id\n    left join catalogue.providers p3 on p3.id=sc.provider_id', '1'],
    array['coalesce(nullif(p.display_name,''''),p.canonical_name,nullif(p2.display_name,''''),p2.canonical_name) provider_name, coalesce(p.id,p2.id) provider_id,',
          'coalesce(nullif(p.display_name,''''),p.canonical_name,nullif(p2.display_name,''''),p2.canonical_name,nullif(p3.display_name,''''),p3.canonical_name) provider_name, coalesce(p.id,p2.id,p3.id) provider_id,', '1'],
    array['coalesce(nullif(c.display_title,''''),c.canonical_title) course_title', 'coalesce(nullif(c.display_title,''''),c.canonical_title,sc.name) course_title', '1'],
    array['when ''scope_resolution'' then ''Scope''', 'when ''scope_resolution'' then ''Scholarship scope''', '2'],
    array[E'when b.escalation_reason is null then null\n',
          E'when b.escalation_reason is null then null\n      when b.entity_type=''scholarship'' and b.field_code=''scope_resolution'' then ''Decide which courses this scholarship applies to before it can be published. Use batch work for scholarship scope.''\n', '1'],
    array['''id'', b.id,', '''id'', b.id, ''can_approve'', b.entity_type=''course'',', '1']
  ];
  i int;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'can_approve')>0 then return; end if;
  for i in 1..array_length(subs,1) loop
    n := (length(d)-length(replace(d,subs[i][1],'')))/length(subs[i][1]);
    if n <> subs[i][3]::int then raise exception 'desk substitution % matched % times (expected %)', i, n, subs[i][3]; end if;
    d := replace(d, subs[i][1], subs[i][2]);
  end loop;
  execute d;
end $mig$;

create or replace function security.layer4_review_batches_v1_impl()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','auth'
as $function$
declare v_desk jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
  v_desk := security.layer4_review_desk_v1_impl('pending',500);
  return jsonb_build_object(
    'can_apply', security.current_role_rank()>=4,
    'groups', coalesce((select jsonb_agg(g order by (g->>'count')::int desc) from (
      select jsonb_build_object(
        'key', i->>'field_code'||'|'||(i->'suggestion'->>'action')||'|'||md5(i->'suggestion'->>'text'),
        'field_code', i->>'field_code', 'task', i->>'task',
        'action', i->'suggestion'->>'action', 'text', i->'suggestion'->>'text',
        'count', count(*), 'oldest_days', max((i->>'age_days')::int),
        'can_approve', bool_and(coalesce((i->>'can_approve')::boolean,false)),
        'item_ids', jsonb_agg(i->>'id' order by (i->>'age_days')::int desc),
        'samples', (jsonb_agg(jsonb_build_object('id',i->>'id','title',coalesce(i->'entity'->>'title',i->>'task'),'code',i->'entity'->>'code','provider',i->'entity'->>'provider','quote',i->>'page_quote','ai_suggested',i->>'ai_suggested') order by (i->>'age_days')::int desc))
      ) g
      from jsonb_array_elements(v_desk->'items') i
      group by i->>'field_code', i->>'task', i->'suggestion'->>'action', i->'suggestion'->>'text'
      having count(*)>=2
    ) x),'[]'::jsonb));
end $function$;

create or replace function security.layer4_batch_decide_v1_impl(p_item_ids uuid[], p_action text, p_reason text, p_confirmation text, p_batch_label text default null)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare v_actor uuid:=auth.uid(); v_ids uuid[]; v_n int; v_kinds int; v_not_pending int; v_field text; v_entity text; v_res jsonb; v_results jsonb:='[]'::jsonb; v_id uuid; v_op uuid;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<4 then raise exception 'Pipeline Operator role is required for batch decisions' using errcode='42501'; end if;
  if p_action not in ('approve','reject','request_more_evidence','return_layer2','return_layer3') then raise exception 'this action cannot be applied as a batch'; end if;
  if length(trim(coalesce(p_reason,'')))<8 then raise exception 'a batch reason of at least 8 characters is required'; end if;
  select array_agg(distinct x) into v_ids from unnest(p_item_ids) x where x is not null;
  v_n := coalesce(cardinality(v_ids),0);
  if v_n<2 then raise exception 'a batch needs at least 2 items'; end if;
  if v_n>100 then raise exception 'a batch can hold at most 100 items'; end if;
  if trim(coalesce(p_confirmation,'')) <> upper(p_action)||' '||v_n then
    raise exception 'confirmation must exactly match "%"', upper(p_action)||' '||v_n;
  end if;
  select count(*) filter (where status<>'pending'), count(distinct (entity_type,field_code)), min(field_code), min(entity_type)
    into v_not_pending, v_kinds, v_field, v_entity
  from pipeline.layer4_review_items where id = any(v_ids);
  if (select count(*) from pipeline.layer4_review_items where id=any(v_ids)) <> v_n then raise exception 'some items were not found'; end if;
  if v_not_pending>0 then raise exception '% item(s) in this batch have already been decided; refresh and preview again', v_not_pending; end if;
  if v_kinds<>1 then raise exception 'a batch must contain one kind of item'; end if;
  if p_action='approve' and v_entity<>'course' then raise exception 'only course facts can be approved in a batch'; end if;

  foreach v_id in array v_ids loop
    v_res := security.layer4_review_decide_impl(v_id, p_action, trim(p_reason), null);
    v_results := v_results || jsonb_build_array(jsonb_build_object('review_item_id',v_id,'decision_id',v_res->>'decision_id','status',v_res->>'status'));
  end loop;

  insert into pipeline.layer4_mass_operations(target_kind,action,actor_id,group_key,reason,before_count,affected_count,result,change_control_ref)
  values ('review_batch',p_action,v_actor,jsonb_build_object('batch_label',p_batch_label,'entity_type',v_entity,'field_code',v_field,'item_ids',to_jsonb(v_ids)),
          trim(p_reason),v_n,jsonb_array_length(v_results),jsonb_build_object('decisions',v_results),'CF-CHG-20260915-247')
  returning id into v_op;
  return jsonb_build_object('ok',true,'mass_operation_id',v_op,'decided',jsonb_array_length(v_results),'action',p_action);
end $function$;

create or replace function public.layer4_review_batches_v1() returns jsonb language sql stable set search_path to 'pg_catalog','security'
as $function$ select security.layer4_review_batches_v1_impl() $function$;
create or replace function public.layer4_batch_decide_v1(p_item_ids uuid[], p_action text, p_reason text, p_confirmation text, p_batch_label text default null)
returns jsonb language sql set search_path to 'pg_catalog','security'
as $function$ select security.layer4_batch_decide_v1_impl(p_item_ids,p_action,p_reason,p_confirmation,p_batch_label) $function$;

revoke all on function security.layer4_review_batches_v1_impl() from public, anon;
revoke all on function security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text) from public, anon;
revoke all on function public.layer4_review_batches_v1() from public, anon;
revoke all on function public.layer4_batch_decide_v1(uuid[],text,text,text,text) from public, anon;
grant execute on function security.layer4_review_batches_v1_impl() to authenticated, service_role;
grant execute on function security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text) to authenticated, service_role;
grant execute on function public.layer4_review_batches_v1() to authenticated, service_role;
grant execute on function public.layer4_batch_decide_v1(uuid[],text,text,text,text) to authenticated, service_role;
