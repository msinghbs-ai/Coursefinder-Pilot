// CF-247 s1110 (S1-Build, Admin #1048, 25 Nov 2026): a PDF is known by what the server sends, not by its address. A content store or
// download script often serves a PDF at an address with no ".pdf" (CQUniversity's country table from delivery-cqucontenthub.stylelabs.cloud),
// which the entry-page fetch used to keep as "not_html". These two checks decide it instead: the HTTP Content-Type, then the file's own
// signature. A PDF file begins with "%PDF-"; the PDF reference allows a few bytes before it, and readers look in the first 1,024 bytes.

const PDF_TYPES = /^(application\/(pdf|x-pdf|acrobat|vnd\.pdf)|applications?\/vnd\.pdf|text\/(x-)?pdf)$/i;
// types a server sends for a file it does not name (a download), and an empty type: worth asking for the file, the signature decides
const UNNAMED_TYPES = /^(application\/(octet-stream|download|x-download|force-download|binary|unknown)|binary\/octet-stream)$/i;
const SIGNATURE_WINDOW = 1024;  // fixed: the PDF reference's header window

export type PdfHint = "pdf" | "unnamed" | "other";

// the media type alone (parameters such as "; charset=" dropped)
export const mediaType = (contentType: string | null | undefined): string => String(contentType || "").split(";")[0].trim().toLowerCase();

// what the Content-Type says: a PDF, a file the server does not name, or something else (HTML, JSON, an image)
export function pdfHint(contentType: string | null | undefined): PdfHint {
  const t = mediaType(contentType);
  if (PDF_TYPES.test(t)) return "pdf";
  if (!t || UNNAMED_TYPES.test(t)) return "unnamed";
  return "other";
}

// the file signature: "%PDF-" within the first 1,024 bytes
export function hasPdfSignature(b: Uint8Array | null | undefined): boolean {
  if (!b || b.length < 5) return false;
  const n = Math.min(b.length - 4, SIGNATURE_WINDOW);
  for (let i = 0; i < n; i++) if (b[i] === 0x25 && b[i + 1] === 0x50 && b[i + 2] === 0x44 && b[i + 3] === 0x46 && b[i + 4] === 0x2d) return true;
  return false;
}

// the same test on text a server sent as a page (a PDF mislabelled text/html is read as text by the page fetch)
export const textHasPdfSignature = (t: string | null | undefined): boolean => /%PDF-/.test(String(t || "").slice(0, SIGNATURE_WINDOW));

// should a direct page read that was not usable HTML be fetched again as a PDF? Yes when the server named a PDF or named nothing, or
// when the text it sent begins like a PDF; never for another named type. The bytes' signature still decides (readPdf: not_pdf otherwise).
export function retryAsPdf(r: { status: string; ctype?: string | null; html?: string | null }): boolean {
  if (r.status === "robots_disallowed" || r.status === "gone" || r.status === "blocked" || r.status === "fetch_failed") return false;
  if (r.html && textHasPdfSignature(r.html)) return true;
  return r.status === "not_html" && pdfHint(r.ctype) !== "other";
}
