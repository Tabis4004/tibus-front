import { format } from "date-fns";
import {
  commercialOfferFieldValue,
  resolveCommercialOfferLocale,
  type CommercialOfferDocument,
  type CommercialOfferField,
  type CommercialOfferLocale,
} from "@/data/commercial-offer-content.ts";

function downloadBlob(filename: string, blob: Blob) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.rel = "noopener";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function exportBaseName(locale: CommercialOfferLocale, countryName?: string | null) {
  const base = locale === "en" ? "tibus-commercial-offer" : "offre-commerciale-tibus";
  if (!countryName?.trim()) return base;
  const slug = countryName
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  return slug ? `${base}-${slug}` : base;
}

export function downloadCommercialOfferJson(
  document: CommercialOfferDocument,
  locale: string | undefined,
  countryName?: string | null,
) {
  const resolved = resolveCommercialOfferLocale(locale);
  const payload = {
    exportedAt: new Date().toISOString(),
    locale: resolved,
    countryName: countryName ?? null,
    document,
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  downloadBlob(`${exportBaseName(resolved, countryName)}.json`, blob);
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function fieldLine(field: CommercialOfferField) {
  return `<p><strong>${escapeHtml(field.label)} :</strong> <em>${escapeHtml(commercialOfferFieldValue(field))}</em></p>`;
}

function buildCommercialOfferHtml(document: CommercialOfferDocument) {
  const { letter, technical, financial, meta } = document;
  const modulesRows = technical.modules
    .map(
      (module) =>
        `<tr><td>☐</td><td>${escapeHtml(module.code)}</td><td>${escapeHtml(module.title)}</td><td>${escapeHtml(module.description)}${module.requires ? ` (requires ${module.requires})` : ""}</td></tr>`,
    )
    .join("");

  const archRows = technical.architectureTable.rows
    .map(([a, b]) => `<tr><td>${escapeHtml(a)}</td><td>${escapeHtml(b)}</td></tr>`)
    .join("");

  const finRows = financial.modulePricingRows
    .map((row) => `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join("")}</tr>`)
    .join("");

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${escapeHtml(meta.title)}</title>
<style>
body { font-family: Calibri, Arial, sans-serif; font-size: 11pt; line-height: 1.45; color: #111; }
h1 { font-size: 18pt; color: #1A5296; }
h2 { font-size: 13pt; margin-top: 24px; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; }
th, td { border: 1px solid #ccc; padding: 6px 8px; vertical-align: top; }
th { background: #E8F0FE; }
.footer { font-size: 9pt; color: #666; font-style: italic; margin-top: 24px; }
.page-break { page-break-before: always; }
ul { margin: 8px 0 8px 20px; }
</style></head><body>
<h1>${escapeHtml(letter.title)}</h1>
${letter.fields.map((field) => fieldLine(field)).join("")}
<p><strong>Objet :</strong> ${escapeHtml(letter.subject)}</p>
<p>${escapeHtml(letter.salutation)}</p>
${letter.paragraphs.map((p) => `<p>${escapeHtml(p)}</p>`).join("")}
<ul>${letter.annexBullets.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
<p><em>${escapeHtml(letter.offlineNote)}</em></p>
${letter.closing.split("\n\n").map((p) => `<p>${escapeHtml(p)}</p>`).join("")}
${letter.signatureFields.map((field) => fieldLine(field)).join("")}

<div class="page-break"></div>
<h1>${escapeHtml(technical.title)}</h1>
<p><strong>${escapeHtml(technical.subtitle)}</strong></p>
${technical.fields.map((field) => fieldLine(field)).join("")}
${technical.sections
  .map((section) => {
    const body = [
      ...(section.paragraphs ?? []).map((p) => `<p>${escapeHtml(p)}</p>`),
      section.bullets?.length
        ? `<ul>${section.bullets.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`
        : "",
    ].join("");
    return `<h2>${escapeHtml(section.heading)}</h2>${body}`;
  })
  .join("")}
<h2>2. Architecture technique (incluse dans l'abonnement)</h2>
<table><thead><tr>${technical.architectureTable.headers.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${archRows}</tbody></table>
<h2>3. Modules proposés (sélection à cocher)</h2>
<table><thead><tr><th>☐</th><th>Module</th><th>Intitulé</th><th>Contenu fonctionnel</th></tr></thead><tbody>${modulesRows}</tbody></table>

<div class="page-break"></div>
<h1>${escapeHtml(financial.title)}</h1>
<p><strong>${escapeHtml(financial.subtitle)}</strong></p>
${financial.fields.map((field) => fieldLine(field)).join("")}
<h2>1. Grille tarifaire par module</h2>
<table><thead><tr>${financial.modulePricingHeaders.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${finRows}</tbody></table>
<h2>2. Pack complet (modules A + B + C + D + E)</h2>
<table><thead><tr>${financial.packTable.headers.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${financial.packTable.rows.map((row) => `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join("")}</tr>`).join("")}</tbody></table>
<h2>3. Conditions de facturation</h2>
<ul>${financial.billingBullets.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
<h2>4. Synthèse de l'offre retenue</h2>
<table><thead><tr>${financial.summaryTable.headers.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${financial.summaryTable.rows.map((row) => `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join("")}</tr>`).join("")}</tbody></table>
<h2>${escapeHtml(financial.agreementTitle)}</h2>
${financial.agreementFields.map((field) => fieldLine(field)).join("")}
<p class="footer">${escapeHtml(meta.footer)}</p>
</body></html>`;
}

export function downloadCommercialOfferWord(
  document: CommercialOfferDocument,
  locale: string | undefined,
  countryName?: string | null,
) {
  const resolved = resolveCommercialOfferLocale(locale);
  const html = buildCommercialOfferHtml(document);
  const blob = new Blob(["\ufeff", html], { type: "application/msword" });
  downloadBlob(`${exportBaseName(resolved, countryName)}.doc`, blob);
}

export async function downloadCommercialOfferPdf(
  document: CommercialOfferDocument,
  locale: string | undefined,
  countryName?: string | null,
) {
  const [{ default: jsPDF }, { default: autoTable }] = await Promise.all([
    import("jspdf"),
    import("jspdf-autotable"),
  ]);
  const resolved = resolveCommercialOfferLocale(locale);
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const stamp = format(new Date(), "yyyy-MM-dd");
  let y = 14;

  const addTitle = (title: string) => {
    if (y > 250) {
      doc.addPage();
      y = 14;
    }
    doc.setFont("helvetica", "bold");
    doc.setFontSize(13);
    doc.text(title, 14, y);
    doc.setFont("helvetica", "normal");
    y += 8;
  };

  const addParagraph = (text: string, size = 9) => {
    const lines = doc.splitTextToSize(text, 182);
    if (y + lines.length * 4 > 285) {
      doc.addPage();
      y = 14;
    }
    doc.setFontSize(size);
    doc.text(lines, 14, y);
    y += lines.length * 4 + 2;
  };

  doc.setFillColor(26, 82, 150);
  doc.rect(0, 0, 210, 22, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(13);
  doc.setFont("helvetica", "bold");
  doc.text(document.meta.title, 14, 10);
  doc.setFontSize(8);
  doc.setFont("helvetica", "normal");
  doc.text(`${document.meta.product} · ${stamp}`, 14, 16);
  doc.setTextColor(0, 0, 0);
  y = 30;

  addTitle(document.letter.title);
  for (const field of document.letter.fields) {
    addParagraph(`${field.label} : ${commercialOfferFieldValue(field)}`, 8);
  }
  addParagraph(`Objet : ${document.letter.subject}`);
  addParagraph(document.letter.salutation);
  for (const paragraph of document.letter.paragraphs) addParagraph(paragraph);
  for (const bullet of document.letter.annexBullets) addParagraph(`• ${bullet}`);
  addParagraph(document.letter.offlineNote, 8);
  addParagraph(document.letter.closing);

  doc.addPage();
  y = 14;
  addTitle(document.technical.title);
  addParagraph(document.technical.subtitle, 10);
  for (const field of document.technical.fields) {
    addParagraph(`${field.label} : ${commercialOfferFieldValue(field)}`, 8);
  }
  for (const section of document.technical.sections) {
    addTitle(section.heading);
    for (const paragraph of section.paragraphs ?? []) addParagraph(paragraph);
    for (const bullet of section.bullets ?? []) addParagraph(`• ${bullet}`);
  }

  autoTable(doc, {
    startY: y,
    head: [document.technical.architectureTable.headers],
    body: document.technical.architectureTable.rows,
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as import("jspdf").jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 30;
  y += 6;

  autoTable(doc, {
    startY: y,
    head: [["☐", "Module", "Intitulé", "Contenu"]],
    body: document.technical.modules.map((module) => [
      "☐",
      module.code,
      module.title,
      `${module.description}${module.requires ? ` (A)` : ""}`,
    ]),
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });

  doc.addPage();
  y = 14;
  addTitle(document.financial.title);
  addParagraph(document.financial.subtitle, 10);
  for (const field of document.financial.fields) {
    addParagraph(`${field.label} : ${commercialOfferFieldValue(field)}`, 8);
  }

  autoTable(doc, {
    startY: y,
    head: [document.financial.modulePricingHeaders],
    body: document.financial.modulePricingRows,
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });
  y = (doc as import("jspdf").jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 30;
  y += 6;

  autoTable(doc, {
    startY: y,
    head: [document.financial.packTable.headers],
    body: document.financial.packTable.rows,
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });

  y = (doc as import("jspdf").jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 20;
  y += 8;
  addTitle("3. Conditions de facturation");
  for (const bullet of document.financial.billingBullets) addParagraph(`• ${bullet}`, 8);

  autoTable(doc, {
    startY: y,
    head: [document.financial.summaryTable.headers],
    body: document.financial.summaryTable.rows,
    styles: { fontSize: 7 },
    headStyles: { fillColor: [26, 82, 150] },
    margin: { left: 14, right: 14 },
  });

  y = (doc as import("jspdf").jsPDF & { lastAutoTable?: { finalY: number } }).lastAutoTable?.finalY ?? y + 20;
  y += 8;
  addTitle(document.financial.agreementTitle);
  for (const field of document.financial.agreementFields) {
    addParagraph(`${field.label} : ${commercialOfferFieldValue(field)}`, 8);
  }
  addParagraph(document.meta.footer, 8);

  doc.save(`${exportBaseName(resolved, countryName)}.pdf`);
}
