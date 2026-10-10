begin;

-- Reject non-university imagery previously discovered from Hotcourses pages.
update pipeline.provider_asset_candidates
set status='rejected',
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'rejection_reason','Hotcourses page UI/subject/placeholder image; not the university logo',
      'rejected_by_change_control','CF-CHG-20260903-101',
      'rejected_at',now()
    )
where source_url ilike 'https://www.hotcoursesabroad.com/%'
  and (
    asset_url ilike '%/newheader_logo_%'
    or asset_url ilike '%/newfooter_logo_%'
    or asset_url ilike '%/idp_logo_%'
    or asset_url ilike '%/default/img_px.gif%'
    or asset_url ilike '%/chubp_subject/%'
    or asset_url ilike '%/flags/%'
    or coalesce(metadata->>'alt','') ilike '%Hotcourses%'
    or coalesce(metadata->>'alt','') ilike 'A photo representing %'
  );

commit;
