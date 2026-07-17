package com.tibus.courrier.printer

import android.content.Context
import android.util.Log
import wangpos.sdk4.libbasebinder.Printer
import java.text.Normalizer
import java.util.Locale
import org.json.JSONObject
import org.json.JSONArray
import org.json.JSONTokener

/**
 * Direct driver for the built-in POS P3 / TPE thermal printer.
 *
 * Repris tel quel depuis tibus-v2-HUB (app.onhercules.tibus.printer.P3PrinterModule)
 * — seul le package a changé (com.tibus.courrier.printer). C'est le driver Wangpos/
 * Wiseasy réellement utilisé en production côté Tibus web (contrairement à
 * WisePrinterModule, qui est un ancien squelette non branché). Utilisé ici via
 * P3PrinterChannel (MethodChannel Flutter) au lieu d'un pont WebView JS.
 */
class P3PrinterModule(private val ctx: Context) {

    @Volatile private var printer: Printer? = null

    fun warmUp() { runCatching { printer() }.onFailure { Log.e(TAG, "warmUp failed", it) } }

    fun init() {
        val p = printer()
        checkCode("printInit", p.printInit())
        runCatching { p.setGrayLevel(4) }
        runCatching { p.setPrintLineSpacing(4) }
    }

    // ------------------------------------------------------------------
    // Public APIs
    // ------------------------------------------------------------------

    /** Text receipt API (used when JS sends a free-form text blob + QR). */
    fun printReceipt58(title: String, rawText: String, qrContent: String = "") {
        val bookingLines = tryBuildV38BookingLines(title, rawText)
        if (bookingLines != null) {
            val pl = tryParseJsonObject(rawText)
            val cName  = pl?.optString("companyName","")?.ifBlank { pl.optString("company","") } ?: ""
            val cPhone = pl?.optString("companyPhone","")?.ifBlank { pl.optString("phone","") } ?: ""
            val cEmail = pl?.optString("companyEmail","")?.ifBlank { pl.optString("email","") } ?: ""
            renderV38BookingReceipt(bookingLines, qrContent, paperWidth = 32, qrSize = 220,
                companyName  = cName.ifBlank { cleanTitle(title) },
                companyPhone = cPhone,
                companyEmail = cEmail)
            return
        }
        renderUnified(parseAny(title, rawText, qrContent), paperWidth = 32, qrSize = 220)
    }

    /** Text receipt API in 80 mm mode (used by the 80 mm mobile button). */
    fun printReceipt80(title: String, rawText: String, qrContent: String = "") {
        val bookingLines = tryBuildV38BookingLines(title, rawText)
        if (bookingLines != null) {
            val pl = tryParseJsonObject(rawText)
            val cName  = pl?.optString("companyName","")?.ifBlank { pl.optString("company","") } ?: ""
            val cPhone = pl?.optString("companyPhone","")?.ifBlank { pl.optString("phone","") } ?: ""
            val cEmail = pl?.optString("companyEmail","")?.ifBlank { pl.optString("email","") } ?: ""
            renderV38BookingReceipt(bookingLines, qrContent, paperWidth = 48, qrSize = 280,
                companyName  = cName.ifBlank { cleanTitle(title) },
                companyPhone = cPhone,
                companyEmail = cEmail)
            return
        }
        renderUnified(parseAny(title, rawText, qrContent), paperWidth = 48, qrSize = 280)
    }

    /** Structured 58 mm API (TPE bridge for vente directe / réservation). */
    fun printReceipt58(
        header: List<String>,
        reference: String,
        rows: List<Pair<String, String>>,
        qrContent: String,
        footer: String
    ) {
        renderUnified(
            normalizeStructured(header, reference, rows, qrContent, footer),
            paperWidth = 32,
            qrSize = 220
        )
    }

    /** Structured 80 mm API. Same fields, same order, wider paper. */
    fun printReceipt80(
        header: List<String>,
        reference: String,
        rows: List<Pair<String, String>>,
        qrContent: String,
        footer: String
    ) {
        renderUnified(
            normalizeStructured(header, reference, rows, qrContent, footer),
            paperWidth = 48,
            qrSize = 280
        )
    }

    fun printText(text: String, opts: PrintOptions) {
        val p = preparePrinter()
        printWrappedLine(p, text, opts, width = 32)
        finishPrinter(p)
    }

    fun printQRCode(content: String, sizePx: Int) {
        val p = preparePrinter()
        checkCode("printQRCode", p.printQRCode(content, sizePx.coerceIn(120, 360), Printer.Align.CENTER))
        finishPrinter(p)
    }

    fun feed(lines: Int) {
        val p = printer()
        checkCode("printPaper", p.printPaper(lines.coerceAtLeast(1) * 24))
    }

    fun cut() { runCatching { printer().cutPaper() } }

    fun status(): Map<String, Any> {
        val p = printer()
        val status = intArrayOf(0)
        val code = p.getPrinterStatus(status)
        return mapOf("ready" to (code == 0), "code" to code, "status" to status[0])
    }

    fun release() { printer = null }

    // ------------------------------------------------------------------
    // Unified ticket data + renderer
    // ------------------------------------------------------------------

    /** Canonical ticket model. All paths converge here. */
    private data class Ticket(
        val company: String = "TIBUS",
        val companyEmail: String = "",
        val companyPhone: String = "",
        val subtitle: String = "Ticket de reservation",
        val reference: String = "",
        val passenger: String = "",
        val passengerPhone: String = "",
        val route: String = "",
        val departurePlace: String = "",
        val departureTime: String = "",
        val arrivalPlace: String = "",
        val arrivalTime: String = "",
        val bus: String = "",
        val seat: String = "",
        val parcel: String = "",
        val parcelWeight: String = "",
        val parcelAmount: String = "",
        val total: String = "",
        val extraFields: List<Pair<String, String>> = emptyList(),
        val qr: String = "",
        val footer: String = "Powered by Tibus",
    )

