import { useCallback, useEffect, useMemo, useState } from "react";
import type { PaymentGateway, PaymentNetwork } from "@/config/commission.ts";
import {
  getPaymentNetworkOptionsForCountry,
  inferCountryNameFromPhone,
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
  /** GeniusPay : pays et réseau choisis sur le checkout GeniusPay, pas côté Tibus. */
  deferCountryToGateway?: boolean;
  deferNetworkToGateway?: boolean;
};

export function usePaymentCountryNetworks({
  activeGateway,
  passengerPhone = "",
  deferCountryToGateway = false,
  deferNetworkToGateway = false,
}: UsePaymentCountryNetworksArgs) {
  const [countries, setCountries] = useState<TravelerPaymentCountry[] | undefined>(undefined);
  const [countriesError, setCountriesError] = useState<string | null>(null);
  const [paymentCountryId, setPaymentCountryId] = useState("");
  const [paymentNetwork, setPaymentNetwork] = useState<PaymentNetwork>("unknown");
  const [countryManual, setCountryManual] = useState(false);
  const [networkManual, setNetworkManual] = useState(false);
  const [paymentNetworkOptions, setPaymentNetworkOptions] = useState<PaymentNetworkOption[]>([]);
  const [networksLoading, setNetworksLoading] = useState(false);

  const paymentCountryName = useMemo(
    () => countries?.find((country) => country.id === paymentCountryId)?.name ?? null,
    [countries, paymentCountryId],
  );

  useEffect(() => {
    if (deferCountryToGateway) {
      setCountries([]);
      setCountriesError(null);
      setPaymentCountryId("");
      return;
    }

    let cancelled = false;
    setCountries(undefined);
    setCountriesError(null);

    void listTravelerPaymentCountriesSupabase({ gateway: activeGateway })
      .then((rows) => {
        if (!cancelled) setCountries(rows);
      })
      .catch((err) => {
        if (!cancelled) {
          setCountries([]);
          setCountriesError(
            err instanceof Error ? err.message : "Impossible de charger les pays",
          );
        }
      });

    return () => {
      cancelled = true;
    };
  }, [activeGateway, deferCountryToGateway]);

  useEffect(() => {
    if (deferCountryToGateway) return;
    if (!countries?.length || countryManual || paymentCountryId) return;

    const inferredName = inferCountryNameFromPhone(passengerPhone);
    if (inferredName) {
      const match = countries.find((country) => country.name === inferredName);
      if (match) {
        setPaymentCountryId(match.id);
        return;
      }
    }

    if (countries.length === 1) {
      setPaymentCountryId(countries[0].id);
    }
  }, [countries, countryManual, passengerPhone, paymentCountryId, deferCountryToGateway]);

  useEffect(() => {
    if (!paymentCountryId || deferNetworkToGateway || deferCountryToGateway) {
      if (deferNetworkToGateway) {
        setPaymentNetworkOptions([]);
      } else if (!paymentCountryId) {
        setPaymentNetworkOptions([]);
        if (!networkManual) {
          setPaymentNetwork("unknown");
        }
      }
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
  }, [paymentCountryId, paymentCountryName, activeGateway, deferNetworkToGateway]);

  useEffect(() => {
    if (deferNetworkToGateway) return;
    if (!paymentCountryId || networksLoading) return;

    const allowed = paymentNetworkOptions
      .map((option) => option.value)
      .filter((value) => value !== "unknown");
    if (paymentNetwork === "unknown") return;
    if (!allowed.includes(paymentNetwork)) {
      setPaymentNetwork("unknown");
    }
  }, [paymentCountryId, paymentNetworkOptions, paymentNetwork, networksLoading, deferNetworkToGateway]);

  useEffect(() => {
    if (deferNetworkToGateway) return;
    if (
      !paymentCountryId ||
      networkManual ||
      networksLoading ||
      paymentNetwork !== "unknown"
    ) {
      return;
    }

    const inferred = inferNetworkFromPhone(passengerPhone, paymentCountryName);
    if (inferred && paymentNetworkOptions.some((option) => option.value === inferred)) {
      setPaymentNetwork(inferred);
      return;
    }

    const concreteOptions = paymentNetworkOptions.filter(
      (option) => option.value !== "unknown",
    );
    if (concreteOptions.length === 1) {
      setPaymentNetwork(concreteOptions[0].value);
    }
  }, [
    passengerPhone,
    paymentCountryId,
    paymentCountryName,
    networkManual,
    networksLoading,
    paymentNetwork,
    paymentNetworkOptions,
  ]);

  const inferredCountryName = useMemo(
    () => inferCountryNameFromPhone(passengerPhone),
    [passengerPhone],
  );

  const selectPaymentCountry = (countryId: string) => {
    setCountryManual(true);
    setPaymentCountryId(countryId);
    if (!deferNetworkToGateway) {
      setNetworkManual(false);
      setPaymentNetwork("unknown");
    }
  };

  const selectPaymentNetwork = (network: PaymentNetwork) => {
    setNetworkManual(true);
    setPaymentNetwork(network);
  };

  const restorePaymentSelection = useCallback(
    (countryId: string | null | undefined, network: PaymentNetwork) => {
      if (countryId) {
        setCountryManual(true);
        setPaymentCountryId(countryId);
      }
      setNetworkManual(true);
      setPaymentNetwork(network);
    },
    [],
  );

  return {
    countries,
    countriesError,
    paymentCountryId,
    paymentCountryName,
    paymentNetwork,
    paymentNetworkOptions,
    networksLoading,
    inferredCountryName,
    selectPaymentCountry,
    selectPaymentNetwork,
    restorePaymentSelection,
    setPaymentCountryId,
    setPaymentNetwork,
  };
}
