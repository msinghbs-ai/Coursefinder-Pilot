-- CF-247 fee wording rules in Layer 4 (Platform Admin, 1 Oct 2026 07:45 AEST: "simplify it and make provision in layer 4
-- to create those batch decisions and rules. And do same for Monash, I want to see how it runs and make rules from ui").
--
-- Finding: most unsettled tuition at the top universities is one wording per university, not a per-course question.
--   UNSW  "2026 Indicative First Year Fee $56,500*"  (international; the domestic block says "First Year Full Fee")
--   Monash "... standard full-time course load for a year. The fees for 2027 are: A$46,640"
-- The page reader keeps every $ amount with the text around it (coverage_course_pages.candidates). A fee wording rule
-- says: at this university, the amount that follows these words is the international tuition, for this period.
--
-- pipeline.fee_wording_rules: provider, the words, fee period, optional page address pattern, status draft / active /
-- paused. Pipeline Operator (4) and above create and preview drafts; PIM Operator (5) and above approve, run and pause
-- (approving is admission authority). An active rule runs hourly on newly read pages.
-- A run admits provider_current_tuition from the saved page (source and evidence of that page, confidence 1) only when:
-- the page is confirmed as the course's page (CRICOS code on the page, or entered by hand); the words match exactly one
-- amount on the page; and the course has no current provider tuition. Years are taken from the words or just before
-- them. Values entered by hand are protected by the manual-lock guard. The course's open Layer 4 tuition items are closed
-- as superseded and its Layer 3 tuition work marked admitted. Every run is logged (layer4_mass_operations) and every
-- admission is kept in pipeline.fee_rule_admissions with the matched text.

create table if not exists pipeline.fee_wording_rules (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id),
  label text not null,
  phrase text not null check (length(btrim(phrase)) >= 6),
  basis text not null check (basis in ('annual','total_indicative','per_semester','per_trimester')),
  url_pattern text,
  status text not null default 'draft' check (status in ('draft','active','paused')),
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  last_run_at timestamptz, admitted int not null default 0, note text);
alter table pipeline.fee_wording_rules enable row level security;
revoke all on pipeline.fee_wording_rules from public, anon, authenticated;

create table if not exists pipeline.fee_rule_admissions (
  id bigint generated always as identity primary key,
  rule_id bigint not null references pipeline.fee_wording_rules(id),
  course_id uuid not null, course_fee_id uuid, amount numeric not null, fee_year int, basis text not null,
  matched_text text not null, admitted_at timestamptz not null default now());
create index if not exists fee_rule_admissions_rule_idx on pipeline.fee_rule_admissions(rule_id, admitted_at desc);
alter table pipeline.fee_rule_admissions enable row level security;
revoke all on pipeline.fee_rule_admissions from public, anon, authenticated;

