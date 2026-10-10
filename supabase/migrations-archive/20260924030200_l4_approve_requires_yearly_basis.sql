-- Layer 4: plain Approve requires a proposed fee already confirmed as per year.
-- A rolled-back proof found approve-suggested items whose proposed basis was Layer 2's
-- unresolved "annual_or_indicative_requires_validation". A person must confirm frequency
-- explicitly, so those items say to use Edit and approve (the form requires a choice).
do $mig$
declare d text;
  a1 text := $q$and jsonb_typeof(b.proposed_value)='object' then jsonb_build_object('action','approve','text','The page shows this amount as a yearly fee.')$q$;
  b1 text := $q$and jsonb_typeof(b.proposed_value)='object' and lower(coalesce(b.proposed_value->>'basis','')) in ('annual','indicative_annual','per_year_explicit') then jsonb_build_object('action','approve','text','The page shows this amount as a yearly fee.')
      when b.quotes_text ~ '\m(annual|annually|per year|per annum|a year|yearly)\M' and jsonb_typeof(b.proposed_value)='object' then jsonb_build_object('action','check','text','The page shows a yearly fee. Use Edit and approve to confirm the amount and that it is charged per year.')$q$;
  a2 text := $q$(b.field_code<>'provider_current_tuition_validation' or jsonb_typeof(b.proposed_value)='object')$q$;
  b2 text := $q$(b.field_code<>'provider_current_tuition_validation' or (jsonb_typeof(b.proposed_value)='object' and lower(coalesce(b.proposed_value->>'basis','')) in ('annual','indicative_annual','per_year_explicit')))$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'confirm the amount and that it is charged per year')>0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $mig$;
