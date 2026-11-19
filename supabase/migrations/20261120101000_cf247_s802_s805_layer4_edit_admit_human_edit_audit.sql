-- CF-247 s802 to s805 (Platform Admin 20 Nov 2026 05:52 AEDT, chat S1-Build): Layer 4 inline Edit & Admit, human-edit audit and the 6-month re-review.
-- s802/s803: a person may edit a University or Course description before admitting it. The internal approval is security.layer4_description_decide_v1
--   (p_item, p_edited_content, p_set_manual_lock default true, p_reason): unedited text (trimmed) is approved as read through the existing path
--   (admission_source machine_human_approved, was_edited false, with every quote check as before); edited text is admitted as human_input
--   (was_edited true): it must pass the description length, sentence and word-list checks, the field is locked by hand (unless the person chose not
--   to), and the original candidate, the final text, who and when are recorded with a review due in six months (a setting). This replaces the
--   2 Nov 2026 rule "approved as read, never edited" for these two kinds, on the Platform Admin's instruction above.
--   A university whose last reading was held (no candidate, for example Torrens and AUT) can be opened for writing from its stored page.
-- s804: pipeline.human_edit_audit holds every Layer 4 description admission (machine_human_approved or human_input); Human Edits & Periodic Audit
--   shows the person's own edits and, to the Platform Admin, all edits with Unacknowledged and Due for re-review counts.
-- s805: Acknowledge & Keep Lock, Re-Verify by Machine (a read-only comparison with the stored page quotes and the latest machine candidate; $0,
--   nothing is overwritten), Edit & Re-Lock (a new revision), Release Lock to Machine, and Accept machine text (after a re-verify).
-- No public function is added or re-signed: the screens reach these through new actions of public.admin_layer4_inbox (md5-guarded edit).
-- Parity before writing (read live 20 Nov 2026 07:01 AEDT): head 20261120095000, 2,202 rows; numbered above every open pull request (Pilot #1403 holds 20261120100000).
-- G3: no consumer object changes (descriptions are data the website already reads). No spend.
-- Replaces: the "approved as read, never edited" refusal in security.layer4_provider_description_apply_impl and security.layer4_course_description_apply_v1.
-- Retires: nothing.

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'governance.human_edit_review_months', 'Human edits: months until re-review',
        'How long a description a person edited stays locked before it is due for review in Human Edits & Periodic Audit (acknowledging it starts the period again).',
        'number', '6'::jsonb, 1, 24, 'months', 1210, 'Layer 4 review',
        'security.human_edit_audit_record_v1 and security.human_edit_admin_v1 (acknowledge)', 'CF-247 s802 to s805 (Platform Admin 20 Nov 2026 05:52): six-month re-review'),
       ('pipeline', 'governance.recheck_word_share', 'Human edits re-verify: words found per sentence',
        'Re-Verify by Machine counts a sentence of the human text as supported when at least this share of its longer words appears in the stored page quotes.',
        'number', '0.6'::jsonb, 0.3, 1, 'share', 1211, 'Layer 4 review',
        'security.human_edit_admin_v1 (human_edits_recheck)', 'CF-247 s805 (Platform Admin 20 Nov 2026 05:52): read-only comparison with the stored page')
on conflict do nothing;

create table if not exists pipeline.human_edit_audit (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('provider', 'course')),
  entity_id uuid not null,
  field_name text not null default 'description',
  provider_id uuid,
  country_code text,
  provider_type text,
  review_item_id uuid,
  admission_source text not null check (admission_source in ('machine_human_approved', 'human_input')),
  was_edited boolean not null,
  original_candidate_text text,
  edited_text text,
  final_approved_text text,
  edited_by uuid,
  edited_at timestamptz not null default now(),
  lock_set boolean not null default false,
  admin_acknowledged_by uuid,
  admin_acknowledged_at timestamptz,
  next_review_due_at timestamptz,
  recheck_status text not null default 'pending_ack'
    check (recheck_status in ('not_applicable', 'pending_ack', 'acknowledged', 'rechecked', 'superseded', 'lock_released', 'machine_accepted')),
  recheck_requested_by uuid,
  recheck_at timestamptz,
  recheck_candidate_text text,
  recheck_support_share numeric,
  recheck_detail jsonb,
  lock_released_by uuid,
  lock_released_at timestamptz,
  revision integer not null default 1,
  supersedes_id uuid references pipeline.human_edit_audit(id),
  reason text,
  created_at timestamptz not null default now()
);
comment on table pipeline.human_edit_audit is 'CF-247 s802 to s805: every Layer 4 description admission. machine_human_approved: a person approved the machine text as read. human_input: a person edited it (original and final text, who, when, the lock, the six-month re-review, acknowledgement and re-verify results). Written only by the security functions of s802 to s805; a revision is a new row that supersedes the old one.';
create index if not exists human_edit_audit_editor_idx on pipeline.human_edit_audit (edited_by, edited_at desc) where was_edited;
create index if not exists human_edit_audit_open_idx on pipeline.human_edit_audit (next_review_due_at) where was_edited and recheck_status not in ('superseded', 'lock_released', 'machine_accepted');
create index if not exists human_edit_audit_entity_idx on pipeline.human_edit_audit (entity_type, entity_id, edited_at desc);
alter table pipeline.human_edit_audit enable row level security;
revoke all on pipeline.human_edit_audit from public, anon, authenticated;

