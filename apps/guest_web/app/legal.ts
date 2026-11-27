import type {Lang} from './i18n';

/** Who runs Sendoh and how to reach them. Set on the host; nothing personal is hard-coded. */
export const operator=process.env.NEXT_PUBLIC_LEGAL_ENTITY||'Sendoh';
export const supportEmail=process.env.NEXT_PUBLIC_SUPPORT_EMAIL||'';
export const supportWhatsApp=process.env.NEXT_PUBLIC_SUPPORT_WHATSAPP||'';
export const UPDATED='2026-11-27';

export type Section={heading:string;body:string[]};
export type LegalDoc={title:string;intro:string;sections:Section[]};

const privacy:Record<Lang,LegalDoc>={
 en:{title:'Privacy policy',intro:`This policy explains what ${operator} ("Sendoh", "we") collects when you use the Sendoh app and website, why, who it is shared with, and the choices you have.`,sections:[
  {heading:'What we collect',body:[
   'Your phone number, used to sign in with a one-time code.',
   'Your name, and if you choose, a @username and a profile photo.',
   'The collections you create or join, your contributions, money requests, payments and receipts, and cash amounts an organizer records for you.',
   'The Mobile Money number and network you pay with or receive on.',
   'A notification token for your device, if you allow notifications.',
   'Basic technical records, such as request times and IP addresses, to keep the service secure.']},
  {heading:'Why we use it',body:[
   'To sign you in and recognise you to the people you organize money with.',
   'To run collections, requests and payments, show the right totals and send receipts.',
   'To prevent double payments, fraud and misuse, and to investigate problems.',
   'To send notifications you have allowed, such as a confirmed contribution.']},
  {heading:'Who sees your information',body:[
   'The organizer of a collection you join sees your name, your contributions and your status. Other members do not see your contributions.',
   'People you send money to or request money from see your name and @username.',
   'We share payment details with our payment partner MeSomb and with MTN Mobile Money or Orange Money, only to process your payments.',
   'We use service providers to send sign-in codes, deliver notifications (Google Firebase) and host the service. They act on our instructions.',
   'We do not sell your information and we do not show advertising.']},
  {heading:'How long we keep it',body:[
   'Your profile stays until you delete your account.',
   'Payment, payout and cash records are financial records. Other people’s receipts and an organizer’s accounts depend on them, so we keep them after you delete your account, for as long as the law requires. Your name on them is replaced by "Deleted user".']},
  {heading:'Your choices',body:[
   'You can change your name and photo in your profile at any time.',
   'You can delete your account in the app (Profile, then Delete account) or on our website at /delete-account. Deletion waits until any payment still in progress has finished.',
   'You can choose English or French at any time.',
   'You can ask us what we hold about you, or ask for a correction, through the Help page.']},
  {heading:'Security',body:['Sign-in uses one-time codes; sessions can be ended from the app. Payments are only marked successful after the Mobile Money provider confirms them.']},
  {heading:'Age',body:['Sendoh is for people aged 18 and over.']},
  {heading:'Changes',body:['If we change this policy in a way that matters, we will tell you in the app before the change applies.']},
 ]},
 fr:{title:'Politique de confidentialité',intro:`Cette politique explique ce que ${operator} (« Sendoh », « nous ») collecte lorsque vous utilisez l’application et le site Sendoh, pourquoi, avec qui ces informations sont partagées et les choix dont vous disposez.`,sections:[
  {heading:'Ce que nous collectons',body:[
   'Votre numéro de téléphone, utilisé pour vous connecter avec un code à usage unique.',
   'Votre nom et, si vous le souhaitez, un @nom d’utilisateur et une photo de profil.',
   'Les collectes que vous créez ou rejoignez, vos contributions, demandes d’argent, paiements et reçus, ainsi que les montants en espèces qu’un organisateur enregistre pour vous.',
   'Le numéro et le réseau Mobile Money avec lesquels vous payez ou recevez.',
   'Un jeton de notification pour votre appareil, si vous autorisez les notifications.',
   'Des données techniques de base, comme l’heure des requêtes et les adresses IP, pour sécuriser le service.']},
  {heading:'Pourquoi nous les utilisons',body:[
   'Pour vous connecter et vous faire reconnaître des personnes avec qui vous organisez de l’argent.',
   'Pour faire fonctionner les collectes, les demandes et les paiements, afficher les bons totaux et envoyer les reçus.',
   'Pour éviter les doubles paiements, la fraude et les abus, et pour examiner les problèmes.',
   'Pour envoyer les notifications que vous avez autorisées, par exemple une contribution confirmée.']},
  {heading:'Qui voit vos informations',body:[
   'L’organisateur d’une collecte que vous rejoignez voit votre nom, vos contributions et votre statut. Les autres membres ne voient pas vos contributions.',
   'Les personnes à qui vous envoyez ou demandez de l’argent voient votre nom et votre @nom d’utilisateur.',
   'Nous partageons les données de paiement avec notre partenaire de paiement MeSomb et avec MTN Mobile Money ou Orange Money, uniquement pour traiter vos paiements.',
   'Nous faisons appel à des prestataires pour envoyer les codes de connexion, délivrer les notifications (Google Firebase) et héberger le service. Ils agissent selon nos instructions.',
   'Nous ne vendons pas vos informations et nous n’affichons pas de publicité.']},
  {heading:'Combien de temps nous les gardons',body:[
   'Votre profil est conservé jusqu’à la suppression de votre compte.',
   'Les enregistrements de paiements, de versements et d’espèces sont des documents financiers. Les reçus d’autres personnes et les comptes d’un organisateur en dépendent : nous les conservons après la suppression de votre compte, aussi longtemps que la loi l’exige. Votre nom y est remplacé par la mention « Deleted user » (utilisateur supprimé).']},
  {heading:'Vos choix',body:[
   'Vous pouvez modifier votre nom et votre photo dans votre profil à tout moment.',
   'Vous pouvez supprimer votre compte dans l’application (Profil, puis Supprimer le compte) ou sur notre site à l’adresse /delete-account. La suppression attend la fin de tout paiement en cours.',
   'Vous pouvez choisir le français ou l’anglais à tout moment.',
   'Vous pouvez nous demander quelles informations nous détenons sur vous, ou en demander la correction, via la page Aide.']},
  {heading:'Sécurité',body:['La connexion utilise des codes à usage unique ; les sessions peuvent être fermées depuis l’application. Un paiement n’est marqué réussi qu’après confirmation par l’opérateur Mobile Money.']},
  {heading:'Âge',body:['Sendoh est destiné aux personnes âgées de 18 ans et plus.']},
  {heading:'Modifications',body:['Si nous modifions cette politique de manière importante, nous vous en informerons dans l’application avant que le changement ne s’applique.']},
 ]},
};

