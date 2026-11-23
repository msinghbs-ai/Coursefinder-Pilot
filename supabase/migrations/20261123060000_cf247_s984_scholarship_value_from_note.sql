-- CF-247 s984 (S2-Build; Platform Admin 23 Nov 2026 11:10 AEDT, Phase 3: "fix deterministic parser, currency/amount bound ('up to' upper-figure rule
-- from REQ-64) ... in the canonical scholarship pipeline so all valid scholarships pass publishability automatically"; REQ-71): the hourly
-- scholarship publishing job reads the award value from the stored note when the record holds it as text only.
-- Measured live 23 Nov 2026 11:40 to 11:55 AEDT (rolled-back read-backs): of the unpublished active scholarships, 193 are held only by "no stated
-- award value". 13 of them state the value in their stored note while the award fields stayed text only ("a one-off payment of $1,000",
-- "a 20% reduction on tuition fees", "offers up to $60,000", "options of $3,000, $5,000, $6,000, or $10,000 per year"); the others state no
-- figure. s959 read three such notes once by hand (REQ-71); this makes the same reading a standing step, so a new record is read the same way.
-- What changes (in place, md5-guarded; no new table, function, job or setting): security.scholarship_auto_publish_v1 (job scholarship-auto-publish,
-- hourly at :29) reads, before its publishability check, every active scholarship held as text only with no amount or percentage, a note, and no
-- manual lock on its value fields. Rules, in order (the first that matches wins; nothing is read from a figure that is not an award):
--   percentage of tuition: "N% reduction|discount|fee waiver|off ... tuition" or "discount|reduction|waiver of [up to] N% on|of|off tuition",
--     1 to 100, applies to tuition_fee;
--   tiered amount: "options of $A, $B ... or $Z" gives the upper figure, marked up to (the REQ-64 rule);
--   amount: "<one-off payment|scholarship|award|grant|bursary|stipend|payment> of [up to] $N", "provides|offers|is worth [up to] $N",
--     "$N [annual|one-off] award|scholarship|grant|bursary|payment"; currency is the provider country's currency; "up to" marks the maximum;
--     "one-off" gives one_off and "per year|annual|each year|per annum" gives annual.
-- Each change is logged in pipeline.scholarship_sweep_changes. The publishability check and every other rule are unchanged, so a record the note
-- fixes is published by the same tick only if it passes every check.
-- Live on deploy. G1: no job. G2: no operational value (the patterns are the reading rule). G3: no consumer object (75/48 before and after).
-- Manual locks untouched. $0 (no fetch, no model). Nothing dropped or removed.
-- Replaces: nothing (a new step at the start of security.scholarship_auto_publish_v1, one fragment).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s984_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $e$
declare v_def text := pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure); v_n int;
        v_old constant text := $o$  perform security.scholarship_expire_v1();
