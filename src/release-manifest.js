// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.318'
export const PACKAGE_VERSION='0.1.245'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'22 Oct 2026',
  title:'Adapter builder: every step by hand',
  changes:[
    'Layer 2/3 › Adapter builder is back in the tabs (after Build adapter). Build adapter › a university has Do it by hand in Adapter builder.',
    'Manual mode end to end: course pages on each row or from a course list page (2.1), samples (2.2), Write the settings by hand (3.1 opens step 4), steps 3.2 and 3.3 count as done when the settings were saved by hand, and step 4 opens with one read page (was 3).',
    '3.4: a Platform Admin can admit a field that has not passed the check, as their own decision (asked to confirm, logged).',
    'Screenshots of a university\'s latest capture are kept while its adapter is not admitting yet, up to 30 days (setting); others are removed after 7 days as before.'
  ],
  bugFixes:['A build done by hand never showed steps 3.2 and 3.3 as done, because they waited for an AI proposal.']
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
