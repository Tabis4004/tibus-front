import { supabase } from "@/lib/supabase";

export type IncomeStatementLine = {
  accountCode: string;
  accountLabel: string;
  amount: number;
};

export type CompanyIncomeStatement = {
  company: {
    id: string;
    name: string;
    currency: string;
  };
  period: {
    from: string;
    to: string;
  };
  framework: string;
  statementType: string;
  products: {
    lines: IncomeStatementLine[];
    total: number;
  };
  charges: {
    lines: IncomeStatementLine[];
    total: number;
  };
  results: {
    operatingResult: number;
    financialResult: number;
    currentResult: number;
    netResult: number;
  };
};

function mapLine(row: Record<string, unknown>): IncomeStatementLine {
  return {
    accountCode: row.accountCode as string,
    accountLabel: row.accountLabel as string,
    amount: Number(row.amount ?? 0),
  };
}

export async function getCompanyIncomeStatementSupabase(
  companyId: string,
  from?: string | null,
  to?: string | null,
): Promise<CompanyIncomeStatement> {
  const { data, error } = await supabase.rpc("get_company_income_statement", {
    p_company_id: companyId,
    p_from: from ?? null,
    p_to: to ?? null,
  });
  if (error) throw error;

  const payload = data as Record<string, unknown>;
  const products = payload.products as Record<string, unknown>;
  const charges = payload.charges as Record<string, unknown>;
  const results = payload.results as Record<string, unknown>;

  return {
    company: payload.company as CompanyIncomeStatement["company"],
    period: payload.period as CompanyIncomeStatement["period"],
    framework: (payload.framework as string) || "SYSCOHADA",
    statementType: (payload.statementType as string) || "compte_de_resultat",
    products: {
      lines: ((products?.lines as Record<string, unknown>[]) ?? []).map(mapLine),
      total: Number(products?.total ?? 0),
    },
    charges: {
      lines: ((charges?.lines as Record<string, unknown>[]) ?? []).map(mapLine),
      total: Number(charges?.total ?? 0),
    },
    results: {
      operatingResult: Number(results?.operatingResult ?? 0),
      financialResult: Number(results?.financialResult ?? 0),
      currentResult: Number(results?.currentResult ?? 0),
      netResult: Number(results?.netResult ?? 0),
    },
  };
}
