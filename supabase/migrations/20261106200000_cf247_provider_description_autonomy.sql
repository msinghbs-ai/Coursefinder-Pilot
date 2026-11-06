-- CF-247 Provider Descriptions — Run & Validate and autonomous continuation (Platform Admin mission 4 Nov 2026).
-- Renumbered 5 Nov 2026 from 20261105010000 (that version is applied in production by v2.15.479, intake_preview_identity_lookup);
-- ownership transferred to Claude agent B by Platform Admin decision 5 Nov 2026 19:14. Body otherwise as qualified on 4 Nov.
-- Replaces: security.provider_description_validate_v1, security.provider_description_enqueue_v1, public.svc_provider_description_next, public.svc_provider_description_record, security.provider_description_fire_v1, security.layer4_provider_description_apply_impl (same existing reader and scheduler).
-- Retires: nothing (extends the existing reader, existing Layer 4 decisions and existing governed task mechanism).
-- No consumer API shape changes. No activation, country/type/provider scope widening, acquisition switch or budget increase.
-- The US$1 lifetime pilot ceiling remains a deliberate policy; it is not reset as a daily budget.

insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason)
values ('pipeline','pdesc.ui_preview_minutes','Provider descriptions: preview valid for','A saved provider-description preview expires after this long; prepare revalidates identity, description and stored evidence before fixing its members.','number','10'::jsonb,1,60,'minutes',990,'Provider descriptions','public.admin_provider_description_run_v1','Provider Description autonomy mission 4 Nov 2026: bounded reviewable previews')
on conflict (toolset_key,key) do nothing;

-- Run Now stays off until a person switches it on (CLAUDE.md: a passing qualification never switches anything on by itself).
-- This migration does NOT add provider-description-read to pipeline.run_now.jobs. Until the Platform Admin adds it on
-- Settings › Pipeline settings (with a reason), Run & Validate previews and saves cohorts, and Run parks as job_not_allowlisted.

insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason)
values('pipeline','pdesc.verbatim_span_max_chars','Provider descriptions: longest verbatim span','A description containing this many consecutive characters copied from an official quote is held; write a concise factual paraphrase and retain the exact supporting quote separately.','number','120'::jsonb,40,1000,'characters',991,'Provider descriptions','security.provider_description_validate_v1, public.svc_provider_description_next, worker provider_description','Provider Description autonomy mandate 4 Nov 2026: no long official passages copied verbatim') on conflict(toolset_key,key) do nothing;

insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason)
values('pipeline','pdesc.reason_min_chars','Provider descriptions: audit reason at least','An operator must supply a reason at least this long before fixing a cohort or explaining its evidence.','number','5'::jsonb,1,200,'characters',992,'Provider descriptions','public.admin_provider_description_run_v1, Provider Descriptions Run & Validate','Provider Description autonomy mandate 4 Nov 2026: governed audit reasons') on conflict(toolset_key,key) do nothing;

-- Platform Admin 5 Nov 2026 20:03 §2: "Approve stronger evidence-aware claim validation for campus, scholarship and guarantee
-- statements. Do not reject legitimate supported claims solely by keyword." These words get their own list, read only by
-- security.provider_description_validate_v1. pdesc.claim_words is NOT changed: security.course_description_check_v1 (course
-- descriptions) also reads it, and course descriptions keep their own behaviour. A word in this list never holds a sentence by
-- itself; it only triggers the evidence check in security.pdesc_claim_check_v1.
insert into pipeline.platform_toolset_settings(toolset_key,key,label,help,kind,value,min_value,max_value,unit,sort,section,used_by,reason)
values('pipeline','pdesc.evidence_claim_words','Provider descriptions: evidence-checked statements',
 'Campus, scholarship and guarantee words. A sentence that uses one (or its plural or tense: campuses, scholarships, guaranteed) is checked against its exact quote from the stored official page. It passes when the quote states the same thing; it is held only when the quote does not contain it, or the quote negates it ("no guarantee") and the sentence does not. Provider descriptions only; course descriptions keep pdesc.claim_words.',
 'list','["campus","scholarship","guarantee"]'::jsonb,null,null,'words',993,'Provider descriptions','security.provider_description_validate_v1 (provider descriptions only) via security.pdesc_claim_check_v1',
 'Platform Admin 5 Nov 2026 20:03 §2: evidence-aware campus, scholarship and guarantee validation; never a keyword-only rejection') on conflict(toolset_key,key) do nothing;

-- The evidence check for one word: null when the sentence does not use the word or its official quote supports it; otherwise the rule.
-- The quote is the sentence's own passage, already proved to be on the stored official page (on_page, exact-source match).
create or replace function security.pdesc_claim_check_v1(p_sentence text, p_quote text, p_term text) returns text
language sql immutable set search_path to '' as $function$
  with t as (select btrim(regexp_replace(lower(coalesce(p_term,'')),'[^a-z0-9#%]+',' ','g')) term),
  f as (select case when t.term ~ ' ' then array[t.term] else array[t.term, t.term||'s', t.term||'es', t.term||'d', t.term||'ed'] end forms from t where t.term<>''),
  hit as (select exists(select 1 from f, unnest(f.forms) x where security.pdesc_has_term_v1(p_sentence,x)) in_sentence,
                 exists(select 1 from f, unnest(f.forms) x where security.pdesc_has_term_v1(p_quote,x)) in_quote,
                 exists(select 1 from f, unnest(f.forms) x where lower(coalesce(p_quote,'')) ~ ('(\m(no(?!\s+matter)|not(?!\s+(only|just))|never|cannot|without|nor|none|neither)\M|n''t)(\W+\w+){0,2}\W+'||x||'\M')) negated_quote,
                 exists(select 1 from f, unnest(f.forms) x where lower(coalesce(p_sentence,'')) ~ ('(\m(no(?!\s+matter)|not(?!\s+(only|just))|never|cannot|without|nor|none|neither)\M|n''t)(\W+\w+){0,2}\W+'||x||'\M')) negated_sentence)
  select case when not hit.in_sentence then null
              when not hit.in_quote then 'unsupported_claim'
              when hit.negated_quote and not hit.negated_sentence then 'claim_negated_in_source'
              end from hit
$function$;
revoke all on function security.pdesc_claim_check_v1(text,text,text) from public,anon,authenticated;
comment on function security.pdesc_claim_check_v1(text,text,text) is 'Provider descriptions (Platform Admin 5 Nov 2026 20:03 §2): evidence-aware check of one pdesc.evidence_claim_words word. Null = not used or supported by the sentence''s own official quote (same word, plural or tense); unsupported_claim = the quote does not state it; claim_negated_in_source = the quote negates it and the sentence does not. Never a keyword-only rejection.';

-- Validation 5 Nov 2026 (decision 20:03 §2): number formats are normalised before a sentence's numbers are compared with its quote's.
-- Thousands separators (comma, space, no-break or thin space, apostrophe) are removed and "per cent"/"percent" is "%". On the quote side
-- number words zero to ninety-nine become digits ("four campuses" supports "4 campuses"); on the sentence side words are left alone, so
-- "one of the oldest" never becomes a numeric claim.
create or replace function security.pdesc_number_norm_v1(p text, p_words boolean) returns text
language plpgsql immutable set search_path to '' as $function$
declare v text := lower(coalesce(p,'')); u text[] := array['one','two','three','four','five','six','seven','eight','nine'];
 teens text[] := array['ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'];
 tens text[] := array['twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety']; i int; k int;
begin
 v := regexp_replace(v, '\m(per\s?cent|percent)\M', '%', 'g');
 v := regexp_replace(v, '([0-9])[,\s   ''](?=[0-9]{3}([^0-9]|$))', '\1', 'g');
 if p_words then
  for i in 1..array_length(tens,1) loop
   for k in 1..array_length(u,1) loop
    v := regexp_replace(v, '\m'||tens[i]||'[-\s]'||u[k]||'\M', ((i+1)*10+k)::text, 'g');
   end loop;
   v := regexp_replace(v, '\m'||tens[i]||'\M', ((i+1)*10)::text, 'g');
  end loop;
  for i in 1..array_length(teens,1) loop v := regexp_replace(v, '\m'||teens[i]||'\M', (i+9)::text, 'g'); end loop;
  for i in 1..array_length(u,1) loop v := regexp_replace(v, '\m'||u[i]||'\M', i::text, 'g'); end loop;
  v := regexp_replace(v, '\mzero\M', '0', 'g');
 end if;
 return v;
end $function$;
revoke all on function security.pdesc_number_norm_v1(text,boolean) from public,anon,authenticated;
comment on function security.pdesc_number_norm_v1(text,boolean) is 'Provider descriptions (validation 5 Nov 2026, decision 20:03 §2): number format normalisation for unsupported_numeric_claim. Never a keyword-only or format-only rejection.';

-- Validation 5 Nov 2026 (decision 20:03 §2): support of a sentence by the present-tense part of its quote. Clauses are split at punctuation and at
-- today/now/currently/but/while/whereas; clauses with a historic marker are left out. Generic institution nouns are not counted as the claim.
create or replace function security.pdesc_present_support_v1(p_sentence text, p_quote text) returns numeric
language sql immutable set search_path to '' as $function$
  select security.pdesc_support_v1(
    regexp_replace(coalesce(p_sentence,''), '\m(university|universities|college|colleges|institute|institution|polytechnic|school)\M', ' ', 'gi'),
    coalesce((select string_agg(c, ' ') from regexp_split_to_table(lower(coalesce(p_quote,'')), '[;:.!?,]|\m(today|now|currently|nowadays|but|while|whereas)\M') c
              where c !~ '\m(former|formerly|previously|renamed|closed|merged|ceased|became)\M' and c !~ 'was known as'), ''))
$function$;
revoke all on function security.pdesc_present_support_v1(text,text) from public,anon,authenticated;
comment on function security.pdesc_present_support_v1(text,text) is 'Provider descriptions (validation 5 Nov 2026, decision 20:03 §2): pdesc_support_v1 of the sentence against the non-historic clauses of its quote; historic_claim_context holds only when this is below pdesc.support_min_share.';

create table if not exists pipeline.provider_description_cohorts (
 id uuid primary key default gen_random_uuid(),
 requested_by uuid not null references auth.users(id),
 state text not null default 'preview' check (state in ('preview','prepared','started')),
 selection jsonb not null,
 snapshot jsonb not null,
 reason text,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null,
 prepared_at timestamptz,
 verified_at timestamptz,
 verification jsonb,
 run_id uuid references pipeline.admin_jobs(id),
 request_key uuid not null default gen_random_uuid() unique
);
comment on table pipeline.provider_description_cohorts is 'Provider Description autonomy 4 Nov 2026: actor-bound saved previews and immutable bounded cohorts; queue and dispatch through the existing provider-description-read job. No admissions or consumer API data.';
create table if not exists pipeline.provider_description_cohort_members (
 cohort_id uuid not null references pipeline.provider_description_cohorts(id),
 provider_id uuid not null references catalogue.providers(id),
 evidence_id uuid references pipeline.evidence_artifacts(id),
 read_id uuid references pipeline.provider_description_reads(id),
 pick integer not null check (pick > 0),
 snapshot jsonb not null,
 primary key (cohort_id,provider_id), unique(cohort_id,pick)
);
comment on table pipeline.provider_description_cohort_members is 'Provider Description autonomy 4 Nov 2026: fixed provider identities, official evidence and before/proposal snapshots for a governed saved Run Now; read_id links the existing reader and Layer 4 lineage.';
alter table pipeline.provider_description_cohorts enable row level security;
alter table pipeline.provider_description_cohort_members enable row level security;
revoke all on pipeline.provider_description_cohorts,pipeline.provider_description_cohort_members from public,anon,authenticated;
create index if not exists provider_description_cohorts_requester_idx on pipeline.provider_description_cohorts(requested_by,created_at desc);
create index if not exists provider_description_members_read_idx on pipeline.provider_description_cohort_members(read_id);

