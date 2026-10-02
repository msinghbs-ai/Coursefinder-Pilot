-- CF-247 (Decision 227, 2 Oct 2026). Proposals parsed from each provider's English language policy and academic
-- calendar (worker coverage-sweep v0.9.5, parser provider-policy-v0.1.0, deterministic). A proposal changes nothing
-- in the catalogue; a Platform Admin approves it (English: provider default by study level, Decision 162 precedent).

create table if not exists pipeline.provider_policy_proposals (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  fact_source_id uuid not null references pipeline.provider_fact_sources(id),
  kind text not null check (kind in ('english_policy', 'intake_calendar')),
  parser text not null,
  content_hash text,
  evidence_id uuid,
  url text not null,
  style text,
  proposal jsonb not null,
  status text not null default 'proposed' check (status in ('proposed', 'no_values', 'approved', 'rejected', 'superseded')),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  apply_summary jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provider_policy_proposals_key unique (fact_source_id, parser, content_hash)
);
create index if not exists provider_policy_proposals_provider on pipeline.provider_policy_proposals(provider_id, kind, status);
alter table pipeline.provider_policy_proposals enable row level security;
revoke all on pipeline.provider_policy_proposals from public, anon, authenticated;

-- One proposal per document, parser and stored copy. A newer parse of the same document replaces an undecided older one.
create or replace function public.svc_provider_policy_record(p_source_id uuid, p_parsed jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare f pipeline.provider_fact_sources%rowtype; v_id uuid; v_status text; v_parser text := coalesce(p_parsed->>'parser', 'unknown');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id;
  if f.id is null or f.kind not in ('english_policy', 'intake_calendar') then raise exception 'not an English policy or calendar document'; end if;
  if jsonb_typeof(p_parsed) <> 'object' then raise exception 'parsed result must be an object'; end if;
  v_status := case
    when f.kind = 'english_policy' and coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb then 'proposed'
    when f.kind = 'intake_calendar' and jsonb_array_length(coalesce(p_parsed->'periods', '[]'::jsonb)) > 0 then 'proposed'
    else 'no_values' end;
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
  values (f.provider_id, f.id, f.kind, v_parser, f.content_hash, f.evidence_id, f.url, left(p_parsed->>'style', 40), p_parsed, v_status)
  on conflict on constraint provider_policy_proposals_key do update
     set proposal = excluded.proposal, style = excluded.style, evidence_id = excluded.evidence_id,
         status = case when pipeline.provider_policy_proposals.status in ('proposed', 'no_values') then excluded.status else pipeline.provider_policy_proposals.status end,
         updated_at = now()
  returning id, status into v_id, v_status;
  update pipeline.provider_policy_proposals set status = 'superseded', updated_at = now()
   where fact_source_id = f.id and id <> v_id and status in ('proposed', 'no_values');
  return jsonb_build_object('id', v_id, 'status', v_status);
end $f$;
revoke all on function public.svc_provider_policy_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_policy_record(uuid, jsonb) to service_role;
