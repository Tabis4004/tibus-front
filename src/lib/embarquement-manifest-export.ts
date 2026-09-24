import { format } from "date-fns";
import jsPDF from "jspdf";
import autoTable from "jspdf-autotable";
import { supabase } from "@/lib/supabase";

export type EmbarquementManifest = {
  session_id: string;
  company_name: string | null;
  route_label: string | null;
  gare_name: string | null;
  departure_time: string | null; // heure du départ Tibus (null hors Tibus)
  bus_plate: string | null; // matricule = plaque du bus
  bus_name: string | null;
  from_tibus: boolean;
  generated_at: string;
  passengers: {
    scan_id: string;
    passenger_name: string | null;
    ticket_number: string | null;
    origin: string | null;
    destination: string | null;
    scanned_at: string;
    source: string | null;
  }[];
};

export async function fetchEmbarquementManifest(
  sessionId: string,
): Promise<EmbarquementManifest> {
  const { data, error } = await supabase.rpc("embarquement_manifest_data", {
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data as EmbarquementManifest;
}

/**
 * Convention « NOM Prénom » : les premiers mots entièrement en majuscules
 * forment le nom, le reste le prénom (ex. « KOFFI Ama Grace » → KOFFI / Ama Grace).
 * Si tout est en majuscules ou en minuscules, le premier mot est le nom.
 * Un seul mot : il est mis dans « Nom ».
 */
export function splitFullName(full: string | null | undefined): { nom: string; prenom: string } {
  const tokens = (full ?? "").trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return { nom: "", prenom: "" };
  if (tokens.length === 1) return { nom: tokens[0], prenom: "" };
  const isUpper = (w: string) => w === w.toUpperCase() && w !== w.toLowerCase();
  let n = 0;
  while (n < tokens.length - 1 && isUpper(tokens[n])) n++;
  if (n === 0 || n === tokens.length) n = 1;
  return { nom: tokens.slice(0, n).join(" "), prenom: tokens.slice(n).join(" ") };
}

const HEADERS = ["N°", "Nom", "Prénom", "Destination", "N° billet"] as const;

function rows(m: EmbarquementManifest) {
  return m.passengers.map((p, i) => {
    const { nom, prenom } = splitFullName(p.passenger_name);
    return [String(i + 1), nom, prenom, p.destination ?? "", p.ticket_number ?? ""];
  });
}

function departureLabel(m: EmbarquementManifest) {
  return m.departure_time ? format(new Date(m.departure_time), "dd/MM/yyyy HH:mm") : "—";
}

function slug(m: EmbarquementManifest) {
  const d = m.departure_time ? new Date(m.departure_time) : new Date(m.generated_at);
  return `manifeste-${format(d, "yyyy-MM-dd_HHmm")}`;
}

function metaLines(m: EmbarquementManifest): [string, string][] {
  return [
    ["Compagnie", m.company_name ?? ""],
    ["Trajet", m.route_label ?? ""],
    ["Gare", m.gare_name ?? ""],
    ["Heure de départ", departureLabel(m)],
    ["Matricule du car", m.bus_plate ?? "—"],
    ["Passagers", String(m.passengers.length)],
  ];
}

export function exportEmbarquementManifestPDF(m: EmbarquementManifest) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  doc.setFontSize(14);
  doc.setFont("helvetica", "bold");
  doc.text("Manifeste passagers", 14, 14);
  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");
  metaLines(m).forEach(([k, v], i) => doc.text(`${k} : ${v}`, 14, 24 + i * 6));

  autoTable(doc, {
    startY: 24 + metaLines(m).length * 6 + 4,
    head: [[...HEADERS]],
    body: rows(m),
    theme: "striped",
    styles: { fontSize: 9, cellPadding: 2 },
    headStyles: { fillColor: [75, 0, 130], fontSize: 9, fontStyle: "bold" },
  });
  doc.setFontSize(7);
  doc.text(
    `Généré le ${format(new Date(), "dd/MM/yyyy HH:mm")} — Powered By Tibus`,
    14,
    doc.internal.pageSize.getHeight() - 8,
  );
  doc.save(`${slug(m)}.pdf`);
}

// Fichier ouvrable dans Excel (CSV UTF-8 avec BOM, séparateur « ; » pour Excel FR).
export function exportEmbarquementManifestExcel(m: EmbarquementManifest) {
  const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;
  const lines = [
    ...metaLines(m).map(([k, v]) => [k, v]),
    [],
    [...HEADERS],
    ...rows(m),
  ]
    .map((r) => r.map((c) => esc(String(c))).join(";"))
    .join("\n");
  const blob = new Blob(["\uFEFF" + lines], { type: "text/csv;charset=utf-8;" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `${slug(m)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

export function printEmbarquementManifest(m: EmbarquementManifest) {
  const html = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const body = rows(m)
    .map((r) => `<tr>${r.map((c) => `<td>${html(c)}</td>`).join("")}</tr>`)
    .join("");
  const meta = metaLines(m)
    .map(([k, v]) => `<div><b>${html(k)} :</b> ${html(v)}</div>`)
    .join("");
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>Manifeste</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:16px}
h1{font-size:16px}table{border-collapse:collapse;width:100%;margin-top:10px}
th,td{border:1px solid #999;padding:4px 6px;text-align:left}th{background:#eee}</style></head>
<body><h1>Manifeste passagers</h1>${meta}
<table><thead><tr>${HEADERS.map((h) => `<th>${h}</th>`).join("")}</tr></thead><tbody>${body}</tbody></table>
<script>window.onload=function(){window.print()}</script></body></html>`);
  w.document.close();
}
