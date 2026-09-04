update pipeline.scholarship_acquisition_trace
set first_party_detail_url='https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/monash-international-leadership-scholarship-5571Z',
    updated_at=now(),
    metadata=metadata || jsonb_build_object('url_verified_at',now(),'change_control_ref','CF-CHG-20260904-109')
where observed_title='Monash International Leadership Scholarship'
  and first_party_detail_url is distinct from 'https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/monash-international-leadership-scholarship-5571Z';