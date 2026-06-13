import { useEffect, useMemo, useState } from "react";
import type { PaymentGateway, PaymentNetwork } from "@/config/commission.ts";
import {
  getPaymentNetworkOptionsForCountry,
  inferNetworkFromPhone,
  type PaymentNetworkOption,
} from "@/lib/payment-networks.ts";
import {
  listTravelerPaymentCountriesSupabase,
  listTravelerPaymentNetworksSupabase,
  type TravelerPaymentCountry,
} from "@/lib/supabase/payment-fees";

type UsePaymentCountryNetworksArgs = {
  activeGateway: PaymentGateway;
  passengerPhone?: string;
};

export function usePaymentCountryNetworks({
  activeGateway,
  passengerPhone = "",
}: UsePaymentCountryNetworksArgs) {
  const [countries, setCountries] = useState<TravelerPaymentCountry[] | undefined>(undefined);
  const [paymentCountryId, setPaymentCountryId] = useState("");
  const [paymentNetwork, setPaymentNetwork] = useState<PaymentNetwork>("unknown");
  const [networkManual, setNetworkManual] = useState(false);
  const [paymentNetworkOptions, setPaymentNetworkOptions] = useState<PaymentNetworkOption[]>([]);
  const [networksLoading, setNetworksLoading] = useState(false);

  const paymentCountryName = useMemo(
    () => countries?.find((country) => country.id === paymentCountryId)?.name ?? null,
    [countries, paymentCountryId],
  );

  useEffect(() => {
    let cancelled = false;
    setCountries(undefined);

    void listTravelerPaymentCountriesSupabase({ gateway: activeGateway })
      .then((rows) => {
        if (!cancelled) setCountries(rows);
      })
      .catch(() => {
        if (!cancelled) setCountries([]);
      });

    return () => {
      cancelled = true;
    };
  }, [activeGateway]);

  useEffect(() => {
    if (!paymentCountryId) {
      setPaymentNetworkOptions([]);
      setPaymentNetwork("unknown");
      return;
    }

    let cancelled = false;
    setNetworksLoading(true);

    void (async () => {
      const gatewayNetworks = await listTravelerPaymentNetworksSupabase({
        countryId: paymentCountryId,
        gateway: activeGateway,
      }).catch(() => [] as string[]);

      if (cancelled) return;

      setPaymentNetworkOptions(
        getPaymentNetworkOptionsForCountry(paymentCountryName, gatewayNetworks),
      );
      setNetworksLoading(false);
    })();

    return () => {
      cancelled = true;
    };
  }, [paymentCountryId, paymentCountryName, activeGateway]);

  useEffect(() => {
    if (!paymentCountryId) return;
    const allowed = paymentNetworkOptions.map((option) => option.value);
    if (!allowed.includes(paymentNetwork)) {
      setPaymentNetwork("unknown");
      setNetworkManual(false);
    }
  }, [paymentCountryId, paymentNetworkOptions, paymentNetwork]);

  useEffect(() => {
    if (!paymentCountryId || networkManual) return;
    const inferred = inferNetworkFromPhone(passengerPhone, paymentCountryName);
    if (inferred && paymentNetworkOptions.some((option) => option.value === inferred)) {
      setPaymentNetwork(inferred);
    }
  }, [passengerPhone, paymentCountryId, paymentCountryName, networkManual, paymentNetworkOptions]);

  const selectPaymentCountry = (countryId: string) => {
    setPaymentCountryId(countryId);
    setNetworkManual(false);
    setPaymentNetwork("unknown");
  };

  const selectPaymentNetwork = (network: PaymentNetwork) => {
    setNetworkManual(true);
    setPaymentNetwork(network);
  };

  return {
    countries,
    paymentCountryId,
    paymentCountryName,
    paymentNetwork,
    paymentNetworkOptions,
    networksLoading,
    selectPaymentCountry,
    selectPaymentNetwork,
    setPaymentCountryId,
    setPaymentNetwork,
  };
}
