-- CF-247 (2 Oct 2026, 22:26 AEST). Platform Admin, in chat, on Decision 203: "Cricos doesnt needs to be checked."
-- Australian English requirements are admitted from a page on the provider's own site that shows the CRICOS code or
-- whose title is exactly the course title (the rule already used for Australian course links and intakes).
-- Values entered by hand are never overwritten; tuition is unchanged (Decision 225).
do $g$
begin
  if (select a.identities->'english' from pipeline.coverage_admission_countries a join ref.countries k on k.id = a.country_id
       where k.iso_alpha2 = 'AU') is distinct from '["cricos_code"]'::jsonb then
    raise exception 'AU English identities are not ["cricos_code"]; not changing';
  end if;
end $g$;

update pipeline.coverage_admission_countries a
   set identities = a.identities || jsonb_build_object('english', '["cricos_code", "exact_title"]'::jsonb),
       approved_ref = a.approved_ref || '; Decision 234 (English from the CRICOS code or the exact title, no CRICOS check needed; Platform Admin 2 Oct 2026 22:26)',
       updated_at = now()
  from ref.countries k
 where k.id = a.country_id and k.iso_alpha2 = 'AU';
