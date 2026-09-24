-- Layer 4: "Suggest approve" and Approve require an actual proposed fee.
-- 33 of 274 waiting tuition items had no fee value (the AI declined to propose one), yet
-- some were labelled "Suggest approve" because the page quoted yearly wording. Approving
-- them could only fail. Now: approve suggestion and can_approve need a proposed value;
-- otherwise the item says to use Edit and approve. Guarded substitution of the live desk read.
do $mig$
declare d text;
  a1 text := $q$when b.quotes_text ~ '\m(annual|annually|per year|per annum|a year|yearly)\M' then jsonb_build_object('action','approve','text','The page shows this amount as a yearly fee.')$q$;
  b1 text := $q$when b.quotes_text ~ '\m(annual|annually|per year|per annum|a year|yearly)\M' and jsonb_typeof(b.proposed_value)='object' then jsonb_build_object('action','approve','text','The page shows this amount as a yearly fee.')
      when b.quotes_text ~ '\m(annual|annually|per year|per annum|a year|yearly)\M' then jsonb_build_object('action','check','text','The page shows a yearly fee, but no amount was proposed. Use Edit and approve to enter it.')$q$;
  a2 text := $q$'can_approve', b.entity_type='course',$q$;
  b2 text := $q$'can_approve', b.entity_type='course' and (b.field_code<>'provider_current_tuition_validation' or jsonb_typeof(b.proposed_value)='object'),$q$;
begin
  d := pg_get_functiondef('security.layer4_review_desk_v1_impl(text,integer)'::regprocedure);
  if strpos(d,'no amount was proposed')>0 then return; end if;
  if (length(d)-length(replace(d,a1,'')))/length(a1) <> 1 then raise exception 'anchor 1 not found exactly once'; end if;
  if (length(d)-length(replace(d,a2,'')))/length(a2) <> 1 then raise exception 'anchor 2 not found exactly once'; end if;
  execute replace(replace(d,a1,b1),a2,b2);
end $mig$;
