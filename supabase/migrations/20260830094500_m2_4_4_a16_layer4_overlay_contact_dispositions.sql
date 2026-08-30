
create table if not exists pipeline.layer4_field_registry (
  entity_type text not null,
  field_code text not null,
  display_label text not null,
  value_kind text not null check (value_kind in ('text','url','email','phone','duration','uuid','json')),
  editability_class text not null check (editability_class in ('editable','elevated','immutable')),
  min_role_rank integer not null check (min_role_rank between 1 and 6),
  publication_sensitive boolean not null default false,
  enabled boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  primary key(entity_type,field_code)
);

create table if not exists pipeline.layer4_override_decisions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  field_code text not null,
  event_type text not null check (event_type in ('apply','revert')),
  underlying_value jsonb,
  override_value jsonb,
  underlying_layer text not null default 'governed_underlying',
  underlying_source_ref text,
  reason_code text not null,
  comment text,
  evidence_refs uuid[] not null default '{}',
  actor_id uuid not null,
  actor_email text,
  supersedes_override_id uuid references pipeline.layer4_override_decisions(id),
  approval_context jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260830-048',
  created_at timestamptz not null default now(),
  constraint layer4_override_field_registry_fkey
    foreign key(entity_type,field_code)
    references pipeline.layer4_field_registry(entity_type,field_code)
);
create index if not exists layer4_override_entity_field_created_idx
  on pipeline.layer4_override_decisions(entity_type,entity_id,field_code,created_at desc);
create index if not exists layer4_override_actor_created_idx
  on pipeline.layer4_override_decisions(actor_id,created_at desc);

create table if not exists pipeline.layer4_publication_decisions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  target_scope text not null default 'governed_publication',
  event_type text not null check (event_type in ('publishable','not_publishable','revert')),
  readiness_snapshot jsonb not null default '{}'::jsonb,
  overridden_checks jsonb not null default '[]'::jsonb,
  reason_code text not null,
  comment text,
  actor_id uuid not null,
  actor_email text,
  supersedes_decision_id uuid references pipeline.layer4_publication_decisions(id),
  approval_context jsonb not null default '{}'::jsonb,
  change_control_ref text not null default 'CF-CHG-20260830-048',
  created_at timestamptz not null default now()
);
create index if not exists layer4_publication_entity_created_idx
  on pipeline.layer4_publication_decisions(entity_type,entity_id,target_scope,created_at desc);

create table if not exists pipeline.provider_contact_dispositions (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  profile_id uuid not null references pipeline.provider_contact_profiles(id),
  disposition text not null check (disposition in (
    'published_contact_found',
    'not_publicly_published',
    'not_found_in_qualified_evidence',
    'needs_layer4_review',
    'pending_layer3',
    'pending_acquisition'
  )),
  international_students_url text,
  contact_team_url text,
  general_email text,
  named_contact_count integer not null default 0,
  territory_contact_count integer not null default 0,
  source_urls text[] not null default '{}',
  evidence_ids uuid[] not null default '{}',
  layer3_interpretation_id uuid,
  interpretation_source text not null check (interpretation_source in ('a15_reconciliation','layer3','layer4')),
  observed_at timestamptz,
  last_verified_at timestamptz,
  supersedes_disposition_id uuid references pipeline.provider_contact_dispositions(id),
  change_control_ref text not null default 'CF-CHG-20260830-048',
  created_at timestamptz not null default now()
);
create index if not exists provider_contact_disposition_provider_created_idx
  on pipeline.provider_contact_dispositions(provider_id,created_at desc);
create index if not exists provider_contact_disposition_profile_created_idx
  on pipeline.provider_contact_dispositions(profile_id,created_at desc);

alter table pipeline.layer4_field_registry enable row level security;
alter table pipeline.layer4_override_decisions enable row level security;
alter table pipeline.layer4_publication_decisions enable row level security;
alter table pipeline.provider_contact_dispositions enable row level security;

revoke all on pipeline.layer4_field_registry from public,anon,authenticated;
revoke all on pipeline.layer4_override_decisions from public,anon,authenticated;
revoke all on pipeline.layer4_publication_decisions from public,anon,authenticated;
revoke all on pipeline.provider_contact_dispositions from public,anon,authenticated;
grant select,insert,update,delete on pipeline.layer4_field_registry to service_role;
grant select,insert on pipeline.layer4_override_decisions to service_role;
grant select,insert on pipeline.layer4_publication_decisions to service_role;
grant select,insert on pipeline.provider_contact_dispositions to service_role;

