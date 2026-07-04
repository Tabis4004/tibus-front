-- Politique de confidentialité (page juridique éditable, même mécanisme que les CGU).

INSERT INTO public."LegalPages" (slug, title, content)
VALUES (
  'politique-confidentialite',
  'Politique de Confidentialité',
  'Dernière mise à jour : 26 juin 2026

Tibus ("nous", "notre plateforme") met en relation voyageurs, compagnies de transport et vendeurs pour la recherche, la réservation et la vente de titres de transport en Afrique. La présente politique explique quelles données nous collectons, pourquoi, et comment vous pouvez les contrôler.

1. Responsable du traitement
Tibus Technology est responsable du traitement des données décrites ci-dessous.
Contact : tabistibus@gmail.com — WhatsApp : +225 01 72 96 00 00

2. Données que nous collectons
- Données de compte : nom, prénom, nom d''utilisateur, adresse e-mail, numéro de téléphone, pays.
- Données de réservation et de paiement : trajets recherchés et réservés, numéro de téléphone associé au paiement mobile money, montant et référence de la transaction. Tibus ne stocke pas les identifiants ou mots de passe de votre compte mobile money.
- Données liées à l''usage de l''application : billets émis, scans de billets et de colis (via la caméra de l''appareil, utilisée uniquement pour lire les QR codes), historique des trajets, avis et notes laissés sur une compagnie.
- Connexion via Google (application Android) : si vous choisissez de vous connecter avec votre compte Google, nous recevons votre nom, votre adresse e-mail et votre photo de profil telle que fournie par Google.
- Données techniques : informations de l''appareil et journaux techniques nécessaires au bon fonctionnement et à la sécurité de l''application (par ex. en cas d''erreur de paiement ou de scan).

3. Pourquoi nous utilisons ces données
- Créer et gérer votre compte, et vous authentifier.
- Vous permettre de rechercher, réserver et payer un trajet, et de recevoir votre billet.
- Permettre aux vendeurs et compagnies de vérifier un billet ou un colis par scan QR.
- Vous envoyer des notifications liées à vos réservations (confirmation, rappel, changement d''horaire).
- Assurer le support client et traiter les réclamations.
- Prévenir la fraude et assurer la sécurité de la plateforme.
- Améliorer nos services.

4. Avec qui nous partageons vos données
- La compagnie de transport concernée par votre réservation, dans la mesure nécessaire à l''exécution du service.
- Les prestataires de paiement (mobile money, agrégateurs de paiement) pour le traitement de vos transactions.
- Google, uniquement si vous utilisez la connexion via Google Sign-In.
- Notre hébergeur cloud (base de données et infrastructure technique), qui agit en tant que sous-traitant et n''utilise vos données que pour notre compte.
Nous ne vendons jamais vos données personnelles à des tiers à des fins publicitaires.

5. Conservation des données
Vos données sont conservées pendant la durée nécessaire à la fourniture du service et à nos obligations légales (notamment comptables et fiscales), puis supprimées ou archivées de façon sécurisée.

6. Sécurité
Nous mettons en œuvre des mesures techniques et organisationnelles raisonnables pour protéger vos données contre l''accès non autorisé, la perte ou la divulgation.

7. Vos droits
Vous pouvez demander l''accès, la rectification ou la suppression de vos données personnelles, ou vous opposer à certains traitements, en nous contactant à tabistibus@gmail.com ou via WhatsApp au +225 01 72 96 00 00. Nous répondons à toute demande dans un délai raisonnable.

8. Caméra et permissions sur mobile
L''application Android demande l''accès à la caméra uniquement pour scanner les QR codes des billets et des colis. Cette permission n''est jamais utilisée pour autre chose, et vous pouvez la refuser, au prix de devoir saisir manuellement la référence du billet.

9. Mineurs
Tibus ne s''adresse pas spécifiquement aux enfants. Nous ne collectons pas sciemment de données concernant des mineurs sans le consentement d''un parent ou tuteur.

10. Modifications de cette politique
Cette politique peut être mise à jour. La version publiée sur cette page fait foi et la date de mise à jour est indiquée en haut du document.

11. Contact
Pour toute question relative à vos données personnelles : tabistibus@gmail.com — WhatsApp : +225 01 72 96 00 00'
)
ON CONFLICT (slug) DO UPDATE
SET
  title = EXCLUDED.title,
  content = EXCLUDED.content,
  "updatedAt" = now();
