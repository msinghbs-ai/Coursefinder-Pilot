CREATE OR REPLACE FUNCTION security.layer4_provider_description_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_pub jsonb; v_shown text; v_key text; v_check jsonb; v_read pipeline.provider_description_reads%rowtype;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' then raise exception 'not a provider description item' using errcode = '22023'; end if;
  if p_actor is null or not exists(select 1 from security.user_roles ur join security.roles rr on rr.code=ur.role_code where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and rr.status='active' and rr.rank>=4) then raise exception 'authorised Layer 4 reviewer rank 4 required' using errcode='42501'; end if;
  if i.status<>'pending' then raise exception 'the provider description decision is no longer pending' using errcode='22023'; end if;
  if not security.provider_description_scope_v1(i.entity_id) or not exists(select 1 from catalogue.providers p where p.id=i.entity_id and p.lifecycle_status='active' and p.publication_status='published')
    or exists(select 1 from security.provider_hidden_v1 h where h.provider_id=i.entity_id) then raise exception 'provider is no longer active, published and eligible' using errcode='22023'; end if;
  select * into v_read from pipeline.provider_description_reads r where r.review_item_id=i.id and r.state='proposed' for update;
  if v_read.id is null or v_read.evidence_id is distinct from i.evidence_id or not exists(select 1 from pipeline.evidence_artifacts a join pipeline.sources s on s.id=a.source_id where a.id=i.evidence_id and s.provider_id=i.entity_id and a.source_url=v_read.source_url and coalesce(a.content_hash,a.id::text)=v_read.content_hash) then
    raise exception 'provider description evidence lineage changed' using errcode='22023'; end if;
  if not (security.provider_description_identity_v1(i.entity_id,v_read.source_url)->>'ok')::boolean then raise exception 'provider description identity no longer valid' using errcode='22023'; end if;
  if v_read.checks->'identity_snapshot' is not null then
    if v_read.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(i.entity_id) then raise exception 'provider identity changed since the source read; request new verified evidence' using errcode='22023'; end if;
  else
    -- Legacy proposals retain their original history: do not fabricate a historical identity snapshot. Revalidate the current full name against their actual retained official quote.
    if not exists(select 1 from catalogue.providers p cross join lateral jsonb_array_elements(coalesce(i.proposed_value->'sentences','[]'::jsonb)) sentence
      where p.id=i.entity_id and exists(select 1 from unnest(array[p.canonical_name,p.display_name]) nm where nullif(btrim(nm),'') is not null and position(regexp_replace(lower(nm),'[^a-z0-9]+','','g') in regexp_replace(lower(sentence->>'quote'),'[^a-z0-9]+','','g'))>0)) then
      raise exception 'legacy proposal has no identity snapshot and its retained quote does not verify the current full provider name' using errcode='22023';
    end if;
    update pipeline.provider_description_reads set checks=coalesce(checks,'{}'::jsonb)||jsonb_build_object('legacy_identity_quote_revalidated_at',now(),'identity_verification','legacy official quotation revalidated against current full name; no historical snapshot inferred') where id=v_read.id;
  end if;

  v_check:=security.provider_description_validate_v1(i.entity_id,v_read.source_url,v_read.source_captured_at,jsonb_build_object('about_page',true,'sentences',i.proposed_value->'sentences'));
  if v_check->>'outcome' not in ('propose','verified') or v_check->>'text' is distinct from i.proposed_value->>'description' then raise exception 'provider description no longer passes source and factual validation: %',v_check->>'rule' using errcode='22023'; end if;
  -- approved as read: an edited description has no quote for its new words, so it is not admitted (reject, and the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('description', 'p_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- verify publication: the Website API v2 provider payload is read back (a provider not published returns nothing yet)
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin
    v_pub := public.website_v2_provider(v_key);
    v_shown := v_pub->'item'->>'description';
  exception when others then v_shown := null;
  end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(),
         published_at = case when v_shown = v_text then now() end, updated_at = now()
   where review_item_id = i.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now()
   where provider_id = i.entity_id and state = 'admitted' and review_item_id is distinct from i.id;
  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id);
end $function$