-- the checks an edited description must pass (the same limits and word lists the readers use)
create or replace function security.description_text_check_v1(p_entity text, p_text text)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_t text := btrim(coalesce(p_text, '')); v_sent int; v_words int; v_chars int; v_min int; v_max int; v_smin int; v_smax int; v_lists text[]; v_bad text[]; v_p text[] := '{}';
begin
  v_chars := length(v_t);
  v_sent := (select count(*) from regexp_split_to_table(v_t, '[.!?]+(\s+|$)') s where btrim(s) <> '');
  v_words := coalesce(array_length(regexp_split_to_array(nullif(v_t, ''), '\s+'), 1), 0);
  if p_entity = 'course' then
    v_min := security.pipeline_num_v1('enrich.course_description_min_chars', 80)::int; v_max := security.pipeline_num_v1('enrich.course_description_max_chars', 360)::int;
    v_smin := security.pipeline_num_v1('enrich.course_description_min_sentences', 1)::int; v_smax := security.pipeline_num_v1('enrich.course_description_max_sentences', 2)::int;
    v_lists := array['enrich.course_description_marketing_words', 'pdesc.superlatives'];
  else
    v_min := security.pipeline_num_v1('pdesc.min_chars', 150)::int; v_max := security.pipeline_num_v1('pdesc.max_chars', 1200)::int;
    v_smin := security.pipeline_num_v1('pdesc.min_sentences', 2)::int; v_smax := security.pipeline_num_v1('pdesc.max_sentences', 5)::int;
    v_lists := array['pdesc.superlatives', 'pdesc.prompt_refused_words'];
  end if;
  v_bad := array(select distinct w from unnest(v_lists) l cross join lateral jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', l), '[]'::jsonb)) w
                  where security.pdesc_has_term_v1(v_t, w) order by w);
  if v_chars < v_min then v_p := v_p || format('at least %s characters (has %s)', v_min, v_chars); end if;
  if v_chars > v_max then v_p := v_p || format('at most %s characters (has %s)', v_max, v_chars); end if;
  if v_sent < v_smin then v_p := v_p || format('at least %s sentences (has %s)', v_smin, v_sent); end if;
  if v_sent > v_smax then v_p := v_p || format('at most %s sentences (has %s)', v_smax, v_sent); end if;
  if cardinality(v_bad) > 0 then v_p := v_p || ('words not allowed: ' || array_to_string(v_bad, ', ')); end if;
  return jsonb_build_object('ok', cardinality(v_p) = 0, 'problems', to_jsonb(v_p), 'chars', v_chars, 'sentences', v_sent, 'words', v_words, 'banned', to_jsonb(v_bad),
                            'limits', jsonb_build_object('min_chars', v_min, 'max_chars', v_max, 'min_sentences', v_smin, 'max_sentences', v_smax));
end $f$;
revoke all on function security.description_text_check_v1(text, text) from public, anon, authenticated;
comment on function security.description_text_check_v1(text, text) is 'CF-247 s802: length, sentence and word-list checks for a description a person writes or edits (the readers'' own settings).';

create or replace function security.human_edit_audit_record_v1(p_actor uuid, p_entity text, p_entity_id uuid, p_item uuid, p_source text, p_was_edited boolean,
  p_original text, p_final text, p_lock_set boolean, p_reason text, p_supersedes uuid)
returns uuid language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; v_pid uuid; v_cc text; v_pt text; v_rev int := 1;
begin
  v_pid := case when p_entity = 'provider' then p_entity_id else (select c.provider_id from catalogue.courses c where c.id = p_entity_id) end;
  select k.iso_alpha2, t.code into v_cc, v_pt from catalogue.providers p left join ref.countries k on k.id = p.country_id
    left join ref.provider_types t on t.id = p.provider_type_id where p.id = v_pid;
  if p_supersedes is not null then v_rev := coalesce((select revision + 1 from pipeline.human_edit_audit where id = p_supersedes), 1); end if;
  insert into pipeline.human_edit_audit (entity_type, entity_id, provider_id, country_code, provider_type, review_item_id, admission_source, was_edited,
         original_candidate_text, edited_text, final_approved_text, edited_by, lock_set, next_review_due_at, recheck_status, revision, supersedes_id, reason)
  values (p_entity, p_entity_id, v_pid, v_cc, v_pt, p_item, p_source, p_was_edited, p_original, case when p_was_edited then p_final end, p_final, p_actor, coalesce(p_lock_set, false),
          case when p_was_edited then now() + make_interval(months => security.pipeline_num_v1('governance.human_edit_review_months', 6)::int) end,
          case when p_was_edited then 'pending_ack' else 'not_applicable' end, v_rev, p_supersedes, nullif(btrim(coalesce(p_reason, '')), ''))
  returning id into v_id;
  return v_id;
end $f$;
revoke all on function security.human_edit_audit_record_v1(uuid, text, uuid, uuid, text, boolean, text, text, boolean, text, uuid) from public, anon, authenticated;
comment on function security.human_edit_audit_record_v1(uuid, text, uuid, uuid, text, boolean, text, text, boolean, text, uuid) is 'CF-247 s802/s804: writes one row of pipeline.human_edit_audit.';

