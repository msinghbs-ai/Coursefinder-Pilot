-- CF-247 (8 Oct 2026, Platform Admin: "Fix Layer 1 reader, refill"): qilt-au-etl v0.3.0 stored every QILT confidence interval without
-- its upper bound (the reader used cell.h; the parsed field is cell.hi). Found by the QILT register adapter replay. qilt-au-etl v0.3.1
-- stores it from now on. This refills the upper bound of the existing rows from the published cell kept with each row
-- (metadata.source_raw), read with the same pattern the reader uses. Refused unless the same reading gives back every stored value and
-- lower bound unchanged. Only confidence_high (and a note in metadata) changes; no row is added or removed.
do $g$
declare v_bad int;
begin
  with p as (select o.metric_value, o.confidence_low,
                    regexp_match(btrim(replace(o.metadata->>'source_raw', chr(160), ' ')), '^(-?[\d,]+(?:\.\d+)?)\s*(?:\(\s*(-?[\d,]+(?:\.\d+)?)\s*,\s*(-?[\d,]+(?:\.\d+)?)\s*\))?') m
               from catalogue.provider_outcomes o where o.metadata->>'publisher' = 'QILT')
  select count(*) into v_bad from p
   where (m[1] is not null and metric_value is distinct from replace(m[1], ',', '')::numeric)
      or (m[2] is not null and confidence_low is distinct from replace(m[2], ',', '')::numeric);
  if v_bad > 0 then raise exception 'QILT rows whose stored value or lower bound does not match the published cell: %; refusing to refill', v_bad; end if;
end $g$;

with p as (select o.id, regexp_match(btrim(replace(o.metadata->>'source_raw', chr(160), ' ')), '^(-?[\d,]+(?:\.\d+)?)\s*(?:\(\s*(-?[\d,]+(?:\.\d+)?)\s*,\s*(-?[\d,]+(?:\.\d+)?)\s*\))?') m
             from catalogue.provider_outcomes o where o.metadata->>'publisher' = 'QILT' and o.confidence_high is null)
update catalogue.provider_outcomes o
   set confidence_high = replace(p.m[3], ',', '')::numeric,
       metadata = o.metadata || jsonb_build_object('confidence_high_refilled', 'CF-247 8 Oct 2026: upper bound refilled from source_raw (qilt-au-etl v0.3.1 fix)'),
       updated_at = now()
  from p where p.id = o.id and p.m[3] is not null;