create or replace function security.layer4_append_only_guard()
returns trigger language plpgsql
set search_path='pg_catalog','security'
as $$
begin
  raise exception 'Layer 4 audit history is append-only' using errcode='42501';
end $$;

drop trigger if exists trg_layer4_override_append_only on pipeline.layer4_override_decisions;
create trigger trg_layer4_override_append_only
before update or delete on pipeline.layer4_override_decisions
for each row execute function security.layer4_append_only_guard();

drop trigger if exists trg_layer4_publication_append_only on pipeline.layer4_publication_decisions;
create trigger trg_layer4_publication_append_only
before update or delete on pipeline.layer4_publication_decisions
for each row execute function security.layer4_append_only_guard();

insert into pipeline.layer4_field_registry(entity_type,field_code,display_label,value_kind,editability_class,min_role_rank,publication_sensitive,notes)
values
('course','course_description','Course description','text','editable',3,false,'Effective-value overlay only'),
('course','official_course_url','Official Course URL','url','editable',3,false,'Effective-value overlay only'),
('course','delivery_mode','Delivery mode','text','editable',3,false,'Effective-value overlay only'),
('course','duration','Duration','duration','editable',3,false,'Effective-value overlay only'),
('course','stable_key','Stable key','text','immutable',6,true,'Protected canonical identity'),
('course','canonical_title','Canonical title','text','immutable',6,true,'Protected canonical identity'),
('course','course_code','Course / CRICOS code','text','immutable',6,true,'Protected regulatory identity'),
('course','canonical_source_id','Canonical source ID','uuid','immutable',6,true,'Protected source authority'),
('provider','display_name','Provider display name','text','editable',3,false,'Effective-value overlay only'),
('provider','website','Provider website','url','editable',3,false,'Effective-value overlay only'),
('provider','description','Provider description','text','editable',3,false,'Effective-value overlay only'),
('provider','primary_city','Provider primary city','text','editable',3,false,'Effective-value overlay only'),
('provider','phone','Provider phone','phone','editable',3,false,'Effective-value overlay only'),
('provider','email','Provider email','email','editable',3,false,'Effective-value overlay only'),
('provider','stable_key','Stable key','text','immutable',6,true,'Protected canonical identity'),
('provider','canonical_name','Canonical name','text','immutable',6,true,'Protected canonical identity'),
('provider','country_id','Country ID','uuid','immutable',6,true,'Protected authority geography'),
('provider','canonical_source_id','Canonical source ID','uuid','immutable',6,true,'Protected source authority'),
('campus','name','Campus name','text','editable',3,false,'Effective-value overlay only'),
('campus','city','Campus city','text','editable',3,false,'Effective-value overlay only'),
('campus','address_line1','Address line 1','text','editable',3,false,'Effective-value overlay only'),
('campus','address_line2','Address line 2','text','editable',3,false,'Effective-value overlay only'),
('campus','postcode','Postcode','text','editable',3,false,'Effective-value overlay only'),
('campus','phone','Campus phone','phone','editable',3,false,'Effective-value overlay only'),
('campus','website','Campus website','url','editable',3,false,'Effective-value overlay only'),
('campus','stable_key','Stable key','text','immutable',6,true,'Protected canonical identity'),
('campus','provider_id','Provider ID','uuid','immutable',6,true,'Protected relationship identity'),
('campus','source_id','Source ID','uuid','immutable',6,true,'Protected source authority'),
('campus','evidence_id','Evidence ID','uuid','immutable',6,true,'Protected Evidence relationship')
on conflict(entity_type,field_code) do update
set display_label=excluded.display_label,
    value_kind=excluded.value_kind,
    editability_class=excluded.editability_class,
    min_role_rank=excluded.min_role_rank,
    publication_sensitive=excluded.publication_sensitive,
    notes=excluded.notes,
    enabled=true;

create or replace function security.layer4_entity_exists(p_entity_type text,p_entity_id uuid)
returns boolean language sql stable security definer
set search_path='pg_catalog','catalogue'
as $$
  select case p_entity_type
    when 'course' then exists(select 1 from catalogue.courses where id=p_entity_id)
    when 'provider' then exists(select 1 from catalogue.providers where id=p_entity_id)
    when 'campus' then exists(select 1 from catalogue.campuses where id=p_entity_id)
    else false
  end
