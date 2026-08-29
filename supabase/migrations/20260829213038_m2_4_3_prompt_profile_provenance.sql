begin;

alter table pipeline.layer3_interpretations
  add column if not exists profile_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists prompt_hash text,
  add column if not exists prompt_input_chars integer check (prompt_input_chars is null or prompt_input_chars>=0),
  add column if not exists output_chars integer generated always as (
    length(coalesce(raw_result #>> '{choices,0,message,content}',''))
  ) stored;

alter table pipeline.layer3_interpretations
  drop constraint if exists layer3_interpretations_prompt_hash_shape_chk;
alter table pipeline.layer3_interpretations
  add constraint layer3_interpretations_prompt_hash_shape_chk
  check (prompt_hash is null or prompt_hash ~ '^[0-9a-f]{64}$');

create or replace function public.layer3_execution_provenance_service(
  p_interpretation_id uuid,
  p_profile_snapshot jsonb,
  p_prompt_hash text,
  p_prompt_input_chars integer
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_row pipeline.layer3_interpretations%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_prompt_hash is null or p_prompt_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'valid sha256 prompt hash required';
  end if;
  if p_prompt_input_chars is null or p_prompt_input_chars<1 then
    raise exception 'positive prompt input length required';
  end if;
  if coalesce(jsonb_typeof(p_profile_snapshot),'null')<>'object' then
    raise exception 'profile snapshot object required';
  end if;

  update pipeline.layer3_interpretations
  set profile_snapshot=coalesce(p_profile_snapshot,'{}'::jsonb),
      prompt_hash=p_prompt_hash,
      prompt_input_chars=p_prompt_input_chars
  where id=p_interpretation_id
    and status in ('reserved','calling')
  returning * into v_row;

  if not found then raise exception 'interpretation is not provenance-writable'; end if;

  return jsonb_build_object(
    'ok',true,
    'interpretation_id',v_row.id,
    'prompt_hash',v_row.prompt_hash,
    'prompt_input_chars',v_row.prompt_input_chars,
    'prompt_profile_version',v_row.prompt_profile_version
  );
end $$;

revoke all on function public.layer3_execution_provenance_service(uuid,jsonb,text,integer)
  from public,anon,authenticated;
grant execute on function public.layer3_execution_provenance_service(uuid,jsonb,text,integer)
  to service_role;

commit;
