-- L4-B: claims for team working.
-- Opening an item claims it (assigned_to + claimed_at). A claim lapses after 30 minutes
-- idle (decision, 24 Sep 2026); reopening refreshes it. Another reviewer cannot take an
-- actively claimed item. Deciding an item releases the claim. Time per decision is
-- decision time minus claimed_at (reporting in L4-D). Batches refuse items actively
-- claimed by someone else.

alter table pipeline.layer4_review_items add column if not exists claimed_at timestamptz;

create or replace function security.layer4_claim_v1_impl(p_review_item_id uuid, p_release boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare v_actor uuid:=auth.uid(); v_item pipeline.layer4_review_items%rowtype; v_active boolean;
begin
  if v_actor is null or security.current_role_rank()<3 then raise exception 'curator role required' using errcode='42501'; end if;
  select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
  if not found then raise exception 'review item not found'; end if;
  v_active := v_item.assigned_to is not null and v_item.claimed_at is not null and v_item.claimed_at > now()-interval '30 minutes';
  if p_release then
    if v_item.assigned_to = v_actor then update pipeline.layer4_review_items set assigned_to=null, claimed_at=null where id=v_item.id; end if;
    return jsonb_build_object('ok',true,'released',v_item.assigned_to = v_actor);
  end if;
  if v_item.status<>'pending' then return jsonb_build_object('ok',false,'reason','already decided'); end if;
  if v_active and v_item.assigned_to<>v_actor then
    return jsonb_build_object('ok',false,'reason','claimed','claimed_by',(select email from auth.users where id=v_item.assigned_to),
      'minutes_left',ceil(extract(epoch from (v_item.claimed_at+interval '30 minutes'-now()))/60));
  end if;
  update pipeline.layer4_review_items set assigned_to=v_actor, claimed_at=now() where id=v_item.id;
  return jsonb_build_object('ok',true,'claimed',true);
end $function$;

create or replace function public.layer4_claim_v1(p_review_item_id uuid, p_release boolean default false)
returns jsonb language sql set search_path to 'pg_catalog','security'
as $function$ select security.layer4_claim_v1_impl(p_review_item_id,p_release) $function$;

revoke all on function security.layer4_claim_v1_impl(uuid,boolean) from public, anon;
revoke all on function public.layer4_claim_v1(uuid,boolean) from public, anon;
grant execute on function security.layer4_claim_v1_impl(uuid,boolean) to authenticated, service_role;
grant execute on function public.layer4_claim_v1(uuid,boolean) to authenticated, service_role;

-- Desk read: claim fields per item (guarded substitution of the live definition).
do $mig$
declare d text; a text := $q$'created_at', b.created_at, 'decided_at', b.decided_at, 'assigned_to', b.assigned_to,$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'claim_active')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'desk anchor not found exactly once'; end if;
  execute replace(d, a, a || $q$
    'claimed_at', b.claimed_at,
    'claim_active', (b.assigned_to is not null and b.claimed_at is not null and b.claimed_at > now()-interval '30 minutes'),
    'claimed_by_me', (b.assigned_to = auth.uid() and b.claimed_at > now()-interval '30 minutes'),
    'claimed_by', (select u.email from auth.users u where u.id=b.assigned_to and b.claimed_at > now()-interval '30 minutes'),$q$);
end $mig$;

-- Batch decision: refuse items actively claimed by another reviewer (guarded substitution).
do $mig$
declare d text;
  a text := $q$  if v_kinds<>1 then raise exception 'a batch must contain one kind of item'; end if;$q$;
begin
  d := pg_get_functiondef('security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)'::regprocedure);
  if strpos(d,'being reviewed by someone else')>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'batch anchor not found exactly once'; end if;
  execute replace(d, a, a || E'\n' || $q$  if exists(select 1 from pipeline.layer4_review_items where id=any(v_ids) and assigned_to is not null and assigned_to<>v_actor and claimed_at > now()-interval '30 minutes') then
    raise exception '% item(s) in this batch are being reviewed by someone else; untick them or try later', (select count(*) from pipeline.layer4_review_items where id=any(v_ids) and assigned_to is not null and assigned_to<>v_actor and claimed_at > now()-interval '30 minutes');
  end if;$q$);
end $mig$;