-- Provider-description-specific identity gate; existing identity/lifecycle controls remain authoritative.
create or replace function security.provider_description_identity_snapshot_v1(p_provider uuid) returns jsonb
language sql stable security definer set search_path to '' as $function$
 select jsonb_strip_nulls(jsonb_build_object('canonical_name',p.canonical_name,'display_name',p.display_name,'provider_type_id',p.provider_type_id,'country_id',p.country_id,'website',p.website))
 from catalogue.providers p where p.id=p_provider
$function$;
revoke all on function security.provider_description_identity_snapshot_v1(uuid) from public,anon,authenticated;

create or replace function security.provider_description_identity_v1(p_provider uuid, p_url text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare p catalogue.providers%rowtype; v_finding text; v_other uuid;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null or p.lifecycle_status <> 'active' or p.publication_status <> 'published'
     or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     or security.provider_lifecycle_held_v1(p_provider) then
    return jsonb_build_object('ok', false, 'rule', 'provider_inactive', 'reason', 'The provider is not active and published, or its lifecycle is held.');
  end if;
  select f.check_code into v_finding from pipeline.provider_identity_findings f
   where f.provider_id = p_provider and f.state = 'open'
   order by f.check_code limit 1;
  if v_finding is not null then
    return jsonb_build_object('ok', false, 'rule', 'identity_' || v_finding,
      'reason', 'An existing provider identity finding requires resolution: ' || v_finding);
  end if;
  if security.provider_page_host_v1(p_provider, p_url) <> 'own' then
    return jsonb_build_object('ok', false, 'rule', 'wrong_host', 'reason', 'The source is not on an approved provider host.');
  end if;
  -- Even an own host is ambiguous when it is another current provider's primary host.
  -- Never infer that a university and similarly named college are interchangeable.
  select o.id into v_other from catalogue.providers o
   where o.id <> p_provider and o.lifecycle_status = 'active'
     and security.site_host_v1(o.website) = security.site_host_v1(p_url)
     and security.site_host_v1(p_url) is not null
   order by o.id limit 1;
  if v_other is not null then
    return jsonb_build_object('ok', false, 'rule', 'provider_host_conflict', 'conflicting_provider_id', v_other,
      'reason', 'Another active provider holds the source host; exact provider identity requires resolution.');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'identity_clear');
end $function$;
revoke all on function security.provider_description_identity_v1(uuid,text) from public, anon, authenticated;
comment on function security.provider_description_identity_v1(uuid,text) is 'Provider descriptions: existing active/published, hidden and lifecycle controls; unresolved identity findings and another current provider primary host refuse extraction and admission. No identity or eligibility authority is granted.';