const terms:Record<Lang,LegalDoc>={
 en:{title:'Terms of use',intro:`These terms apply when you use Sendoh, run by ${operator}. By using Sendoh you accept them.`,sections:[
  {heading:'What Sendoh is',body:[
   'Sendoh helps people organize money together: group collections, recurring rounds such as a njangi, money requests and person-to-person payments.',
   'Sendoh is not a bank. Mobile Money payments are processed by our payment partner MeSomb with MTN Mobile Money and Orange Money. Contributions to a collection are held through MeSomb until the organizer closes the collection and the payout is sent.']},
  {heading:'Early access',body:['During the pilot, payments run in test mode: no real money moves. We will tell you in the app and on this website before real payments open.']},
  {heading:'Your account',body:[
   'You sign in with your own phone number and keep access to it. You are responsible for what is done with your account.',
   'Use your real name, so the people you organize money with can recognise you.']},
  {heading:'Fees',body:['Any fee is shown before you approve a payment or close a collection. You never pay a fee you were not shown first. There is no fee on cash an organizer records.']},
  {heading:'Payments',body:[
   'A payment counts only once the Mobile Money provider confirms it. While it is being confirmed, please do not pay again.',
   'A confirmed payment cannot be cancelled by Sendoh. If something is wrong, contact the organizer or the person you paid, then our Help page.']},
  {heading:'Organizers',body:[
   'Organizers describe their collection honestly, record cash accurately and use the money for the stated purpose.',
   'When a collection is closed, no new contributions are accepted and the payout is sent once, to the receiving number shown before closing.']},
  {heading:'What is not allowed',body:['Fraud, scams, money laundering, financing illegal activity, impersonating someone, or using Sendoh to harass people. We may suspend accounts or hold payments to protect people, and we cooperate with lawful requests.']},
  {heading:'Responsibility',body:['We work to keep Sendoh available and accurate, but it may sometimes be interrupted. To the extent the law allows, we are not responsible for losses caused by Mobile Money networks, by information you enter incorrectly, or by agreements between members of a group.']},
  {heading:'Law',body:['These terms are governed by the law of Cameroon.']},
  {heading:'Changes',body:['If we change these terms in a way that matters, we will tell you in the app before the change applies.']},
 ]},
 fr:{title:'Conditions d’utilisation',intro:`Ces conditions s’appliquent lorsque vous utilisez Sendoh, exploité par ${operator}. En utilisant Sendoh, vous les acceptez.`,sections:[
  {heading:'Ce qu’est Sendoh',body:[
   'Sendoh aide les gens à organiser l’argent ensemble : collectes de groupe, tours récurrents comme une njangi ou une tontine, demandes d’argent et paiements entre personnes.',
   'Sendoh n’est pas une banque. Les paiements Mobile Money sont traités par notre partenaire de paiement MeSomb avec MTN Mobile Money et Orange Money. Les contributions à une collecte sont détenues via MeSomb jusqu’à ce que l’organisateur clôture la collecte et que le versement soit envoyé.']},
  {heading:'Accès anticipé',body:['Pendant la phase pilote, les paiements fonctionnent en mode test : aucun argent réel ne circule. Nous vous préviendrons dans l’application et sur ce site avant l’ouverture des paiements réels.']},
  {heading:'Votre compte',body:[
   'Vous vous connectez avec votre propre numéro de téléphone et en gardez l’accès. Vous êtes responsable de l’utilisation de votre compte.',
   'Utilisez votre vrai nom, afin que les personnes avec qui vous organisez de l’argent puissent vous reconnaître.']},
  {heading:'Frais',body:['Tous les frais sont affichés avant que vous approuviez un paiement ou clôturiez une collecte. Vous ne payez jamais de frais qui ne vous ont pas été montrés d’abord. Aucun frais sur les espèces enregistrées par un organisateur.']},
  {heading:'Paiements',body:[
   'Un paiement ne compte qu’une fois confirmé par l’opérateur Mobile Money. Pendant la confirmation, merci de ne pas payer à nouveau.',
   'Sendoh ne peut pas annuler un paiement confirmé. En cas de problème, contactez l’organisateur ou la personne que vous avez payée, puis notre page Aide.']},
  {heading:'Organisateurs',body:[
   'Les organisateurs décrivent leur collecte honnêtement, enregistrent les espèces avec exactitude et utilisent l’argent pour l’objet annoncé.',
   'Une fois la collecte clôturée, aucune nouvelle contribution n’est acceptée et le versement est envoyé une seule fois, au numéro de réception affiché avant la clôture.']},
  {heading:'Ce qui est interdit',body:['La fraude, les arnaques, le blanchiment d’argent, le financement d’activités illégales, l’usurpation d’identité ou l’utilisation de Sendoh pour harceler quelqu’un. Nous pouvons suspendre des comptes ou retenir des paiements pour protéger les personnes, et nous coopérons avec les demandes légales.']},
  {heading:'Responsabilité',body:['Nous faisons en sorte que Sendoh reste disponible et exact, mais il peut parfois être interrompu. Dans la mesure permise par la loi, nous ne sommes pas responsables des pertes causées par les réseaux Mobile Money, par des informations saisies de façon incorrecte, ou par des accords entre membres d’un groupe.']},
  {heading:'Droit applicable',body:['Ces conditions sont régies par le droit camerounais.']},
  {heading:'Modifications',body:['Si nous modifions ces conditions de manière importante, nous vous en informerons dans l’application avant que le changement ne s’applique.']},
 ]},
};