-- s802: an edited description is admitted as human input (called by the two apply functions when the final text differs from the candidate)
create or replace function security.layer4_description_human_admit_v1(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; v_entity text; v_text text; v_check jsonb; v_now text; v_lock boolean; v_audit uuid; v_fields text[];
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.field_code not in ('provider_description', 'course_description_first_read') then raise exception 'not a description item' using errcode = '22023'; end if;
  if i.status <> 'pending' then raise exception 'the description decision is no longer pending' using errcode = '22023'; end if;
  if p_actor is null or not exists (select 1 from security.user_roles ur join security.roles rr on rr.code = ur.role_code
                                     where ur.user_id = p_actor and (ur.expires_at is null or ur.expires_at > now()) and rr.status = 'active' and rr.rank >= 4) then
    raise exception 'editing a description needs the Pipeline Operator role or above' using errcode = '42501'; end if;
  v_entity := i.entity_type;
  v_text := nullif(btrim(coalesce(p_value->>'description', '')), '');
  if v_text is null then raise exception 'the edited description is empty' using errcode = '22023'; end if;
  v_check := security.description_text_check_v1(v_entity, v_text);
  if not (v_check->>'ok')::boolean then raise exception 'the edited description does not pass the checks: %', (select string_agg(x, '; ') from jsonb_array_elements_text(v_check->'problems') x) using errcode = '22023'; end if;
  v_fields := case when v_entity = 'provider' then array['description', 'p_description', 'all'] else array['description', 'course_description', 'all'] end;
  if exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = i.entity_id and l.field = any (v_fields)) then
    raise exception 'the description is already locked by hand; change it in Human Edits & Periodic Audit (Edit & Re-Lock)' using errcode = '22023'; end if;
  if v_entity = 'provider' then select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
  else select nullif(btrim(c.description), '') into v_now from catalogue.courses c where c.id = i.entity_id for update; end if;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; refresh the item' using errcode = '22023'; end if;
  v_lock := coalesce((p_value->>'set_manual_lock')::boolean, true);
  perform set_config('cf.manual_edit', 'on', true);   -- a person's edit passes the manual-lock guard
  if v_entity = 'provider' then update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  else
    update catalogue.courses set description = v_text, updated_at = now() where id = i.entity_id;
    insert into search.course_refresh_requests (course_id, requested_at, requested_by) values (i.entity_id, now(), 'human_edit');
  end if;
  if v_lock then
    insert into pipeline.manual_locks (entity, entity_id, field, mode, set_by) values (v_entity, i.entity_id, 'description', 'value', p_actor)
    on conflict (entity, entity_id, field) do update set mode = 'value', set_by = excluded.set_by, set_at = now();
  end if;
  perform set_config('cf.manual_edit', '', true);
  if v_entity = 'provider' then
    update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(), checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('admission_source', 'human_input'), updated_at = now()
     where review_item_id = i.id and state in ('proposed', 'held');
    update pipeline.provider_description_reads set state = 'superseded', updated_at = now()
     where provider_id = i.entity_id and state = 'admitted' and review_item_id is distinct from i.id;
  end if;
  v_audit := security.human_edit_audit_record_v1(p_actor, v_entity, i.entity_id, i.id, 'human_input', true,
               coalesce(p_value->>'original_description', i.proposed_value->>'description'), v_text, v_lock, p_reason, null);
  return jsonb_build_object(case when v_entity = 'provider' then 'provider_id' else 'course_id' end, i.entity_id, 'admission_source', 'human_input', 'was_edited', true,
                            'description_chars', length(v_text), 'locked', v_lock, 'audit_id', v_audit, 'evidence_id', i.evidence_id);
end $f$;
revoke all on function security.layer4_description_human_admit_v1(uuid, uuid, jsonb, text) from public, anon, authenticated;
comment on function security.layer4_description_human_admit_v1(uuid, uuid, jsonb, text) is 'CF-247 s802: admits an edited University or Course description as human input (checks, lock, audit).';