$o$;
        v_new constant text := $n$  perform security.scholarship_expire_v1();
  -- s984 (23 Nov 2026, REQ-64/REQ-71): the award value read from the stored note of a record held as text only (rules in migration 20261123060000)
  with c as (
    select s.id, s.evidence_id, s.description d, coalesce(co.default_currency_code::text, 'AUD') cur
      from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id left join ref.countries co on co.id = p.country_id
     where s.lifecycle_status = 'active' and coalesce(s.award_value_type, 'text_only') = 'text_only'
       and s.award_amount is null and s.award_percentage is null and nullif(btrim(s.description), '') is not null
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id
                         and k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage', 'all'))),
  m as (
    select c.*,
           coalesce(substring(c.d from '(?i)((?:up to )?[0-9]{1,3}(?:\.[0-9]+)? ?(?:%|per ?cent)[^.]{0,30}?(?:reduction|discount|fee waiver|off)[^.]{0,40}?tuition)'),
                    substring(c.d from '(?i)((?:discount|reduction|waiver) of (?:up to )?[0-9]{1,3}(?:\.[0-9]+)? ?(?:%|per ?cent) (?:on|of|off) (?:the )?tuition)')) pct_clause,
           substring(c.d from '(?i)(options of (?:\$ ?[0-9][0-9,]*(?:,? or |,? and |, ))+\$ ?[0-9][0-9,]*[^.]{0,40})') tier_clause,
           coalesce(substring(c.d from '(?i)((?:one-off payment|scholarship|award|grant|bursary|stipend|payment)[^.$]{0,30}? of (?:up to )?\$ ?[0-9][0-9,]*[^.]{0,40})'),
                    substring(c.d from '(?i)((?:provides|offers|is worth) (?:up to )?\$ ?[0-9][0-9,]*[^.]{0,40})'),
                    substring(c.d from '(?i)(\$ ?[0-9][0-9,]* (?:annual |one-off )?(?:award|scholarship|grant|bursary|payment)[^.]{0,40})')) amt_clause
      from c),
  v as (
    select m.id, m.evidence_id, m.cur,
           case when m.pct_clause is not null then 'percentage' when coalesce(m.tier_clause, m.amt_clause) is not null then 'fixed_amount' end kind,
           case when m.pct_clause is not null then substring(m.pct_clause from '([0-9]{1,3}(?:\.[0-9]+)?) ?(?:%|per ?cent)')::numeric
                when m.tier_clause is not null then (select max(replace(x[1], ',', '')::numeric) from regexp_matches(m.tier_clause, '\$ ?([0-9][0-9,]*)', 'g') x)
                when m.amt_clause is not null then replace(substring(m.amt_clause from '\$ ?([0-9][0-9,]*)'), ',', '')::numeric end num,
           coalesce(m.pct_clause, m.tier_clause, m.amt_clause) clause,
           (m.pct_clause is null and m.tier_clause is not null) or coalesce(m.pct_clause, m.tier_clause, m.amt_clause) ~* 'up to' is_max
      from m),
  ok as (
    select v.* from v
     where v.kind is not null and v.num > 0 and (v.kind <> 'percentage' or v.num <= 100)),
  u as (
    update scholarship.scholarships s
       set award_value_type = ok.kind,
           award_percentage = case when ok.kind = 'percentage' then ok.num end,
           award_amount = case when ok.kind = 'fixed_amount' then ok.num end,
           award_currency_code = case when ok.kind = 'fixed_amount' then ok.cur else s.award_currency_code end,
           award_applies_to_fee_type = case when ok.kind = 'percentage' then 'tuition_fee' else s.award_applies_to_fee_type end,
           award_duration_basis = coalesce(s.award_duration_basis, case when ok.clause ~* 'one-off' then 'one_off'
                                                                         when ok.clause ~* '(per year|annual|each year|per annum)' then 'annual' end),
           award_value_is_maximum = ok.is_max,
           award_value_text = coalesce(nullif(btrim(s.award_value_text), ''), left(btrim(ok.clause), 200)),  -- fixed: the value text shows 200 characters
           updated_at = now()
      from ok
     where s.id = ok.id and s.award_amount is null and s.award_percentage is null
    returning s.id, ok.kind, ok.num, ok.is_max, ok.evidence_id)
  insert into pipeline.scholarship_sweep_changes (scholarship_id, field, before_value, after_value, evidence_id)
  select u.id, 'award_value', 'text_only', u.kind || ' ' || u.num || case when u.is_max then ' (up to)' else '' end || ' (s984: read from the stored note)', u.evidence_id
    from u;
$n$;
begin
  if position('s984 (23 Nov 2026' in v_def) > 0 then raise notice 's984: already applied'; return; end if;
  if md5(v_def) <> '971c6011f0cb1c53dc77e1e4d6ce6bb2' then
    raise exception 'guard: live security.scholarship_auto_publish_v1 differs from the definition this change edits (live md5 %)', md5(v_def);
  end if;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n <> 1 then raise exception 'guard: the fragment is found % times', v_n; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from pg_temp.s984_locks) then raise exception 'post-check: manual locks changed'; end if;
  if position('s984 (23 Nov 2026' in pg_get_functiondef('security.scholarship_auto_publish_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the publishing job was not edited';
  end if;
end $p$;
