update pipeline.sources s
set url='https://www.niagaracollege.ca/enrolmentservices/admissions/availability/',
    metadata=metadata||jsonb_build_object('source_url_updated','2026-08-14','source_url_previous','https://www.niagaracollege.ca/enrolmentservices/program-availability/'),
    updated_at=now()
from integration.systems i
where s.system_id=i.id and i.code='ca_on_niagara_availability';
