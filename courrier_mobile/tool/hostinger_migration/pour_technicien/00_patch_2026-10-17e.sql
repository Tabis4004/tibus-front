-- 225 — Liste des catégories de dépenses : fonction VOLATILE
--
-- list_company_expense_categories crée les catégories OHADA par défaut au
-- premier appel (ensure_company_expense_categories = INSERT). Déclarée STABLE,
-- PostgREST l'exécutait dans une transaction en lecture seule :
-- « cannot execute INSERT in a read-only transaction » à l'ouverture du
-- formulaire « Nouvelle dépense » pour une compagnie sans catégories.
ALTER FUNCTION public.list_company_expense_categories(uuid) VOLATILE;