-- A worker reserves a conservative quoted maximum before a paid model call. Accrued spend and all live reservations share the existing caps.
alter table pipeline.provider_description_reads add column if not exists consumer_checked_at timestamptz, add column if not exists zoho_published_at timestamptz, add column if not exists consumer_checks jsonb;
comment on column pipeline.provider_description_reads.consumer_checked_at is 'Last actual bounded Website/Zoho read-back; distinct from source verification and human admission time.';
comment on column pipeline.provider_description_reads.zoho_published_at is 'First exact provider identity and approved description publication proof from the existing Zoho provider route. consumer_checked_at and consumer_checks hold current verification separately; Website proof alone never proves Zoho.';
alter table pipeline.provider_description_reads add column if not exists ai_calls integer not null default 0 check(ai_calls>=0);
comment on column pipeline.provider_description_reads.ai_calls is 'Actual model calls reported by the worker after it starts the approved provider-description request; pre-AI source and budget holds do not count. Unknown interrupted calls are shown separately through retained cost reservations.';
alter table pipeline.provider_description_reads add column if not exists reserved_usd numeric not null default 0 check(reserved_usd>=0);
comment on column pipeline.provider_description_reads.reserved_usd is 'Provider descriptions: conservative model-price upper bound reserved before the worker calls the pinned model. Cleared when actual cost is recorded; unknown-cost reservations remain charged against the ceiling until authoritative actual cost settles, including interrupted leases.';
create or replace function public.svc_provider_description_reserve_v1(p_item uuid,p_model text,p_max_cost numeric,p_source_hash text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r pipeline.provider_description_reads%rowtype; v_model text; v_spent numeric; v_today numeric; v_reserved numeric; v_cap numeric; v_daily numeric; v_source_hash text;
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext('cf247 provider description spend')); -- fixed: serialize reservations across reader calls.
 select * into r from pipeline.provider_description_reads where id=p_item for update;
 if r.id is null or r.state<>'reading' or r.leased_until<=now() then return jsonb_build_object('ok',false,'reason','no_active_read_lease'); end if;
 select model_identifier into v_model from pipeline.central_ai_settings where id=1;
 if p_model is distinct from v_model or p_max_cost is null or p_max_cost<=0 then return jsonb_build_object('ok',false,'reason','invalid_pinned_model_price_quote'); end if;
 v_source_hash:=coalesce(nullif(p_source_hash,''),(select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(r.provider_id)));
 if v_source_hash is null then return jsonb_build_object('ok',false,'reason','no_source_version_before_ai'); end if;
 if exists(select 1 from pipeline.provider_description_reads rejected where rejected.provider_id=r.provider_id and rejected.state='rejected' and rejected.content_hash=v_source_hash) then return jsonb_build_object('ok',false,'reason','unchanged_rejected_evidence'); end if;
 if not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1(v_source_hash,p_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) then return jsonb_build_object('ok',false,'reason','recovery_knowledge_unchanged_failure'); end if;
 if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then return jsonb_build_object('ok',false,'reason','identity_changed_after_lease'); end if;
 if r.reserved_usd>0 then return jsonb_build_object('ok',false,'reason','existing_cost_reservation_uncertain','ai_calls',r.ai_calls,'reserved_usd',r.reserved_usd); end if;
 if security.pipeline_num_v1('pdesc.enabled',0)<1 or not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('ok',false,'reason','ai_refused'); end if;
 select coalesce(sum(cost_usd),0),coalesce(sum(cost_usd) filter(where at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0) into v_spent,v_today from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening';
 select coalesce(sum(reserved_usd),0) into v_reserved from pipeline.provider_description_reads where reserved_usd>0 and id<>r.id;
 v_cap:=security.pipeline_num_v1('pdesc.ai_usd_max',1);
 v_daily:=coalesce((security.toolset_setting('openrouter','guard_provider_description')#>>'{}')::numeric,1);
 if v_spent+v_reserved+p_max_cost>v_cap then return jsonb_build_object('ok',false,'reason','ai_ceiling','remaining_usd',greatest(0,v_cap-v_spent-v_reserved)); end if;
 if v_today+v_reserved+p_max_cost>v_daily then return jsonb_build_object('ok',false,'reason','ai_daily_guard','remaining_usd',greatest(0,v_daily-v_today-v_reserved)); end if;
 update pipeline.provider_description_reads set reserved_usd=p_max_cost where id=r.id;
 return jsonb_build_object('ok',true,'reserved_usd',p_max_cost,'remaining_usd',greatest(0,v_cap-v_spent-v_reserved-p_max_cost));
end $function$;
revoke all on function public.svc_provider_description_reserve_v1(uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function public.svc_provider_description_reserve_v1(uuid,text,numeric,text) to service_role;
comment on function public.svc_provider_description_reserve_v1(uuid,text,numeric,text) is 'Provider descriptions: service-only pre-call price reservation for the pinned approved model, inside the unchanged lifetime pilot ceiling and daily lane guard. Actual ledger cost replaces the reservation on record; no new spending authority.';

-- Existing recovery knowledge, existing platform lane. Proposal yield and actual human admission are separate patterns.
insert into pipeline.ops_remedy_knowledge(code,lane,title,authority,performed_by,expected_outcome,no_retry_condition,reuse_conditions,seeded_from)
values('provider_description:official_about','platform','Provider description: grounded official About-page proposal','auto','platform','A correctly bound official stored source produces a validated proposal for individual human review.','Do not repeat unchanged evidence after an ineffective read or a human rejection.','Reuse when official source, approved model, prompt or validation contract changes.','Provider Description autonomy mandate 4 Nov 2026'),
('provider_description:human_admission','platform','Provider description: authorised admission and consumer verification','layer4_human','layer4_human','A human Layer 4 approval admits the exact grounded description; actual consumer read-back is measured separately.','No automatic reviewer impersonation; no approval over changed identity, evidence or manual locks.','Reuse only through the existing authorised Layer 4 decision.','Provider Description autonomy mandate 4 Nov 2026') on conflict(code) do nothing;

create or replace function security.provider_description_signature_v1(p_hash text,p_model text,p_prompt text) returns text
language sql stable security definer set search_path to '' as $function$
 select md5(coalesce(p_hash,'')||'|'||coalesce(p_model,'')||'|'||coalesce(p_prompt,'provider-description-v2')||'|'||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||coalesce((select jsonb_object_agg(key,value order by key)::text from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('pdesc.min_quote_chars','pdesc.min_sentences','pdesc.max_sentences','pdesc.min_chars','pdesc.max_chars','pdesc.support_min_share','pdesc.duplicate_share','pdesc.source_max_age_days','pdesc.verbatim_span_max_chars','pdesc.claim_words','pdesc.evidence_claim_words','pdesc.superlatives')),''))
$function$;
revoke all on function security.provider_description_signature_v1(text,text,text) from public,anon,authenticated;

create or replace function security.provider_description_learning_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare v_sig text; v_human boolean;
begin
 if new.rule in ('review_full','recovery_knowledge_unchanged_failure','source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') or new.state is not distinct from old.state or new.content_hash is null or new.state not in ('proposed','held','rejected','admitted','verified') then return new; end if;
 v_sig:=security.provider_description_signature_v1(new.content_hash,new.model,new.prompt_version);
 v_human:=new.state='admitted';
 perform security.ops_learning_record_v1(jsonb_build_object('code',case when v_human then 'provider_description:human_admission' else 'provider_description:official_about' end,
 'entity',new.provider_id::text,'evidence_signature',v_sig,'performed_by',case when v_human then 'layer4_human' else 'platform' end,
 'success',new.state in ('proposed','admitted','verified'),'stage_advanced',new.state in ('proposed','admitted','verified'),
 'cost_usd',case when v_human then 0 else new.cost_usd end,'expected',case when v_human then 'Authorised exact description admitted; consumer verification separate' else 'Official evidence-backed description proposal' end,
 'observed',jsonb_build_object('read_id',new.id,'state',new.state,'rule',new.rule,'review_item_id',new.review_item_id,'admitted',new.state='admitted','website_published',new.published_at is not null),
 'evidence',jsonb_build_object('evidence_id',new.evidence_id,'content_hash',new.content_hash,'model',new.model,'prompt_version',new.prompt_version,'reason',new.reason)));
 return new;
end $function$;
revoke all on function security.provider_description_learning_trg_v1() from public,anon,authenticated;
create or replace trigger provider_description_learning after update of state on pipeline.provider_description_reads for each row execute function security.provider_description_learning_trg_v1();

create or replace function security.provider_description_approved_lineage_v1(p_provider uuid,p_text text) returns uuid
language sql stable security definer set search_path to '' as $function$
 select li.id from pipeline.provider_description_reads h join pipeline.layer4_review_items li on li.id=h.review_item_id
 where h.provider_id=p_provider and h.state in ('admitted','superseded') and li.status in ('approved','edited_approved')
 and h.proposal->>'description'=p_text and li.proposed_value->>'description'=p_text
 order by h.created_at desc,h.id desc limit 1
$function$;
revoke all on function security.provider_description_approved_lineage_v1(uuid,text) from public,anon,authenticated;

create or replace function security.provider_description_selection_v1(p_args jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_size int := coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int);
 v_max int := least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int;
 v_cc text := upper(nullif(btrim(p_args->>'country'),'')); v_type text := nullif(btrim(coalesce(p_args->>'provider_type',p_args->>'type')),'');
 v_provider uuid := nullif(p_args->>'provider_id','')::uuid; v_filter text := coalesce(nullif(coalesce(p_args->>'description_state',p_args->>'filter'),''),'missing');
 v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb;
begin
 if v_size < 1 or v_size > v_max then raise exception 'cohort size must be between 1 and %',v_max using errcode='22023'; end if;
 if v_mode not in ('stored','approved') then raise exception 'unsupported processing mode' using errcode='22023'; end if;
 if v_mode='approved' and security.pipeline_num_v1('pdesc.acquire_direct',0)<1 then raise exception 'acquisition has not been authorised' using errcode='42501'; end if;
 if v_filter not in ('missing','stale','failed','all') then raise exception 'unsupported description selection' using errcode='22023'; end if;
 with candidates as materialized (
 select p.*,k.iso_alpha2::text cc,t.code typ,
  (select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') active_course_count,
  security.provider_description_stored_v1(p.id) stored_id
 from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id
 where (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
  -- Scope is governed by the existing policy. The UI selector can narrow it, never widen it.
  and security.provider_description_scope_v1(p.id)
 ), rows as (
 select p.*,r.id last_read_id,r.state read_state,r.rule read_rule,r.reason read_reason,r.proposal,r.checks,r.review_item_id,(select li.created_at from pipeline.layer4_review_items li where li.id=r.review_item_id) review_created_at,r.model,r.cost_usd,r.tries,r.updated_at read_updated_at,r.last_verified_at read_last_verified_at,
 a.source_url,a.id evidence_id,coalesce(a.captured_at,a.created_at) source_captured_at,coalesce(a.content_hash,a.id::text) source_hash,
 case
  when p.lifecycle_status<>'active' then 'provider_inactive'
  when p.publication_status<>'published' or exists(select 1 from security.provider_hidden_v1 h where h.provider_id=p.id) then 'provider_not_published'
  when exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p.id and l.field in ('description','p_description','all')) then 'manual_lock'
  when nullif(btrim(p.description),'') is not null and security.provider_description_approved_lineage_v1(p.id,p.description) is null then 'manual_description'
  when nullif(btrim(p.description),'') is not null and (select z.proposal->>'description' from pipeline.provider_description_reads z where z.provider_id=p.id and z.state in ('admitted','verified') order by coalesce(z.last_verified_at,z.updated_at) desc,z.id desc limit 1) is distinct from p.description then 'manual_description_changed'
  when r.state in ('queued','reading','proposed') then 'existing_work'
  when r.state='dead_letter' then 'dead_letter_requires_retry'
  when coalesce(r.reserved_usd,0)>0 then 'cost_reservation_uncertain'
  when r.state='held' and r.rule='review_full' then 'review_capacity_parked'
  when r.state='held' and r.rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') then 'policy_retry_parked'
  when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) then 'unchanged_unsuitable_evidence'
  when r.state in ('held','rejected') and r.updated_at>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'retry_wait'
  when r.state in ('admitted','verified') and r.proposal->'sentences' is not null and a.id is not null
   and security.provider_description_validate_v1(p.id,r.source_url,r.source_captured_at,jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))->>'outcome' not in ('propose','verified')
   then case when coalesce(a.content_hash,a.id::text) is distinct from r.content_hash then 'invalid_description' else 'invalid_description_unchanged_evidence' end
  when r.state in ('admitted','verified') and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'
  when a.id is not null and not (security.provider_description_identity_v1(p.id,a.source_url)->>'ok')::boolean then security.provider_description_identity_v1(p.id,a.source_url)->>'rule'
  when a.id is not null and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select model_identifier from pipeline.central_ai_settings where id=1),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) then 'recovery_knowledge_unchanged_failure'
  when v_mode='stored' and a.id is null then 'no_verified_stored_source'
  else 'eligible' end eligibility_reason
 from candidates p left join lateral(select x.* from pipeline.provider_description_reads x where x.provider_id=p.id order by x.created_at desc,x.id desc limit 1) r on true
 left join pipeline.evidence_artifacts a on a.id=p.stored_id
 ), shaped as (
 select jsonb_build_object('provider_id',rows.id,'provider',coalesce(display_name,canonical_name),'name',coalesce(display_name,canonical_name),'stable_key',stable_key,
 'registration',coalesce((select jsonb_agg(jsonb_build_object('registration_id',pr.id,'scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'valid_to',pr.valid_to,'checked_at',pr.checked_at,'source_id',pr.source_id,'evidence_id',pr.evidence_id) order by pr.registration_scheme,pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=rows.id),'[]'::jsonb),'country',cc,'type',typ,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
 'active_course_count',active_course_count,'current_description',description,'proposed_description',proposal->>'description','sentences',proposal->'sentences','checks',checks,
 'source_url',source_url,'evidence_id',evidence_id,'source_hash',source_hash,'source_captured_at',source_captured_at,'source_age_days',extract(epoch from (now()-source_captured_at))/86400,
 'evidence_version',source_hash,'approval_status',case when read_state='proposed' then 'pending' else read_state end,'manual_locked',eligibility_reason='manual_lock','last_read_id',last_read_id,'state',coalesce(read_state,'missing'),'rule',read_rule,'reason',read_reason,'review_item_id',review_item_id,'review_created_at',review_created_at,
 'model',coalesce(model,(select c.model_identifier from pipeline.central_ai_settings c where c.id=1)),'cost_usd',cost_usd,'tries',tries,
 'eligible',eligibility_reason in ('eligible','invalid_description'),'eligibility_reason',eligibility_reason,'required_approval','Individual human Layer 4 decision','last_verified_at',read_last_verified_at) row,
 eligibility_reason,active_course_count,coalesce(display_name,canonical_name) nm
 from rows where v_filter='all' or (v_filter='missing' and nullif(btrim(description),'') is null)
 or (v_filter='stale' and nullif(btrim(description),'') is not null)
 or (v_filter='failed' and read_state in ('held','dead_letter','rejected'))
 ) select coalesce(jsonb_agg(row order by eligibility_reason in ('eligible','invalid_description') desc,active_course_count desc,nm),'[]'::jsonb) into v_rows
 from (select * from shaped order by eligibility_reason in ('eligible','invalid_description') desc,active_course_count desc,nm limit v_size) b;
 return jsonb_build_object('providers',v_rows,'selected',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),
 'eligible',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),'bounded',true,'size',v_size,'as_at',now(),
 'exclusions',(select coalesce(jsonb_agg(jsonb_build_object('provider_id',x->>'provider_id','reason',x->>'eligibility_reason')),'[]') from jsonb_array_elements(v_rows) x where not (x->>'eligible')::boolean));
end $function$;
revoke all on function security.provider_description_selection_v1(jsonb) from public,anon,authenticated;

-- Actual existing consumer routes, isolated per provider so a failed projection never hides the rest of a cohort.
create or replace function security.provider_description_consumer_read_v1(p_consumer text,p_key text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v jsonb; v_error text;
begin
 if p_consumer='website' then v:=public.website_v2_provider(p_key);
 elsif p_consumer='zoho' then v:=public.zoho_v2_provider(p_key);
 else raise exception 'unsupported consumer'; end if;
 return v;
exception when others then
 get stacked diagnostics v_error=message_text;
 return jsonb_build_object('error',jsonb_build_object('code',sqlstate,'message',v_error),'consumer',p_consumer);
end $function$;
revoke all on function security.provider_description_consumer_read_v1(text,text) from public,anon,authenticated;

-- Integration Controller decision 5 Nov 2026 (item 3): no second writer of pipeline.website_sync_items. The existing website-sync-check
-- scan (security.website_sync_check_v1, every minute) is the only writer; it picks up an approved description like any catalogue change.

create or replace function security.provider_description_run_result_v1(p_cohort uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_rows jsonb; c pipeline.provider_description_cohorts%rowtype;
begin
 select * into c from pipeline.provider_description_cohorts where id=p_cohort;
 if c.id is null then raise exception 'unknown cohort' using errcode='22023'; end if;
 select coalesce(jsonb_agg(m.snapshot || case when m.snapshot->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(m.snapshot->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',m.snapshot->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(m.snapshot->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end || jsonb_build_object('read_id',r.id,'approval_status',case when r.state='proposed' then 'pending human Layer 4 decision' when r.state='admitted' and lineage.approved_item_id is not null then 'authorised admission' when r.state='verified' and lineage.approved_item_id is not null then 'previously approved; source reverified' when r.state is null then m.snapshot->>'approval_status' else r.state end,'state',coalesce(r.state,m.snapshot->>'state'),'rule',r.rule,'reason',r.reason,
 'proposed_description',r.proposal->>'description','sentences',r.proposal->'sentences','checks',r.checks,'review_item_id',coalesce(r.review_item_id,lineage.approved_item_id),'review_created_at',(select li.created_at from pipeline.layer4_review_items li where li.id=coalesce(r.review_item_id,lineage.approved_item_id)),'approval_lineage_item_id',lineage.approved_item_id,'review_item_created_this_read',r.review_item_id is not null,'existing_approved_verified',r.state='verified' and lineage.approved_item_id is not null,
 'source_url',coalesce(r.source_url,m.snapshot->>'source_url'),'evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_captured_at',coalesce(to_jsonb(r.source_captured_at),m.snapshot->'source_captured_at'),
 'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'evidence_version',coalesce(r.content_hash,m.snapshot->>'source_hash'),'model',coalesce(r.model,m.snapshot->>'model'),'prompt_version',r.prompt_version,'worker',r.worker,'ai_calls',r.ai_calls,'reserved_usd',r.reserved_usd,'cost_uncertain',coalesce(r.reserved_usd,0)>0,'cost_usd',r.cost_usd,'tries',r.tries,'read_completed',r.read_via is not null and r.content_hash is not null,
 'current_description',p.description,'admitted',r.state='admitted','published_at',r.published_at,'zoho_published_at',r.zoho_published_at,'consumer_checked_at',r.consumer_checked_at,'consumer_checks',r.consumer_checks,'last_verified_at',r.last_verified_at,
 'publication',jsonb_build_object('catalogue',jsonb_build_object('status',case when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) and p.description=r.proposal->>'description' then 'verified' when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) then 'mismatch' else 'awaiting_admission' end),'website',jsonb_build_object('status',case when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) and web.body->'item'->>'description'=p.description and web.body->'item'->>'provider_id'=p.stable_key and p.description=r.proposal->>'description' then 'verified' when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) then 'mismatch' else 'awaiting_admission' end),'zoho',jsonb_build_object('status',case when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) and zoho.body->'item'->>'description'=p.description and zoho.body->'item'->>'provider_id'=p.stable_key and p.description=r.proposal->>'description' then 'verified' when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) and zoho.body?'error' then 'error' when (r.state in ('admitted','verified') and lineage.approved_item_id is not null) then 'mismatch' else 'awaiting_admission' end,'description',zoho.body->'item'->>'description','read_at',now(),'api_version',zoho.body->>'api_version','error',zoho.body->'error'),'as_at',now()),
 'website',jsonb_build_object('status',case when r.state not in ('admitted','verified') or r.state is null or lineage.approved_item_id is null then 'awaiting_admission' when web.body->'item'->>'description'=p.description and web.body->'item'->>'provider_id'=p.stable_key and p.description=r.proposal->>'description' then 'verified' else 'mismatch' end,'description',web.body->'item'->>'description','read_at',now()),
 'zoho',jsonb_build_object('status',case when r.state not in ('admitted','verified') or r.state is null or lineage.approved_item_id is null then 'awaiting_admission' when zoho.body->'item'->>'description'=p.description and zoho.body->'item'->>'provider_id'=p.stable_key and p.description=r.proposal->>'description' then 'verified' when zoho.body?'error' then 'error' else 'mismatch' end,'description',zoho.body->'item'->>'description','read_at',now(),'api_version',zoho.body->>'api_version','error',zoho.body->'error')) order by m.pick),'[]') into v_rows
 from pipeline.provider_description_cohort_members m join catalogue.providers p on p.id=m.provider_id
 left join pipeline.provider_description_reads r on r.id=m.read_id
 left join lateral(select security.provider_description_approved_lineage_v1(p.id,p.description) approved_item_id) lineage on true
 left join lateral(select security.provider_description_consumer_read_v1('website',p.stable_key) body where (r.state in ('admitted','verified') and lineage.approved_item_id is not null)) web on true
 left join lateral(select security.provider_description_consumer_read_v1('zoho',p.stable_key) body where (r.state in ('admitted','verified') and lineage.approved_item_id is not null)) zoho on true
 where m.cohort_id=c.id;
 return jsonb_build_object('cohort_id',c.id,'state',c.state,'can_run',c.state='prepared' and c.run_id is null and jsonb_array_length(v_rows)<=least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,'reason_code',case when c.state='prepared' and c.run_id is null and jsonb_array_length(v_rows)>least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int then 'current_cap_changed' end,'selection',c.selection,'scope',c.selection,'requested_by',c.requested_by,'reason',c.reason,'created_at',c.created_at,'verified_at',c.verified_at,'last_verification',c.verification,'run_id',c.run_id,
 'providers',v_rows,'as_at',now(),'totals',jsonb_build_object('selected',jsonb_array_length(v_rows),
 'evidence_read',(select count(*) from jsonb_array_elements(v_rows) x where coalesce((x->>'read_completed')::boolean,false)),
 'proposed',(select count(*) from jsonb_array_elements(v_rows) x where x->>'state' in ('proposed','admitted','rejected')),
 'validation_failed',(select count(*) from jsonb_array_elements(v_rows) x where x->>'state' in ('held','dead_letter')),
 'layer4_created',(select count(*) from jsonb_array_elements(v_rows) x where coalesce((x->>'review_item_created_this_read')::boolean,false)),
 'human_decisions_required',(select count(*) from jsonb_array_elements(v_rows) x where x->>'state'='proposed'),
 'verified_existing',(select count(*) from jsonb_array_elements(v_rows) x where coalesce((x->>'existing_approved_verified')::boolean,false)),'admitted',(select count(*) from jsonb_array_elements(v_rows) x where x->>'state'='admitted'),
 'website_verified',(select count(*) from jsonb_array_elements(v_rows) x where x->'website'->>'status'='verified'),
 'cost_usd',(select coalesce(sum((x->>'cost_usd')::numeric),0) from jsonb_array_elements(v_rows) x),'reserved_usd',(select coalesce(sum((x->>'reserved_usd')::numeric),0) from jsonb_array_elements(v_rows) x),'actual_ai_calls',(select coalesce(sum((x->>'ai_calls')::int),0) from jsonb_array_elements(v_rows) x),
 'retries',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'tries')::int>1)),
 'zoho_verified',(select count(*) from jsonb_array_elements(v_rows) x where x->'zoho'->>'status'='verified'),'runs',coalesce((select jsonb_agg(jsonb_build_object('run_id',j.id,'state',j.state,'outcome',j.outcome,'created_at',j.created_at,'started_at',j.started_at,'finished_at',j.finished_at,'result',j.result)) from pipeline.admin_jobs j where j.id=c.run_id),'[]'));
