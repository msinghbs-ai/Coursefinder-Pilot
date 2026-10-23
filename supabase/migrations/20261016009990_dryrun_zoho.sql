-- CF-247 (23 Oct 2026). First run of the AI reader for every attribute (Enrich fields, NZ, 9,642 items, Platform Admin 10:25):
-- 1 Intakes: 121 readings were refused because NZ course pages name semesters ("Semester One and Semester Two") rather than months.
--   A semester, trimester or term the page names is now turned into its start month from the university's approved academic
--   calendar (Layer 4 › Attributes, kind intake_calendar), only when the quote names it.
-- 2 English: 1,416 NZ course pages give no IELTS at all; their value can only come from the university's English rule. Why values
--   are missing now says, for English and intakes the page does not give, the state of the university rule: approved (applies by
--   study level), waiting for approval, its central page gives no values, or no central page found; the last three are listed under
--   Needs a change.
-- Replaces: nothing (public.svc_enrich_ai_record and security.gap_causes_snapshot_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 semesters, trimesters and terms to months from the university's approved calendar ---------------------------------------------
create or replace function security.enrich_parse_intake_periods_v1(p_provider uuid, p_text text, p_quote text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_t text; v_q text; v_months int[] := '{}'; per jsonb; v_name text; v_rx text;
begin
  -- "Semester One", "semester 1", "S1", "Trimester Two" are compared as "semester 1", "trimester 2"
  v_t := regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_text, '')), '\mone\M|\mfirst\M', '1', 'g'), '\mtwo\M|\msecond\M', '2', 'g'), '\mthree\M|\mthird\M', '3', 'g'), '\s+', ' ', 'g');
  v_q := regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_quote, '')), '\mone\M|\mfirst\M', '1', 'g'), '\mtwo\M|\msecond\M', '2', 'g'), '\mthree\M|\mthird\M', '3', 'g'), '\s+', ' ', 'g');
  for per in
    select x from pipeline.provider_policy_proposals p, jsonb_array_elements(coalesce(p.proposal->'periods', '[]'::jsonb)) x
     where p.provider_id = p_provider and p.kind = 'intake_calendar' and p.status = 'approved'
  loop
    v_name := lower(btrim(per->>'period'));
    continue when v_name !~ '^(semester|trimester|term|quarter|block) [0-9]$';
    v_rx := '\m' || split_part(v_name, ' ', 1) || '\s*' || split_part(v_name, ' ', 2) || '\M';
    if v_t ~ v_rx and v_q ~ v_rx then
      v_months := v_months || array(select jsonb_array_elements_text(coalesce(per->'months', '[]'::jsonb))::int);
    end if;
  end loop;
  if cardinality(v_months) = 0 then return null; end if;
  return jsonb_build_object('months', (select jsonb_agg(to_char(make_date(2000, m, 1), 'FMMonth') order by m) from (select distinct unnest(v_months) m) z where m between 1 and 12),
                            'from', 'university calendar');
end $function$;
revoke execute on function security.enrich_parse_intake_periods_v1(uuid, text, text) from public, anon, authenticated;

select pg_temp.edit_once('public.svc_enrich_ai_record(jsonb)', 'ff7e34b9c51241794f61c9c37e436a68', array[
  array[$o$        when 'intakes' then security.enrich_parse_intakes_v1(r->'value'->>'text', r->>'quote')$o$,
        $n$        when 'intakes' then coalesce(security.enrich_parse_intakes_v1(r->'value'->>'text', r->>'quote'),
                                     security.enrich_parse_intake_periods_v1(i.provider_id, r->'value'->>'text', r->>'quote'))  -- 23 Oct 2026: semesters from the approved calendar$n$]]);