export const legal={privacy,terms};

export type Faq={q:string;a:string};
export const faqs:Record<Lang,Faq[]>={
 en:[
  {q:'I paid, but the page still says it’s confirming.',a:'Please don’t pay again. Mobile Money can take a few minutes to confirm. Keep the collection link: it shows the result as soon as the provider confirms it.'},
  {q:'My cash contribution is wrong or missing.',a:'Cash is recorded by the organizer, not by Sendoh. Contact them first. In the Sendoh app, you can also flag a cash error so they are told.'},
  {q:'I received a collection link. Do I need the app?',a:'No. Open the link, verify your number with a code, and contribute from your browser.'},
  {q:'How does a njangi work on Sendoh?',a:'The organizer runs the collection in rounds. Each round has its own total and payout. When a new round opens, the same link shows your new share, and your earlier rounds stay paid.'},
  {q:'How do I delete my account?',a:'In the app: Profile, then Delete account. On the web: open /delete-account and verify your number.'},
 ],
 fr:[
  {q:'J’ai payé, mais la page indique toujours que la confirmation est en cours.',a:'Merci de ne pas payer à nouveau. Mobile Money peut prendre quelques minutes pour confirmer. Gardez le lien de la collecte : il affiche le résultat dès que l’opérateur confirme.'},
  {q:'Ma contribution en espèces est erronée ou manquante.',a:'Les espèces sont enregistrées par l’organisateur, pas par Sendoh. Contactez-le d’abord. Dans l’application Sendoh, vous pouvez aussi signaler une erreur d’espèces pour qu’il soit prévenu.'},
  {q:'J’ai reçu un lien de collecte. Ai-je besoin de l’application ?',a:'Non. Ouvrez le lien, vérifiez votre numéro avec un code et contribuez depuis votre navigateur.'},
  {q:'Comment fonctionne une njangi sur Sendoh ?',a:'L’organisateur gère la collecte par tours. Chaque tour a son propre total et son propre versement. Quand un nouveau tour s’ouvre, le même lien affiche votre nouvelle part, et vos tours précédents restent payés.'},
  {q:'Comment supprimer mon compte ?',a:'Dans l’application : Profil, puis Supprimer le compte. Sur le web : ouvrez /delete-account et vérifiez votre numéro.'},
 ],
};