$$;

create or replace function security.layer4_underlying_value(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','catalogue'
as $$
declare v jsonb;
begin
  if p_entity_type='course' then
    if p_field_code='course_description' then select to_jsonb(description) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='delivery_mode' then select to_jsonb(delivery_mode) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='duration' then select jsonb_build_object('value',duration_value,'unit',duration_unit) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='official_course_url' then
      select to_jsonb(coalesce(
        (select cl.url from catalogue.course_links cl where cl.course_id=p_entity_id and cl.link_type='official_course' and coalesce(cl.status,'active')='active'
         order by (cl.audience='international') desc,cl.last_verified_at desc nulls last,cl.created_at desc limit 1),
        c.course_url
      )) into v from catalogue.courses c where c.id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='canonical_title' then select to_jsonb(canonical_title) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='course_code' then select to_jsonb(course_code) into v from catalogue.courses where id=p_entity_id;
    elsif p_field_code='canonical_source_id' then select to_jsonb(canonical_source_id) into v from catalogue.courses where id=p_entity_id;
    end if;
  elsif p_entity_type='provider' then
    if p_field_code='display_name' then select to_jsonb(display_name) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='website' then select to_jsonb(website) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='description' then select to_jsonb(description) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='primary_city' then select to_jsonb(primary_city) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='phone' then select to_jsonb(phone) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='email' then select to_jsonb(email) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='canonical_name' then select to_jsonb(canonical_name) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='country_id' then select to_jsonb(country_id) into v from catalogue.providers where id=p_entity_id;
    elsif p_field_code='canonical_source_id' then select to_jsonb(canonical_source_id) into v from catalogue.providers where id=p_entity_id;
    end if;
  elsif p_entity_type='campus' then
    if p_field_code='name' then select to_jsonb(name) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='city' then select to_jsonb(city) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='address_line1' then select to_jsonb(address_line1) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='address_line2' then select to_jsonb(address_line2) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='postcode' then select to_jsonb(postcode) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='phone' then select to_jsonb(phone) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='website' then select to_jsonb(website) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='stable_key' then select to_jsonb(stable_key) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='provider_id' then select to_jsonb(provider_id) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='source_id' then select to_jsonb(source_id) into v from catalogue.campuses where id=p_entity_id;
    elsif p_field_code='evidence_id' then select to_jsonb(evidence_id) into v from catalogue.campuses where id=p_entity_id;
    end if;
  end if;
  return v;
end $$;

create or replace function security.layer4_validate_override_value(p_value_kind text,p_value jsonb)
returns void language plpgsql immutable
set search_path='pg_catalog','security'
as $$
declare v_text text; v_num numeric;
begin
  if p_value is null then raise exception 'override value is required' using errcode='22023'; end if;
  if p_value_kind in ('text','url','email','phone') then
    if jsonb_typeof(p_value)<>'string' then raise exception 'override value must be a JSON string' using errcode='22023'; end if;
    v_text:=trim(p_value #>> '{}');
    if v_text='' then raise exception 'override value cannot be empty' using errcode='22023'; end if;
    if p_value_kind='url' and v_text !~* '^https?://[^[:space:]]+$' then raise exception 'URL override must use http/https' using errcode='22023'; end if;
    if p_value_kind='email' and v_text !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid email override' using errcode='22023'; end if;
    if p_value_kind='phone' and length(regexp_replace(v_text,'[^0-9+]','','g'))<5 then raise exception 'invalid phone override' using errcode='22023'; end if;
  elsif p_value_kind='duration' then
    if jsonb_typeof(p_value)<>'object' then raise exception 'duration override must be an object' using errcode='22023'; end if;
    v_num:=nullif(p_value->>'value','')::numeric;
    if v_num is null or v_num<=0 or nullif(trim(p_value->>'unit'),'') is null then raise exception 'duration requires positive value and unit' using errcode='22023'; end if;
  elsif p_value_kind='uuid' then
    perform (p_value #>> '{}')::uuid;
  end if;
end $$;

create or replace function security.layer4_override_apply_impl(
  p_actor uuid,p_entity_type text,p_entity_id uuid,p_field_code text,p_value jsonb,
  p_reason_code text,p_comment text default null,p_evidence_refs uuid[] default '{}',
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rank int:=0; v_reg pipeline.layer4_field_registry%rowtype; v_underlying jsonb;
        v_prev uuid; v_id uuid; v_email text;
begin
  if p_actor is null or p_actor<>auth.uid() then raise exception 'authenticated actor required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  select * into v_reg from pipeline.layer4_field_registry where entity_type=p_entity_type and field_code=p_field_code and enabled;
  if not found then raise exception 'field is not registered for Layer 4' using errcode='22023'; end if;
  if v_reg.editability_class='immutable' then raise exception 'field is immutable source/history and cannot be edited through Layer 4' using errcode='42501'; end if;
  if v_rank<v_reg.min_role_rank then raise exception 'insufficient role for Layer 4 field' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then raise exception 'entity not found' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  perform security.layer4_validate_override_value(v_reg.value_kind,p_value);
  v_underlying:=security.layer4_underlying_value(p_entity_type,p_entity_id,p_field_code);
  select id into v_prev from pipeline.layer4_override_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and field_code=p_field_code
   order by created_at desc,id desc limit 1;
  select email into v_email from auth.users where id=p_actor;
  insert into pipeline.layer4_override_decisions(
    entity_type,entity_id,field_code,event_type,underlying_value,override_value,
    reason_code,comment,evidence_refs,actor_id,actor_email,supersedes_override_id,
    approval_context
  ) values (
    p_entity_type,p_entity_id,p_field_code,'apply',v_underlying,p_value,
    trim(p_reason_code),nullif(trim(coalesce(p_comment,'')),''),coalesce(p_evidence_refs,'{}'),
    p_actor,v_email,v_prev,coalesce(p_approval_context,'{}')
  ) returning id into v_id;
  return jsonb_build_object(
    'ok',true,'override_id',v_id,'entity_type',p_entity_type,'entity_id',p_entity_id,
    'field_code',p_field_code,'underlying_value',v_underlying,'effective_value',p_value,
    'effective_source','L4','layer',4,'publication_changed',false,'canonical_changed',false
  );
end $$;

create or replace function public.layer4_override_apply(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_value jsonb,
  p_reason_code text,p_comment text default null,p_evidence_refs uuid[] default '{}',
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','auth'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  return security.layer4_override_apply_impl(auth.uid(),p_entity_type,p_entity_id,p_field_code,p_value,p_reason_code,p_comment,p_evidence_refs,p_approval_context);
end $$;
revoke all on function public.layer4_override_apply(text,uuid,text,jsonb,text,text,uuid[],jsonb) from public,anon;
grant execute on function public.layer4_override_apply(text,uuid,text,jsonb,text,text,uuid[],jsonb) to authenticated,service_role;

create or replace function public.layer4_override_revert(
  p_entity_type text,p_entity_id uuid,p_field_code text,p_reason_code text,p_comment text default null
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_reg pipeline.layer4_field_registry%rowtype; v_prev pipeline.layer4_override_decisions%rowtype; v_id uuid; v_email text; v_underlying jsonb;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  select * into v_reg from pipeline.layer4_field_registry where entity_type=p_entity_type and field_code=p_field_code and enabled;
  if not found or v_reg.editability_class='immutable' then raise exception 'field is not revertible through Layer 4' using errcode='42501'; end if;
  if v_rank<v_reg.min_role_rank then raise exception 'insufficient role for Layer 4 field' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  select * into v_prev from pipeline.layer4_override_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and field_code=p_field_code
   order by created_at desc,id desc limit 1;
  if not found or v_prev.event_type='revert' then raise exception 'no active Layer 4 override to revert' using errcode='22023'; end if;
  v_underlying:=security.layer4_underlying_value(p_entity_type,p_entity_id,p_field_code);
  select email into v_email from auth.users where id=v_actor;
  insert into pipeline.layer4_override_decisions(
    entity_type,entity_id,field_code,event_type,underlying_value,override_value,
    reason_code,comment,actor_id,actor_email,supersedes_override_id
  ) values (
    p_entity_type,p_entity_id,p_field_code,'revert',v_underlying,null,
    trim(p_reason_code),nullif(trim(coalesce(p_comment,'')),''),v_actor,v_email,v_prev.id
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'override_id',v_id,'event_type','revert','effective_value',v_underlying,'effective_source','UNDERLYING','canonical_changed',false);
end $$;
revoke all on function public.layer4_override_revert(text,uuid,text,text,text) from public,anon;
grant execute on function public.layer4_override_revert(text,uuid,text,text,text) to authenticated,service_role;

create or replace function security.layer4_effective_field_read(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rank int; v_reg pipeline.layer4_field_registry%rowtype; v_last pipeline.layer4_override_decisions%rowtype; v_underlying jsonb; v_effective jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  select * into v_reg from pipeline.layer4_field_registry where entity_type=p_entity_type and field_code=p_field_code and enabled;
  if not found then return null; end if;
  v_underlying:=security.layer4_underlying_value(p_entity_type,p_entity_id,p_field_code);
  select * into v_last from pipeline.layer4_override_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and field_code=p_field_code
   order by created_at desc,id desc limit 1;
  v_effective:=case when found and v_last.event_type='apply' then v_last.override_value else v_underlying end;
  return jsonb_build_object(
    'field_code',p_field_code,'display_label',v_reg.display_label,'value_kind',v_reg.value_kind,
    'editability_class',v_reg.editability_class,'min_role_rank',v_reg.min_role_rank,
    'can_edit',(v_reg.editability_class<>'immutable' and v_rank>=v_reg.min_role_rank),
    'underlying_value',v_underlying,'effective_value',v_effective,
    'effective_source',case when found and v_last.event_type='apply' then 'L4' else 'UNDERLYING' end,
    'override_id',case when found then v_last.id else null end,
    'override_event',case when found then v_last.event_type else null end,
    'actor_id',case when found then v_last.actor_id else null end,
    'actor_email',case when found then v_last.actor_email else null end,
    'edited_at',case when found then v_last.created_at else null end,
    'reason_code',case when found then v_last.reason_code else null end,
    'comment',case when found then v_last.comment else null end,
    'upstream_changed',case when found and v_last.event_type='apply' then v_underlying is distinct from v_last.underlying_value else false end,
    'history_count',(select count(*) from pipeline.layer4_override_decisions d where d.entity_type=p_entity_type and d.entity_id=p_entity_id and d.field_code=p_field_code)
  );
end $$;

create or replace function security.layer4_effective_entity_read(p_entity_type text,p_entity_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rows jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(security.layer4_effective_field_read(r.entity_type,p_entity_id,r.field_code) order by r.display_label),'[]'::jsonb)
  into v_rows
  from pipeline.layer4_field_registry r
  where r.entity_type=p_entity_type and r.enabled;
  return jsonb_build_object(
    'entity_type',p_entity_type,'entity_id',p_entity_id,
    'fields',coalesce(v_rows,'[]'::jsonb),
    'active_override_count',(
      select count(*) from (
        select distinct on (field_code) field_code,event_type
        from pipeline.layer4_override_decisions
        where entity_type=p_entity_type and entity_id=p_entity_id
        order by field_code,created_at desc,id desc
      ) q where event_type='apply'
    )
  );
end $$;

create or replace function public.layer4_effective_entity(p_entity_type text,p_entity_id uuid)
returns jsonb language sql stable security definer
set search_path='pg_catalog','public','security','auth'
as $$ select security.layer4_effective_entity_read(p_entity_type,p_entity_id) $$;
revoke all on function public.layer4_effective_entity(text,uuid) from public,anon;
grant execute on function public.layer4_effective_entity(text,uuid) to authenticated,service_role;

create or replace function public.layer4_override_history(p_entity_type text,p_entity_id uuid,p_field_code text)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_rank int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',d.id,'event_type',d.event_type,'underlying_value',d.underlying_value,'override_value',d.override_value,
      'reason_code',d.reason_code,'comment',d.comment,'evidence_refs',d.evidence_refs,
      'actor_id',d.actor_id,'actor_email',d.actor_email,'created_at',d.created_at,'supersedes_override_id',d.supersedes_override_id
    ) order by d.created_at desc,d.id desc)
    from pipeline.layer4_override_decisions d
    where d.entity_type=p_entity_type and d.entity_id=p_entity_id and d.field_code=p_field_code
  ),'[]'::jsonb);
end $$;
revoke all on function public.layer4_override_history(text,uuid,text) from public,anon;
grant execute on function public.layer4_override_history(text,uuid,text) to authenticated,service_role;

create or replace function public.layer4_publication_decide(
  p_entity_type text,p_entity_id uuid,p_target_scope text,p_event_type text,
  p_readiness_snapshot jsonb,p_overridden_checks jsonb,p_reason_code text,p_comment text default null,
  p_approval_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline','auth'
as $$
declare v_actor uuid:=auth.uid(); v_rank int; v_prev uuid; v_id uuid; v_email text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Admin role required for publication override' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then raise exception 'entity not found' using errcode='22023'; end if;
  if p_event_type not in ('publishable','not_publishable','revert') then raise exception 'invalid publication decision' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  select id into v_prev from pipeline.layer4_publication_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and target_scope=coalesce(nullif(trim(p_target_scope),''),'governed_publication')
   order by created_at desc,id desc limit 1;
  if p_event_type='revert' and v_prev is null then raise exception 'no publication override to revert' using errcode='22023'; end if;
  select email into v_email from auth.users where id=v_actor;
  insert into pipeline.layer4_publication_decisions(
    entity_type,entity_id,target_scope,event_type,readiness_snapshot,overridden_checks,
    reason_code,comment,actor_id,actor_email,supersedes_decision_id,approval_context
  ) values (
    p_entity_type,p_entity_id,coalesce(nullif(trim(p_target_scope),''),'governed_publication'),p_event_type,
    coalesce(p_readiness_snapshot,'{}'),coalesce(p_overridden_checks,'[]'),trim(p_reason_code),
    nullif(trim(coalesce(p_comment,'')),''),v_actor,v_email,v_prev,coalesce(p_approval_context,'{}')
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'publication_decision_id',v_id,'event_type',p_event_type,'publication_status_changed',false,'consumer_cutover_authorised',false);
end $$;
revoke all on function public.layer4_publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb) from public,anon;
grant execute on function public.layer4_publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb) to authenticated,service_role;

create or replace function security.layer4_publication_state_read(p_entity_type text,p_entity_id uuid,p_target_scope text default 'governed_publication')
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_last pipeline.layer4_publication_decisions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select * into v_last from pipeline.layer4_publication_decisions
  where entity_type=p_entity_type and entity_id=p_entity_id and target_scope=p_target_scope
  order by created_at desc,id desc limit 1;
  return jsonb_build_object(
    'target_scope',p_target_scope,
    'effective_decision',case when found and v_last.event_type<>'revert' then v_last.event_type else 'no_override' end,
    'decision_id',case when found then v_last.id else null end,
    'actor_id',case when found then v_last.actor_id else null end,
    'actor_email',case when found then v_last.actor_email else null end,
    'decided_at',case when found then v_last.created_at else null end,
    'reason_code',case when found then v_last.reason_code else null end,
    'comment',case when found then v_last.comment else null end,
    'readiness_snapshot',case when found then v_last.readiness_snapshot else '{}'::jsonb end,
    'overridden_checks',case when found then v_last.overridden_checks else '[]'::jsonb end
  );
end $$;

create or replace function security.provider_contact_disposition_current(p_provider_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rank int; v pipeline.provider_contact_dispositions%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select * into v from pipeline.provider_contact_dispositions where provider_id=p_provider_id order by created_at desc,id desc limit 1;
  if not found then return jsonb_build_object('disposition','pending_acquisition'); end if;
  return jsonb_build_object(
    'id',v.id,'disposition',v.disposition,'international_students_url',v.international_students_url,
    'contact_team_url',v.contact_team_url,'general_email',v.general_email,
    'named_contact_count',v.named_contact_count,'territory_contact_count',v.territory_contact_count,
    'source_urls',v.source_urls,'evidence_ids',v.evidence_ids,'layer3_interpretation_id',v.layer3_interpretation_id,
    'interpretation_source',v.interpretation_source,'observed_at',v.observed_at,'last_verified_at',v.last_verified_at
  );
end $$;

insert into pipeline.provider_contact_dispositions(
  provider_id,profile_id,disposition,international_students_url,contact_team_url,general_email,
  named_contact_count,territory_contact_count,source_urls,evidence_ids,
  interpretation_source,observed_at,last_verified_at
)
select
  p.provider_id,p.id,
  case when coalesce(c.contact_count,0)>0 then 'published_contact_found'
       when p.last_success_at is not null and coalesce(a.success_count,0)>0 then 'not_found_in_qualified_evidence'
       else 'pending_acquisition' end,
  case when p.base_url ~* '(international|study)' then p.base_url else null end,
  case when p.base_url ~* '(contact|international)' then p.base_url else null end,
  c.general_email,
  coalesce(c.named_count,0),
  coalesce(c.territory_count,0),
  coalesce(a.source_urls,'{}'::text[]),
  coalesce(c.evidence_ids,'{}'::uuid[]),
  'a15_reconciliation',
  p.last_run_at,
  p.last_success_at
from pipeline.provider_contact_profiles p
left join lateral (
  select
    count(*) contact_count,
    count(*) filter(where nullif(trim(o.full_name),'') is not null) named_count,
    count(*) filter(where nullif(trim(o.territory_text),'') is not null) territory_count,
    (array_agg(o.work_email order by (o.source_class='first_party') desc,o.last_verified_at desc) filter(where nullif(trim(o.work_email),'') is not null))[1] general_email,
    array_remove(array_agg(distinct o.evidence_id),null) evidence_ids
  from pipeline.provider_contact_observations o
  where o.provider_id=p.provider_id and o.is_current=true and o.verification_state<>'rejected'
) c on true
left join lateral (
  select
    count(*) filter(where a0.status='succeeded') success_count,
    array_remove(array_agg(distinct a0.metadata->>'source_url'),null) source_urls
  from pipeline.provider_contact_enrichment_attempts a0
  where a0.provider_id=p.provider_id and a0.request_type='first_party_contact_page'
) a on true
where not exists(select 1 from pipeline.provider_contact_dispositions d where d.profile_id=p.id);

-- Route the legacy Course scalar action through the overlay ledger while keeping the legacy
-- resolution row as a compatibility/audit bridge for existing review-decision foreign keys.
create or replace function security.layer4_course_scalar_resolve_impl(
  p_actor uuid,p_course_id uuid,p_field_code text,p_value jsonb,p_reason text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','security','catalogue','pipeline','auth'
as $$
declare v_overlay jsonb; v_prior jsonb; v_prev_id uuid; v_resolution_id uuid;
begin
  if p_field_code not in ('course_description','official_course_url','delivery_mode','duration') then
    raise exception 'field is not enabled for scalar Layer 4 editing' using errcode='22023';
  end if;
  v_prior:=security.layer4_underlying_value('course',p_course_id,p_field_code);
  v_overlay:=security.layer4_override_apply_impl(
    p_actor,'course',p_course_id,p_field_code,p_value,'human_resolution',p_reason,'{}'::uuid[],'{}'::jsonb
  );
  select id into v_prev_id from pipeline.layer4_course_field_resolutions
   where course_id=p_course_id and field_code=p_field_code and status='applied'
   order by created_at desc limit 1;
  if v_prev_id is not null then
    update pipeline.layer4_course_field_resolutions set status='superseded' where id=v_prev_id;
  end if;
  insert into pipeline.layer4_course_field_resolutions(
    course_id,field_code,prior_value,resolved_value,resolution_reason,actor_id,supersedes_id
  ) values (
    p_course_id,p_field_code,v_prior,p_value,trim(p_reason),p_actor,v_prev_id
  ) returning id into v_resolution_id;
  return v_overlay||jsonb_build_object('resolution_id',v_resolution_id,'legacy_resolution_bridge',true,'canonical_changed',false,'search_changed',false);
end $$;

create or replace function public.layer4_course_scalar_resolve(
  p_course_id uuid,p_field_code text,p_value jsonb,p_reason text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','catalogue','pipeline','auth'
as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  return security.layer4_course_scalar_resolve_impl(auth.uid(),p_course_id,p_field_code,p_value,p_reason);
end $$;
revoke all on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) from public,anon;
grant execute on function public.layer4_course_scalar_resolve(uuid,text,jsonb,text) to authenticated,service_role;

-- Extend provider contact read with explicit A16 disposition.
create or replace function security.admin_provider_contacts(p_provider_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','public','auth'
as $$
declare v_rank integer:=0; v_profile jsonb; v_items jsonb; v_events jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select jsonb_build_object(
    'profile_id',p.id,'enabled',p.enabled,'paused',p.paused,'base_url',p.base_url,'domain',p.domain,
    'last_run_at',p.last_run_at,'last_success_at',p.last_success_at,'last_error',p.last_error
  ) into v_profile from pipeline.provider_contact_profiles p where p.provider_id=p_provider_id;
  select coalesce(jsonb_agg(row_json order by source_priority,lower(coalesce(row_json->>'territory_text','')),lower(coalesce(row_json->>'job_title','')),lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb)
  into v_items from (
    select case o.source_class when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
      jsonb_build_object(
        'id',o.id,'source_class',o.source_class,'source_provider',o.source_provider,'full_name',o.full_name,
        'job_title',o.job_title,'team_name',o.team_name,'territory_text',o.territory_text,'territory_codes',o.territory_codes,
        'work_email',o.work_email,'work_phone',o.work_phone,'professional_profile_url',o.professional_profile_url,
        'source_url',o.source_url,'evidence_id',o.evidence_id,'verification_state',o.verification_state,'confidence',o.confidence,
        'observed_at',o.observed_at,'last_verified_at',o.last_verified_at,
        'source_priority',case o.source_class when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end
      ) row_json
    from pipeline.provider_contact_observations o
    where o.provider_id=p_provider_id and o.is_current=true and o.verification_state<>'rejected'
    order by 1,o.last_verified_at desc limit 50
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'event_type',e.event_type,'source_class',e.source_class,'before_state',e.before_state,
    'after_state',e.after_state,'detected_at',e.detected_at,'acknowledged',e.acknowledged
  ) order by e.detected_at desc),'[]'::jsonb)
  into v_events from (
    select * from pipeline.provider_contact_watch_events
    where provider_id=p_provider_id and event_type<>'new_contact' and coalesce(metadata->>'a15_quality_probe','false')<>'true'
    order by detected_at desc limit 20
  ) e;
  return jsonb_build_object(
    'profile',coalesce(v_profile,'{}'::jsonb),'items',coalesce(v_items,'[]'::jsonb),'events',coalesce(v_events,'[]'::jsonb),
    'disposition',security.provider_contact_disposition_current(p_provider_id),
    'summary',jsonb_build_object(
      'current_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and verification_state<>'rejected'),
      'first_party_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='first_party' and verification_state<>'rejected'),
      'enriched_contacts',(select count(*) from pipeline.provider_contact_observations where provider_id=p_provider_id and is_current=true and source_class='licensed_enrichment' and verification_state<>'rejected'),
      'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events e where e.provider_id=p_provider_id and e.acknowledged=false and e.event_type<>'new_contact' and coalesce(e.metadata->>'a15_quality_probe','false')<>'true')
    )
  );
end $$;

-- Extend existing Admin detail payloads with the effective Layer 4 overlay and separate publication state.
do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;
  if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;

  if position('layer4_effective_entity_read' in v_def)=0 then
    v_def:=replace(v_def,
      'return security.admin_provider_detail(v_id)||jsonb_build_object(''contextual_insights'',security.admin_contextual_insights(''provider'',v_id));',
      'return security.admin_provider_detail(v_id)||jsonb_build_object(''contextual_insights'',security.admin_contextual_insights(''provider'',v_id))||jsonb_build_object(''layer4'',security.layer4_effective_entity_read(''provider'',v_id))||jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''provider'',v_id));'
    );
    v_def:=replace(v_def,
      'return security.admin_campus_detail(v_id);',
      'return security.admin_campus_detail(v_id)||jsonb_build_object(''layer4'',security.layer4_effective_entity_read(''campus'',v_id))||jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''campus'',v_id));'
    );
    v_def:=replace(v_def,
      '||jsonb_build_object(''contextual_insights'',security.admin_contextual_insights(''course'',v_id));',
      '||jsonb_build_object(''contextual_insights'',security.admin_contextual_insights(''course'',v_id))||jsonb_build_object(''layer4'',security.layer4_effective_entity_read(''course'',v_id))||jsonb_build_object(''layer4_publication'',security.layer4_publication_state_read(''course'',v_id));'
    );
    execute v_def;
  end if;
end $$;

comment on table pipeline.layer4_override_decisions is 'A16 append-only Layer 4 effective-value override ledger. Source/canonical history is not overwritten.';
comment on table pipeline.layer4_publication_decisions is 'A16 separate append-only publication override decisions. Does not itself authorise Production/Website/Zoho cutover.';
comment on table pipeline.provider_contact_dispositions is 'A16 explicit AU/NZ Provider international-contact coverage/disposition history; absence is retained explicitly and contacts are never manufactured.';