end $function$;
revoke all on function security.provider_description_run_result_v1(uuid) from public,anon,authenticated;

-- Exact production-before and isolated PostgreSQL 17.6 after definitions; a marker is never a drift exemption.
do $guard$
declare x record;
begin
 for x in select * from (values
 ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)','528d5a3d2e3780fcb58e2c19db31c199','b4959fe6f0daad62b93c83c1feeea7e4'),
 ('security.provider_description_enqueue_v1()','97e6b926a545c4032159f9dbf52e3cf3','0a1897bb7f56697a9f01d4ec3e8befc0'),
 ('public.svc_provider_description_next(integer)','5342ae3f9279f6c2ec0849ec4fe0fffd','559407dc479753698b858231b2e7eb93'),
 ('public.svc_provider_description_record(jsonb)','d5aec36ddd55c4a0bdc823fb8a02fec0','d95f0bafc894b662468a309254544444'),
 ('security.provider_description_fire_v1()','8f5918c9c26445d9347988d850aba6f5','b334fbefe8a7fb2b8cfd2feda570a616'),
 ('security.layer4_provider_description_apply_impl(uuid,uuid,jsonb,text)','875b25c4f35568cb9ac6379812546d42','97685b737007410288297dea9d650d2a')) v(sig,before_hash,after_hash) loop
 if md5(pg_get_functiondef(x.sig::regprocedure)) not in (x.before_hash,x.after_hash) then
 raise exception 'provider description dependency drift: %; Controller reconciliation required',x.sig;
 end if;
 end loop;
end $guard$;

create or replace function security.provider_description_enqueue_v1() returns integer
language plpgsql security definer set search_path to '' as $function$
-- provider-description-autonomy-v1
 declare v_n int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 insert into pipeline.provider_description_reads(provider_id)
 select (x->>'provider_id')::uuid from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,
 'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end))->'providers') x
 where (x->>'eligible')::boolean on conflict do nothing;
 get diagnostics v_n=row_count; return v_n;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v jsonb; v_model text; v_pending int; v_spent numeric; v_fc_used int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('idle', true, 'reason', 'off', 'items', '[]'::jsonb); end if;
  -- Validation 5 Nov 2026: a worker leases only through public.svc_provider_description_lease_v1 or _cohort_next, which declare the
  -- reservation protocol. A worker from before this release (it calls this function directly and never reserves) gets no item, so it cannot
  -- make an unreserved paid AI call against this database.
  if coalesce(auth.role(), '') = 'service_role' and coalesce(current_setting('cf.pdesc_worker_protocol', true), '') <> 'provider-description-reserve-v1' then
    return jsonb_build_object('idle', true, 'reason', 'worker_protocol_required', 'items', '[]'::jsonb);
  end if;
  -- fixed: serialize reservation of review slots across all reader callers; no waiting behind another worker.
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;
  select (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')
       + (select count(*) from pipeline.provider_description_reads r where r.state='reading' and r.leased_until>=now()) into v_pending;
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
  select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;
  if nullif(btrim(v_model), '') is null then return jsonb_build_object('idle', true, 'reason', 'no_model', 'items', '[]'::jsonb); end if;
  -- the shared AI rule (credit floor, daily ceiling, lane guard; v2.15.404): nothing new is claimed while AI use is refused
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if;
  -- the pilot's hard ceilings: total AI spend of this lane in the shared ledger, and total Firecrawl reads of this reader
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
  where r.id in (select x.id from pipeline.provider_description_reads x join pipeline.evidence_artifacts a on a.id=security.provider_description_stored_v1(x.provider_id)
    where x.state='queued' and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',x.provider_id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(x.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)
    order by x.next_try_at,x.id limit security.pipeline_num_v1('batch.provider_description',3)::int);
  with pick as (select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(r.provider_id)),v_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified')))
                   and exists(select 1 from catalogue.providers p where p.id=r.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(p.id)),p.website))->>'ok')::boolean)
                   and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=r.provider_id)
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else security.provider_description_stored_v1(r.provider_id) is not null end
                 order by r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(security.pipeline_num_v1('pdesc.pending_max', 10) - v_pending)::int))
                 for update skip locked),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('description_at_lease',(select p.description from catalogue.providers p where p.id=r.provider_id),'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id)),
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
           'website', p.website, 'country', k.iso_alpha2, 'identity_names',jsonb_build_array(p.canonical_name,p.display_name), 'provider_type',(select t.code from ref.provider_types t where t.id=p.provider_type_id), 'hosts', to_jsonb(security.provider_hosts_v1(u.provider_id)),
           'stored', (select jsonb_build_object('evidence_id', a.id, 'storage_path', a.storage_path, 'url', a.source_url, 'captured_at', coalesce(a.captured_at, a.created_at),'content_hash',coalesce(a.content_hash,a.id::text))
                        from pipeline.evidence_artifacts a where a.id = st.stored_id),
           -- About pages the central page finder suggested (page type about_page, central.ts), on the provider's own hosts, best first
           -- IQ-00055: the page rule once per suggestion (a lateral), for the filter and the order
           'candidates', (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select y.url, y.score, g.pg from (
                              select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                                from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                               where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                                 and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                              cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g
                             where (g.pg->>'ok')::boolean) z))), '[]'::jsonb)
    into v
    -- IQ-00055: the stored copy once per claimed row
    from upd u cross join lateral (select case when nullif(current_setting('cf.pdesc_cohort',true),'') is not null then (select m.evidence_id from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=u.id) else security.provider_description_stored_v1(u.provider_id) end stored_id offset 0) st
         join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return jsonb_build_object('model', v_model,
    'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'firecrawl_left', greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used),
    'page_chars', security.pipeline_num_v1('pdesc.page_chars', 16000)::int,'verbatim_span_max_chars',security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int,
    'min_quote_chars', security.pipeline_num_v1('pdesc.min_quote_chars', 20)::int,
    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb),
    -- pilot 2 Nov 2026 16:16: the page rule's lists, for the home page's links (security.provider_description_page_v1 decides the same way)
    'page_rule', jsonb_build_object('about_prefixes', coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb),
                                    'refused_path_words', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb),
                                    'refused_host_labels', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb),
                                    'about_max_segments', security.pipeline_num_v1('pdesc.about_max_segments', 2)::int),
    -- pilot 2 Nov 2026 16:16 (CDU held at 916 characters): the model is told the limits the validation applies
    'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2)::int, 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5)::int,
                                 'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150)::int, 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int),
    'items', v);
end $function$;

