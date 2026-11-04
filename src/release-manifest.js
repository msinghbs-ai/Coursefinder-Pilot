// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.470'
export const PACKAGE_VERSION='0.1.397'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'4 Nov 2026',
  title:'AER review queue: ready items first, university summary and readable recovery',
  changes:[
    'A university\'s Entry requirements (AER) pill opens on its items ready to decide first, with All waiting one click away; every decision is still one item at a time through the existing Approve, Approve except and Reject actions, gated as before.',
    'Each university shows a summary: pending, ready, technically held, needing input, stale, open human input, admitted and unresolved.',
    'Held AER cards show a review packet (course, qualification, country, audience, stored evidence and quotations, proposed and active rows, manual locks, checks, recommended decision and its consequences) and a readable recovery summary instead of raw data.',
    'Held reads that no automatic fix can reach raise one Human input needed item each; reads refused at the row limit wait for a row-limit decision and are not re-read or sent for rows.',
    'Reviewers can claim a university so two reviewers do not work the same items.'
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