-- Pages of the provider where the words match exactly one amount.
-- The amount must follow the words within 30 characters that hold no other number except a year ("The fees for 2027
-- are: A$46,640"). The year is taken from that gap, or from just before the words ("2026 Indicative First Year Fee").
create or replace function security.fee_rule_matches(p_provider_id uuid, p_phrase text, p_url_pattern text default null)
returns table(course_id uuid, evidence_id uuid, url text, amount numeric, fee_year int, matched_text text, amounts int, has_fee boolean)
language sql stable set search_path = '' as $$
  with q as (select regexp_replace(btrim(p_phrase), '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') ph),
  m as (
    select g.course_id, g.evidence_id, g.url, x.ctx, q.ph,
           regexp_match(x.ctx, '(?i)' || q.ph || '((?:[^$0-9]|20[2-3][0-9]){0,30}?)(?:A\$|AUD\s*\$?|\$)\s*([0-9]{1,3}(?:,[0-9]{3})+|[0-9]{4,6})(?![0-9]|,[0-9])') mm
      from q, pipeline.coverage_course_pages g
      cross join lateral (select distinct c->>'context' ctx from jsonb_array_elements(coalesce(g.candidates->'fee'->'candidates', '[]'::jsonb)) c) x
     where g.provider_id = p_provider_id and g.read_status = 'read' and g.identity_basis in ('cricos_code','manual') and g.evidence_id is not null
       and (p_url_pattern is null or g.url ~* p_url_pattern)),
  hit as (select *, coalesce(substring(mm[1] from '(20[2-3][0-9])'), substring(ctx from '(?i)(20[2-3][0-9])[^0-9$]{0,6}' || ph))::int yr from m where mm is not null)
  select h.course_id, min(h.evidence_id::text)::uuid, min(h.url),
         min(replace(h.mm[2], ',', '')::numeric), min(h.yr),
         min(left(btrim(coalesce(h.yr::text || ' ', '') || btrim(p_phrase) || h.mm[1] || '$' || h.mm[2]), 200)),
         count(distinct h.mm[2])::int,
         exists (select 1 from catalogue.course_fees f where f.course_id = h.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active')
    from hit h group by h.course_id
$$;
revoke all on function security.fee_rule_matches(uuid, text, text) from public, anon, authenticated;

-- The words just before an amount, as a person would type them into a rule (for suggestions).
create or replace function security.fee_suggest_phrase(p_ctx text, p_amount numeric) returns text language plpgsql immutable set search_path = '' as $$
declare a text := to_char(p_amount, 'FM999,999,999'); p int; pre text; tail text;
begin
  p := strpos(coalesce(p_ctx, ''), a);
  if p = 0 then return null; end if;
  pre := left(p_ctx, p - 1);
  pre := regexp_replace(pre, '(A\$|AUD\s*\$?|\$)\s*$', '');
  pre := regexp_replace(pre, '[\s:*>-]*$', '');
  pre := regexp_replace(pre, '\s*(20[2-3][0-9])(\s+(are|is))?$', '');
  tail := right(pre, 60);
  if tail ~ '20[2-3][0-9]' then tail := regexp_replace(tail, '^.*20[2-3][0-9]\s*', ''); else tail := regexp_replace(tail, '^\S*\s+', ''); end if;
  if position('. ' in tail) > 0 and length(regexp_replace(tail, '^.*\.\s+', '')) >= 12 then tail := regexp_replace(tail, '^.*\.\s+', ''); end if;
  tail := btrim(regexp_replace(tail, '\s+', ' ', 'g'));
  if length(tail) < 8 or tail !~ '[A-Za-z]{3}' then return null; end if;
  return tail;
end $$;
revoke all on function security.fee_suggest_phrase(text, numeric) from public, anon, authenticated;

-- Run one rule (p_apply false = preview only).
create or replace function security.fee_rule_run_v1(p_rule_id bigint, p_apply boolean, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r pipeline.fee_wording_rules%rowtype; m record; v_src uuid; v_fee uuid; n_ok int := 0; n_amb int := 0; n_has int := 0; n_locked int := 0;
        v_courses uuid[] := '{}'; v_op bigint;
begin
  select * into r from pipeline.fee_wording_rules where id = p_rule_id;
  if r.id is null then raise exception 'rule not found'; end if;
  for m in select * from security.fee_rule_matches(r.provider_id, r.phrase, r.url_pattern) loop
    if m.amounts > 1 then n_amb := n_amb + 1; continue; end if;
    if m.has_fee then n_has := n_has + 1; continue; end if;
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
    if not p_apply then n_ok := n_ok + 1; continue; end if;
    select source_id into v_src from pipeline.evidence_artifacts where id = m.evidence_id;
    v_fee := null;
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, evidence_id, confidence, source_fee_key, status, last_verified_at, source_snapshot_at, updated_at)
    values (m.course_id, m.fee_year, 'international', 'provider_current_tuition', m.amount, 'AUD', r.basis,
            format('CF-247 Layer 4 fee wording rule #%s (%s)', r.id, r.label), v_src, m.evidence_id, 1,
            'fee-rule:' || r.id || ':' || coalesce(m.fee_year::text, '') || ':' || r.basis, 'active', now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null do nothing
    returning id into v_fee;
    if v_fee is null then n_has := n_has + 1; continue; end if;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           escalation_reason = format('Settled by Layer 4 fee wording rule #%s (%s)', r.id, r.label)
     where entity_type = 'course' and entity_id = m.course_id and field_code = 'provider_current_tuition_validation' and status in ('pending','returned_layer3');
    update pipeline.layer3_work_items set status = 'admitted', completed_at = now(), last_error = null, updated_at = now()
     where entity_id = m.course_id and task_class = 'provider_current_tuition_validation' and status in ('pending','layer4_required','failed','no_candidate','rejected');
    insert into pipeline.fee_rule_admissions(rule_id, course_id, course_fee_id, amount, fee_year, basis, matched_text)
    values (r.id, m.course_id, v_fee, m.amount, m.fee_year, r.basis, m.matched_text);
    v_courses := v_courses || m.course_id; n_ok := n_ok + 1;
  end loop;
  if p_apply then
    update pipeline.fee_wording_rules set last_run_at = now(), admitted = admitted + n_ok where id = r.id;
    if n_ok > 0 then
      insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
      values ('course_tuition', 'fee_wording_rule_run', coalesce(p_actor, r.approved_by, r.created_by), jsonb_build_object('rule_id', r.id, 'provider_id', r.provider_id, 'phrase', r.phrase),
              format('Fee wording rule #%s: %s', r.id, r.label), n_ok + n_amb + n_has + n_locked, n_ok,
              jsonb_build_object('admitted', n_ok, 'ambiguous', n_amb, 'already_had_fee', n_has, 'entered_by_hand', n_locked), 'CF-CHG-20260915-247');
      perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    end if;
  end if;
  return jsonb_build_object('mode', case when p_apply then 'run' else 'preview' end, 'admitted', n_ok, 'ambiguous', n_amb, 'already_had_fee', n_has, 'entered_by_hand', n_locked);
end $$;
revoke all on function security.fee_rule_run_v1(bigint, boolean, uuid) from public, anon, authenticated;

create or replace function security.fee_rules_run_active_v1() returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v jsonb := '[]'::jsonb;
begin
  for r in select id from pipeline.fee_wording_rules where status = 'active' order by id loop
    v := v || jsonb_build_object('rule', r.id, 'result', security.fee_rule_run_v1(r.id, true, null));
  end loop;
  return v;
end $$;
revoke all on function security.fee_rules_run_active_v1() from public, anon, authenticated;

-- Read: rules, suggestions and recent admissions
create or replace function public.admin_fee_rules_read() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_create', v_rank >= 4, 'can_approve', v_rank >= 5,
    'rules', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'provider_id', r.provider_id, 'provider', coalesce(p.display_name, p.canonical_name),
                'label', r.label, 'phrase', r.phrase, 'basis', r.basis, 'url_pattern', r.url_pattern, 'status', r.status, 'admitted', r.admitted,
                'created_at', r.created_at, 'created_by', cu.email, 'approved_at', r.approved_at, 'approved_by', au.email, 'last_run_at', r.last_run_at, 'note', r.note)
                order by r.status = 'active' desc, r.created_at desc), '[]'::jsonb)
                from pipeline.fee_wording_rules r left join catalogue.providers p on p.id = r.provider_id
                left join auth.users cu on cu.id = r.created_by left join auth.users au on au.id = r.approved_by),
    'suggestions', (select coalesce(jsonb_agg(s order by (s->>'pages')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('provider_id', w.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'phrase', w.phrase,
              'pages', count(distinct w.course_id), 'example', min(w.example),
              'has_rule', exists (select 1 from pipeline.fee_wording_rules r where r.provider_id = w.provider_id and lower(r.phrase) = lower(w.phrase))) s
         from (select g.provider_id, g.course_id, security.fee_suggest_phrase(c->>'context', (c->>'amount')::numeric) phrase, left(c->>'context', 240) example
                 from pipeline.coverage_course_pages g
                 join pipeline.provider_priority pp on pp.provider_id = g.provider_id and pp.rank <= 100
                 cross join lateral jsonb_array_elements(coalesce(g.candidates->'fee'->'candidates', '[]'::jsonb)) c
                where g.read_status = 'read' and g.identity_basis in ('cricos_code','manual') and coalesce(g.candidates->'fee'->>'safe', 'false') <> 'true'
                  and coalesce((c->>'domestic')::boolean, false) = false
                  and not exists (select 1 from catalogue.course_fees f where f.course_id = g.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active')) w
         join catalogue.providers p on p.id = w.provider_id
        where w.phrase is not null
        group by w.provider_id, p.display_name, p.canonical_name, w.phrase
       having count(distinct w.course_id) >= 10
        order by count(distinct w.course_id) desc limit 25) z),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', a.admitted_at, 'rule_id', a.rule_id, 'course_id', a.course_id,
                'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', a.amount, 'fee_year', a.fee_year, 'basis', a.basis, 'text', a.matched_text)
                order by a.admitted_at desc), '[]'::jsonb)
                from (select * from pipeline.fee_rule_admissions order by admitted_at desc limit 30) a join catalogue.courses c on c.id = a.course_id));