create or replace function public.svc_provider_description_cohort_next(p_limit integer,p_cohort uuid) returns jsonb
language plpgsql security definer set search_path to '' as $function$
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 if not exists(select 1 from pipeline.provider_description_cohorts c where c.id=p_cohort and c.state='started') then raise exception 'unknown started cohort'; end if;
 perform set_config('cf.pdesc_cohort',p_cohort::text,true);
 perform set_config('cf.pdesc_worker_protocol','provider-description-reserve-v1',true); -- only the reservation-capable worker calls this (new in this release)
 return public.svc_provider_description_next(p_limit);
end $function$;
revoke all on function public.svc_provider_description_cohort_next(integer,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_description_cohort_next(integer,uuid) to service_role;

-- The reservation-capable worker's lease (validation 5 Nov 2026). It must name the protocol it follows: reserve with
-- svc_provider_description_reserve_v1 before every paid AI call.
create or replace function public.svc_provider_description_lease_v1(p_limit integer,p_cohort uuid default null,p_protocol text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 if p_protocol is distinct from 'provider-description-reserve-v1' then return jsonb_build_object('idle',true,'reason','worker_protocol_required','items','[]'::jsonb); end if;
 if p_cohort is not null then return public.svc_provider_description_cohort_next(p_limit,p_cohort); end if;
 perform set_config('cf.pdesc_worker_protocol',p_protocol,true);
 return public.svc_provider_description_next(p_limit);
end $function$;
revoke all on function public.svc_provider_description_lease_v1(integer,uuid,text) from public,anon,authenticated;
grant execute on function public.svc_provider_description_lease_v1(integer,uuid,text) to service_role;
comment on function public.svc_provider_description_lease_v1(integer,uuid,text) is 'Provider descriptions (validation 5 Nov 2026): the only lease for the reservation-capable coverage-sweep worker; a worker that does not declare provider-description-reserve-v1 receives no item.';

CREATE OR REPLACE FUNCTION public.svc_provider_description_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare x jsonb; r pipeline.provider_description_reads%rowtype; v_ev uuid; v_url text; v_cap timestamptz; v_via text; v_hash text;
        v_chk jsonb; v_item uuid; v_tally jsonb := '{}'::jsonb; v_out text; v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity')); -- fixed: serialize final Layer 4 capacity check with leases.
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into r from pipeline.provider_description_reads where id = (x->>'item_id')::uuid for update;
    if r.id is null or r.state <> 'reading' then v_tally := v_tally || jsonb_build_object('stale', coalesce((v_tally->>'stale')::int, 0) + 1); continue; end if;
    update pipeline.provider_description_reads set ai_calls=ai_calls+case when coalesce((x->>'ai_call_started')::boolean,false) then 1 else 0 end, checks=coalesce(checks,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known')), reserved_usd=case when coalesce((x->>'cost_known')::boolean,false) or coalesce((x->>'cost')::numeric,0)>0 then 0 else reserved_usd end, cost_usd = cost_usd + greatest(coalesce((x->>'cost')::numeric, 0), 0),
           firecrawl_reads = firecrawl_reads + greatest(coalesce((x->>'fc_reads')::int, 0), 0),
           model = coalesce(nullif(x->>'model', ''), model), prompt_version = coalesce(nullif(x->>'prompt_version', ''), prompt_version),
           worker = coalesce(left(nullif(x->>'worker', ''), 60), worker), updated_at = now()
     where id = r.id;
    v_ev := null; v_url := null; v_cap := null; v_via := null; v_hash := null;
    -- the page: a stored copy, or a page the worker read and stored now (registered as evidence under the provider's coverage-sweep source)
    if (x->>'stored_evidence_id') is not null then
      select a.id, a.source_url, coalesce(a.captured_at, a.created_at), coalesce(a.content_hash, a.id::text) into v_ev, v_url, v_cap, v_hash
        from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
       where a.id = (x->>'stored_evidence_id')::uuid and s.provider_id = r.provider_id;
      v_via := case when v_ev is not null then 'stored' end;
    elsif x->'fetch'->>'status' = 'read' and x->'fetch'->>'storage_path' is not null and x->'fetch'->>'sha256' ~ '^[0-9a-f]{64}$' then
      v_url := x->'fetch'->>'url'; v_hash := x->'fetch'->>'sha256'; v_via := x->'fetch'->>'via'; v_cap := now();
      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = security.coverage_sweep_source(r.provider_id) and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(security.coverage_sweep_source(r.provider_id), v_url, x->'fetch'->>'storage_path', v_hash,
                    coalesce(x->'fetch'->>'mime', 'text/html'),
                    jsonb_build_object('layer', 2, 'kind', 'provider_about_page', 'worker', 'coverage-sweep', 'provider_description_read_id', r.id, 'read_via', v_via));
        end if;
      end if;
    end if;
    update pipeline.provider_description_reads set evidence_id = coalesce(v_ev, evidence_id), source_url = coalesce(v_url, x->'fetch'->>'url', source_url),
           read_via = coalesce(v_via, read_via), content_hash = coalesce(v_hash, content_hash), source_captured_at = coalesce(v_cap, source_captured_at)
     where id = r.id;
    v_err := nullif(x->>'error', '');
    if v_err is not null or coalesce((x->>'retry')::boolean, false) then
      -- a failed read is tried again after pdesc.retry_minutes, at most pdesc.tries times; then the dead letter list
      update pipeline.provider_description_reads set state = case when tries >= v_max then 'dead_letter' else 'queued' end,
             next_try_at = now() + make_interval(mins => security.pipeline_num_v1('pdesc.retry_minutes', 360)::int), leased_until = null,
             rule = case when tries >= v_max then 'dead_letter' else 'retry' end, reason = left(coalesce(v_err, x->>'reason', 'retry'), 400), updated_at = now()
       where id = r.id returning state into v_out;
      v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1); continue;
    end if;
    if x->'answer' is null and x->>'rule' in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and coalesce((select reserved_usd from pipeline.provider_description_reads where id=r.id),0)=0 then
      update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,rule=x->>'rule',reason=left(coalesce(x->>'reason','Waiting for existing AI spending or pricing policy to allow the next read.'),400),updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked_policy',coalesce((v_tally->>'parked_policy')::int,0)+1); continue;
    end if;
    if x->'answer' is null then
      -- no page to read: no About page on the provider's own hosts, robots.txt, another provider's host
      update pipeline.provider_description_reads set state = 'held', leased_until = null, rule = coalesce(nullif(x->>'rule', ''), 'no_about_page'),
             reason = left(coalesce(x->>'reason', 'no About page found on the provider''s own website'), 400), updated_at = now()
       where id = r.id;
      v_tally := v_tally || jsonb_build_object('held', coalesce((v_tally->>'held')::int, 0) + 1); continue;
    end if;
    select * into r from pipeline.provider_description_reads where id = r.id;
    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer');
    if v_chk->>'outcome' = 'propose' and r.evidence_id is null then
      v_chk := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'no_evidence', 'reason', 'the page copy is not stored as evidence', 'checks', v_chk->'checks');
    end if;
    if (select p.description from catalogue.providers p where p.id=r.provider_id) is distinct from r.checks->>'description_at_lease' then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','description_changed_after_lease','reason','The description was edited while this read was in progress; retain the human value.','checks',v_chk->'checks');
    end if;
    if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','identity_changed_after_lease','reason','Provider names, type, country or website changed after source identity was checked.','checks',v_chk->'checks');
    end if;
    if not security.provider_description_scope_v1(r.provider_id) or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all')) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','provider_eligibility_changed','reason','Provider eligibility or manual lock changed after the read was leased.','checks',v_chk->'checks');
    end if;
    if exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and (m.evidence_id is distinct from r.evidence_id or m.snapshot->>'source_hash' is distinct from r.content_hash) and m.evidence_id is not null) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','cohort_evidence_changed','reason','The recorded evidence differs from the immutable cohort source. Preview the changed evidence again.','checks',v_chk->'checks');
    end if;
    if x->'quality_hold' is not null then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',coalesce(x->'quality_hold'->>'rule','worker_quality_hold'),'reason',x->'quality_hold'->>'reason','checks',v_chk->'checks');
    end if;
    if not (security.provider_description_identity_v1(r.provider_id,r.source_url)->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'rule','reason',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'reason','checks',v_chk->'checks');
    end if;
    if v_chk->>'outcome' in ('propose','verified') and not coalesce((x->'identity_check'->>'ok')::boolean,(r.checks->'identity'->>'ok')::boolean,false) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','source_identity_proof_missing','reason','The worker did not provide current source-identity proof; retain this evidence and retry only through the current approved reader.','checks',v_chk->'checks');
    end if;
    v_chk:=v_chk||jsonb_build_object('checks',coalesce(v_chk->'checks','{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known','description_at_lease',r.checks->'description_at_lease','identity_snapshot',r.checks->'identity_snapshot')));
    if v_chk->>'outcome'='propose' and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
      -- Keep the complete validated proposal; scheduler resumes this exact evidence without another AI call.
      update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='review_full',reason='Layer 4 provider-description capacity is full; resume automatically when a slot is free',updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked',coalesce((v_tally->>'parked')::int,0)+1); continue;
    end if;
    if v_chk->>'outcome' = 'propose' then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, 'provider_description', r.evidence_id,
              jsonb_build_object('description', (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = r.provider_id)),
              jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences', 'source_url', r.source_url, 'evidence_id', r.evidence_id,
                                 'captured_at', r.source_captured_at, 'read_id', r.id),
              jsonb_build_object('read_via', r.read_via, 'content_hash', r.content_hash, 'source_url', r.source_url),
              jsonb_build_object('model', r.model, 'prompt_version', r.prompt_version, 'worker', r.worker, 'cost_usd', r.cost_usd, 'checks', v_chk->'checks', 'rule', v_chk->>'rule'),
              'pending', 'Provider description read from the official page: every sentence quotes the page. A person approves or rejects it; nothing is published before.',
              'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28)')
      returning id into v_item;
      update pipeline.provider_description_reads set state = 'proposed', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = null, review_item_id = v_item, last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'proposed';
    elsif v_chk->>'outcome' = 'verified' then
      update pipeline.provider_description_reads set state = 'verified', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = v_chk->>'reason', last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'verified';
    else
      update pipeline.provider_description_reads set state = 'held', leased_until = null, proposal = jsonb_build_object('sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = left(v_chk->>'reason', 400), updated_at = now()
       where id = r.id;
      v_out := 'held';
    end if;
    v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1);
  end loop;
  return v_tally;
end $function$;

create or replace function security.provider_description_publication_check_v1() returns integer
language plpgsql security definer set search_path to '' as $function$
declare r record; v_body jsonb; v_zoho jsonb; v_n int:=0;
begin
 for r in select d.id,d.provider_id,d.proposal,p.stable_key,p.description from pipeline.provider_description_reads d join catalogue.providers p on p.id=d.provider_id where d.state in ('admitted','verified') and p.description=d.proposal->>'description' and security.provider_description_approved_lineage_v1(p.id,p.description) is not null order by d.consumer_checked_at nulls first,d.id limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int for update of d skip locked loop
  begin v_body:=public.website_v2_provider(r.stable_key); exception when others then v_body:=null; end;
  v_zoho:=security.provider_description_consumer_read_v1('zoho',r.stable_key);
  update pipeline.provider_description_reads set consumer_checked_at=now(),consumer_checks=jsonb_build_object('website_verified',coalesce(v_body->'item'->>'provider_id'=r.stable_key and v_body->'item'->>'description'=r.description and r.description=r.proposal->>'description',false),'zoho_verified',coalesce(v_zoho->'item'->>'provider_id'=r.stable_key and v_zoho->'item'->>'description'=r.description and r.description=r.proposal->>'description',false),'website_error',v_body->'error','zoho_error',v_zoho->'error','checked_at',now()),zoho_published_at=case when v_zoho->'item'->>'provider_id'=r.stable_key and v_zoho->'item'->>'description'=r.description and r.description=r.proposal->>'description' then coalesce(zoho_published_at,now()) else zoho_published_at end,published_at=case when v_body->'item'->>'description'=r.description and v_body->'item'->>'provider_id'=r.stable_key and r.description=r.proposal->>'description' then coalesce(published_at,now()) else published_at end,updated_at=now() where id=r.id;
  if v_body->'item'->>'description'=r.description and v_body->'item'->>'provider_id'=r.stable_key and r.description=r.proposal->>'description' then v_n:=v_n+1; end if;
 end loop;
 return v_n;