-- 2 the university rule's state in Why values are missing -----------------------------------------------------------------------------
select pg_temp.edit_once('security.gap_causes_snapshot_v1()', '8162f563d34d49bd8c76f585e59d5040', array[
  array[$o$  create temp table _gm on commit drop as$o$,
        $n$  create temp table _grule on commit drop as
    select k.provider_id, k.kind,
           case when bool_or(x.status = 'approved') then 'approved' when bool_or(x.status = 'proposed') then 'waiting for approval'
                when bool_or(x.status in ('no_values', 'rejected')) then 'gives no values' else 'not found' end state
      from (select distinct provider_id from _gc) g
      cross join lateral (values (g.provider_id, 'english_policy'), (g.provider_id, 'intake_calendar')) k(provider_id, kind)
      left join pipeline.provider_policy_proposals x on x.provider_id = k.provider_id and x.kind = k.kind and x.status in ('approved', 'proposed', 'no_values', 'rejected')
     group by k.provider_id, k.kind;
  create temp table _gm on commit drop as$n$],
  array[$o$(rv.id is not null) in_review,$o$,
        $n$(rv.id is not null) in_review,
           (select r.state from _grule r where r.provider_id = m.provider_id and r.kind = 'english_policy') eng_rule,
           (select r.state from _grule r where r.provider_id = m.provider_id and r.kind = 'intake_calendar') cal_rule,$n$],
  array[$o$        when e.no_value then 'AI: the page does not state it'$o$,
        $n$        when e.no_value and e.attr = 'english' then 'AI: page gives no IELTS; university English rule ' || coalesce(e.eng_rule, 'not found')
        when e.no_value and e.attr = 'intakes' then 'AI: page gives no start dates; university calendar ' || coalesce(e.cal_rule, 'not found')
        when e.no_value then 'AI: the page does not state it'$n$],
  array[$o$           when z.cause like 'AI:%' then 'read again when the page changes; university-wide rule where there is one'$o$,
        $n$           when z.cause like 'AI:%approved' then 'none: the university rule covers other study levels; the rule needs this course''s level'
           when z.cause like 'AI:%waiting for approval' then 'a person approves the university rule (Layer 4 › Attributes)'
           when z.cause like 'AI:%gives no values' then 'none: the central page read gives no values; the right central page is needed (Adapter builder › central page)'
           when z.cause like 'AI:%not found' then 'none: no central page found; add it (Adapter builder › central page)'
           when z.cause like 'AI:%' then 'read again when the page changes'$n$],
  array[$o$or (z.cause = 'page not read: needs_render' and not (z.cc = any (v_render)))),$o$,
        $n$or (z.cause = 'page not read: needs_render' and not (z.cc = any (v_render)))
              or (z.cause like 'AI:%' and (z.cause like '%approved' or z.cause like '%waiting for approval' or z.cause like '%gives no values' or z.cause like '%not found'))),$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.enrich_parse_intake_periods_v1', 'Layer 2', 'Semesters, trimesters and terms a course page names, to start months from the approved university calendar', 'active', '{}', '20261023013000')
on conflict (kind, name) do nothing;

select security.gap_causes_snapshot_v1();
select 'intake periods from the calendar; university rule state in why values are missing' ok;
do $t$ declare v_p uuid; begin
  select provider_id into v_p from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'approved' and security.coverage_country(provider_id) = 'NZ'
     and proposal->'periods' @> '[{"period":"semester 2"}]' limit 1;
  raise exception 'DRYRUN OK %', jsonb_build_object('p', security.enrich_parse_intake_periods_v1(v_p, 'Semester One, Semester Two', 'Intakes: Semester One (February) and Semester Two'),
    'neg', security.enrich_parse_intake_periods_v1(v_p, 'Semester 2', 'Starts in Semester 1'),
    'rules', (select jsonb_agg(jsonb_build_object('c', cause, 'n', courses, 'a', automatic) order by courses desc) from pipeline.gap_cause_snapshots
               where at = (select max(at) from pipeline.gap_cause_snapshots) and country_code = 'NZ' and attribute = 'english' and cause like 'AI:%')); end $t$;