-- s802: the internal approval with the edited content
create or replace function security.layer4_description_decide_v1(p_item_id uuid, p_edited_content text, p_set_manual_lock boolean default true, p_reason text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; v_orig text; v_edit text := nullif(btrim(coalesce(p_edited_content, '')), '');
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.field_code not in ('provider_description', 'course_description_first_read') then raise exception 'not a description item' using errcode = '22023'; end if;
  v_orig := nullif(btrim(coalesce(i.proposed_value->>'description', '')), '');
  if v_edit is null or v_edit = v_orig then
    if v_orig is null then raise exception 'there is no candidate to approve; write the description' using errcode = '22023'; end if;
    return public.layer4_review_decide(p_item_id, 'approve', p_reason, null);   -- machine_human_approved: the existing path and every quote check
  end if;
  return public.layer4_review_decide(p_item_id, 'edit_and_approve', p_reason,
    i.proposed_value || jsonb_build_object('description', v_edit, 'sentences', '[]'::jsonb, 'edited', true,
                                           'set_manual_lock', coalesce(p_set_manual_lock, true), 'original_description', coalesce(v_orig, '')));
end $f$;
revoke all on function security.layer4_description_decide_v1(uuid, text, boolean, text) from public, anon, authenticated;
comment on function security.layer4_description_decide_v1(uuid, text, boolean, text) is 'CF-247 s802: Layer 4 description approval with edited content: unedited text is approved as read; edited text is admitted as human input and locked unless p_set_manual_lock is false.';

-- s804/s805: Human Edits & Periodic Audit, and the held university writing path (reached through public.admin_layer4_inbox)
create or replace function security.human_edit_admin_v1(p_action text, p_args jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_uid uuid := auth.uid(); v_rank int := coalesce(security.current_role_rank(), 0); v_ids uuid[]; v_n int := 0; rw record; v_out jsonb; v_scope text;
        v_lim int := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200);  -- fixed: page bound
        v_off int := greatest(coalesce((p_args->>'offset')::int, 0), 0); v_share numeric := security.pipeline_num_v1('governance.recheck_word_share', 0.6);
        v_cand text; v_quotes text; v_detail jsonb; v_sup numeric; v_text text; v_check jsonb; v_new uuid; v_item uuid; v_read record; v_gone int;
begin
  if v_uid is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_action = 'description_rules' then
    if v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
    return jsonb_build_object(
      'provider', jsonb_build_object('min_chars', security.pipeline_num_v1('pdesc.min_chars', 150), 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 1200),
                                     'min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2), 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5),
                                     'words', coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb) || coalesce(security.toolset_setting('pipeline', 'pdesc.prompt_refused_words'), '[]'::jsonb)),
      'course', jsonb_build_object('min_chars', security.pipeline_num_v1('enrich.course_description_min_chars', 80), 'max_chars', security.pipeline_num_v1('enrich.course_description_max_chars', 360),
                                   'min_sentences', security.pipeline_num_v1('enrich.course_description_min_sentences', 1), 'max_sentences', security.pipeline_num_v1('enrich.course_description_max_sentences', 2),
                                   'words', coalesce(security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), '[]'::jsonb) || coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)),
      'review_months', security.pipeline_num_v1('governance.human_edit_review_months', 6));
  elsif p_action = 'description_check' then
    if v_rank < 3 then raise exception 'curator role required' using errcode = '42501'; end if;
    return security.description_text_check_v1(coalesce(p_args->>'entity', 'provider'), p_args->>'text');
  elsif p_action = 'description_held_list' then
    -- universities in scope whose last reading was held and that have no description waiting, to open for writing by hand
    if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
    select jsonb_build_object('items', coalesce(jsonb_agg(to_jsonb(z) order by z.name), '[]'::jsonb), 'total', count(*)) into v_out from (
      select p.id provider_id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country, h.rule, h.reason, h.source_url, h.updated_at
        from catalogue.providers p join ref.countries k on k.id = p.country_id
        join lateral (select rd.* from pipeline.provider_description_reads rd where rd.provider_id = p.id order by rd.updated_at desc limit 1) h on h.state = 'held'
       where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null
         and security.provider_description_scope_v1(p.id)
         and (nullif(btrim(p_args->>'q'), '') is null or coalesce(p.display_name, p.canonical_name) ilike '%' || btrim(p_args->>'q') || '%')
         and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = p.id and i.field_code = 'provider_description' and i.status = 'pending')
       order by 2 limit v_lim offset v_off) z;
    return coalesce(v_out, jsonb_build_object('items', '[]'::jsonb, 'total', 0));
  elsif p_action = 'description_open_held' then
    if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
    select rd.* into v_read from catalogue.providers p join lateral (select x.* from pipeline.provider_description_reads x where x.provider_id = p.id order by x.updated_at desc limit 1) rd on true
     where p.id = (p_args->>'provider_id')::uuid and p.lifecycle_status = 'active' and p.publication_status = 'published' and security.provider_description_scope_v1(p.id);
    if v_read.id is null or v_read.state <> 'held' then raise exception 'this university has no held reading to write from' using errcode = '22023'; end if;
    if exists (select 1 from pipeline.layer4_review_items i where i.entity_id = v_read.provider_id and i.field_code = 'provider_description' and i.status = 'pending') then
      raise exception 'a description for this university is already waiting in the Inbox' using errcode = '22023'; end if;
    insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason)
    values ('provider', v_read.provider_id, 'provider_description', v_read.evidence_id,
            jsonb_build_object('description', (select nullif(btrim(description), '') from catalogue.providers where id = v_read.provider_id)),
            jsonb_build_object('description', '', 'sentences', '[]'::jsonb, 'source_url', v_read.source_url, 'evidence_id', v_read.evidence_id, 'read_id', v_read.id,
                               'captured_at', v_read.source_captured_at, 'held_rule', v_read.rule, 'held_reason', v_read.reason, 'opened_for', 'human_input'),
            jsonb_build_object('read_via', v_read.read_via, 'source_url', v_read.source_url, 'opened_by', v_uid, 'opened_for', 'human_input'),
            'held: ' || coalesce(v_read.rule, 'no candidate') || '; opened for writing by hand')
    returning id into v_item;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('layer4', 'description_open_held', 'provider:' || v_read.provider_id, jsonb_build_object('item_id', v_item, 'read_id', v_read.id, 'rule', v_read.rule), v_uid);
    return jsonb_build_object('ok', true, 'item_id', v_item, 'provider_id', v_read.provider_id);
  elsif p_action = 'human_edits' then
    v_scope := coalesce(p_args->>'scope', 'mine');
    if v_scope = 'all' and v_rank < 6 then raise exception 'All Human Edits is for the Platform Admin' using errcode = '42501'; end if;
    if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
    with base as (
      select a.* from pipeline.human_edit_audit a
       where a.was_edited and a.recheck_status not in ('superseded')
         and (v_scope = 'all' or a.edited_by = v_uid)
         and (nullif(p_args->>'entity_type', '') is null or a.entity_type = p_args->>'entity_type')
         and (nullif(p_args->>'country', '') is null or a.country_code = upper(p_args->>'country'))
         and (nullif(p_args->>'provider_type', '') is null or a.provider_type = p_args->>'provider_type')),
    f as (
      select b.* from base b
       where case coalesce(p_args->>'filter', 'open')
               when 'unacknowledged' then b.admin_acknowledged_at is null and b.recheck_status not in ('lock_released', 'machine_accepted')
               when 'due' then b.next_review_due_at <= now() and b.recheck_status not in ('lock_released', 'machine_accepted')
               when 'open' then b.recheck_status not in ('lock_released', 'machine_accepted')
               else true end)
    select jsonb_build_object('scope', v_scope, 'rank', v_rank, 'review_months', security.pipeline_num_v1('governance.human_edit_review_months', 6),
      'counts', jsonb_build_object('open', (select count(*) from base where recheck_status not in ('lock_released', 'machine_accepted')),
                                   'unacknowledged', (select count(*) from base where admin_acknowledged_at is null and recheck_status not in ('lock_released', 'machine_accepted')),
                                   'due', (select count(*) from base where next_review_due_at <= now() and recheck_status not in ('lock_released', 'machine_accepted'))),
      'total', (select count(*) from f),
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'entity_type', x.entity_type, 'entity_id', x.entity_id, 'field', x.field_name,
          'name', case when x.entity_type = 'provider' then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.entity_id)
                       else (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = x.entity_id) end,
          'provider_name', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
          'country', x.country_code, 'provider_type', x.provider_type, 'original', x.original_candidate_text, 'edited', x.edited_text,
          'current', case when x.entity_type = 'provider' then (select p.description from catalogue.providers p where p.id = x.entity_id)
                          else (select c.description from catalogue.courses c where c.id = x.entity_id) end,
          'locked', exists (select 1 from pipeline.manual_locks l where l.entity = x.entity_type and l.entity_id = x.entity_id and l.field = 'description'),
          'edited_by', x.edited_by, 'edited_by_name', (select coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''), u.email) from auth.users u where u.id = x.edited_by),
          'mine', x.edited_by = v_uid, 'edited_at', x.edited_at, 'age_days', floor(extract(epoch from now() - x.edited_at) / 86400),
          'acknowledged_at', x.admin_acknowledged_at, 'next_review_due_at', x.next_review_due_at, 'due', x.next_review_due_at <= now(),
          'status', x.recheck_status, 'revision', x.revision, 'recheck_at', x.recheck_at, 'recheck_candidate', x.recheck_candidate_text,
          'recheck_support_share', x.recheck_support_share, 'recheck_detail', x.recheck_detail, 'reason', x.reason)
          order by (x.next_review_due_at <= now()) desc, (x.admin_acknowledged_at is null) desc, x.edited_at desc)
        from (select * from f order by (next_review_due_at <= now()) desc, (admin_acknowledged_at is null) desc, edited_at desc limit v_lim offset v_off) x), '[]'::jsonb))
      into v_out;
    return v_out;
  end if;

  -- the governed actions on edits: each row the person may act on (own with Pipeline Operator, any with Platform Admin)
  v_ids := array(select jsonb_array_elements_text(coalesce(p_args->'ids', jsonb_build_array(p_args->>'id')))::uuid);
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose at least one edit' using errcode = '22023'; end if;
  if cardinality(v_ids) > 200 then raise exception 'choose at most 200 edits at once' using errcode = '22023'; end if;  -- fixed: one action's bound
  if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  if v_rank < 6 and exists (select 1 from pipeline.human_edit_audit a where a.id = any (v_ids) and a.edited_by is distinct from v_uid) then
    raise exception 'you can act only on your own edits; the Platform Admin acts on all' using errcode = '42501'; end if;
  if p_action in ('human_edits_release', 'human_edits_accept_machine') and v_rank < 6 then raise exception 'releasing a lock is for the Platform Admin' using errcode = '42501'; end if;
  if exists (select 1 from pipeline.human_edit_audit a where a.id = any (v_ids) and (not a.was_edited or a.recheck_status in ('superseded', 'lock_released', 'machine_accepted'))) then
    raise exception 'one of the chosen edits is no longer open' using errcode = '22023'; end if;

  if p_action = 'human_edits_ack' then
    update pipeline.human_edit_audit set admin_acknowledged_by = v_uid, admin_acknowledged_at = now(), recheck_status = 'acknowledged',
           next_review_due_at = now() + make_interval(months => security.pipeline_num_v1('governance.human_edit_review_months', 6)::int)
     where id = any (v_ids);
    get diagnostics v_n = row_count;
  elsif p_action = 'human_edits_recheck' then
    -- read-only: the latest machine candidate and the stored page quotes it was read from; no reading, no AI, no Firecrawl; nothing is overwritten
    for rw in select a.* from pipeline.human_edit_audit a where a.id = any (v_ids) loop
      v_cand := null; v_quotes := null;
      if rw.entity_type = 'provider' then
        select x.proposal->>'description', (select string_agg(s->>'quote', ' ') from jsonb_array_elements(coalesce(x.proposal->'sentences', '[]'::jsonb)) s)
          into v_cand, v_quotes from pipeline.provider_description_reads x
         where x.provider_id = rw.entity_id and nullif(btrim(coalesce(x.proposal->>'description', '')), '') is not null order by x.updated_at desc limit 1;
      end if;
      if v_cand is null then
        select i.proposed_value->>'description', (select string_agg(s->>'quote', ' ') from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s)
          into v_cand, v_quotes from pipeline.layer4_review_items i
         where i.entity_id = rw.entity_id and i.field_code in ('provider_description', 'course_description_first_read')
           and nullif(btrim(coalesce(i.proposed_value->>'description', '')), '') is not null order by i.created_at desc limit 1;
      end if;
      select coalesce(jsonb_agg(jsonb_build_object('sentence', s, 'share', sh, 'supported', sh >= v_share) order by n), '[]'::jsonb),
             case when count(*) = 0 then null else round(avg(case when sh >= v_share then 1 else 0 end)::numeric, 2) end
        into v_detail, v_sup
        from (select s, n, (select case when count(*) = 0 then 0 else round(avg(case when position(w in lower(coalesce(v_quotes, ''))) > 0 then 1 else 0 end)::numeric, 2) end
                              from regexp_split_to_table(lower(s), '[^a-z0-9]+') w where length(w) >= 4) sh
                from regexp_split_to_table(coalesce(rw.edited_text, ''), '(?<=[.!?])\s+') with ordinality t(s, n) where btrim(s) <> '') z;
      update pipeline.human_edit_audit set recheck_status = 'rechecked', recheck_at = now(), recheck_requested_by = v_uid, recheck_candidate_text = v_cand,
             recheck_support_share = v_sup, recheck_detail = jsonb_build_object('sentences', v_detail, 'quotes_held', v_quotes is not null, 'word_share', v_share,
                                                                                'candidate_differs', v_cand is distinct from rw.edited_text)
       where id = rw.id;
      v_n := v_n + 1;
    end loop;
  elsif p_action = 'human_edits_edit' then
    if cardinality(v_ids) <> 1 then raise exception 'edit one description at a time' using errcode = '22023'; end if;
    select * into rw from pipeline.human_edit_audit where id = v_ids[1];
    v_text := nullif(btrim(coalesce(p_args->>'text', '')), '');
    if length(btrim(coalesce(p_args->>'reason', ''))) < 5 then raise exception 'a reason is needed' using errcode = '22023'; end if;
    v_check := security.description_text_check_v1(rw.entity_type, v_text);
    if not (v_check->>'ok')::boolean then raise exception 'the description does not pass the checks: %', (select string_agg(x, '; ') from jsonb_array_elements_text(v_check->'problems') x) using errcode = '22023'; end if;
    perform set_config('cf.manual_edit', 'on', true);
    if rw.entity_type = 'provider' then update catalogue.providers set description = v_text, updated_at = now() where id = rw.entity_id;
    else update catalogue.courses set description = v_text, updated_at = now() where id = rw.entity_id;
      insert into search.course_refresh_requests (course_id, requested_at, requested_by) values (rw.entity_id, now(), 'human_edit'); end if;
    insert into pipeline.manual_locks (entity, entity_id, field, mode, set_by) values (rw.entity_type, rw.entity_id, 'description', 'value', v_uid)
    on conflict (entity, entity_id, field) do update set mode = 'value', set_by = excluded.set_by, set_at = now();
    perform set_config('cf.manual_edit', '', true);
    update pipeline.human_edit_audit set recheck_status = 'superseded' where id = rw.id;
    v_new := security.human_edit_audit_record_v1(v_uid, rw.entity_type, rw.entity_id, rw.review_item_id, 'human_input', true, rw.edited_text, v_text, true, p_args->>'reason', rw.id);
    v_n := 1;
  elsif p_action = 'human_edits_release' then
    for rw in select a.* from pipeline.human_edit_audit a where a.id = any (v_ids) loop
      with d as (delete from pipeline.manual_locks where entity = rw.entity_type and entity_id = rw.entity_id and field = 'description' returning 1) select count(*) into v_gone from d;
      update pipeline.human_edit_audit set recheck_status = 'lock_released', lock_released_by = v_uid, lock_released_at = now() where id = rw.id;
      v_n := v_n + 1;
    end loop;
  elsif p_action = 'human_edits_accept_machine' then
    if cardinality(v_ids) <> 1 then raise exception 'accept one machine text at a time' using errcode = '22023'; end if;
    select * into rw from pipeline.human_edit_audit where id = v_ids[1];
    v_text := nullif(btrim(coalesce(rw.recheck_candidate_text, '')), '');
    if rw.recheck_status <> 'rechecked' or v_text is null then raise exception 'Re-Verify by Machine first; there is no machine text to accept' using errcode = '22023'; end if;
    v_check := security.description_text_check_v1(rw.entity_type, v_text);
    if not (v_check->>'ok')::boolean then raise exception 'the machine text does not pass the checks: %', (select string_agg(x, '; ') from jsonb_array_elements_text(v_check->'problems') x) using errcode = '22023'; end if;
    perform set_config('cf.manual_edit', 'on', true);
    if rw.entity_type = 'provider' then update catalogue.providers set description = v_text, updated_at = now() where id = rw.entity_id;
    else update catalogue.courses set description = v_text, updated_at = now() where id = rw.entity_id;
      insert into search.course_refresh_requests (course_id, requested_at, requested_by) values (rw.entity_id, now(), 'human_edit'); end if;
    with d as (delete from pipeline.manual_locks where entity = rw.entity_type and entity_id = rw.entity_id and field = 'description' returning 1) select count(*) into v_gone from d;
    perform set_config('cf.manual_edit', '', true);
    update pipeline.human_edit_audit set recheck_status = 'machine_accepted', lock_released_by = v_uid, lock_released_at = now() where id = rw.id;
    v_new := security.human_edit_audit_record_v1(v_uid, rw.entity_type, rw.entity_id, rw.review_item_id, 'machine_human_approved', false, rw.edited_text, v_text, false, 'machine text accepted after re-verify', rw.id);
    v_n := 1;
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('governance', p_action, 'pipeline.human_edit_audit', jsonb_build_object('ids', to_jsonb(v_ids), 'rows', v_n, 'new_revision', v_new), v_uid);
  return jsonb_build_object('ok', true, 'action', p_action, 'rows', v_n, 'new_id', v_new);