    /** Single source of truth: layout used by sale, reservation and reprint. */
    private fun renderUnified(t: Ticket, paperWidth: Int, qrSize: Int) {
        val p = preparePrinter()

        // ---- Header
        printWrappedLine(p, t.company.ifBlank { "TIBUS" },
            PrintOptions(align = "center", size = "large", bold = true), paperWidth)
        if (t.companyPhone.isNotBlank())
            printWrappedLine(p, "Tel: ${t.companyPhone}",
                PrintOptions(align = "center", size = "small"), paperWidth)
        if (t.companyEmail.isNotBlank())
            printWrappedLine(p, t.companyEmail,
                PrintOptions(align = "center", size = "small"), paperWidth)
        if (t.subtitle.isNotBlank())
            printWrappedLine(p, t.subtitle,
                PrintOptions(align = "center", size = "small"), paperWidth)

        // ---- Reference
        // Cadre ASCII (+/-) plutôt que des glyphes Unicode de dessin de boîte :
        // ces derniers ne sont pas fiables sur toutes les polices ESC/POS
        // (rendu en caractères parasites sur certains modèles). +/- fonctionne
        // partout et reproduit l'effet "N° encadré" du modèle papier de
        // référence. Taille normale (pas "large") pour que la largeur du texte
        // reste alignée avec celle des bordures.
        if (t.reference.isNotBlank()) {
            printBoxedLine(p, "N°  ${t.reference}", paperWidth)
        }

        // ---- Passenger block
        separator(p, paperWidth)
        printField(p, "Voyageur", t.passenger, paperWidth)
        printField(p, "Telephone", t.passengerPhone, paperWidth)

        // ---- Trip block
        val sectionHasTrip = listOf(t.route, t.departurePlace, t.departureTime,
            t.arrivalPlace, t.arrivalTime, t.bus, t.seat).any { it.isNotBlank() }
        if (sectionHasTrip) {
            separator(p, paperWidth)
            printField(p, "Trajet", t.route, paperWidth)
            printField(p, "Depart", listOf(t.departurePlace, t.departureTime)
                .filter { it.isNotBlank() }.joinToString(" "), paperWidth)
            if (t.arrivalPlace.isNotBlank() || t.arrivalTime.isNotBlank())
                printField(p, "Arrivee", listOf(t.arrivalPlace, t.arrivalTime)
                    .filter { it.isNotBlank() }.joinToString(" "), paperWidth)
            printField(p, "Bus", t.bus, paperWidth)
            printField(p, "Siege", t.seat, paperWidth)
        }

        // ---- Parcel block
        val sectionHasParcel = listOf(t.parcel, t.parcelWeight, t.parcelAmount).any { it.isNotBlank() }
        if (sectionHasParcel) {
            separator(p, paperWidth)
            printField(p, "Colis", t.parcel, paperWidth)
            printField(p, "Poids", t.parcelWeight, paperWidth)
            printField(p, "Montant colis", t.parcelAmount, paperWidth)
        }

        // ---- Extra rows (vente directe / reçu colis)
        // Reçu colis (voir printer_service.dart printColisReceipt) envoie des
        // labels de section en capitales ("EXPÉDITEUR", "BÉNÉFICIAIRE",
        // "CONTENU") pour marquer visuellement chaque bloc sur le modèle
        // papier de référence (cadre + sections soulignées). L'imprimante P3
        // intégrée ne sait pas dessiner de cadre, donc chaque section est
        // rendue comme un titre en gras suivi d'un filet plein (soulignement),
        // reproduisant l'effet "Expéditeur / Bénéficiaire / Contenu" soulignés
        // du modèle papier de référence.
        if (t.extraFields.isNotEmpty()) {
            val sectionMarkers = setOf("EXPÉDITEUR", "BÉNÉFICIAIRE", "CONTENU")
            separator(p, paperWidth)
            t.extraFields.forEach { (label, value) ->
                if (label.uppercase(Locale.US) in sectionMarkers) {
                    printWrappedLine(p, label.uppercase(Locale.US), PrintOptions(bold = true), paperWidth)
                    printWrappedLine(p, "-".repeat(paperWidth.coerceIn(24, 56)), PrintOptions(), paperWidth)
                    printWrappedLine(p, value, PrintOptions(bold = true), paperWidth)
                } else {
                    printField(p, label, value, paperWidth)
                }
            }
            separator(p, paperWidth)
        }

        // ---- Total
        if (t.total.isNotBlank()) {
            separator(p, paperWidth)
            printWrappedLine(p, "TOTAL", PrintOptions(bold = true, align = "center"), paperWidth)
            printWrappedLine(p, t.total,
                PrintOptions(bold = true, size = "large", align = "center"), paperWidth)
            separator(p, paperWidth)
        }

        // ---- QR
        if (t.qr.isNotBlank()) {
            blank(p)
            checkCode("printQRCode", p.printQRCode(t.qr, qrSize, Printer.Align.CENTER))
        }

        // ---- Footer
        if (t.footer.isNotBlank()) {
            t.footer.lineSequence().map { it.trim() }.filter { it.isNotBlank() }.forEach {
                printWrappedLine(p, it, PrintOptions(align = "center", size = "small"), paperWidth)
            }
        }

        finishPrinter(p)
    }

    // ------------------------------------------------------------------
    // Normalisation: structured rows (TPE) -> canonical Ticket
    // ------------------------------------------------------------------