end $function$;
revoke all on function security.provider_description_publication_check_v1() from public,anon,authenticated;

create or replace function security.provider_description_resume_v1() returns integer
language plpgsql security definer set search_path to '' as $function$
declare r record; v_n int:=0; v_free int;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return 0; end if;
 select greatest(0,security.pipeline_num_v1('pdesc.pending_max',10)::int-count(*)::int) into v_free from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending';
 for r in select * from pipeline.provider_description_reads x where ((x.state='held' and x.rule='review_full') or (x.state='queued' and x.rule='retried' and x.proposal->>'description' is not null)) and x.evidence_id is not null order by x.updated_at,x.id limit v_free for update skip locked loop
  update pipeline.provider_description_reads set state='reading' where id=r.id;
  perform public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id',r.id,'stored_evidence_id',r.evidence_id,'answer',jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))));
  v_n:=v_n+1;
 end loop;
 return v_n;
end $function$;
revoke all on function security.provider_description_resume_v1() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION security.provider_description_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description fire')) then return jsonb_build_object('sent',0,'reason','reader_dispatch_in_flight'); end if; -- fixed: serialize the existing job dispatch, never wait or duplicate a nonce.
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- Publication and parked proposal progress do not require another paid read. Manual Run Now never adds work outside its fixed cohort.
  if nullif(current_setting('cf.pdesc_run_now',true),'') is null then
  perform security.provider_description_publication_check_v1();
  update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,updated_at=now()
  where state='held' and rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and reserved_usd=0;

  update pipeline.provider_description_reads r set state='held',rule='selection_changed_before_lease',reason='Provider scope, identity, manual lock or pinned source changed; inspect saved evidence before preparing another cohort',updated_at=now()
  where r.state='queued' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_cohorts c on c.id=m.cohort_id where m.read_id=r.id and c.state='started')
  and (not security.provider_description_scope_v1(r.provider_id)
    or exists(select 1 from pipeline.provider_description_cohort_members m join catalogue.providers p on p.id=m.provider_id where m.read_id=r.id and p.description is distinct from m.snapshot->>'current_description')
    or exists(select 1 from catalogue.providers p where p.id=r.provider_id and not (security.provider_description_identity_v1(r.provider_id,coalesce((select m.snapshot->>'source_url' from pipeline.provider_description_cohort_members m where m.read_id=r.id order by m.pick limit 1),p.website))->>'ok')::boolean)
    or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
    or exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and m.evidence_id is not null and not exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int) and (security.provider_description_identity_v1(r.provider_id,a.source_url)->>'ok')::boolean)));
  v_resumed:=security.provider_description_resume_v1();
  v_q := security.provider_description_enqueue_v1();
  else v_q:=0; v_resumed:=0; end if;
  select count(*) into v_dead from pipeline.provider_description_reads r where r.state = 'dead_letter';
  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then
    return jsonb_build_object('queued', v_q, 'ai', 'ceiling', 'dead_letter', v_dead);
  end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
  select count(*) into v_due from pipeline.provider_description_reads r
   where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
     and (nullif(current_setting('cf.pdesc_run_now',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid and m.read_id=r.id));
  select max(l.created_at) into v_last from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int);
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_last:=null; end if; -- Run Now bypasses frequency only; all other job guards remain.
  if v_due > 0 and v_open = 0 and v_last is null then
    if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_cohort:=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid;
    else
    select c.id into v_cohort from pipeline.provider_description_cohorts c
    where c.state='started' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and ((r.state='queued' and r.next_try_at<=now()) or (r.state='reading' and r.leased_until<now())))
    order by c.prepared_at,c.id limit 1;
    end if;
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 1, 'dead_letter', v_dead);
  end if;
  return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 0, 'dead_letter', v_dead);
end $function$;

CREATE OR REPLACE FUNCTION security.layer4_provider_description_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_pub jsonb; v_shown text; v_key text; v_check jsonb; v_read pipeline.provider_description_reads%rowtype;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' then raise exception 'not a provider description item' using errcode = '22023'; end if;
  if p_actor is null or not exists(select 1 from security.user_roles ur join security.roles rr on rr.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and rr.status='active' and rr.rank>=4) then raise exception 'authorised Layer 4 reviewer rank 4 required' using errcode='42501'; end if;
  if i.status<>'pending' then raise exception 'the provider description decision is no longer pending' using errcode='22023'; end if;
  if not security.provider_description_scope_v1(i.entity_id) or not exists(select 1 from catalogue.providers p where p.id=i.entity_id and p.lifecycle_status='active' and p.publication_status='published')
    or exists(select 1 from security.provider_hidden_v1 h where h.provider_id=i.entity_id) then raise exception 'provider is no longer active, published and eligible' using errcode='22023'; end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id=i.id and r.state='proposed' for update;
  if v_read.id is null or v_read.evidence_id is distinct from i.evidence_id or not exists(select 1 from pipeline.evidence_artifacts a join pipeline.sources s on s.id=a.source_id where a.id=i.evidence_id and s.provider_id=i.entity_id and a.source_url=v_read.source_url and coalesce(a.content_hash,a.id::text)=v_read.content_hash) then
    raise exception 'provider description evidence lineage changed' using errcode='22023'; end if;
  if not (security.provider_description_identity_v1(i.entity_id,v_read.source_url)->>'ok')::boolean then raise exception 'provider description identity no longer valid' using errcode='22023'; end if;
  if v_read.checks->'identity_snapshot' is not null then
    if v_read.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(i.entity_id) then raise exception 'provider identity changed since the source read; request new verified evidence' using errcode='22023'; end if;
  else
    -- Legacy proposals retain their original history: do not fabricate a historical identity snapshot. Revalidate the current full name against their actual retained official quote.
    if not exists(select 1 from catalogue.providers p cross join lateral jsonb_array_elements(coalesce(i.proposed_value->'sentences','[]'::jsonb)) sentence
      where p.id=i.entity_id and exists(select 1 from unnest(array[p.canonical_name,p.display_name]) nm where nullif(btrim(nm),'') is not null and position(regexp_replace(lower(nm),'[^a-z0-9]+','','g') in regexp_replace(lower(sentence->>'quote'),'[^a-z0-9]+','','g'))>0)) then
      raise exception 'legacy proposal has no identity snapshot and its retained quote does not verify the current full provider name' using errcode='22023';
    end if;
    update pipeline.provider_description_reads set checks=coalesce(checks,'{}'::jsonb)||jsonb_build_object('legacy_identity_quote_revalidated_at',now(),'identity_verification','legacy official quotation revalidated against current full name; no historical snapshot inferred') where id=v_read.id;
  end if;

  v_check:=security.provider_description_validate_v1(i.entity_id,v_read.source_url,v_read.source_captured_at,jsonb_build_object('about_page',true,'sentences',i.proposed_value->'sentences'));
  if v_check->>'outcome' not in ('propose','verified') or v_check->>'text' is distinct from i.proposed_value->>'description' then raise exception 'provider description no longer passes source and factual validation: %',v_check->>'rule' using errcode='22023'; end if;
  -- approved as read: an edited description has no quote for its new words, so it is not admitted (reject, and the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('description', 'p_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- verify publication: the Website API v2 provider payload is read back (a provider not published returns nothing yet)
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin
    v_pub := public.website_v2_provider(v_key);
    v_shown := v_pub->'item'->>'description';
  exception when others then v_shown := null;
  end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(),
         published_at = case when v_shown = v_text then now() end, updated_at = now()
   where review_item_id = i.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now()
   where provider_id = i.entity_id and state = 'admitted' and review_item_id is distinct from i.id;
  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id);
end $function$;

CREATE OR REPLACE FUNCTION security.provider_description_validate_v1(p_provider uuid, p_url text, p_captured_at timestamp with time zone, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v_host text := security.provider_page_host_v1(p_provider, p_url);
        v_s jsonb := coalesce(p_result->'sentences', '[]'::jsonb); v_n int; v_text text; s jsonb; t text;
        v_sup numeric; v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);
        v_dup numeric := security.pipeline_num_v1('pdesc.duplicate_share', 0.8);
        v_current text; v_other record; v_checks jsonb := '{}'::jsonb; v_claim text;
begin
  v_n := jsonb_array_length(v_s);
  v_text := (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(v_s) with ordinality e(x, o));
  v_checks := jsonb_build_object('host', v_host, 'sentences', v_n, 'chars', length(coalesce(v_text, '')));
  if v_host <> 'own' then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', 'wrong_host', 'checks', v_checks,
      'reason', case v_host when 'other_provider' then 'the page is on another provider''s website' when 'no_url' then 'no page address' else 'the page is not on the provider''s own website' end);
  end if;
  -- pilot 2 Nov 2026 16:16: only the provider's own About or Overview page is a description source
  if not (security.provider_description_page_v1(p_provider, p_url)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'outcome', 'refused', 'rule', security.provider_description_page_v1(p_provider, p_url)->>'rule', 'checks', v_checks,
      'reason', 'the page is not the provider''s own About or Overview page');
  end if;
  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  if v_n < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_n > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'sentence_count', 'checks', v_checks, 'reason', v_n || ' sentence(s), outside the set range');
  end if;
  for s in select x from jsonb_array_elements(v_s) x loop
    t := btrim(coalesce(s->>'text', ''));
    if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'quote_not_on_page', 'checks', v_checks, 'reason', 'a sentence''s quote is not on the page: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_marketing', 'checks', v_checks, 'reason', 'a marketing word that is not in the quote: ' || left(t, 120));
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w
                where security.pdesc_has_term_v1(t, w) and not security.pdesc_has_term_v1(s->>'quote', w)) then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_claim', 'checks', v_checks, 'reason', 'a ranking, facility, outcome or accreditation claim that is not in the quote: ' || left(t, 120));
    end if;
    -- Platform Admin 5 Nov 2026 20:03 §2: campus, scholarship and guarantee statements are checked against their official quote, never held by keyword alone
    select r into v_claim from (select security.pdesc_claim_check_v1(t, s->>'quote', w) r from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb)) w) z where r is not null limit 1;
    if v_claim is not null then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', v_claim, 'checks', v_checks, 'reason', case v_claim when 'claim_negated_in_source' then 'the official quote negates a campus, scholarship or guarantee statement that the sentence makes: ' else 'a campus, scholarship or guarantee statement that its official quote does not support: ' end || left(t, 120));
    end if;
    -- Platform Admin 2 Nov 2026 23:24 ("avoid cutting essential conditions or publishing fragments as complete descriptions"): a sentence
    -- that does not end as a sentence (no closing full stop, question or exclamation mark, or an ellipsis) is a fragment; the description is
    -- held, never cut or completed
    if t !~ '[.!?]["'')\]’”]*$' or t ~ '(\.\.\.|…)["'')\]’”]*$' then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'incomplete_sentence', 'checks', v_checks,
        'reason', 'a sentence is not complete (it would be published as a fragment): ' || left(t, 120));
    end if;
    -- Validation 5 Nov 2026 (decision 20:03 §2): numbers are compared after normalising format (80,000 = 80 000; per cent = %), and the quote's number words count (four = 4).
    if exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(t,false),'[0-9]+(?:[.,][0-9]+)*','g') n where not exists(select 1 from regexp_matches(security.pdesc_number_norm_v1(s->>'quote',true),'[0-9]+(?:[.,][0-9]+)*','g') q where q[1]=n[1])) then
      return jsonb_build_object('ok',false,'outcome','held','rule','unsupported_numeric_claim','reason','A number in a factual claim does not occur in its supporting quote.','checks',v_checks);
    end if;
    -- Quote provenance is retained separately; long verbatim spans fail the existing factual description path.
    if exists(select 1 from generate_series(1,greatest(0,length(regexp_replace(t,'\s+',' ','g'))-security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int+1)) n where position(lower(substring(regexp_replace(t,'\s+',' ','g') from n for security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int)) in lower(regexp_replace(s->>'quote','\s+',' ','g')))>0) then
      return jsonb_build_object('ok',false,'outcome','held','rule','verbatim_passage','reason','A long official passage was copied; a concise source-grounded paraphrase is required.','checks',v_checks);
    end if;
    if coalesce(s->>'quote','')~* '\m(former|formerly|previously|renamed|closed|merged|ceased)\M|was known as|became'
      and t~* '\m(is|are|operates|offers)\M' and t!~* '\m(former|formerly|previously|was|were|became|renamed|closed|merged|ceased|history|founded|established|origin|since)\M'
      -- Validation 5 Nov 2026 (decision 20:03 §2): evidence-aware. Held only when the quote's present-tense part does not support the sentence,
      -- i.e. the sentence's claim is the one the quote places in the past; a historic word elsewhere in the quote never holds a supported claim.
      and security.pdesc_present_support_v1(t, s->>'quote') < v_min_sup then
      return jsonb_build_object('ok',false,'outcome','held','rule','historic_claim_context','reason','Historical source context cannot establish a present institutional identity or operation.','checks',v_checks);
    end if;
    v_sup := security.pdesc_support_v1(t, s->>'quote');
    if v_sup < v_min_sup then
      return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'unsupported_sentence', 'checks', v_checks || jsonb_build_object('support', v_sup),
        'reason', 'a sentence is not supported by its quote (' || v_sup || '): ' || left(t, 120));
    end if;
  end loop;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'length', 'checks', v_checks, 'reason', length(v_text) || ' characters, outside the set range');
  end if;
  if p_captured_at is not null and p_captured_at < now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'source_outdated', 'checks', v_checks, 'reason', 'the stored page is older than the set age');
  end if;
  -- duplicate: another provider's description held, or another provider's proposal waiting
  select z.provider_id, z.sim into v_other from (
    select p.id provider_id, security.pdesc_similarity_v1(v_text, p.description) sim from catalogue.providers p
     where p.id <> p_provider and nullif(btrim(p.description), '') is not null
    union all
    select r.provider_id, security.pdesc_similarity_v1(v_text, r.proposal->>'description') from pipeline.provider_description_reads r
     where r.provider_id <> p_provider and r.state = 'proposed') z
   where z.sim >= v_dup order by z.sim desc limit 1;
  if v_other.provider_id is not null then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'duplicate_other_provider', 'checks', v_checks || jsonb_build_object('duplicate_of', v_other.provider_id, 'similarity', v_other.sim),
      'reason', 'the same as another provider''s description (' || v_other.sim || ')');
  end if;
  select nullif(btrim(p.description), '') into v_current from catalogue.providers p where p.id = p_provider;
  if v_current is not null and security.pdesc_similarity_v1(v_text, v_current) >= v_dup then
    return jsonb_build_object('ok', true, 'outcome', 'verified', 'rule', 'same_as_current', 'text', v_text,
      'checks', v_checks || jsonb_build_object('similarity_current', security.pdesc_similarity_v1(v_text, v_current)), 'reason', 'the page still supports the description held');
  end if;
  return jsonb_build_object('ok', true, 'outcome', 'propose', 'rule', case when v_current is null then 'missing' else 'changed' end, 'text', v_text, 'checks', v_checks, 'reason', null);
