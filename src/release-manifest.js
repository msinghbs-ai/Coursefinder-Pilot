// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.334'
export const PACKAGE_VERSION='0.1.261'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Oct 2026',
  title:'NZ brief Release 1: transition register, domain move, fee floor',
  changes:[
    'New Zealand polytechnic transition: each provider in the transition carries its status from the Government\'s published pages (source cited on the row); a daily job re-checks its website and asks the source finder to look again (Settings › Pipeline settings › Transition: re-check every; Tai Poutini every 14 days).',
    'Adapter builder › Change website: "Move the course pages too" moves the bound course pages and list sources to the new host, keeping their proof, and reads them again first in line (Platform Admin, logged).',
    'International fee floor per country (Settings › Pipeline settings › Identify the page: NZ, AU and CA 8,000 in their currency): a fee on an annual basis below the floor is quarantined to Layer 4 with the reason, never shown until a person decides. 20 NZ fees below NZ$8,000 withdrawn to review, 2 short English-course fees kept and flagged.'
  ],
  bugFixes:[]
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
