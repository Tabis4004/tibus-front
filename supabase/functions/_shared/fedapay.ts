const FEDAPAY_BASE =
  Deno.env.get("FEDAPAY_BASE_URL") ?? "https://sandbox-api.fedapay.com";

function headers() {
  const secretKey = Deno.env.get("FEDAPAY_SECRET_KEY");
  if (!secretKey) throw new Error("FEDAPAY_SECRET_KEY manquant");
  return {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/json",
  };
}

type TxnData = {
  id?: number;
  reference?: string;
  status?: string;
  custom_metadata?: Record<string, string>;
};

/** Numéro local CI (10 chiffres, ex. 0700000000) pour FedaPay country=ci */
export function normalizeFedaPayPhone(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (!digits) {
    throw new Error(
      "Numéro de téléphone requis — format: 07 00 00 00 00 ou +225 07...",
    );
  }

  let local = digits;
  if (local.startsWith("225") && local.length >= 12) {
    local = local.slice(3);
  }

  if (local.length === 9 && /^[1-9]/.test(local)) {
    local = `0${local}`;
  }

  if (!/^0[1-9]\d{8}$/.test(local)) {
    throw new Error(
      "Numéro invalide — utilisez 10 chiffres ivoiriens (ex: 07 00 00 00 00)",
    );
  }

  return local;
}

function parseTxn(json: Record<string, unknown>): TxnData | null {
  const txn =
    (json["v1/transaction"] as TxnData | undefined) ??
    (json as { v1?: { transaction?: TxnData } }).v1?.transaction ??
    (json as TxnData);
  return txn?.id ? txn : null;
}

export async function createFedaPayCheckout(args: {
  amount: number;
  description: string;
  callbackUrl: string;
  customer: {
    firstname: string;
    lastname: string;
    email: string;
    phone: string;
  };
  metadata: Record<string, string>;
}) {
  const phoneNumber = normalizeFedaPayPhone(args.customer.phone);

  const txnRes = await fetch(`${FEDAPAY_BASE}/v1/transactions`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({
      description: args.description,
      amount: args.amount,
      currency: { iso: "XOF" },
      callback_url: args.callbackUrl,
      customer: {
        firstname: args.customer.firstname,
        lastname: args.customer.lastname,
        email: args.customer.email,
        phone_number: { number: phoneNumber, country: "ci" },
      },
      custom_metadata: args.metadata,
    }),
  });

  const txnText = await txnRes.text();
  if (!txnRes.ok) {
    throw new Error(`FedaPay transaction failed: ${txnText.slice(0, 300)}`);
  }

  const txnJson = JSON.parse(txnText) as Record<string, unknown>;
  const txn = parseTxn(txnJson);
  if (!txn?.id || !txn.reference) {
    throw new Error(`FedaPay transaction invalide: ${txnText.slice(0, 300)}`);
  }

  const tokenRes = await fetch(
    `${FEDAPAY_BASE}/v1/transactions/${txn.id}/token`,
    { method: "POST", headers: headers() },
  );
  const tokenText = await tokenRes.text();
  if (!tokenRes.ok) {
    throw new Error(`FedaPay token failed: ${tokenText.slice(0, 300)}`);
  }

  const tokenJson = JSON.parse(tokenText) as Record<string, unknown>;
  const checkoutUrl =
    (tokenJson.url as string | undefined) ??
    (tokenJson.token as string | undefined);

  if (!checkoutUrl) {
    throw new Error(`FedaPay checkout URL manquant: ${tokenText.slice(0, 300)}`);
  }

  return { checkoutUrl, reference: txn.reference, transactionId: String(txn.id) };
}

export async function fetchFedaPayTransaction(args: {
  transactionId?: string;
  reference?: string;
}): Promise<TxnData | null> {
  if (args.transactionId) {
    const res = await fetch(
      `${FEDAPAY_BASE}/v1/transactions/${args.transactionId}`,
      { headers: headers() },
    );
    const text = await res.text();
    if (!res.ok) return null;
    try {
      const json = JSON.parse(text) as Record<string, unknown>;
      return parseTxn(json);
    } catch {
      return null;
    }
  }

  if (args.reference) {
    const res = await fetch(
      `${FEDAPAY_BASE}/v1/transactions/search?reference=${encodeURIComponent(args.reference)}`,
      { headers: headers() },
    );
    const text = await res.text();
    if (!res.ok) return null;
    try {
      const json = JSON.parse(text) as Record<string, unknown>;
      const txnList =
        (json["v1/transactions"] as TxnData[] | undefined) ??
        (json["v1/transaction"] as TxnData | TxnData[] | undefined);
      const transactions: TxnData[] = Array.isArray(txnList)
        ? txnList
        : txnList
          ? [txnList]
          : [];
      return transactions.find((t) => t.reference === args.reference) ?? null;
    } catch {
      return null;
    }
  }

  return null;
}

export function isFedaPayApproved(status?: string) {
  return status === "approved" || status === "transferred";
}
