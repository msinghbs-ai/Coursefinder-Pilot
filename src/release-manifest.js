// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.153'
export const PACKAGE_VERSION='0.1.80'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'English from each university\'s own policy',
  changes:[
    'Coverage › Attributes › English policies: each university\'s English language policy is read from its own site and parsed without AI into a default score for undergraduate and postgraduate coursework courses, plus any courses it names with their own score.',
    'Review courses shows what approval does to each course. A Platform Admin approves each policy; approval fills only courses with no English requirement, no review open and no page still to read, and holds back research degrees, double degrees, other levels and courses the policy names. Approved policies are applied again every six hours.',
    'Each policy shows how many courses whose own pages already give a score agree or differ with it; a default that most course pages disagree with (at least 10 compared) cannot be approved. Warnings show when a policy has exceptions it does not name or when some courses need more.',
    'Coverage › Attributes › Academic calendars: the month each semester, trimester or term starts, read from each university\'s calendar, for a Platform Admin to approve.',
    'The 446 intake and English reviews where the AI quoted text that was not on the saved page were sent back to the AI check.'
  ],
  bugFixes:[
    'Retry failed for tuition no longer brings back tuition work parked because the regulator publishes the fee (Decision 225).'
  ]
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