end $f$;
revoke all on function security.human_edit_admin_v1(text, jsonb) from public, anon, authenticated;
comment on function security.human_edit_admin_v1(text, jsonb) is 'CF-247 s804/s805: Human Edits & Periodic Audit (list, acknowledge, re-verify, edit and re-lock, release, accept machine text) and the held university writing path.';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- the two apply functions: an edited value goes to human admission; an approval as read records machine_human_approved
select pg_temp.cf_edit_def('security.layer4_provider_description_apply_impl(uuid,uuid,jsonb,text)'::regprocedure, '97685b737007410288297dea9d650d2a',
  array[$o$  select * into v_read from pipeline.provider_description_reads r where r.review_item_id=i.id and r.state='proposed' for update;$o$,
        $o$  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id);$o$],
  array[$n$  if p_value is distinct from i.proposed_value then return security.layer4_description_human_admit_v1(p_actor, i.id, p_value, p_reason); end if;  -- s802: edited by a person
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id=i.id and r.state='proposed' for update;$n$,
        $n$  perform security.human_edit_audit_record_v1(p_actor, 'provider', i.entity_id, i.id, 'machine_human_approved', false, v_text, v_text, false, p_reason, null);  -- s802
  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id, 'admission_source', 'machine_human_approved');$n$]);
