// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.16'
export const PACKAGE_VERSION='0.1.438'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Invitations and password resets return to the admin sign-in; catalogue lists export to CSV',
  changes:[
    'Administration › Users & roles: Reset password emails another person a link to choose a new password (not a Platform Admin, a disabled account or one whose invitation is still open).',
    'Administration › Users & roles › Create user: an invitation can carry the person\'s full name; the email names their role and links the Platform guide.',
    'Invitation and reset links open the StudySearch Admin sign-in, which asks for the new password first. The sign-in screen has Forgot password? for your own account.',
    'Providers, Courses, Locations and Scholarships catalogues: Export CSV writes the whole filtered list, with the visible columns or all columns (opens in Excel).'
  ],
  bugFixes:[
    'An invited person was signed in by the link but never asked to choose a password; they now set it on arrival.',
    'The website and Zoho APIs are unchanged (no database change in this release).'
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
