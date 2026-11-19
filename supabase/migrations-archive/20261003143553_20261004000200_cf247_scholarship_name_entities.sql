-- CF-247 (4 Oct 2026). Scholarship names read from a page's heading kept numeric character references
-- ("Vice-Chancellor&#039;s", "President&#x27;s", "&#8217;"): six names. The page reader decodes them from v0.6.1; the
-- names already stored are decoded here. A name entered by hand is left alone.
create or replace function scholarship.decode_entities(p text) returns text
language plpgsql immutable set search_path = '' as $f$
declare v text := p; m text[];
begin
  if v is null then return null; end if;
  for m in select regexp_matches(v, '&#[xX]([0-9a-fA-F]{1,6});', 'g') loop
    v := replace(v, '&#x' || m[1] || ';', chr(('x' || lpad(m[1], 8, '0'))::bit(32)::int));
    v := replace(v, '&#X' || m[1] || ';', chr(('x' || lpad(m[1], 8, '0'))::bit(32)::int));
  end loop;
  for m in select regexp_matches(v, '&#([0-9]{1,7});', 'g') loop
    v := replace(v, '&#' || m[1] || ';', chr(m[1]::int));
  end loop;
  return replace(replace(v, '&apos;', ''''), '&amp;', '&');
end $f$;
update scholarship.scholarships s set name = scholarship.decode_entities(s.name), updated_at = now() where s.name ~ '&(#[0-9]+|#[xX][0-9a-fA-F]+|apos|amp);' and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'name');