select pg_temp.cf_edit_def('security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)'::regprocedure, 'ba97236f3010e248bac44a0a7c09611a',
  array[$o$  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;$o$,
        $o$  return jsonb_build_object('course_id', i.entity_id, 'description_chars', length(v_text), 'held', v_shown = v_text, 'evidence_id', i.evidence_id, 'actor', p_actor);$o$],
  array[$n$  if p_value is distinct from i.proposed_value then return security.layer4_description_human_admit_v1(p_actor, i.id, p_value, p_reason); end if;  -- s802: edited by a person$n$,
        $n$  perform security.human_edit_audit_record_v1(p_actor, 'course', i.entity_id, i.id, 'machine_human_approved', false, v_text, v_text, false, p_reason, null);  -- s802
  return jsonb_build_object('course_id', i.entity_id, 'description_chars', length(v_text), 'held', v_shown = v_text, 'evidence_id', i.evidence_id, 'actor', p_actor, 'admission_source', 'machine_human_approved');$n$]);

-- the Inbox: Save Edit & Admit on description cards, and the Human Edits actions (no new public function)
select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, '3dd1d45d43332dd60a274c9996238806',
  array[$o$v_hooks := security.layer4_inbox_hooks_v1(); v_kinds := v_hooks->'kinds';$o$,
        $o$  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$o$,
        $o$  elsif v_kind = 'provider_description' then$o$],
  array[$n$v_hooks := security.layer4_inbox_hooks_v1();
  if v_hooks->'kinds' ? 'provider_description' then  -- s802: Save Edit & Admit on University and Course description cards
    v_hooks := jsonb_set(v_hooks, '{kinds,provider_description,choices}', coalesce(v_hooks->'kinds'->'provider_description'->'choices', '[]'::jsonb)
      || jsonb_build_array(jsonb_build_object('key', 'edit_approve', 'label', 'Save Edit & Admit', 'input', 'text', 'editor', true, 'rank', 4,
           'returns', 'Your text is admitted as human input and the description is locked by hand (unless you clear the lock box); it is listed in Human Edits & Periodic Audit for review in six months')));
  end if;
  v_kinds := v_hooks->'kinds';$n$,
        $n$  if p_action in ('description_rules', 'description_check', 'description_held_list', 'description_open_held', 'human_edits', 'human_edits_ack', 'human_edits_recheck',
                  'human_edits_edit', 'human_edits_release', 'human_edits_accept_machine') then
    return security.human_edit_admin_v1(p_action, p_args);  -- s804/s805
  end if;
  if p_action <> 'decide' then raise exception 'unknown action %', p_action; end if;$n$,
        $n$  elsif v_kind = 'provider_description' and v_choice = 'edit_approve' then
    -- s802 (Platform Admin 20 Nov 2026 05:52): an edited description is admitted as human input and locked; unedited text is approved as read
    v_r := security.layer4_description_decide_v1(v_ref::uuid, p_args->>'value', coalesce((p_args->>'set_manual_lock')::boolean, true), v_reason);
  elsif v_kind = 'provider_description' then$n$]);

