-- CF-247 Layer 4 operational groups fixtures: the readiness table as live (20261104120000 §4; columns read live 4 Nov 2026 17:11 AEDT)
create table if not exists pipeline.layer4_item_readiness (
  item_id uuid primary key references pipeline.layer4_review_items(id),
  entity_type text not null,
  entity_id uuid not null,
  field_code text not null,
  item_created_at timestamptz not null,
  item_status text not null,
  readiness text not null check (readiness in ('judgement_ready', 'technical_blocked', 'resolvable', 'closed')),
  reasons text[] not null default '{}',
  route text not null,
  resolution jsonb,
  blockers jsonb not null default '[]'::jsonb,
  est_minutes numeric,
  gate jsonb,
  gate_checked_at timestamptz,
  classified_at timestamptz not null default now(),
  rule text not null default 'L4R-1'
);
-- live columns the card evidence reads (information_schema, 4 Nov 2026 12:30 AEDT)
alter table pipeline.provider_onboarding add column if not exists result jsonb;
alter table pipeline.enrichment_flags add column if not exists checks int, add column if not exists tries int;
-- the decide routes this change guards, as stand-ins with the live contracts (onboarding retry starts a new run; rebuild queues a build; a hold
-- release clears the hold); the scholarship route as live, including the reply seen on 30 Oct 2026 23:11 AEDT when it did not apply (the
-- screen's status: models, chain and queue), reproduced for a reason marked [fx-not-applied]
create or replace function public.admin_provider_onboarding(p_action text, p_args jsonb) returns jsonb language plpgsql as $f$
declare o pipeline.provider_onboarding;
begin
  select * into o from pipeline.provider_onboarding where id = (p_args->'ids'->>0)::uuid;
  update pipeline.provider_onboarding set status = 'retried', updated_at = now() where id = o.id;
  insert into pipeline.provider_onboarding(id, provider_id, status, stop_reason, note, created_at, updated_at) values (gen_random_uuid(), o.provider_id, 'running', null, 'retry', now(), now());
  return jsonb_build_object('retried', 1);
end $f$;
create or replace function public.admin_adapter_build(p_action text, p_args jsonb) returns jsonb language sql as
  $f$ select jsonb_build_object('queued', jsonb_array_length(p_args->'provider_ids')) $f$;
create or replace function security.flag_release_v1(p_id bigint, p_by text, p_kind text, p_reason text, p_meta jsonb, p_quiet boolean) returns jsonb language sql as
  $f$ update pipeline.enrichment_flags set state = 'released', released_at = now() where id = p_id returning jsonb_build_object('released', id) $f$;
create or replace function public.admin_scholarship_ai(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql as $f$
begin
  if p_action <> 'review_decide' then raise exception 'stand-in handles review_decide only'; end if;
  if coalesce(p_args->>'reason', '') like '%[fx-not-applied]%' then
    return jsonb_build_object('chain', jsonb_build_array('qwen3-30b', 'gpt-4.1-mini'), 'queue', jsonb_build_object('waiting', 0, 'done_today', 0));
  end if;
  update pipeline.scholarship_ai_reviews set status = case when p_args->>'decision' = 'admit' then 'admitted' else 'refused' end, decided_at = now(), note = p_args->>'reason'
   where id = (p_args->>'review_id')::bigint and status = 'pending';
  return jsonb_build_object('applied', jsonb_build_object('review_id', p_args->>'review_id', 'decision', p_args->>'decision'));
end $f$;
-- the Course Link workstream's classifier (security.course_link_route_class_v1, migration 20261104570000), as a stand-in with its published
-- contract: {item, group A|B|C|D or null when the item is not a pending official link, class, action, authority, reason, recommended, evidence}
create table if not exists fx.cl_route(item uuid primary key, grp text, cls text, action text, authority text);
create or replace function security.course_link_route_class_v1(p_item uuid) returns jsonb language sql stable security definer set search_path to '' as $f$
  select case when r.id is null then jsonb_build_object('item', p_item, 'group', null)
              else jsonb_build_object('item', p_item, 'group', coalesce(c.grp, 'C'), 'class', coalesce(c.cls, 'cricos_page_differs'), 'action', coalesce(c.action, 'keep'),
                                      'authority', c.authority, 'reason', 'fixture', 'recommended', null, 'evidence', '{}'::jsonb) end
    from (select 1) z left join pipeline.layer4_review_items r on r.id = p_item and r.status = 'pending' and r.field_code = 'official_course_url'
    left join fx.cl_route c on c.item = p_item
$f$;