end $function$;

create or replace function public.admin_provider_description_run_v1(p_action text,p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid:=auth.uid(); v_rank int:=security.current_role_rank(); c pipeline.provider_description_cohorts%rowtype;
 v_res jsonb; v_preview jsonb; v_fresh jsonb; x jsonb; v_id uuid; v_reason text:=btrim(coalesce(p_args->>'reason','')); v_n int:=0; v_run uuid; v_why text;
 v_mode text; v_history jsonb; v_rule text; v_diagnosis jsonb; v_context jsonb; v_issue bigint; v_ai_request bigint; v_ai_model text; v_ai_why text; v_job pipeline.automation_catalogue%rowtype; v_dispatch_error text; v_dispatch_sqlstate text;
begin
 if v_actor is null or v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_job from pipeline.automation_catalogue where jobname='provider-description-read';
 if p_action='verify' and v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
 if p_action='capabilities' then
 return jsonb_build_object('contract','provider-description-run-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
 'can_explain',v_rank>=coalesce(v_job.control_rank,6),'can_diagnose',security.pipeline_num_v1('ops.ai_diagnosis_on',0)>=1 and security.ai_use_allowed_v1('ops_diagnose') and nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','') is not null,'ai_diagnosis_reason','AI assistance requires the existing approved Operations diagnosis switch, model and spending guards plus an existing open issue linked to this exact provider and evidence. Explain evidence always uses stored checks.',
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',k.iso_alpha2,'label',coalesce(to_jsonb(k)->>'name',to_jsonb(k)->>'country_name',k.iso_alpha2::text),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.countries'),'[]')?k.iso_alpha2::text)) from ref.countries k where k.iso_alpha2 in ('AU','NZ','CA')),'[]'),
 'provider_types',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'label',coalesce(to_jsonb(t)->>'label',to_jsonb(t)->>'name',t.code),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.provider_types'),'[]')?t.code)) from ref.provider_types t),'[]'),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.id,'name',coalesce(p.display_name,p.canonical_name),'country',k.iso_alpha2,'type',t.code) order by coalesce(p.display_name,p.canonical_name)) from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id where security.provider_description_scope_v1(p.id)),'[]'),
 'min_size',1,'max_size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,'default_size',security.pipeline_num_v1('batch.provider_description',3)::int,
 'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
 'model',(select model_identifier from pipeline.central_ai_settings where id=1),'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,
 'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
 'policy',jsonb_build_object('countries',security.toolset_setting('pipeline','pdesc.countries'),'types',security.toolset_setting('pipeline','pdesc.provider_types'),'provider_keys',security.toolset_setting('pipeline','pdesc.provider_keys'),'ai_usd_max',security.pipeline_num_v1('pdesc.ai_usd_max',1),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'reserved_usd',(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads),'remaining_usd',greatest(0,security.pipeline_num_v1('pdesc.ai_usd_max',1)-(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')-(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads)),'actual_ai_calls',(select coalesce(sum(ai_calls),0) from pipeline.provider_description_reads),'recorded_billable_calls',(select coalesce(sum(calls),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'recorded_cost_usd',(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'ai_call_counter_scope','reported model calls since provider-description-autonomy instrumentation; ledger calls are separate recorded billable calls','budget_period','lifetime pilot','required_approval','Individual human Layer 4 decision'));
 elsif p_action='preview' then
 v_res:=security.provider_description_selection_v1(p_args);
 insert into pipeline.provider_description_cohorts(requested_by,selection,snapshot,expires_at)
 values(v_actor,p_args||jsonb_build_object('mode',coalesce(nullif(p_args->>'mode',''),'stored')),v_res,now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int)) returning id into v_id;
 return v_res||jsonb_build_object('token',v_id,'preview_token',v_id,'expires_at',now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int));
 elsif p_action='prepare' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason is shorter than the governed minimum' using errcode='22023'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'preview_token','')::uuid and requested_by=v_actor for update;
 if c.id is null then raise exception 'unknown owned preview' using errcode='42501'; end if;
 if c.state in ('prepared','started') then return security.provider_description_run_result_v1(c.id); end if;
 if c.expires_at<now() then raise exception 'preview expired; preview again' using errcode='22023'; end if;
 v_fresh:=security.provider_description_selection_v1(c.selection);
 for x in select * from jsonb_array_elements(c.snapshot->'providers') where (value->>'eligible')::boolean loop
  if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where f->>'provider_id'=x->>'provider_id' and (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description' and f->>'last_read_id' is not distinct from x->>'last_read_id') then raise exception 'preview changed; preview again' using errcode='22023'; end if;
  v_n:=v_n+1;
  insert into pipeline.provider_description_cohort_members(cohort_id,provider_id,evidence_id,pick,snapshot) values(c.id,(x->>'provider_id')::uuid,(x->>'evidence_id')::uuid,v_n,x);
 end loop;
 if v_n=0 then raise exception 'no eligible provider with approved evidence in this preview' using errcode='22023'; end if;
 update pipeline.provider_description_cohorts set state='prepared',reason=v_reason,prepared_at=now() where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','cohort_prepare',c.id::text,jsonb_build_object('selected',v_n,'reason',v_reason,'selection',c.selection),v_actor);
 return security.provider_description_run_result_v1(c.id);
 elsif p_action='run' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot start this job' using errcode='42501'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'cohort_id','')::uuid and requested_by=v_actor for update;
 if c.id is null or c.state='preview' then raise exception 'unknown owned fixed cohort' using errcode='42501'; end if;
 if c.run_id is not null then return security.provider_description_run_result_v1(c.id)||jsonb_build_object('repeat',true); end if;
 if (select count(*) from pipeline.provider_description_cohort_members where cohort_id=c.id)>least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int then
   raise exception 'current_cap_changed: the fixed cohort exceeds the current governed cap; prepare a new cohort' using errcode='22023';
 end if;
 -- Same task kind, catalogue permission, pause/spend/review rules and provider-description job. Never a second scheduler.
 v_why:=case when not coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read' then 'job_not_allowlisted'
 when v_job.jobname is null then 'job_not_catalogued'
 when not exists(select 1 from cron.job where jobname='provider-description-read' and active) then 'job_paused'
 when security.pipeline_num_v1('pdesc.enabled',0)<1 then 'reader_off'
 when not security.ai_use_allowed_v1('provider_description') then 'ai_refused'
 when (select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')>=security.pipeline_num_v1('pdesc.ai_usd_max',1) then 'ai_ceiling'
 when (select count(*) from pipeline.layer4_review_items where field_code='provider_description' and status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then 'review_full' end;
 -- Policy/capacity holds are durable: the fixed cohort stays recoverable and the existing scheduled job resumes it.
 for x in select m.snapshot from pipeline.provider_description_cohort_members m where m.cohort_id=c.id order by m.pick loop
   v_fresh:=security.provider_description_selection_v1(c.selection||jsonb_build_object('provider_id',x->>'provider_id','size',1));
   if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description') then
     update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('eligibility_reason','selection_changed_before_run','eligible',false) where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid; continue;
   end if;
   insert into pipeline.provider_description_reads(provider_id) values((x->>'provider_id')::uuid) on conflict do nothing returning id into v_id;
   if v_id is null then select id into v_id from pipeline.provider_description_reads where provider_id=(x->>'provider_id')::uuid and state in ('queued','reading','proposed') order by created_at desc limit 1; end if;
   update pipeline.provider_description_cohort_members set read_id=v_id where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid;
   v_n:=v_n+1; v_id:=null;
 end loop;
 update pipeline.provider_description_cohorts set state='started' where id=c.id;
 if v_why is null and v_n>0 then
   perform set_config('cf.pdesc_run_now',c.id::text,true);
   begin
     v_res:=security.provider_description_fire_v1();
   exception when others then
     -- OTHERS deliberately excludes query cancellation: the caller's statement/lock limits remain authoritative.
     get stacked diagnostics v_dispatch_error=message_text,v_dispatch_sqlstate=returned_sqlstate;
     v_res:=jsonb_build_object('sent',0,'parked',true,'reason','reader_dispatch_failed','error',v_dispatch_error,'sqlstate',v_dispatch_sqlstate,'retry_strategy','existing provider-description-read schedule resumes this saved queued cohort');
   end;
 else v_res:=jsonb_build_object('sent',0,'parked',true,'reason',coalesce(v_why,'selection_changed_before_run')); end if;
 insert into pipeline.admin_jobs(kind,lane,state,title,args,result,error,requested_by,reason,started_at,finished_at,scope,outcome)
 values('job_run_now','run_now',case when v_dispatch_error is not null then 'failed' when v_why is null then 'done' else 'cancelled' end,'Provider descriptions: bounded Run Now',jsonb_build_object('job','provider-description-read','cohort_id',c.id,'idempotency_key',c.request_key),v_res||jsonb_build_object('selected',v_n,'admitted',0,'publication_measured_separately',true),v_dispatch_error,v_actor,c.reason,now(),clock_timestamp(),'cohort:'||c.id,case when v_dispatch_error is not null then 'failed_retryable' when v_why is not null then 'blocked_policy' else 'succeeded_no_movement' end) returning id into v_run;
 update pipeline.provider_description_cohorts set run_id=v_run where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','run_now','provider-description-read',jsonb_build_object('cohort_id',c.id,'run_id',v_run,'dispatch',v_res,'reason',c.reason),v_actor);
 return security.provider_description_run_result_v1(c.id)||jsonb_build_object('dispatch',v_res);
 elsif p_action in ('saved','verify','diagnose') then
 if p_action='diagnose' and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor;
 elsif nullif(p_args->>'cohort_id','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'cohort_id')::uuid and requested_by=v_actor;
 else select * into c from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc,id desc limit 1; end if;
 if p_action='diagnose' then
   if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot diagnose this job' using errcode='42501'; end if;
   if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason required'; end if;
   if c.id is null and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor; end if;
   if c.id is null then raise exception 'owned saved evidence required' using errcode='42501'; end if;
   select coalesce(r.rule,m.snapshot->>'eligibility_reason'),coalesce(r.reason,m.snapshot->>'reason') into v_rule,v_why from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid;
   if v_rule is null then select x->>'eligibility_reason',x->>'reason' into v_rule,v_why from jsonb_array_elements(c.snapshot->'providers') x where x->>'provider_id'=p_args->>'provider_id'; end if;
   if v_rule is null then raise exception 'provider is not in owned saved evidence' using errcode='42501'; end if;
   v_diagnosis:=jsonb_build_object('method','stored_checks','rule',v_rule,'explanation',coalesce(v_why,case v_rule when 'no_verified_stored_source' then 'A current official About/Overview page stored against this exact provider is needed.' when 'unchanged_unsuitable_evidence' then 'The same evidence previously failed or was rejected. A changed approved source is needed before another AI read.' when 'review_full' then 'The validated proposal is parked until Layer 4 capacity becomes available; no further AI read is needed.' else 'Inspect the official source, identity references and validation checks. Only the existing human Layer 4 decision can authorise admission.' end),'ai_used',false,'cost_usd',0,'ai_reason','Provider-description AI diagnostics have no approved existing route.','at',now());
   -- AI is advice through the existing Operations lane only, bound to an already recorded issue and the exact stored source.
   select coalesce((select m.snapshot||jsonb_build_object('evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'checks',r.checks,'sentences',r.proposal->'sentences') from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid),
     (select z from jsonb_array_elements(c.snapshot->'providers') z where z->>'provider_id'=p_args->>'provider_id')) into v_context;
   v_ai_model:=nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','');
   v_ai_why:=case when security.pipeline_num_v1('ops.ai_diagnosis_on',0)<1 then 'ops.ai_diagnosis_on is 0'
      when v_ai_model is null then 'no approved Operations diagnosis model'
      when not security.ai_use_allowed_v1('ops_diagnose') then 'existing Operations AI spending guard refuses assistance'
      when nullif(v_context->>'evidence_id','') is null then 'no exact stored evidence reference for an existing issue' end;
   if v_ai_why is null then
    select i.id into v_issue from pipeline.integration_issues i where i.status not in ('closed','superseded') and (p_args->>'provider_id')::uuid=any(i.provider_ids)
      and jsonb_path_exists(i.evidence,'$.**.evidence_id ? (@ == $id)',jsonb_build_object('id',v_context->>'evidence_id')) order by i.id desc limit 1;
    if v_issue is null then v_ai_why:='no existing open integration issue links this exact provider and stored evidence'; end if;
   end if;
   if v_ai_why is null then
    perform pg_advisory_xact_lock(hashtext('cf247 pdesc diagnosis '||v_issue::text)); -- fixed: duplicate request suppression for the existing issue/evidence.
    select q.id into v_ai_request from pipeline.ops_ai_diagnosis_requests q where q.issue_id=v_issue and q.context->>'provider_description_evidence_id'=v_context->>'evidence_id' and q.state in ('queued','leased','answered','refused') order by q.id desc limit 1;
    if v_ai_request is null then
     insert into pipeline.ops_ai_diagnosis_requests(issue_id,context,model,note)
     values(v_issue,jsonb_build_object('issue',v_issue,'provider_id',p_args->>'provider_id','provider_description_evidence_id',v_context->>'evidence_id','evidence',v_context,'question','Explain why this official source or claim is unsuitable and which evidence is missing. Advice only; do not authorise a description or change any setting.',
       'deterministic',v_diagnosis,'root_causes',(select jsonb_agg(jsonb_build_object('code',rc.code,'class',rc.class,'title',rc.title,'description',rc.description)) from pipeline.ops_root_causes rc)),v_ai_model,'Provider description evidence explanation; advice through existing Operations diagnosis') returning id into v_ai_request;
    end if;
    v_diagnosis:=v_diagnosis||jsonb_build_object('request_id',v_ai_request,'request_status','queued','integration_issue_id',v_issue,'model',v_ai_model,'ai_reason','Queued through the existing Operations diagnosis worker; no approval or settings authority.');
   else v_diagnosis:=v_diagnosis||jsonb_build_object('ai_reason',v_ai_why); end if;
   update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('diagnosis',v_diagnosis) where cohort_id=c.id and provider_id=(p_args->>'provider_id')::uuid;
   update pipeline.provider_description_cohorts set snapshot=jsonb_set(snapshot,'{providers}',(select jsonb_agg(case when z->>'provider_id'=p_args->>'provider_id' then z||jsonb_build_object('diagnosis',v_diagnosis) else z end) from jsonb_array_elements(snapshot->'providers') z)) where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','explain_evidence',c.id::text,jsonb_build_object('provider_id',p_args->>'provider_id','reason',v_reason,'diagnosis',v_diagnosis),v_actor);
   return v_diagnosis;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('cohort_id',h.id,'state',h.state,'created_at',h.created_at,'reason',h.reason,'run_id',h.run_id) order by h.created_at desc),'[]') into v_history from (select * from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int) h;
 if c.state='preview' then
   v_preview:=jsonb_set(c.snapshot,'{providers}',coalesce((select jsonb_agg(z||case when z->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(z->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',z->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(z->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end) from jsonb_array_elements(c.snapshot->'providers') z),'[]'::jsonb));
   return jsonb_build_object('preview',v_preview||jsonb_build_object('token',c.id,'expires_at',c.expires_at),'scope',c.selection,'history',v_history);
 end if;
 if c.id is null then return jsonb_build_object('history',v_history,'providers','[]'::jsonb,'runs','[]'::jsonb); end if;
 v_res:=security.provider_description_run_result_v1(c.id);
 if p_action='verify' then
   update pipeline.provider_description_cohorts set verified_at=now(),verification=v_res-'last_verification' where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify',c.id::text,jsonb_build_object('totals',v_res->'totals','as_at',now(),'reason','Operator requested actual catalogue and consumer read-back'),v_actor);
 end if;
 return v_res||jsonb_build_object('history',v_history);
 end if;
 raise exception 'unknown provider-description action %',p_action using errcode='22023';
end $function$;
revoke all on function public.admin_provider_description_run_v1(text,jsonb) from public,anon;
grant execute on function public.admin_provider_description_run_v1(text,jsonb) to authenticated;
comment on function public.admin_provider_description_run_v1(text,jsonb) is 'Provider Description autonomy 4 Nov 2026: authorised bounded scope preview, actor-bound saved immutable cohort, idempotent governed Run Now through existing provider-description-read, persisted results and actual Website read-back; existing Layer 4 is the only admission decision. Explain evidence preserves original checks without AI spend.';

insert into pipeline.component_register(kind,name,layer,purpose,status,replaces,introduced_in) values
 ('table','pipeline.provider_description_cohorts','Operations','Provider descriptions: saved bounded cohort and run recovery','active','{}','20261106200000'),
 ('table','pipeline.provider_description_cohort_members','Operations','Provider descriptions: fixed identity/evidence and existing reader references','active','{}','20261106200000'),
 ('function','public.admin_provider_description_run_v1','Operations','Provider descriptions: governed Run & Validate UI bridge','active','{}','20261106200000'),
 ('function','security.provider_description_resume_v1','Layer 3','Provider descriptions: resume validated parked proposals without another AI read','active','{}','20261106200000')
on conflict do nothing;

-- Refuse partial replacement or edited source: every changed existing reader definition must match the qualified after-body exactly.
do $after$
declare x record;
begin
 for x in select * from (values
 ('security.provider_description_fire_v1()','b334fbefe8a7fb2b8cfd2feda570a616'),
 ('security.provider_description_enqueue_v1()','0a1897bb7f56697a9f01d4ec3e8befc0'),
 ('public.svc_provider_description_next(integer)','559407dc479753698b858231b2e7eb93'),
 ('public.svc_provider_description_record(jsonb)','d95f0bafc894b662468a309254544444'),
 ('security.layer4_provider_description_apply_impl(uuid,uuid,jsonb,text)','97685b737007410288297dea9d650d2a'),
 ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)','b4959fe6f0daad62b93c83c1feeea7e4')) v(sig,hash) loop
   if md5(pg_get_functiondef(x.sig::regprocedure))<>x.hash then raise exception 'provider description after-definition differs: %',x.sig; end if;
 end loop;
end $after$;