-- post-checks, as a signed-in Platform Admin, on real items, in a sub-block that is always rolled back (nothing kept)
do $$
declare v_admin uuid; v_o text := ''; ci uuid; ci2 uuid; pi uuid; v_c uuid; v_orig text; v_edit text; r jsonb; a pipeline.human_edit_audit%rowtype; v_torrens uuid; v_hi uuid; v_list jsonb; v_aid uuid;
begin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  if v_admin is null then raise exception 'post-check: no Platform Admin to act as'; end if;
  begin
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    -- the Inbox offers the new choice
    if not exists (select 1 from jsonb_array_elements(public.admin_layer4_inbox('summary', '{}')->'kinds'->'provider_description'->'choices') c where c->>'key' = 'edit_approve') then
      raise exception 'post-check: Save Edit & Admit is not offered'; end if;
    -- 1. a course description edited and admitted as human input
    select i.id, i.entity_id, i.proposed_value->>'description' into ci, v_c, v_orig from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
     where i.field_code = 'course_description_first_read' and i.status = 'pending' and nullif(btrim(i.proposed_value->>'description'), '') is not null
       and (security.description_text_check_v1('course', i.proposed_value->>'description')->>'ok')::boolean
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id)
       and nullif(btrim(c.description), '') is not distinct from nullif(btrim(i.before_value->>'description'), '') limit 1;
    if ci is not null then
      v_edit := lower(left(v_orig, 1)) || substr(v_orig, 2);
      if v_edit = v_orig then v_edit := upper(left(v_orig, 1)) || substr(v_orig, 2); end if;
      r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'provider_description', 'ref', ci, 'choice', 'edit_approve', 'value', v_edit, 'reason', 'post-check edit (rolled back)'));
      if (select description from catalogue.courses where id = v_c) is distinct from v_edit then raise exception 'post-check: the edited course text was not admitted %', left(r::text, 300); end if;
      if not exists (select 1 from pipeline.manual_locks where entity = 'course' and entity_id = v_c and field = 'description') then raise exception 'post-check: no lock'; end if;
      select * into a from pipeline.human_edit_audit where review_item_id = ci;
      if a.admission_source <> 'human_input' or not a.was_edited or a.original_candidate_text is distinct from v_orig or a.next_review_due_at < now() + interval '5 months' then raise exception 'post-check: audit row %', to_jsonb(a); end if;
      if (select status from pipeline.layer4_review_items where id = ci) <> 'edited_approved' then raise exception 'post-check: item status'; end if;
      v_o := v_o || 'course edit: admitted, locked, audited (human_input)';
    end if;
    -- 2. another course description approved as read (machine_human_approved)
    select i.id into ci2 from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
     where i.field_code = 'course_description_first_read' and i.status = 'pending' and i.id is distinct from ci and nullif(btrim(i.proposed_value->>'description'), '') is not null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id)
       and nullif(btrim(c.description), '') is not distinct from nullif(btrim(i.before_value->>'description'), '') limit 1;
    if ci2 is not null then
      begin
        r := security.layer4_description_decide_v1(ci2, null, true, 'post-check approve as read (rolled back)');
        if not exists (select 1 from pipeline.human_edit_audit where review_item_id = ci2 and admission_source = 'machine_human_approved' and not was_edited) then raise exception 'post-check: no machine_human_approved row'; end if;
        v_o := v_o || ' | course approve as read: machine_human_approved';
      exception when others then
        if sqlerrm like 'post-check:%' then raise; end if;
        v_o := v_o || ' | course approve as read refused by its own checks (' || left(sqlerrm, 80) || ')';
      end;
    end if;
    -- 3. a held university opened for writing and admitted by hand
    select h->>'provider_id' into v_torrens from jsonb_array_elements(security.human_edit_admin_v1('description_held_list', jsonb_build_object('q', 'Torrens'))->'items') h limit 1;
    if v_torrens is null then
      select (h->>'provider_id')::uuid into v_torrens from jsonb_array_elements(security.human_edit_admin_v1('description_held_list', '{}')->'items') h limit 1;
    end if;
    if v_torrens is not null then
      r := public.admin_layer4_inbox('description_open_held', jsonb_build_object('provider_id', v_torrens));
      v_hi := (r->>'item_id')::uuid;
      v_edit := 'This provider offers higher education courses in Australia. Students can study undergraduate and postgraduate programs at its campuses and online. Details of each course are set out on its course pages.';
      r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'provider_description', 'ref', v_hi, 'choice', 'edit_approve', 'value', v_edit, 'reason', 'post-check write by hand (rolled back)'));
      if (select description from catalogue.providers where id = v_torrens) is distinct from v_edit then raise exception 'post-check: the written university text was not admitted %', left(r::text, 300); end if;
      v_o := v_o || ' | held university opened and written by hand: admitted, locked';
    end if;
    -- 4. the governance list and its actions
    v_list := public.admin_layer4_inbox('human_edits', jsonb_build_object('scope', 'all', 'filter', 'open'));
    if (v_list->'counts'->>'unacknowledged')::int < 1 then raise exception 'post-check: Human Edits list %', left(v_list::text, 300); end if;
    v_aid := (v_list->'items'->0->>'id')::uuid;
    r := public.admin_layer4_inbox('human_edits_recheck', jsonb_build_object('ids', jsonb_build_array(v_aid)));
    if (select recheck_status from pipeline.human_edit_audit where id = v_aid) <> 'rechecked' then raise exception 'post-check: recheck'; end if;
    r := public.admin_layer4_inbox('human_edits_ack', jsonb_build_object('ids', jsonb_build_array(v_aid)));
    if (select admin_acknowledged_at from pipeline.human_edit_audit where id = v_aid) is null then raise exception 'post-check: acknowledge'; end if;
    select * into a from pipeline.human_edit_audit where id = v_aid;
    r := public.admin_layer4_inbox('human_edits_edit', jsonb_build_object('id', v_aid, 'text', a.edited_text || '', 'reason', 'post-check re-lock (rolled back)'));
    if (select recheck_status from pipeline.human_edit_audit where id = v_aid) <> 'superseded' or not exists (select 1 from pipeline.human_edit_audit where supersedes_id = v_aid and revision = 2) then
      raise exception 'post-check: edit and re-lock'; end if;
    v_aid := (select id from pipeline.human_edit_audit where supersedes_id = v_aid);
    r := public.admin_layer4_inbox('human_edits_release', jsonb_build_object('ids', jsonb_build_array(v_aid)));
    select * into a from pipeline.human_edit_audit where id = v_aid;
    if a.recheck_status <> 'lock_released' or exists (select 1 from pipeline.manual_locks where entity = a.entity_type and entity_id = a.entity_id and field = 'description') then raise exception 'post-check: release'; end if;
    v_o := v_o || ' | Human Edits: listed, re-verified, acknowledged, edited and re-locked, released';
    -- refusals
    begin perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'provider_description', 'ref', coalesce(ci2, ci), 'choice', 'edit_approve', 'value', 'Too short.', 'reason', 'post-check refusal'));
      raise exception 'post-check: a too-short edit was admitted';
    exception when others then if sqlerrm like 'post-check:%' then raise; end if; end;
    raise exception 'cf-s802-undo';
  exception when raise_exception then if sqlerrm <> 'cf-s802-undo' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if (select count(*) from pipeline.human_edit_audit) <> 0 then raise exception 'post-check: the audit is not empty at creation'; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
