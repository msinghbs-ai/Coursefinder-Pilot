import './ui-kit.css'
// Layer 1 › + Add source › Country & scheme: what this source will create (v2.16.38, Platform Admin 18 Nov 2026 10:31 and 10:33: "onboarding a new
// country supports mapping all newly introduced API v3 and Layer 1 fields, and establishing baseline records directly from the wizard").
// The records are made by the server when the activated source's first apply run reads its rows (S2-Build, Pilot PRs 1258 and 1263: security.layer1_parser_targets_v1 and
// public.svc_layer1_apply_baseline_records_v1, called by layer1-declarative-runner 1.1.0 in apply runs only). This panel says, before anything is
// saved, which baseline records a record type creates, the rule each follows, and which API v3 fields its mapping fills. It writes nothing.
import React from'react'

// by record type: what an apply run creates, and the API v3 fields the mapped values reach (field paths as in ref.api_field_dictionary)
export const BASELINE={
  course_register:{creates:['Providers and courses the register lists, made by the register apply (as for every country: all 249 are in the reference list).',
    'Study load (full-time, part-time or both) and Empty reason, only on courses that hold none.'],
    fields:['study_load','empty_reason_code'],v3:['item.study_load','item.empty_reason_code']},
  provider_register:{creates:['Providers and their registrations, made by the register apply.'],fields:[],v3:['item.provider_id']},
  campuses:{creates:['A campus only where the registered provider has none of that name.','Primary only when the provider has no primary campus yet.'],
    fields:['provider_code','campus_name','postcode','is_primary'],v3:['item.campuses[].is_primary','item.campuses[].locality (from the postcode, once its locality is approved)']},
  provider_accreditations:{creates:['An AACSB, EQUIS or AMBA accreditation only where the provider has none from that body.'],
    fields:['provider_code','body_code','accredited_unit_name'],v3:['item.provider.accreditations[]','item.accreditations[] (provider action)']},
  grade_scale_conversions:{creates:['Grade scale conversions, held inactive until a person reviews them on Reference data › Grade scale conversions.'],
    fields:['qualification_code','scale_code','raw_grade_label'],v3:['Reference data only (not returned by the API until reviewed)']},
  destination_metrics:{creates:['City and region figures, staged for a person to review. Nothing is written to the destination tables until approved on Destination data › City metrics & costs.'],
    fields:['locality_name','metric_category','metric_key','numeric_value'],v3:['localities[].metrics[] (destination action, once approved and the edition published)']},
  tuition_fees:{creates:['Tuition rows, staged for a person to review before they reach the course.'],fields:['course_code','amount','currency_code','fee_year'],v3:['item.tuition (course action, once admitted)']},
  study_rules:{creates:['Visa, work and study rules, staged for review; approved on Destination data › Study rules.'],fields:['rule_category','title','quote_on_page','source_url'],v3:['study_rules[] (destination action, once approved and the edition published)']},
  career_outcomes:{creates:['Occupations, earnings and outlook, staged for review; approved on Destination data › Careers & outcomes.'],fields:['occupation_scheme','occupation_code','median_salary'],v3:['career_outcomes[] (destination action, once approved)']},
  scholarships:{creates:['Scholarship records, staged for review before they are published.'],fields:['provider_code','title','url'],v3:['scholarship and scholarships actions (once published)']},
}
export const NOT_INVENTED='Rows for a provider the register does not list are counted, never invented. Nothing is published, overwritten or deleted, and nothing runs until a Platform Admin activates the source and its terms are approved.'

export default function Layer1BaselinePreview({type,countryName=''}){const b=BASELINE[type];if(!b)return null
  return <aside className="ui-l1i-baseline" data-l1i-baseline={type} aria-label="What this source will create">
    <h4>What this source will create{countryName?` for ${countryName}`:''}</h4>
    <ul>{b.creates.map(x=><li key={x}>{x}</li>)}</ul>
    <p className="ui-l1i-baseline-v3"><strong>API v3 fields it fills:</strong> {b.v3.join(' · ')}</p>
    {b.fields.length>0&&<p className="ui-l1i-baseline-map" data-l1i-baseline-fields><strong>Parser spec fields:</strong> {b.fields.map(x=><code key={x}>{x}</code>)} (AI Auto-Map fills them on the Field mapping step)</p>}
    <p className="ui-l1i-baseline-rule">{NOT_INVENTED}</p>
  </aside>}