    /**
     * Some TPE bridges send rows where the value contains the entire header
     * blob (company, phone, email, "Booking reference", reference, seat...).
     * Here we salvage real fields from any noisy value, then strip the noise.
     */
    private fun salvage(map: MutableMap<String, String>, raw: String) {
        val text = raw.replace('\u00A0', ' ').replace(Regex("\\s+"), " ").trim()
        if (text.isBlank()) return

        // Reference
        Regex("(?i)TB[-\\s]?[A-Z0-9]{6,16}(?![A-Z0-9])").find(text)?.value?.let {
            map.putIfAbsent("reference", it.replace(Regex("\\s+"), "").uppercase(Locale.US))
        }
        // Email
        Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}").find(text)?.value?.let {
            map.putIfAbsent("email", it)
        }
        // Phone (+xxxxxxxx)
        Regex("\\+\\d{8,15}").find(text)?.value?.let {
            map.putIfAbsent("telephone", it)
        }
        // Seat
        Regex("(?i)si[eè]ge\\s*:?\\s*(#?\\d+[A-Z]?)").find(text)?.groupValues?.getOrNull(1)?.let {
            map.putIfAbsent("siege", if (it.startsWith("#")) it else "#$it")
        }
        // Total XAF
        Regex("(?i)XAF\\s*[0-9][0-9 .]*").find(text)?.value?.let {
            map.putIfAbsent("total", it.uppercase(Locale.US).replace(Regex("\\s+"), " "))
        }
    }

    /** Strip noise (emails, phones, "Booking reference TB-...", "Scan ...") from a value. */
    private fun stripNoise(value: String): String {
        var v = value
        v = v.replace(Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"), " ")
        v = v.replace(Regex("\\+?\\d{8,15}"), " ")
        v = v.replace(Regex("(?i)booking\\s+reference[^A-Za-z0-9]*TB[-\\s]?[A-Z0-9]{6,16}"), " ")
        v = v.replace(Regex("(?i)booking\\s+reference"), " ")
        v = v.replace(Regex("(?i)TB[-\\s]?[A-Z0-9]{6,16}(?![A-Z0-9])"), " ")
        v = v.replace(Regex("(?i)si[eè]ge\\s*:?\\s*#?\\d+[A-Z]?"), " ")
        v = v.replace(Regex("(?i)scan\\s+(pour|for|your)[^|]*"), " ")
        v = v.replace(Regex("(?i)powered\\s+by\\s+tibus"), " ")
        v = v.replace(Regex("[|·•\\-]{2,}"), " ")
        v = v.replace(Regex("\\s+"), " ").trim().trim(':', '-', '|', '·', '•')
        return v
    }

    private fun normalizeStructured(
        header: List<String>,
        reference: String,
        rows: List<Pair<String, String>>,
        qrContent: String,
        footer: String
    ): Ticket {
        val cleanHeader = header.map { it.trim() }.filter { it.isNotBlank() }
        val companyFromHeader = cleanHeader.firstOrNull()?.let { cleanTitle(it) }?.ifBlank { "TIBUS" } ?: "TIBUS"
        val map = linkedMapOf<String, String>()
        val exactRows = mutableListOf<Pair<String, String>>()
        // First pass: salvage hidden fields from every header line, explicit
        // reference, QR payload and every row key/value. Older bridge versions
        // sometimes put the reference in qrContent or inside a noisy label/value.
        cleanHeader.forEach { salvage(map, it) }
        salvage(map, reference)
        salvage(map, qrContent)
        rows.forEach { (k, v) ->
            salvage(map, k)
            salvage(map, v)
        }
        // Second pass: keep EVERY labelled row exactly as sent. This is the
        // important part for the 56 mm and 80 mm buttons: label/value rows are
        // the receipt body, not only an input for recognized standard fields.
        rows.forEach { (k, v) ->
            val exactRow = normalizeStructuredRow(k, v)
            if (exactRow != null) {
                exactRows += exactRow
                val canonicalKey = canonicalStructuredKey(normalizeFieldKey(exactRow.first))
                if (canonicalKey.isNotBlank()) map.putIfAbsent(canonicalKey, exactRow.second)
            }
        }
        val companyEmail = (cleanHeader.firstOrNull { it.contains("@") }
            ?.let { Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}").find(it)?.value }
            ?: map["email"]).orEmpty()
        val companyPhone = (cleanHeader.firstOrNull { Regex("(?i)t[ée]l").containsMatchIn(it) || it.contains("+") }
            ?.let { Regex("\\+?\\d{8,15}").find(it)?.value }
            ?: map["telephone"]).orEmpty()
        val subtitle = cleanHeader.drop(1).firstOrNull {
            !it.contains("@") && !it.startsWith("+") && !Regex("(?i)t[ée]l").containsMatchIn(it)
        }.orEmpty()
        // Reference passed explicitly always wins
        if (reference.isNotBlank()) {
            val ref = cleanReference(reference)
            if (ref.isNotBlank()) map["reference"] = ref
        }
        val resolvedReference = cleanReference(reference.ifBlank { map["reference"].orEmpty() })
        // qrContent vide = demande EXPLICITE de ne pas imprimer de QR (ex.
        // reçu colis client, voir printer_service.dart printColisReceipt) —
        // ne PAS retomber sur la référence comme le fait resolveQrContent,
        // sinon un QR réapparaît sur le reçu malgré qr: ''.
        val resolvedQr = if (qrContent.isBlank()) "" else resolveQrContent(
            qrContent = qrContent,
            reference = resolvedReference,
            reference,
            map["reference"].orEmpty(),
            rows.joinToString(" ") { "${it.first}: ${it.second}" }
        )

        // If the bridge sent labelled rows, those rows are the ticket body.
        // Standard parsed fields are only used as fallback when no rows exist.
        val useExactRows = exactRows.isNotEmpty()
        return Ticket(
            company = map["company"]?.let { cleanTitle(it) }?.ifBlank { companyFromHeader } ?: companyFromHeader,
            companyEmail = companyEmail,
            companyPhone = companyPhone,
            subtitle = subtitle.ifBlank { "Ticket" },
            reference = resolvedReference,
            passenger = if (useExactRows) "" else pickFirst(map, "voyageur", "passager", "nom", "client", "nom du passager", "nom et prenom"),
            passengerPhone = if (useExactRows) "" else cleanPhone(pickFirst(map, "telephone", "téléphone", "tel", "phone", "numero", "numéro de téléphone")),
            route = if (useExactRows) "" else pickFirst(map, "trajet", "route", "itineraire", "itinéraire"),
            departurePlace = if (useExactRows) "" else pickFirst(map, "lieu depart", "lieu de depart", "depart lieu", "origine", "de"),
            departureTime = if (useExactRows) "" else pickFirst(map, "heure depart", "heure de depart", "depart heure", "depart", "heure"),
            arrivalPlace = if (useExactRows) "" else pickFirst(map, "lieu arrivee", "lieu d arrivee", "arrivee lieu", "destination", "a"),
            arrivalTime = if (useExactRows) "" else pickFirst(map, "heure arrivee", "heure d arrivee", "arrivee heure", "arrivee"),
            bus = if (useExactRows) "" else pickFirst(map, "bus", "vehicule", "véhicule"),
            seat = if (useExactRows) "" else cleanSeat(pickFirst(map, "siege", "siège", "place", "places", "seat")),
            parcel = if (useExactRows) "" else pickFirst(map, "colis", "bagage", "bagages", "parcel"),
            parcelWeight = if (useExactRows) "" else pickFirst(map, "poids", "weight"),
            parcelAmount = if (useExactRows) "" else cleanTotal(pickFirst(map, "montant colis", "montant du colis", "prix colis")),
            total = if (useExactRows) "" else cleanTotal(pickFirst(map, "total", "montant", "prix")),
            extraFields = if (useExactRows) dedupeExtraFields(exactRows) else emptyList(),
            qr = resolvedQr,
            footer = footer.ifBlank { "Powered by Tibus" }
        )
    }

    // ------------------------------------------------------------------
    // Normalisation: free-form text (legacy path) -> canonical Ticket
    // ------------------------------------------------------------------

    private fun parseAny(title: String, rawText: String, qrContent: String): Ticket {
        // routing handled by tryBuildBookingTicket() in printReceipt58/80
        return parseAnyInternal(title, rawText, qrContent)
    }

    // ------------------------------------------------------------------
    // V38 booking reprint path — kept separate from vente / reprint vente
    // ------------------------------------------------------------------

    /**
     * Keeps the working V38 booking rendering intact.
     * Only booking/reservation payloads enter this path; sales and sold-ticket
     * reprints continue to use parseAnyInternal()/normalizeStructured().
     */
    private fun tryBuildV38BookingLines(title: String, rawText: String): JSONArray? {
        val payload = tryParseJsonObject(rawText)
        if (payload != null) {
            val structured = buildV38ReprintBookingLines(payload)
            if (structured != null) return structured
            return null
        }

        if (!looksLikeV38BookingReprint(title, rawText)) return null
        val normalized = normalizeV38BookingText(rawText)
        return linesFromV38Text(normalized)
    }

    private fun renderV38BookingReceipt(
        lines: JSONArray, qrContent: String, paperWidth: Int, qrSize: Int,
        companyName: String = "", companyPhone: String = "", companyEmail: String = ""
    ) {
        val p = preparePrinter()
        val reference = findV38Reference(qrContent, lines)

        val displayName = companyName.ifBlank { "TIBUS" }
        printV38Line(p, displayName, align = Printer.Align.CENTER, size = 30, bold = true)
        if (companyPhone.isNotBlank())
            printV38Line(p, "Tel: $companyPhone", align = Printer.Align.CENTER, size = 20, bold = false)
        if (companyEmail.isNotBlank())
            printV38Line(p, companyEmail, align = Printer.Align.CENTER, size = 20, bold = false)
        printV38Line(p, "Ticket", align = Printer.Align.CENTER, size = 24, bold = false)

        if (reference.isNotBlank()) {
            printV38Line(p, "--------------------------------", align = Printer.Align.CENTER, size = 24, bold = false)
            printV38Line(p, reference, align = Printer.Align.CENTER, size = 30, bold = true)
        }

        printV38Line(p, "--------------------------------", align = Printer.Align.CENTER, size = 24, bold = false)

        for (i in 0 until lines.length()) {
            val line = lines.optJSONObject(i) ?: continue
            val text = line.optString("text", "")
            if (text.isBlank()) continue
            // Ignorer les lignes qui ne sont qu'un tiret solitaire "-"
            if (text.trim() == "-" || text.trim() == "--") continue
            val align = when (line.optString("align", "left").lowercase(Locale.US)) {
                "center" -> Printer.Align.CENTER
                "right"  -> Printer.Align.RIGHT
                else     -> Printer.Align.LEFT
            }
            val size = when (line.optString("size", "normal").lowercase(Locale.US)) {
                "large" -> 30
                "small" -> 20
                else    -> 24
            }
            printV38Line(p, text, align = align, size = size, bold = line.optBoolean("bold", false))
        }

        if (qrContent.isNotBlank()) {
            blank(p)
            checkCode("printQRCode", p.printQRCode(qrContent, qrSize.coerceIn(120, 360), Printer.Align.CENTER))
        }

        finishPrinter(p)
    }

    private fun buildV38ReprintBookingLines(payload: JSONObject): JSONArray? {
        val trip = payload.optJSONObject("trip") ?: return null
        val hasBookingShape = payload.has("bookingReference") ||
            payload.has("passengerName") ||
            payload.has("totalPrice")
        if (!hasBookingShape) return null

        val arr = JSONArray()
        val currency = firstV38String(payload, "currency")
            .ifBlank { firstV38String(trip, "currency") }
            .ifBlank { "XAF" }
        val reference = firstV38String(payload, "bookingReference", "reference", "ticketReference")
        val origin = v38PlaceLabel(trip.optJSONObject("originLoc"))
            .ifBlank { v38PlaceLabel(trip.optJSONObject("origin")) }
        val destination = v38PlaceLabel(trip.optJSONObject("destLoc"))
            .ifBlank { v38PlaceLabel(trip.optJSONObject("destination")) }
        val bus = v38BusLabel(trip.optJSONObject("bus"))

        addV38Line(arr, "Voyageur: ${firstV38String(payload, "passengerName", "passenger", "name")}")
        addV38Line(arr, "Téléphone: ${firstV38String(payload, "passengerPhone", "phone", "telephone")}")
        addV38Separator(arr)
        addV38Line(arr, "Départ: $origin")
        addV38Line(arr, "Arrivée: $destination")
        addV38Line(arr, "Heure départ: ${v38FormatDateTime(firstV38String(trip, "departureTime"))}")
        addV38Line(arr, "Heure arrivée: ${v38FormatDateTime(firstV38String(trip, "arrivalTime"))}")
        addV38Line(arr, "Bus: $bus")
        addV38Line(arr, "Siège: ${v38SeatLabel(firstV38String(payload, "seatNumber", "seat", "seatNo"))}", bold = true)
        addV38Separator(arr)
        addV38Line(arr, "Colis: ${v38NumberString(payload, "parcelCount")}")
        addV38Line(arr, "Poids: ${v38NumberString(payload, "parcelWeight")} Kg")
        addV38Line(arr, "Montant colis: ${v38MoneyString(payload, "parcelAmount", currency)}")
        addV38Separator(arr)
        if (reference.isNotBlank()) {
            addV38Line(arr, "Scan pour vérification ticket n°:", bold = true)
            addV38Line(arr, reference)
            addV38Separator(arr)
        }
        addV38Line(arr, "TOTAL", size = "large", bold = true, align = "center")
        addV38Line(arr, v38MoneyString(payload, "totalPrice", currency), size = "large", bold = true, align = "center")
        addV38Separator(arr)
        // Espace + bloc voyageur sous le total
        addV38Line(arr, "Voyageur: ${firstV38String(payload, "passengerName", "passenger", "name")}")

        return arr
    }

    private fun normalizeV38BookingText(raw: String): String {
        val labels = listOf(
            "Référence", "Reference", "Voyageur", "Passager", "Client", "Téléphone", "Telephone", "Tél", "Tel",
            "Trajet", "Itinéraire", "Itineraire", "Départ", "Depart", "Arrivée", "Arrivee", "Heure départ",
            "Heure depart", "Heure d'arrivée", "Heure d'arrivee", "Heure arrivée", "Heure arrivee", "Heure",
            "Compagnie", "Company", "Nom", "Bus", "Véhicule", "Vehicule", "Places", "Place", "Siège", "Siege",
            "Colis", "Poids", "Montant colis", "Mont colis", "Prix colis", "Prix", "Total", "Montant",
            "Scan pour vérification ticket n°", "Scan pour verification ticket n"
        )
        val labelPattern = labels.joinToString("|") { Regex.escape(it) }
        return raw
            .replace("\u00A0", " ")
            .replace("\r", "\n")
            .replace(Regex("(?<=[\\p{L}\\p{N})#])(?=(?:$labelPattern)\\s*:)", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("(?<=[\\p{L}\\p{N})#])(?=(?:Non payé|Non paye|Payé|Paye)\\b)", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("(?<=\\S)(-{3,})"), "\n$1")
            .lines()
            .map { normalizeV38PrintedLabel(it.replace(Regex("[ \\t]+"), " ").trim()) }
            .filter { it.isNotBlank() }
            .joinToString("\n")
    }

    private fun normalizeV38PrintedLabel(line: String): String {
        return line
            .replace(Regex("^Telephone\\s*:", RegexOption.IGNORE_CASE), "Téléphone:")
            .replace(Regex("^Tel\\s*:", RegexOption.IGNORE_CASE), "Téléphone:")
            .replace(Regex("^Siege\\s*:", RegexOption.IGNORE_CASE), "Siège:")
            .replace(Regex("^Mont\\s+colis\\s*:", RegexOption.IGNORE_CASE), "Montant colis:")
            .replace(Regex("^Arrivee\\s*:", RegexOption.IGNORE_CASE), "Arrivée:")
            .replace(Regex("^Depart\\s*:", RegexOption.IGNORE_CASE), "Départ:")
    }

    private fun linesFromV38Text(text: String): JSONArray {
        val arr = JSONArray()
        text.replace("\r", "\n")
            .lines()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .forEach { line ->
                val isSeparator = Regex("^-{3,}$").matches(line)
                val isTotal = Regex("(?i)^TOTAL(?:\\s|:|$)").containsMatchIn(line) ||
                    Regex("(?i)^[0-9 .]+XAF$").matches(line)
                arr.put(
                    JSONObject()
                        .put("text", line)
                        .put("align", if (isSeparator) "center" else "left")
                        .put("size", if (isTotal) "large" else "normal")
                        .put("bold", isTotal || Regex("(?i)^(Référence|Reference|Siège|Siege|Téléphone|Telephone|Bus|Arrivée|Arrivee|TOTAL)").containsMatchIn(line))
                )
            }
        return arr
    }

    private fun looksLikeV38BookingReprint(title: String, text: String): Boolean {
        val score = listOf(
            "TB-[A-Z0-9]+",
            "Voyageur|Passager|Téléphone|Telephone",
            "Arrivée|Arrivee|Départ|Depart|Heure",
            "Colis|Poids|Montant colis|Mont colis",
            "Non payé|Non paye|Payé|Paye",
            "Places|Siège|Siege"
        ).count { Regex(it, RegexOption.IGNORE_CASE).containsMatchIn(text) }
        val titleIsBooking = Regex("(?i)booking|reservation|réservation").containsMatchIn(title)
        return score >= 4 || (titleIsBooking && score >= 2)
    }

    private fun findV38Reference(qrContent: String, lines: JSONArray): String {
        // 1. Dans le QR content
        Regex("TB-?[A-Z0-9]{4,}", RegexOption.IGNORE_CASE).find(qrContent)
            ?.value?.uppercase(Locale.US)?.let { return it }
        // 2. Dans les lignes — avec ou sans préfixe TB
        for (i in 0 until lines.length()) {
            val text = lines.optJSONObject(i)?.optString("text", "") ?: ""
            // Chercher TB-XXXX ou TB XXXX
            Regex("TB-?[A-Z0-9]{4,}", RegexOption.IGNORE_CASE).find(text)
                ?.value?.uppercase(Locale.US)?.let { return it }
            // Chercher après "Référence :" ou "Reference :"
            Regex("(?i)r[ée]f[ée]rence\\s*:?\\s*([A-Z0-9][A-Z0-9\\-]{3,})", RegexOption.IGNORE_CASE)
                .find(text)?.groupValues?.getOrNull(1)?.uppercase(Locale.US)?.let {
                    if (it.isNotBlank()) return it
                }
        }
        // 3. Chercher n'importe quelle valeur après "Scan pour vérification ticket n°:"
        for (i in 0 until lines.length()) {
            val text = lines.optJSONObject(i)?.optString("text", "") ?: ""
            if (Regex("(?i)scan pour v[ée]rification").containsMatchIn(text)) {
                val next = lines.optJSONObject(i + 1)?.optString("text", "") ?: ""
                if (next.isNotBlank() && !Regex("(?i)scan|----").containsMatchIn(next)) return next.uppercase(Locale.US)
            }
        }
        return ""
    }

    private fun addV38Line(arr: JSONArray, text: String, align: String = "left", size: String = "normal", bold: Boolean = false) {
        val clean = text.replace(Regex("[ \\t]+"), " ").trim()
        if (clean.isBlank()) return
        // Ignorer les tirets solitaires parasites
        if (Regex("^-{1,3}$").matches(clean)) return
        // Ignorer les lignes label: vide ou label: 0
        if (clean.contains(':')) {
            val value = clean.substringAfter(':').trim()
            if (value.isBlank()) return
            if (value == "0" || value == "0 XAF" || value == "0 Kg" || value == "0.0") return
        }
        arr.put(JSONObject().put("text", clean).put("align", align).put("size", size).put("bold", bold))
    }

    private fun addV38Separator(arr: JSONArray) {
        arr.put(JSONObject().put("text", "--------------------------------").put("align", "center"))
    }

    private fun firstV38String(obj: JSONObject?, vararg keys: String): String {
        if (obj == null) return ""
        for (key in keys) {
            if (!obj.has(key) || obj.isNull(key)) continue
            val value = obj.opt(key)
            val s = when (value) {
                is Number -> value.toString()
                is Boolean -> value.toString()
                else -> obj.optString(key, "")
            }.trim()
            if (s.isNotBlank() && s != "null") return s
        }
        return ""
    }

    private fun v38NumberString(obj: JSONObject, key: String): String {
        if (!obj.has(key) || obj.isNull(key)) return "0"
        val raw = obj.opt(key)
        return when (raw) {
            is Number -> if (raw.toDouble() % 1.0 == 0.0) raw.toLong().toString() else raw.toString()
            else -> obj.optString(key, "0").ifBlank { "0" }
        }
    }

    private fun v38MoneyString(obj: JSONObject, key: String, currency: String): String {
        val amount = v38NumberString(obj, key)
        return "$amount $currency".trim()
    }

    private fun v38PlaceLabel(obj: JSONObject?): String {
        return firstV38String(obj, "city", "name", "label", "title")
    }

    private fun v38BusLabel(obj: JSONObject?): String {
        if (obj == null) return ""
        val plate = firstV38String(obj, "plateNumber", "plate", "registration")
        val name = firstV38String(obj, "name")
        val type = firstV38String(obj, "busType", "type")
        return listOf(plate, name, type).filter { it.isNotBlank() }.joinToString(" - ")
    }

    private fun v38SeatLabel(value: String): String {
        val clean = value.trim()
        if (clean.isBlank()) return ""
        return if (clean.startsWith("#")) clean else "#$clean"
    }

    private fun v38FormatDateTime(value: String): String {
        val clean = value.trim()
        if (clean.isBlank()) return ""
        val iso = Regex("^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})")
        val m = iso.find(clean)
        if (m != null) {
            val (y, mo, d, h, mi) = m.destructured
            return "$d/$mo/$y $h:$mi"
        }
        return clean.replace('T', ' ').replace(Regex("(?i)Z$"), "")
    }

    private fun printV38Line(
        p: Printer,
        text: String,
        align: Printer.Align = Printer.Align.LEFT,
        size: Int = 24,
        bold: Boolean = false,
    ) {
        val font = if (bold) Printer.Font.DEFAULT_BOLD else Printer.Font.MONOSPACE
        checkCode("printString", p.printString(text + "\n", font, size, align, bold, false, false))
    }

    // ------------------------------------------------------------------
    // Booking reprint structured path (from JS ReprintBooking JSON payload)
    // Merged from v38: when JS sends a JSON blob with bookingReference /
    // passengerName / trip{...}, we rebuild the Ticket from the typed fields
    // instead of trying to re-parse the mobile display text.
    // ------------------------------------------------------------------

    /** Returns a Ticket when rawText is a ReprintBooking JSON payload, else null. */
    private fun tryBuildBookingTicket(title: String, rawText: String, qrContent: String): Ticket? {
        val payload = tryParseJsonObject(rawText) ?: return null
        val hasBookingShape = payload.has("bookingReference") ||
            payload.has("passengerName") ||
            (payload.has("totalPrice") && payload.has("trip"))
        if (!hasBookingShape) return null
        return buildTicketFromBookingPayload(payload, title, qrContent)
    }

    private fun tryParseJsonObject(raw: String): JSONObject? {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("{")) return null
        return runCatching {
            val parsed = JSONTokener(trimmed).nextValue()
            parsed as? JSONObject
        }.getOrNull()
    }

    private fun buildTicketFromBookingPayload(
        payload: JSONObject,
        title: String,
        qrContent: String
    ): Ticket {
        val trip = payload.optJSONObject("trip") ?: JSONObject()
        val currency = firstNonBlank(
            payload.optString("currency"),
            trip.optString("currency"),
            "XAF"
        )
        val reference = firstNonBlank(
            payload.optString("bookingReference"),
            payload.optString("reference"),
            payload.optString("ticketReference")
        )
        val origin = bookingPlace(trip.optJSONObject("originLoc"))
            .ifBlank { bookingPlace(trip.optJSONObject("origin")) }
        val destination = bookingPlace(trip.optJSONObject("destLoc"))
            .ifBlank { bookingPlace(trip.optJSONObject("destination")) }
        val bus = bookingBus(trip.optJSONObject("bus"))
        val passenger = firstNonBlank(
            payload.optString("passengerName"),
            payload.optString("passenger"),
            payload.optString("name")
        )
        val phone = firstNonBlank(
            payload.optString("passengerPhone"),
            payload.optString("phone"),
            payload.optString("telephone")
        )
        val seat = firstNonBlank(
            payload.optString("seatNumber"),
            payload.optString("seat"),
            payload.optString("seatNo")
        )
        val depTime = bookingDate(firstNonBlank(trip.optString("departureTime")))
        val arrTime = bookingDate(firstNonBlank(trip.optString("arrivalTime")))
        val total = bookingMoney(payload, "totalPrice", currency)
        val parcelCount = bookingNumber(payload, "parcelCount")
        val parcelWeight = bookingNumber(payload, "parcelWeight")
        val parcelAmount = bookingMoney(payload, "parcelAmount", currency)

        return Ticket(
            company = "TIBUS",
            subtitle = title.ifBlank { "Ticket de reservation" },
            reference = reference,
            passenger = passenger,
            passengerPhone = phone,
            route = if (origin.isNotBlank() && destination.isNotBlank()) "$origin -> $destination" else "",
            departurePlace = origin,
            departureTime = depTime,
            arrivalPlace = destination,
            arrivalTime = arrTime,
            bus = bus,
            seat = seat,
            parcel = parcelCount,
            parcelWeight = if (parcelWeight.isNotBlank()) "$parcelWeight Kg" else "",
            parcelAmount = parcelAmount,
            total = total,
            qr = qrContent.ifBlank { reference },
            footer = "Powered by Tibus"
        )
    }

    private fun firstNonBlank(vararg values: String?): String {
        for (v in values) {
            if (!v.isNullOrBlank() && v != "null") return v.trim()
        }
        return ""
    }

    private fun bookingPlace(obj: JSONObject?): String {
        if (obj == null) return ""
        return firstNonBlank(obj.optString("city"), obj.optString("name"))
    }

    private fun bookingBus(obj: JSONObject?): String {
        if (obj == null) return ""
        val name = obj.optString("name", "")
        val plate = obj.optString("plateNumber", "")
        val type = obj.optString("busType", "")
        return listOf(name, plate, type).filter { it.isNotBlank() && it != "null" }.joinToString(" / ")
    }

    private fun bookingNumber(payload: JSONObject, key: String): String {
        if (!payload.has(key) || payload.isNull(key)) return ""
        val v = payload.opt(key) ?: return ""
        return v.toString().trim()
    }

    private fun bookingMoney(payload: JSONObject, key: String, currency: String): String {
        val raw = bookingNumber(payload, key)
        if (raw.isBlank()) return ""
        val num = raw.toDoubleOrNull() ?: return raw
        val formatted = if (num == num.toLong().toDouble()) num.toLong().toString() else String.format(Locale.US, "%.2f", num)
        return "$formatted $currency"
    }

    private fun bookingDate(raw: String): String {
        if (raw.isBlank()) return ""
        // ISO 8601 like 2026-05-24T08:30:00Z -> "2026-05-24 08:30"
        val isoRegex = Regex("^(\\d{4}-\\d{2}-\\d{2})[T ](\\d{2}:\\d{2})")
        val m = isoRegex.find(raw) ?: return raw
        return "${m.groupValues[1]} ${m.groupValues[2]}"
    }

    private fun parseAnyInternal(title: String, rawText: String, qrContent: String): Ticket {
        val rawNormalized = normalizeReceipt(rawText)

        // --- Fix réimpression booking : libellés collés sans espace
        val bookingLabels = listOf(
            "Heure d'arrivée", "Heure d'arrivee",
            "Heure de départ", "Heure de depart",
            "Montant du colis", "Montant colis", "Mont colis",
            "Prix colis", "Prix du colis",
            "Référence", "Reference",
            "Voyageur", "Passager", "Client",
            "Téléphone", "Telephone", "Tél", "Tel",
            "Trajet", "Itinéraire", "Itineraire",
            "Départ", "Depart", "Arrivée", "Arrivee", "Heure",
            "Bus", "Véhicule", "Vehicule",
            "Siège", "Siege", "Places", "Place", "Seat",
            "Colis", "Bagages", "Bagage", "Poids",
            "Prix", "Total", "Montant",
            "Compagnie", "Company", "Nom", "Email",
            "Payé le", "Paye le", "Date"
        )
        val bookingLabelRegex = Regex(
            "(?<=[A-Za-z0-9àâäéèêëïîôöùûüçÀÂÄÉÈÊËÏÎÔÖÙÛÜÇ])" +
            "(?=(?:" + bookingLabels.joinToString("|") + ")\\s*:)"
        )
        val text = bookingLabelRegex.replace(rawNormalized, "\n")

        // Keep a line-preserving view so we can honour any "Label: value"
        // pairs the JS bridge already laid out one-per-line.
        val lined = text.replace('\u00A0', ' ').replace('\r', '\n')
        val compact = lined
            .replace('\u00A0', ' ')
            .replace('\n', ' ')
            .replace(Regex("\\s+"), " ")
            .trim()

        // ---- Pass 1: respect existing line breaks (preferred).
        val values = linkedMapOf<String, String>()
        val extraFields = mutableListOf<Pair<String, String>>()
        val canonical = mapOf(
            "reference" to "reference", "ref" to "reference", "reservation" to "reference",
            "reference ticket" to "reference", "reference du ticket" to "reference",
            "référence ticket" to "reference", "référence du ticket" to "reference",
            "ticket" to "reference", "ticket id" to "reference", "id ticket" to "reference",
            "code ticket" to "reference", "numero ticket" to "reference", "numéro ticket" to "reference",
            "passager" to "passenger", "voyageur" to "passenger", "client" to "passenger",
            "nom" to "passenger", "nom et prenom" to "passenger", "nom et prénom" to "passenger",
            "nom du passager" to "passenger", "nom du voyageur" to "passenger",
            "telephone" to "phone", "téléphone" to "phone", "tel" to "phone",
            "tél" to "phone", "phone" to "phone", "numero" to "phone", "numéro" to "phone",
            "trajet" to "route", "itineraire" to "route", "itinéraire" to "route", "route" to "route",
            "depart" to "departure", "départ" to "departure", "de" to "departure",
            "lieu depart" to "departPlace", "lieu de depart" to "departPlace",
            "lieu de départ" to "departPlace", "origine" to "departPlace",
            "heure depart" to "departTime", "heure de depart" to "departTime",
            "heure de départ" to "departTime", "heure" to "departTime",
            "arrivee" to "arrival", "arrivée" to "arrival", "a" to "arrival",
            "à" to "arrival", "vers" to "arrival", "destination" to "arrival",
            "lieu arrivee" to "arrivalPlace", "lieu d arrivee" to "arrivalPlace",
            "lieu d'arrivée" to "arrivalPlace",
            "heure arrivee" to "arrivalTime", "heure d arrivee" to "arrivalTime",
            "heure d'arrivée" to "arrivalTime",
            "bus" to "bus", "vehicule" to "bus", "véhicule" to "bus", "transport" to "bus",
            "transportbus" to "bus", "transport bus" to "bus",
            "siege" to "seat", "siège" to "seat", "place" to "seat", "places" to "seat", "seat" to "seat",
            "colis" to "parcel", "bagage" to "parcel", "bagages" to "parcel", "parcel" to "parcel",
            "poids" to "weight", "weight" to "weight",
            "montant colis" to "parcelAmt", "montant du colis" to "parcelAmt",
            "prix colis" to "parcelAmt", "prix du colis" to "parcelAmt",
            "total" to "total", "montant" to "total", "montant total" to "total",
            "prix" to "total", "prix total" to "total",
            "compagnie" to "company", "company" to "company",
        )
        lined.lineSequence().forEach { raw ->
            val line = raw.trim().trimEnd(':')
            val sep = line.indexOf(':')
            if (sep <= 0 || sep > 40) return@forEach
            val rawKey = line.take(sep).trim()
                .lowercase(Locale.US)
                .replace(Regex("[^a-zàâéèêëïîôùûüç' ]"), " ")
                .replace(Regex("\\s+"), " ")
                .trim()
            val canon = canonical[rawKey] ?: canonical[rawKey.replace("'", " ").trim()]
            val v = cleanParsedValue(line.drop(sep + 1))
            if (canon != null) {
                if (v.isNotBlank()) values.putIfAbsent(canon, v)
            } else if (rawKey.isNotBlank() && v.isNotBlank()) {
                extraFields += cleanDisplayLabel(rawKey) to v
            }
        }

        // ---- Pass 2: marker-split fallback on the compact single-line view,
        // used only to fill fields not already set by pass 1.
        var marked = compact
            .replace(Regex("(?i)tibus\\s*[—–-]\\s*voyager\\s+par\\s+bus\\s+devient\\s+facile"), " ")
            .replace(Regex("(?i)hand\\s+the\\s+reference[^.]*"), " ")
            .replace(Regex("(?i)scan\\s+(your|for|pour)[^.]*"), " ")

        val markers = listOf(
            // Order matters: longer / more specific labels first so they win
            // over their shorter aliases (e.g. "heure depart" before "depart").
            "reference"    to Regex("(?i)r[ée]f[ée]\\s*rence(?:\\s+(?:de\\s+)?r[ée]servation)?\\s*:?"),
            "passenger"    to Regex("(?i)(?:nom\\s+(?:et\\s+pr[ée]nom\\s+)?(?:du\\s+)?)?(?:passager|voyageur|client)\\s*\\*?\\s*:?"),
            "phone"        to Regex("(?i)(?:num[ée]ro(?:\\s+de\\s+t[ée]l[ée]phone)?|t[ée]l[ée]phone|t[ée]l|phone)(?:\\s*\\(facultatif\\))?\\s*:?"),
            "route"        to Regex("(?i)(?:trajet|itin[ée]raire|route)\\s*:?"),
            "departTime"   to Regex("(?i)heure\\s+(?:de\\s+)?d[ée]part\\s*:?"),
            "departPlace"  to Regex("(?i)lieu\\s+(?:de\\s+)?d[ée]part\\s*:?"),
            "departure"    to Regex("(?i)d[ée]part\\s*:?|\\bde\\s*:"),
            "arrivalTime"  to Regex("(?i)heure\\s+(?:d['’])?\\s*arriv[ée]e\\s*:?"),
            "arrivalPlace" to Regex("(?i)lieu\\s+(?:d['’])?\\s*arriv[ée]e\\s*:?"),
            "arrival"      to Regex("(?i)arriv[ée]e\\s*:?|\\b[àa]\\s*:|\\bvers\\s*:|\\bdestination\\s*:?"),
            "bus"          to Regex("(?i)\\b(?:bus|v[ée]hicule)\\s*:?"),
            "seat"         to Regex("(?i)\\bsi[eè]ge\\s*:?|\\bplaces?\\s*:?|\\bseat\\s*:?"),
            "parcelAmt"    to Regex("(?i)(?:montant\\s+(?:du\\s+)?colis|prix\\s+(?:du\\s+)?colis)\\s*:?"),
            "parcel"       to Regex("(?i)(?:colis|bagages?|parcel)\\s*:?"),
            "weight"       to Regex("(?i)(?:poids|weight)\\s*:?"),
            "total"        to Regex("(?i)(?:total|montant(?:\\s+total)?|prix\\s+total)\\s*:?"),
            "powered"      to Regex("(?i)powered\\s+by\\s+tibus"),
        )
        markers.forEach { (key, regex) -> marked = regex.replace(marked, "\n$key:") }

        marked.lineSequence().forEach { rawLine ->
            val line = rawLine.trim().trim(':')
            val sep = line.indexOf(':')
            if (sep <= 0) return@forEach
            val key = line.take(sep).trim()
            val value = cleanParsedValue(line.drop(sep + 1))
            if (key.isNotBlank() && value.isNotBlank()) values.putIfAbsent(key, value)
        }

        val reference = cleanReference(
            values["reference"] ?: Regex("(?i)TB[-\\s]?[A-Z0-9]{6,16}(?![A-Z0-9])").find(compact)?.value.orEmpty()
        )
        // Header company contacts harvested directly from the raw text
        val headerEmail = Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
            .find(compact)?.value.orEmpty()
        val headerPhone = Regex("\\+\\d{8,15}").find(compact)?.value.orEmpty()
        val resolvedQr = resolveQrContent(
            qrContent = qrContent,
            reference = reference,
            compact,
        )
        return Ticket(
            company = cleanTitle(title).ifBlank { "TIBUS" },
            companyEmail = headerEmail,
            companyPhone = headerPhone,
            subtitle = "Ticket",
            reference = reference,
            passenger = values["passenger"].orEmpty(),
            passengerPhone = cleanPhone(values["phone"].orEmpty()).let {
                if (it.isBlank() || it == headerPhone) "" else it
            },
            route = values["route"].orEmpty(),
            departurePlace = values["departPlace"].orEmpty(),
            departureTime = values["departTime"].orEmpty().ifBlank { values["departure"].orEmpty() },
            arrivalPlace = values["arrivalPlace"].orEmpty(),
            arrivalTime = values["arrivalTime"].orEmpty().ifBlank { values["arrival"].orEmpty() },
            bus = values["bus"].orEmpty(),
            seat = cleanSeat(values["seat"].orEmpty()
                .ifBlank { Regex("(?<![A-Z0-9])#\\d+").find(compact)?.value.orEmpty() }),
            parcel = values["parcel"].orEmpty(),
            parcelWeight = values["weight"].orEmpty(),
            parcelAmount = cleanTotal(values["parcelAmt"].orEmpty()),
            total = cleanTotal(values["total"].orEmpty()),
            extraFields = dedupeExtraFields(extraFields),
            qr = resolvedQr,
            footer = "Powered by Tibus"
        )
    }


    private fun normalizeStructuredRow(labelRaw: String, valueRaw: String): Pair<String, String>? {
        val directLabel = cleanDisplayLabel(labelRaw)
        val directValue = cleanParsedValue(valueRaw)
        if (directLabel.isNotBlank() && directValue.isNotBlank()) return directLabel to directValue

        splitLabelValue(labelRaw)?.let { (label, value) ->
            val cleanLabel = cleanDisplayLabel(label)
            val cleanValue = cleanParsedValue(value)
            if (cleanLabel.isNotBlank() && cleanValue.isNotBlank()) return cleanLabel to cleanValue
        }
        splitLabelValue(valueRaw)?.let { (label, value) ->
            val cleanLabel = cleanDisplayLabel(label)
            val cleanValue = cleanParsedValue(value)
            if (cleanLabel.isNotBlank() && cleanValue.isNotBlank()) return cleanLabel to cleanValue
        }
        return null
    }

    private fun splitLabelValue(raw: String): Pair<String, String>? {
        val line = raw.replace('\u00A0', ' ').trim()
        val sep = line.indexOf(':')
        if (sep <= 0 || sep > 48 || sep >= line.lastIndex) return null
        return line.take(sep) to line.drop(sep + 1)
    }

    private fun extractReference(value: String): String = Regex("(?i)TB[-\\s]?[A-Z0-9]{6,16}(?![A-Z0-9])")
        .find(value)?.value?.replace(Regex("\\s+"), "")?.uppercase(Locale.US).orEmpty()

    private fun looksLikeSeatOnly(value: String): Boolean = Regex(
        "(?i)^\\s*(?:si[eè]ge|seat|places?|fauteuil)?\\s*:?\\s*#?\\d+[A-Z]?\\s*$"
    ).matches(value.trim())

    private fun resolveQrContent(qrContent: String, reference: String, vararg sources: String): String {
        val rawQr = qrContent.replace('\u00A0', ' ').trim()
        val refFromQr = extractReference(rawQr)
        val resolvedReference = cleanReference(reference.ifBlank {
            sources.asSequence().map { extractReference(it) }.firstOrNull { it.isNotBlank() }.orEmpty()
        })

        return when {
            refFromQr.isNotBlank() -> refFromQr.take(512)
            resolvedReference.isNotBlank() && (rawQr.isBlank() || looksLikeSeatOnly(rawQr)) -> resolvedReference.take(512)
            rawQr.isNotBlank() -> rawQr.take(512)
            else -> resolvedReference.take(512)
        }
    }

    private fun pickFirst(map: Map<String, String>, vararg keys: String): String {
        for (k in keys) {
            val v = map[canonicalStructuredKey(normalizeFieldKey(k))]
            if (!v.isNullOrBlank()) return v
            val raw = map[k.lowercase(Locale.US)]
            if (!raw.isNullOrBlank()) return raw
        }
        return ""
    }

    private fun normalizeFieldKey(value: String): String {
        val noAccent = Normalizer.normalize(value, Normalizer.Form.NFD)
            .replace(Regex("\\p{Mn}+"), "")
        return noAccent
            .lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun canonicalStructuredKey(normalizedKey: String): String = when (normalizedKey) {
        "reference", "ref", "reservation", "reference reservation", "reference de reservation",
        "reference ticket", "reference du ticket", "ticket", "ticket id", "id ticket",
        "code ticket", "numero ticket", "numero du ticket", "booking reference", "booking ref" -> "reference"
        "passager", "voyageur", "client", "nom", "nom prenom", "nom et prenom",
        "nom du passager", "nom du voyageur", "passenger" -> "voyageur"
        "telephone", "tel", "phone", "numero", "numero telephone", "numero de telephone" -> "telephone"
        "trajet", "route", "itineraire" -> "trajet"
        "depart", "de", "origine" -> "depart"
        "lieu depart", "lieu de depart" -> "lieu depart"
        "heure", "heure depart", "heure de depart" -> "heure depart"
        "arrivee", "a", "vers", "destination" -> "arrivee"
        "lieu arrivee", "lieu d arrivee", "lieu de arrivee" -> "lieu arrivee"
        "heure arrivee", "heure d arrivee", "heure de arrivee" -> "heure arrivee"
        "bus", "vehicule", "transport", "transport bus" -> "vehicule"
        "siege", "sieges", "siege s", "place", "places", "place s", "seat" -> "siege"
        "colis", "bagage", "bagages", "parcel" -> "colis"
        "poids", "weight" -> "poids"
        "montant colis", "montant du colis", "prix colis", "prix du colis" -> "montant colis"
        "total", "montant", "montant total", "prix", "prix total", "amount" -> "total"
        "compagnie", "company", "societe", "societe transport", "transporteur" -> "company"
        else -> normalizedKey
    }

    private fun cleanStructuredValue(canonicalKey: String, value: String): String {
        val raw = cleanParsedValue(value)
        if (raw.isBlank()) return ""
        return when (canonicalKey) {
            "reference", "voyageur", "telephone", "trajet", "depart", "lieu depart",
            "heure depart", "arrivee", "lieu arrivee", "heure arrivee", "vehicule",
            "siege", "colis", "poids", "montant colis", "total", "company" -> raw
            else -> stripNoise(value).ifBlank { raw }
        }
    }

    private fun isStandardPrintedKey(key: String): Boolean = key in setOf(
        "reference", "voyageur", "telephone", "trajet", "depart", "lieu depart",
        "heure depart", "arrivee", "lieu arrivee", "heure arrivee", "vehicule",
        "siege", "colis", "poids", "montant colis", "total", "company", "email"
    )

    private fun cleanDisplayLabel(value: String): String {
        val clean = value
            .replace('_', ' ')
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim(':', '-', '|', '·', '•')
        if (clean.isBlank()) return ""
        return clean.substring(0, 1).uppercase(Locale.US) + clean.drop(1)
    }

    private fun dedupeExtraFields(fields: List<Pair<String, String>>): List<Pair<String, String>> {
        val seen = mutableSetOf<String>()
        return fields.mapNotNull { (label, value) ->
            val cleanLabel = cleanDisplayLabel(label)
            val cleanValue = value.replace(Regex("\\s+"), " ").trim().trim(':', '-', '|')
            val id = normalizeFieldKey(cleanLabel) + "=" + cleanValue.lowercase(Locale.US)
            if (cleanLabel.isBlank() || cleanValue.isBlank() || !seen.add(id)) null else cleanLabel to cleanValue
        }
    }

    // ------------------------------------------------------------------
    // Printer primitives
    // ------------------------------------------------------------------

    private fun preparePrinter(): Printer {
        val p = printer()
        checkCode("clearPrintDataCache", p.clearPrintDataCache())
        checkCode("printInit", p.printInit())
        runCatching { p.setGrayLevel(4) }
        runCatching { p.setPrintLineSpacing(1) }
        return p
    }

    private fun finishPrinter(p: Printer) {
        runCatching { p.printPaper(96) }
        checkCode("printFinish", p.printFinish())
    }

    private fun printField(p: Printer, label: String, value: String, width: Int) {
        val cleanLabel = label.trim().trimEnd(':')
        val cleanValue = value.replace(Regex("\\s+"), " ").trim().trim(':', '-', '|')
        if (cleanLabel.isBlank() || cleanValue.isBlank()) return
        // Valeurs en GRAS (demande explicite : « Téléphone: *5555555* ») —
        // l'imprimante ne gère qu'un style par ligne, donc la ligne complète
        // label+valeur est imprimée en gras, comme l'aperçu à l'écran.
        val oneLine = "$cleanLabel: $cleanValue"
        if (oneLine.length <= width) {
            printWrappedLine(p, oneLine, PrintOptions(bold = true), width)
        } else {
            printWrappedLine(p, "$cleanLabel:", PrintOptions(bold = true), width)
            printWrappedLine(p, cleanValue, PrintOptions(bold = true), width)
        }
    }

    private fun printer(): Printer = printer ?: synchronized(this) {
        printer ?: Printer(ctx.applicationContext).also { printer = it }
    }

    private fun printWrappedLine(p: Printer, line: String, opts: PrintOptions, width: Int) {
        if (line.isBlank()) { blank(p); return }
        val effectiveWidth = when (opts.size) {
            "large" -> (width * 0.62f).toInt().coerceAtLeast(18)
            "small" -> (width * 1.18f).toInt().coerceAtLeast(width)
            else -> width
        }
        wrap(line, effectiveWidth).forEach { part ->
            checkCode("printString", p.printString(
                part,
                if (opts.bold) Printer.Font.DEFAULT_BOLD else Printer.Font.MONOSPACE,
                when (opts.size) { "large" -> 30; "small" -> 20; else -> 24 },
                when (opts.align) { "center" -> Printer.Align.CENTER; "right" -> Printer.Align.RIGHT; else -> Printer.Align.LEFT },
                opts.bold, false, false
            ))
        }
    }

    private fun blank(p: Printer, dots: Int = 16) { checkCode("printPaper", p.printPaper(dots)) }

    private fun separator(p: Printer, width: Int) {
        printWrappedLine(p, "-".repeat(width.coerceIn(24, 56)), PrintOptions(), width)
    }

    /** Cadre ASCII (+---+ / | texte | / +---+) autour d'une ligne, taille
     * normale pour que le texte et les bordures restent alignés en largeur. */
    private fun printBoxedLine(p: Printer, text: String, width: Int) {
        val w = width.coerceIn(24, 56)
        val border = "+" + "-".repeat(w - 2) + "+"
        printWrappedLine(p, border, PrintOptions(align = "center"), width)
        printWrappedLine(p, text, PrintOptions(align = "center", bold = true), width)
        printWrappedLine(p, border, PrintOptions(align = "center"), width)
    }

    private fun formatRow(label: String, value: String, width: Int): String {
        if (label.isBlank()) return value
        if (value.isBlank()) return label
        val maxLabel = (width * 0.62f).toInt().coerceAtLeast(12)
        val safeLabel = label.take(maxLabel)
        val remaining = width - safeLabel.length - 1
        if (remaining <= 8 || value.length > remaining) return "$safeLabel\n$value"
        return safeLabel + " ".repeat(remaining - value.length + 1) + value
    }

    // ------------------------------------------------------------------
    // Cleaning helpers
    // ------------------------------------------------------------------

    private fun cleanTitle(title: String): String {
        val clean = title.replace(Regex("\\s+"), " ").trim().take(48)
        if (clean.isBlank()) return ""
        if (Regex("(?i)tibus\\s*[—–-]\\s*voyager\\s+par\\s+bus\\s+devient\\s+facile").containsMatchIn(clean)) return ""
        return clean
    }

    private fun cleanParsedValue(value: String): String = value
        .replace(Regex("\\s+"), " ")
        .replace(Regex("(?i)powered\\s+by\\s+tibus"), "")
        .trim().trim(':', '-', '|')

    private fun cleanReference(value: String): String {
        val clean = value.replace('\u00A0', ' ').trim()
        if (clean.isBlank() || looksLikeSeatOnly(clean)) return ""
        val tibusRef = extractReference(clean)
        if (tibusRef.isNotBlank()) return tibusRef
        return clean.replace(Regex("\\s+"), "").uppercase(Locale.US).take(24)
    }

    private fun cleanPhone(value: String): String {
        val digits = value
            .replace(Regex("[:;]?\\s*#\\d+.*$"), "")
            .replace(Regex("[^+0-9]"), "")
        return if (digits.length >= 6) digits else ""
    }

    private fun cleanSeat(value: String): String {
        val m = Regex("(?i)#?\\d+[A-Z]?").find(value)?.value ?: return value.trim()
        return if (m.startsWith("#")) m else "#$m"
    }

    private fun cleanTotal(value: String): String {
        val normalized = value.replace(Regex("\\s+"), " ").trim()
        val withCurrency = Regex("(?i)XAF\\s*[0-9][0-9 .]*").find(normalized)?.value
        if (withCurrency != null) return withCurrency.uppercase(Locale.US).replace(Regex("\\s+"), " ")
        return normalized
    }

    private fun normalizeReceipt(raw: String): String = raw
        .replace('\u00A0', ' ')
        .replace(Regex("[ \\t]+\\n"), "\n")
        .replace(Regex("\\n{3,}"), "\n\n")
        .trim()

    private fun wrap(value: String, width: Int): List<String> {
        val src = value.trimEnd()
        if (src.length <= width) return listOf(src)
        val out = mutableListOf<String>()
        var rest = src
        while (rest.length > width) {
            val cut = rest.take(width + 1).lastIndexOf(' ').takeIf { it >= 12 } ?: width
            out += rest.take(cut).trimEnd()
            rest = rest.drop(cut).trimStart()
        }
        if (rest.isNotBlank()) out += rest
        return out
    }

    private fun checkCode(op: String, code: Int) {
        if (code != 0) throw IllegalStateException("$op a échoué: code $code")
    }

    data class PrintOptions(
        val align: String = "left",
        val size: String = "normal",
        val bold: Boolean = false
    )

    companion object { private const val TAG = "P3Printer" }
}
