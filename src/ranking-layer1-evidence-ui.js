// CF-230 — Ranking Layer 1 Evidence UI guard
// Ranking acquisition is Evidence-first. Parse.bot and URL acquisition remain retired
// at the backend and are not exposed to operators in Sources & Imports.

const PANEL = '.m-ranking-import-page';

function textOf(node) {
  return String(node?.textContent || '').replace(/\s+/g, ' ').trim();
}

function applyRankingEvidenceUi() {
  const root = document.querySelector(PANEL);
  if (!root) return;

  const head = root.querySelector('.m-ranking-import-head p');
  if (head) {
    head.textContent = 'Upload authorised publisher Evidence for the selected ranking system and edition. QS and THE are processed by dedicated Layer 1 Ranking ETL workers; source URL remains provenance metadata only.';
  }

  for (const label of root.querySelectorAll('label')) {
    const text = textOf(label);
    if (text.startsWith('Import method')) {
      label.hidden = true;
      label.setAttribute('aria-hidden', 'true');
    }
    if (/^(QS publisher URL|THE publisher URL|Parse\.bot scraper URL)/i.test(text)) {
      label.hidden = true;
      label.setAttribute('aria-hidden', 'true');
    }
  }

  for (const node of root.querySelectorAll('.m-ranking-detected')) {
    if (/Parse\.bot|established API|metered/i.test(textOf(node))) node.remove();
  }

  const fileLabel = [...root.querySelectorAll('label')].find(x => textOf(x).startsWith('Publisher file(s)'));
  if (fileLabel) {
    const small = fileLabel.querySelector('small');
    if (small) small.textContent = 'Select an authorised publisher Evidence file. A complete global edition is preferred; supported same-edition country/page bundles remain accepted where required.';
  }

  const workflow = root.querySelector('.m-ranking-history-head p');
  if (workflow) {
    workflow.textContent = 'Register publisher Evidence → Layer 1 Ranking ETL validates and applies → mapping exceptions remain traceable separately. Historical imports and Evidence remain available for audit.';
  }

  root.dataset.cf230EvidenceOnly = 'true';
}

const observer = new MutationObserver(applyRankingEvidenceUi);
observer.observe(document.documentElement, { childList: true, subtree: true });
window.addEventListener('hashchange', applyRankingEvidenceUi);
window.addEventListener('DOMContentLoaded', applyRankingEvidenceUi);
applyRankingEvidenceUi();