end $$;
revoke all on function public.admin_fee_rules_read() from public, anon;
grant execute on function public.admin_fee_rules_read() to authenticated;

-- Preview a rule before saving it (or a saved rule)
create or replace function public.admin_fee_rule_preview(p_provider_id uuid, p_phrase text, p_url_pattern text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or security.current_role_rank() < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_phrase, ''))) < 6 then raise exception 'type at least 6 characters of the words that come before the fee'; end if;
  return (select jsonb_build_object(
      'would_admit', count(*) filter (where amounts = 1 and not has_fee and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition')),
      'ambiguous', count(*) filter (where amounts > 1), 'already_had_fee', count(*) filter (where amounts = 1 and has_fee),
      'amount_range', jsonb_build_object('min', min(amount), 'max', max(amount)),
      'samples', (select coalesce(jsonb_agg(s), '[]'::jsonb) from (
          select jsonb_build_object('course_id', m2.course_id, 'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'amount', m2.amount,
                 'fee_year', m2.fee_year, 'text', m2.matched_text, 'url', m2.url, 'has_fee', m2.has_fee, 'amounts', m2.amounts) s
            from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m2 join catalogue.courses c on c.id = m2.course_id
           order by m2.amounts desc, m2.amount limit 15) z))
    from security.fee_rule_matches(p_provider_id, p_phrase, nullif(btrim(coalesce(p_url_pattern, '')), '')) m);
end $$;
revoke all on function public.admin_fee_rule_preview(uuid, text, text) from public, anon;
grant execute on function public.admin_fee_rule_preview(uuid, text, text) to authenticated;

-- Create, approve, run, pause, resume, delete
create or replace function public.admin_fee_rule_control(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_rank int := security.current_role_rank(); v_id bigint := nullif(p_args->>'id', '')::bigint; r pipeline.fee_wording_rules%rowtype; v_res jsonb;
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if p_action in ('approve','run','pause','resume') and v_rank < 5 then raise exception 'PIM Operator role or above required to approve or run a rule' using errcode = '42501'; end if;
  if p_action = 'create' then
    if nullif(p_args->>'provider_id', '') is null or not exists (select 1 from catalogue.providers where id = (p_args->>'provider_id')::uuid) then raise exception 'choose the university'; end if;
    if length(btrim(coalesce(p_args->>'phrase', ''))) < 6 then raise exception 'type at least 6 characters of the words that come before the fee'; end if;
    if coalesce(p_args->>'basis', '') not in ('annual','total_indicative','per_semester','per_trimester') then raise exception 'choose the fee period'; end if;
    insert into pipeline.fee_wording_rules(provider_id, label, phrase, basis, url_pattern, note, created_by)
    values ((p_args->>'provider_id')::uuid, coalesce(nullif(btrim(coalesce(p_args->>'label', '')), ''), left(btrim(p_args->>'phrase'), 60)), btrim(p_args->>'phrase'),
            p_args->>'basis', nullif(btrim(coalesce(p_args->>'url_pattern', '')), ''), nullif(btrim(coalesce(p_args->>'note', '')), ''), auth.uid())
    returning * into r;
  else
    select * into r from pipeline.fee_wording_rules where id = v_id;
    if r.id is null then raise exception 'rule not found'; end if;
    if p_action = 'approve' then
      if r.status <> 'draft' then raise exception 'only a draft can be approved'; end if;
      update pipeline.fee_wording_rules set status = 'active', approved_by = auth.uid(), approved_at = now() where id = r.id;
      v_res := security.fee_rule_run_v1(r.id, true, auth.uid());
    elsif p_action = 'run' then
      if r.status <> 'active' then raise exception 'only an active rule can be run'; end if;
      v_res := security.fee_rule_run_v1(r.id, true, auth.uid());
    elsif p_action = 'pause' then update pipeline.fee_wording_rules set status = 'paused' where id = r.id;
    elsif p_action = 'resume' then update pipeline.fee_wording_rules set status = 'active' where id = r.id;
    elsif p_action = 'delete' then
      if r.status <> 'draft' then raise exception 'only a draft can be deleted; pause an approved rule instead'; end if;
      delete from pipeline.fee_wording_rules where id = r.id;
    else raise exception 'unknown action %', p_action; end if;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fee_rules', p_action, coalesce(r.label, v_id::text), p_args || jsonb_build_object('rule_id', r.id) || coalesce(jsonb_build_object('result', v_res), '{}'::jsonb), auth.uid());
  return public.admin_fee_rules_read() || jsonb_build_object('result', v_res, 'rule_id', r.id);
end $$;
revoke all on function public.admin_fee_rule_control(text, jsonb) from public, anon;
grant execute on function public.admin_fee_rule_control(text, jsonb) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('fee-wording-rules', 'Admission', 75, 'Apply approved fee wording rules',
  'Admits international tuition from newly read pages using the fee wording rules approved in Layer 4 › Batch rules.', 5, false)
on conflict (jobname) do nothing;
select cron.schedule('fee-wording-rules', '37 * * * *', 'select security.fee_rules_run_active_v1()');
