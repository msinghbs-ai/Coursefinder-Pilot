CREATE OR REPLACE FUNCTION security.provider_presentable_name(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with a as (select replace(replace(replace(replace(replace(coalesce(p,''),'&#039;',''''),'&#39;',''''),'&amp;','&'),'&quot;','"'),'&apos;','''') x),
       b as (select btrim(split_part(x,';',1)) x from a),
       c as (select btrim(regexp_replace(regexp_replace(x,'[\s,]+(pty\.?\s*(ltd|limited)\.?|limited|ltd\.?|incorporated|inc\.?)\s*$','','i'),'[\s,]+(pty\.?\s*(ltd|limited)\.?|limited|ltd\.?)\s*$','','i')) x from b)
  select case when p is null then null
              when c.x !~ '[a-z]' and c.x ~ '[A-Z]' then
                (select string_agg(case when w ~ '^\(?(TAFE|RMIT|UNSW|ANU|UTS|QUT|ACU|CQU|JCU|NSW|QLD|VIC|TAS|WA|SA|NT|ACT|UK|USA|ELICOS|ESL|EAP|IT|IELTS|AIBT|ICHM|MIT|KOI|SIBT|UWA|ECU|CDU|USQ|USC|SCU|CIT|AIE|AIT|ATMC|NIET|IIBIT|AIH|APIC|ACBI|ACAH|CBD|RTO|VET)\)?[,.]?$' then w
                                        when ord>1 and lower(w) in ('of','and','the','for','in','at','&','de') then lower(w)
                                        else initcap(w) end, ' ' order by ord)
                   from regexp_split_to_table(c.x,'\s+') with ordinality t(w,ord))
              else c.x end
    from c
$function$
