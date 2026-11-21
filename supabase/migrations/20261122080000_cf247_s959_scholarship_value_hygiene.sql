-- CF-247 s959 (session S1-API-Frontend-Delivery, Lane 1 item 3; Platform Admin 22 Nov 2026 01:20 AEDT: "Upper figure, marked up to"): scholarship
-- value hygiene. REQ-64, REQ-71; REQ-72 checked.
--
-- REQ-64: published scholarships whose value disagreed with their note. Read live 22 Nov 2026 01:15 AEDT:
--   26 notes read "X% to Y% of tuition fees" (19 held X, 7 held Y, none marked up to);
--   2 notes read "Up to Y% of tuition fees" but held a lower figure.
--   Rule (Platform Admin): the value is the upper figure Y, marked up to (award_value_is_maximum), so it reads "up to Y%" and agrees with the
--   note, which is unchanged.
-- REQ-71: the last 3 published scholarships held as text only. Their stored notes state the value, so they are read from the note, with no
--   page fetch ($0 Firecrawl):
--   "20% to 50% of tuition fees" gives 50%, up to (the REQ-64 rule);
--   "Up to A$8,025 (...)" gives A$8,025, up to;
--   "Up to A$15,000 (...)" gives A$15,000, up to.
-- REQ-72: checked live 22 Nov 2026 01:10 AEDT: round states are refreshed (1,000 in the last hour, job scholarship-flow-guard), and no published
--   scholarship with a passed closing date (Melbourne date) is anything but closed or ended. The post-check below asserts it.
-- A value held under a manual lock (award_value, award_value_type, award_amount, award_percentage) is never changed. Each change is logged in
-- pipeline.scholarship_sweep_changes (by s959, with the rule). No row is published, unpublished or deleted.
-- Live on deploy. $0. G1: no job. G2: no operational value. G3: checked before and after. Locks: 7,585 unchanged.
-- Parity: live head 20261122070000 read 22 Nov 2026 01:25 AEDT; this file is numbered strictly above it.
-- Replaces: the lower or mixed figures held for range notes.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s959_locks on commit drop as select count(*) n from pipeline.manual_locks;

create temp table s959_fix on commit drop as
with base as (
  select s.id, s.evidence_id, s.award_value_type t, s.award_percentage pct, s.award_amount amt, s.award_currency_code cur, s.award_value_is_maximum mx, s.award_value_text v,
         regexp_match(s.award_value_text, '^(\d+(?:\.\d+)?)%\s+to\s+(\d+(?:\.\d+)?)%\s+of\s') rng,
         regexp_match(s.award_value_text, '^Up to (\d+(?:\.\d+)?)%\s+of\s') upto_pct,
         regexp_match(s.award_value_text, '^Up to A\$([0-9][0-9,]*(?:\.\d+)?)(?:\s|$)') upto_aud
    from scholarship.scholarships s
   where s.publication_status = 'published' and s.lifecycle_status = 'active' and s.award_value_type in ('percentage', 'text_only')
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id
                       and k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage')))
select id, evidence_id, v, jsonb_build_object('type', t, 'percentage', pct, 'amount', amt, 'currency', cur, 'maximum', mx) before,
       case when rng is not null then 'percentage' when upto_pct is not null then 'percentage' else 'fixed_amount' end new_type,
       case when rng is not null then rng[2]::numeric when upto_pct is not null then upto_pct[1]::numeric end new_pct,
       case when rng is null and upto_pct is null then replace(upto_aud[1], ',', '')::numeric end new_amt,
       case when rng is not null then 'range_upper_up_to' when upto_pct is not null then 'up_to_stated' else 'up_to_amount_stated' end rule
  from base
 where (rng is not null and rng[1]::numeric < rng[2]::numeric and rng[2]::numeric <= 100 and (t <> 'percentage' or pct is distinct from rng[2]::numeric or mx is not true))
    or (upto_pct is not null and upto_pct[1]::numeric <= 100 and (t <> 'percentage' or pct is distinct from upto_pct[1]::numeric or mx is not true))
    or (t = 'text_only' and rng is null and upto_pct is null and upto_aud is not null);

update scholarship.scholarships s
   set award_value_type = f.new_type,
       award_percentage = case when f.new_type = 'percentage' then f.new_pct else s.award_percentage end,
       award_amount = case when f.new_type = 'fixed_amount' then f.new_amt else s.award_amount end,
       award_currency_code = case when f.new_type = 'fixed_amount' then 'AUD' else s.award_currency_code end,
       award_applies_to_fee_type = case when f.new_type = 'percentage' then coalesce(s.award_applies_to_fee_type, 'tuition_fee') else s.award_applies_to_fee_type end,
       award_value_is_maximum = true,
       updated_at = now()
  from s959_fix f where f.id = s.id;

insert into pipeline.scholarship_sweep_changes (scholarship_id, field, before_value, after_value, evidence_id)
select f.id, 'award_value', f.before,
       jsonb_build_object('by', 's959', 'rule', f.rule, 'type', f.new_type, 'percentage', f.new_pct, 'amount', f.new_amt,
                          'currency', case when f.new_type = 'fixed_amount' then 'AUD' end, 'maximum', true, 'note', left(f.v, 300),
                          'decision', 'Platform Admin 22 Nov 2026 01:20 AEDT: upper figure, marked up to'),
       f.evidence_id
  from s959_fix f;

do $c$
declare v_api jsonb := security.consumer_api_check_v1(); v_left int; v_text int; v_open int; v_n int := (select count(*) from s959_fix);
begin
  select count(*) into v_left from scholarship.scholarships s
   where s.publication_status = 'published' and s.lifecycle_status = 'active' and s.award_value_type = 'percentage'
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage'))
     and ((s.award_value_text ~ '^(\d+(?:\.\d+)?)%\s+to\s+(\d+(?:\.\d+)?)%\s+of\s' and not (s.award_percentage = (regexp_match(s.award_value_text, '^(\d+(?:\.\d+)?)%\s+to\s+(\d+(?:\.\d+)?)%'))[2]::numeric and s.award_value_is_maximum))
       or (s.award_value_text ~ '^Up to (\d+(?:\.\d+)?)%\s+of\s' and not (s.award_percentage = (regexp_match(s.award_value_text, '^Up to (\d+(?:\.\d+)?)%'))[1]::numeric and s.award_value_is_maximum)));
  if v_left <> 0 then raise exception 'post-check: % range or up-to values still disagree with their note', v_left; end if;
  select count(*) into v_text from scholarship.scholarships where publication_status = 'published' and lifecycle_status = 'active' and award_value_type = 'text_only';
  select count(*) into v_open from scholarship.scholarships s left join pipeline.scholarship_round_states r on r.scholarship_id = s.id
   where s.publication_status = 'published' and s.lifecycle_status = 'active' and s.application_close_date < (now() at time zone 'Australia/Melbourne')::date
     and coalesce(r.state, '?') not in ('closed_round', 'ended');
  if v_open <> 0 then raise exception 'post-check (REQ-72): % published scholarships with a passed closing date are not closed', v_open; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s959_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's959: % values corrected; text-only left %; open with passed date %', v_n, v_text, v_open;
end $c$;
