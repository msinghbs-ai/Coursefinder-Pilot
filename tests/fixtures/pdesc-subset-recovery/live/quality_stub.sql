-- Guards: F-PDESC.01-.05 (sentence-subset recovery): a stand-in for security.provider_description_quality_v1 (which lives in the Fill fields migration 20261110030000, outside this harness): one row for each provider asked for, with the columns the status read joins. Fixture only; it computes nothing the status read adds.
create or replace function security.provider_description_quality_v1(p_ids uuid[] default null, p_feeds boolean default true)
 returns table(provider_id uuid, quality_class text, description_filled boolean, admission_state text, source_tier text, evidence_id uuid, source_url text, reader_state text, reader_rule text, reader_tries integer,
               l4_status text, hold_reason text, next_retry_at timestamptz, last_read_ok_at timestamptz, admitted_at timestamptz, admitted_by text, website_state text, zoho_state text,
               website_publication text, zoho_publication text, readback_at timestamptz, missing_fields text[])
 language sql stable as $f$
  select p.id, 'fixture'::text, nullif(btrim(p.description), '') is not null, null::text, null::text, null::uuid, null::text, null::text, null::text, null::integer,
         (select li.status from pipeline.layer4_review_items li where li.entity_id = p.id and li.field_code = 'provider_description' order by li.created_at desc limit 1),
         null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::text, null::text, null::text, null::text, null::text, null::timestamptz, array[]::text[]
    from catalogue.providers p where p.id = any(p_ids)
$f$;
