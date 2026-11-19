-- Include the explicitly reviewed Sydney regional-expert set in the final A15
-- runtime acceptance contract without duplicating the complete governed helper.

do $$
declare
  v_oid oid;
  v_def text;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='security'
    and p.proname='admin_a15_acceptance_status'
    and pg_get_function_identity_arguments(p.oid)=''
  limit 1;
  if v_oid is null then raise exception 'security.admin_a15_acceptance_status() not found'; end if;

  select pg_get_functiondef(v_oid) into v_def;
  if position($needle$'sydney'$needle$ in v_def)=0 then
    if position($needle$    'otago',exists($needle$ in v_def)=0 then
      raise exception 'A15 key-contact marker not found';
    end if;
    if position($needle$    and coalesce((v_key_contacts->>'otago')::boolean,false)$needle$ in v_def)=0 then
      raise exception 'A15 acceptance conjunction marker not found';
    end if;

    v_def:=replace(
      v_def,
      $needle$    'otago',exists($needle$,
      $replacement$    'sydney',(
      select count(*)=4
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='the university of sydney'
        and o.is_current and o.verification_state='current'
        and o.team_name='International Recruitment'
        and o.source_url='https://www.sydney.edu.au/study/applying/how-to-apply/international-students/contact-our-regional-experts.html'
        and o.metadata->>'a15_quality_reconciliation'='sydney_first_party_regional_experts'
        and (o.full_name,o.job_title,o.territory_text,o.work_email) in (
          ('Chris Lawrance','Regional Manager','Americas and Europe','chris.lawrance@sydney.edu.au'),
          ('Nishant Jadhav','Senior Regional Manager','Central Asia, South Asia, Middle East and Africa','nishant.jadhav@sydney.edu.au'),
          ('Sean Lee','Senior Regional Manager','Asia (excluding China, Hong Kong and Macau)','sean.lee@sydney.edu.au'),
          ('Sherrie Huan','Senior Regional Manager','China, Hong Kong and Macau','sherrie.huan@sydney.edu.au')
        )
    ),
    'otago',exists($replacement$
    );
    v_def:=replace(
      v_def,
      $needle$    and coalesce((v_key_contacts->>'otago')::boolean,false)$needle$,
      $replacement$    and coalesce((v_key_contacts->>'sydney')::boolean,false)
    and coalesce((v_key_contacts->>'otago')::boolean,false)$replacement$
    );
    execute v_def;
  end if;
end $$;
