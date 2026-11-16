package me.untreu.qiqstr.ui.auth

import me.untreu.qiqstr.core.AppLanguage

object AuthTermsText {
    const val SUPPORT_URL = "https://github.com/untreu2/qiqstr/issues"

    val localized: String
        get() = when (AppLanguage.current) {
            AppLanguage.TR -> markdownTR
            AppLanguage.DE -> markdownDE
            // The terms are only written in English, Turkish and German.
            else -> markdown
        }

    private val markdown = """
# Privacy Policy and Terms of Use

**Application:** qiqstr for iOS — Nostr Client
**Developer:** emir yorulmaz
**Effective Date:** November 13, 2026

---

## Privacy Policy

### Overview

qiqstr does not collect, process, or store any personal information on servers controlled by the developer. The developer runs no servers for the App and has no access to the data on your device. Your account is a cryptographic key pair that only you hold.

The App is a client for the Nostr network. To work, it connects directly from your device to services operated by third parties, listed below. Those services are not covered by this policy and have their own terms and privacy practices.

---

### Information We Do Not Collect

qiqstr does not collect:

- Your name, email address, or any personally identifiable information
- Your location data
- Your private key or seed phrase — these never leave your device
- Usage analytics or crash reports sent to the developer
- Any data for advertising, tracking, or profiling purposes

---

### Services the App Connects To

Every service you connect to can see your IP address. In addition:

- **Nostr relays.** By default relay.damus.io, nos.lol, relay.primal.net and vitor.nostr1.com, plus the relays you add, the relays used by people you follow, and public discovery, search and index relays. They receive your public key, your requests, and everything you publish. Notes, reactions, reposts, follows, profile details and zap receipts are public and may be stored and redistributed by relays indefinitely.
- **Primal caching service (cache2.primal.net).** Used for Explore, trending content and suggestions. It receives your public key so results can be personalised.
- **nostr.wine.** Used for trending content and search. It receives your search queries.
- **Media hosts (blossom.primal.net and nostr.download).** Photos and videos you attach are uploaded there. Media in public notes can be opened by anyone who has the link. Media in direct messages is encrypted on your device before it is uploaded.
- **Websites linked in notes.** Link previews, images and videos are loaded directly from the sites that host them.
- **Your wallet.** If you connect a wallet with Nostr Wallet Connect, payment requests are sent to it through the relay named in your connection. When you send a zap or pay a Lightning address, the App contacts the recipient's Lightning provider. Redeeming a Cashu token contacts the mint that issued it.
- **Identity providers.** Verifying a Nostr address (NIP-05) contacts the domain in that address.
- **mempool.space.** Used to show Bitcoin prices in your local currency. You can turn this off in Settings.

---

### Data Stored on Your Device

- Your private keys and wallet connection are kept in the iOS Keychain.
- Direct messages are stored in an encrypted database on your device.
- Notes, profiles and media are cached so the App works quickly. You can clear this cache in Settings.
- Your preferences, drafts, mute list and hidden posts are stored locally.

---

### Deleting Your Data

You can delete your account at any time in **Settings > Delete account**. The App then asks relays to delete your events (NIP-09) and to remove your account (NIP-62 request to vanish), and erases the account's keys, messages, wallet connection and other data from your device.

Relays are operated by third parties. The developer cannot force them to honour deletion requests, and content that others have already copied cannot be recalled. Logging out removes your key from the device without sending any deletion request.

---

### Children

The App is not directed to children. You must meet the minimum age set by the App's rating in the App Store and by the laws of your country.

---

## Terms of Use

### 1. Acceptance of Terms

By downloading, installing, or using qiqstr ("the App"), you agree to be bound by these Terms of Use. If you do not agree, do not use the App.

---

### 2. Description of the App

qiqstr is a free, open-source Nostr protocol client that allows you to:

- Publish and read notes, articles, and other content on the Nostr network
- Follow other users and manage your social graph
- Send and receive end-to-end encrypted direct messages
- React to, repost, and quote content
- Send and receive Bitcoin Lightning payments through a wallet you connect with Nostr Wallet Connect (NWC)
- Manage cryptographic key pairs for identity on the Nostr network

The App is released under the [MIT License](https://github.com/untreu2/qiqstr/blob/master/LICENSE). Source code is publicly available.

---

### 3. The Nostr Protocol and Decentralization

qiqstr is a client for the **Nostr protocol**, a decentralized and open network:

- **No central server.** Content is published to and retrieved from independently operated relays. The developer does not operate or control these relays.
- **No accounts held by the developer.** Your identity on Nostr is defined solely by a cryptographic key pair that you generate and control.
- **Moderation happens in the App.** The developer cannot delete data from relays it does not operate. The App therefore filters what it shows and gives you the tools described in Section 7.
- **Content is public by default.** Notes, reactions, reposts, and profile metadata are publicly visible to anyone with access to the relays you publish to, unless encrypted.

---

### 4. Your Cryptographic Keys

Your Nostr identity is controlled entirely by your private key (`nsec`). You are solely responsible for:

- Generating, storing, and backing up your private key securely.
- Any actions taken with your private key, whether by you or by any third party who gains access to it.
- Understanding that **if you lose your private key, your identity cannot be recovered** — not by the developer, not by any relay operator.
- Understanding that **if your private key is compromised**, any party in possession of it can act as you on the Nostr network.

The App stores your private key locally on your device using secure storage provided by the operating system. The developer never has access to your private key.

---

### 5. Bitcoin and Lightning Payments

qiqstr can send and request Bitcoin Lightning payments through the Nostr Wallet Connect (NWC) protocol. By using the wallet features, you acknowledge:

- The App remote-controls an external wallet service or node that you configure. The developer does not operate any wallet service and does not hold, control, or have access to your funds.
- **Zaps are voluntary gifts.** A zap is an optional payment sent directly from your wallet to another person's wallet. Zaps do not unlock any content, feature, or service in the App, and the developer receives no part of them.
- Bitcoin and Lightning Network transactions are **irreversible**. Verify all payment details before confirming.
- The developer is not a financial institution, money services business, or payment processor.
- You are solely responsible for compliance with any applicable laws regarding cryptocurrency use in your jurisdiction.
- The developer is not liable for any loss of funds resulting from incorrect transactions, wallet service failures, or network errors.

---

### 6. Cashu Tokens

The App can redeem a Cashu token that you paste or scan. The token is exchanged with the mint that issued it and paid out to your connected Lightning wallet. By using this feature, you acknowledge:

- **Mints are independent third parties.** The developer has no affiliation with, control over, or responsibility for any mint.
- **Redemption can fail.** If the payout does not complete, the value remains in the App on your device until you retry. It is not backed up and is lost if you delete the App or its data.
- The developer is not liable for any loss of funds caused by a mint, by a failed redemption, or by loss of the data on your device.

---

### 7. Prohibited Conduct and Moderation

**qiqstr has zero tolerance for objectionable content and abusive users.**

By using qiqstr, you agree not to use the App to:

- Publish, distribute, or facilitate content that is illegal under applicable law.
- Submit objectionable content, including but not limited to: (i) sexually explicit materials; (ii) obscene, defamatory, libelous, slanderous, violent, or unlawful content; (iii) content that infringes upon the rights of any third party, including copyright, trademark, or privacy rights; (iv) content that promotes the use or sale of illegal or regulated substances, tobacco products, ammunition, or firearms; (v) illegal content related to gambling.
- Harass, threaten, or harm other individuals.
- Impersonate any person or entity.
- Distribute malware, spam, or other harmful content.
- Attempt to disrupt or degrade the operation of Nostr relays or other network infrastructure.

To keep the App safe:

- **Report.** You can report any note, profile, conversation, live stream, chat message, or article from its menu. Reported content is hidden for you immediately.
- **Block.** You can mute any user. A muted user's notes, replies, messages and notifications no longer appear for you.
- **Filtering.** Posts marked as sensitive are hidden behind a warning, and spam filters are on by default.
- **Review within 24 hours.** The developer reviews reports and complaints received through the contact in Section 15 within 24 hours and removes offending content and the accounts responsible from the parts of the App it controls.

If you violate these terms, your right to use the App ends immediately.

---

### 8. App Store Terms

If you downloaded qiqstr from Apple's App Store, your use is also subject to Apple's terms, including the Apple Media Services Terms and Conditions. Apple is not responsible for the App or its content and has no obligation to provide maintenance or support for it.

---

### 9. Open Source and Intellectual Property

qiqstr is open-source software licensed under the **MIT License**. You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software in accordance with the MIT License.

The qiqstr name, logo, and associated branding are the property of the developer. The MIT License does not grant rights to use these for branding or endorsement purposes without prior written permission.

---

### 10. Disclaimer of Warranties

THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

THE DEVELOPER DOES NOT WARRANT THAT:
- THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.
- ANY DEFECTS WILL BE CORRECTED.
- THE APP OR THE SERVERS THAT MAKE IT AVAILABLE ARE FREE OF VIRUSES OR OTHER HARMFUL COMPONENTS.

---

### 11. Limitation of Liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE DEVELOPER SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO:

- LOSS OF FUNDS, BITCOIN, OR OTHER DIGITAL ASSETS.
- LOSS OF DATA OR PRIVATE KEYS.
- UNAUTHORIZED ACCESS TO YOUR ACCOUNT OR KEYS.
- ANY DAMAGES ARISING FROM YOUR USE OF OR INABILITY TO USE THE APP.

THIS LIMITATION APPLIES REGARDLESS OF THE THEORY OF LIABILITY AND EVEN IF THE DEVELOPER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

---

### 12. Indemnification

You agree to indemnify and hold harmless the developer from and against any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or in any way connected with your use of the App, your violation of these Terms, or your violation of any rights of another party.

---

### 13. Changes to These Terms

The developer reserves the right to modify these Terms at any time. Changes will be reflected by updating the "Effective Date" at the top of this document. Continued use of the App after changes constitutes acceptance of the revised Terms.

---

### 14. Governing Law

These Terms are governed by and construed in accordance with applicable law. Any disputes arising under these Terms shall be resolved in the jurisdiction of the developer's residence, to the extent permitted by law.

---

### 15. Contact

To report content or a user, to ask about your data, or for any question about this Privacy Policy or these Terms of Use, contact the developer at [github.com/untreu2/qiqstr/issues](https://github.com/untreu2/qiqstr/issues). The same link is available in the App under **Settings > Contact support**.
"""

    private val markdownDE = """
# Datenschutzerklärung und Nutzungsbedingungen

Dieser Text ist eine Übersetzung, die nur der Einfachheit halber bereitgestellt wird. Bei Abweichungen zwischen der englischen Fassung und dieser Übersetzung ist die englische Fassung maßgeblich.

**Anwendung:** qiqstr for iOS — Nostr-Client
**Entwickler:** emir yorulmaz
**Gültig ab:** 13. November 2026

---

## Datenschutzerklärung

### Überblick

qiqstr erhebt, verarbeitet oder speichert keine personenbezogenen Daten auf Servern, die vom Entwickler kontrolliert werden. Der Entwickler betreibt keine Server für die App und hat keinen Zugriff auf die Daten auf Ihrem Gerät. Ihr Konto ist ein kryptografisches Schlüsselpaar, das nur Sie besitzen.

Die App ist ein Client für das Nostr-Netzwerk. Damit sie funktioniert, verbindet sie sich von Ihrem Gerät direkt mit Diensten, die von Dritten betrieben werden und unten aufgeführt sind. Diese Dienste sind nicht Gegenstand dieser Erklärung und haben eigene Bedingungen und Datenschutzpraktiken.

---

### Informationen, die wir nicht erheben

qiqstr erhebt nicht:

- Ihren Namen, Ihre E-Mail-Adresse oder sonstige personenbezogene Daten
- Ihre Standortdaten
- Ihren privaten Schlüssel oder Ihre Seed-Phrase — diese verlassen Ihr Gerät nie
- Nutzungsanalysen oder Absturzberichte, die an den Entwickler gesendet werden
- Daten für Werbe-, Tracking- oder Profiling-Zwecke

---

### Dienste, mit denen sich die App verbindet

Jeder Dienst, mit dem Sie sich verbinden, kann Ihre IP-Adresse sehen. Darüber hinaus:

- **Nostr-Relays.** Standardmäßig relay.damus.io, nos.lol, relay.primal.net und vitor.nostr1.com, dazu die von Ihnen hinzugefügten Relays, die Relays der Personen, denen Sie folgen, sowie öffentliche Discovery-, Such- und Index-Relays. Sie erhalten Ihren öffentlichen Schlüssel, Ihre Anfragen und alles, was Sie veröffentlichen. Notizen, Reaktionen, Reposts, Follows, Profilangaben und Zap-Belege sind öffentlich und können von Relays unbegrenzt gespeichert und weiterverbreitet werden.
- **Primal-Caching-Dienst (cache2.primal.net).** Wird für Entdecken, Trendinhalte und Vorschläge verwendet. Er erhält Ihren öffentlichen Schlüssel, damit die Ergebnisse personalisiert werden können.
- **nostr.wine.** Wird für Trendinhalte und die Suche verwendet. Er erhält Ihre Suchanfragen.
- **Medien-Hosts (blossom.primal.net und nostr.download).** Fotos und Videos, die Sie anhängen, werden dorthin hochgeladen. Medien in öffentlichen Notizen kann jeder öffnen, der den Link hat. Medien in Direktnachrichten werden auf Ihrem Gerät verschlüsselt, bevor sie hochgeladen werden.
- **In Notizen verlinkte Websites.** Linkvorschauen, Bilder und Videos werden direkt von den Websites geladen, die sie hosten.
- **Ihre Wallet.** Wenn Sie eine Wallet über Nostr Wallet Connect verbinden, werden Zahlungsanfragen über das in Ihrer Verbindung genannte Relay an sie gesendet. Wenn Sie einen Zap senden oder eine Lightning-Adresse bezahlen, kontaktiert die App den Lightning-Anbieter des Empfängers. Das Einlösen eines Cashu-Tokens kontaktiert die Mint, die ihn ausgegeben hat.
- **Identitätsanbieter.** Die Überprüfung einer Nostr-Adresse (NIP-05) kontaktiert die Domain in dieser Adresse.
- **mempool.space.** Wird verwendet, um Bitcoin-Preise in Ihrer lokalen Währung anzuzeigen. Sie können dies in den Einstellungen ausschalten.

---

### Auf Ihrem Gerät gespeicherte Daten

- Ihre privaten Schlüssel und Ihre Wallet-Verbindung werden im iOS-Schlüsselbund (Keychain) aufbewahrt.
- Direktnachrichten werden in einer verschlüsselten Datenbank auf Ihrem Gerät gespeichert.
- Notizen, Profile und Medien werden zwischengespeichert, damit die App schnell arbeitet. Diesen Cache können Sie in den Einstellungen leeren.
- Ihre Einstellungen, Entwürfe, Stummschaltungsliste und ausgeblendeten Beiträge werden lokal gespeichert.

---

### Löschen Ihrer Daten

Sie können Ihr Konto jederzeit unter **Einstellungen > Konto löschen** löschen. Die App fordert die Relays daraufhin auf, Ihre Ereignisse zu löschen (NIP-09) und Ihr Konto zu entfernen (NIP-62-Anfrage zum Verschwinden), und löscht die Schlüssel, Nachrichten, die Wallet-Verbindung und weitere Daten des Kontos von Ihrem Gerät.

Relays werden von Dritten betrieben. Der Entwickler kann sie nicht zwingen, Löschanfragen nachzukommen, und Inhalte, die andere bereits kopiert haben, können nicht zurückgerufen werden. Beim Abmelden wird Ihr Schlüssel vom Gerät entfernt, ohne dass eine Löschanfrage gesendet wird.

---

### Kinder

Die App richtet sich nicht an Kinder. Sie müssen das Mindestalter erfüllen, das durch die Altersfreigabe der App im App Store und durch die Gesetze Ihres Landes festgelegt ist.

---

## Nutzungsbedingungen

### 1. Annahme der Bedingungen

Durch das Herunterladen, Installieren oder Verwenden von qiqstr („die App“) erklären Sie sich an diese Nutzungsbedingungen gebunden. Wenn Sie nicht einverstanden sind, verwenden Sie die App nicht.

---

### 2. Beschreibung der App

qiqstr ist ein kostenloser, quelloffener Client für das Nostr-Protokoll, mit dem Sie:

- Notizen, Artikel und andere Inhalte im Nostr-Netzwerk veröffentlichen und lesen können
- anderen Nutzern folgen und Ihren Social Graph verwalten können
- Ende-zu-Ende-verschlüsselte Direktnachrichten senden und empfangen können
- auf Inhalte reagieren, sie reposten und zitieren können
- Bitcoin-Lightning-Zahlungen über eine mit Nostr Wallet Connect (NWC) verbundene Wallet senden und empfangen können
- kryptografische Schlüsselpaare für Ihre Identität im Nostr-Netzwerk verwalten können

Die App wird unter der [MIT-Lizenz](https://github.com/untreu2/qiqstr/blob/master/LICENSE) veröffentlicht. Der Quellcode ist öffentlich verfügbar.

---

### 3. Das Nostr-Protokoll und Dezentralisierung

qiqstr ist ein Client für das **Nostr-Protokoll**, ein dezentrales und offenes Netzwerk:

- **Kein zentraler Server.** Inhalte werden auf unabhängig betriebenen Relays veröffentlicht und von dort abgerufen. Der Entwickler betreibt oder kontrolliert diese Relays nicht.
- **Keine vom Entwickler geführten Konten.** Ihre Identität auf Nostr wird ausschließlich durch ein kryptografisches Schlüsselpaar bestimmt, das Sie selbst erzeugen und kontrollieren.
- **Moderation findet in der App statt.** Der Entwickler kann keine Daten von Relays löschen, die er nicht betreibt. Die App filtert daher, was sie anzeigt, und stellt Ihnen die in Abschnitt 7 beschriebenen Werkzeuge zur Verfügung.
- **Inhalte sind standardmäßig öffentlich.** Notizen, Reaktionen, Reposts und Profil-Metadaten sind für jeden sichtbar, der Zugriff auf die Relays hat, auf denen Sie veröffentlichen, sofern sie nicht verschlüsselt sind.

---

### 4. Ihre kryptografischen Schlüssel

Ihre Nostr-Identität wird vollständig von Ihrem privaten Schlüssel (`nsec`) kontrolliert. Sie sind allein verantwortlich für:

- Das sichere Erzeugen, Aufbewahren und Sichern Ihres privaten Schlüssels.
- Alle Handlungen mit Ihrem privaten Schlüssel, gleich ob durch Sie oder durch einen Dritten, der Zugriff darauf erlangt.
- Das Verständnis, dass **Ihre Identität nicht wiederhergestellt werden kann, wenn Sie Ihren privaten Schlüssel verlieren** — weder durch den Entwickler noch durch einen Relay-Betreiber.
- Das Verständnis, dass **bei einer Kompromittierung Ihres privaten Schlüssels** jede Partei, die ihn besitzt, im Nostr-Netzwerk in Ihrem Namen handeln kann.

Die App speichert Ihren privaten Schlüssel lokal auf Ihrem Gerät in dem vom Betriebssystem bereitgestellten sicheren Speicher. Der Entwickler hat niemals Zugriff auf Ihren privaten Schlüssel.

---

### 5. Bitcoin- und Lightning-Zahlungen

qiqstr kann Bitcoin-Lightning-Zahlungen über das Nostr-Wallet-Connect-Protokoll (NWC) senden und anfordern. Durch die Nutzung der Wallet-Funktionen erkennen Sie Folgendes an:

- Die App steuert einen von Ihnen konfigurierten externen Wallet-Dienst oder Node fern. Der Entwickler betreibt keinen Wallet-Dienst, verwahrt und kontrolliert Ihre Gelder nicht und hat keinen Zugriff darauf.
- **Zaps sind freiwillige Geschenke.** Ein Zap ist eine optionale Zahlung, die direkt von Ihrer Wallet an die Wallet einer anderen Person gesendet wird. Zaps schalten keine Inhalte, Funktionen oder Dienste in der App frei, und der Entwickler erhält keinen Anteil daran.
- Bitcoin- und Lightning-Network-Transaktionen sind **unumkehrbar**. Prüfen Sie alle Zahlungsangaben, bevor Sie bestätigen.
- Der Entwickler ist kein Finanzinstitut, kein Geldtransferdienstleister und kein Zahlungsabwickler.
- Sie sind allein für die Einhaltung aller geltenden Gesetze zur Nutzung von Kryptowährungen in Ihrer Rechtsordnung verantwortlich.
- Der Entwickler haftet nicht für Geldverluste, die durch fehlerhafte Transaktionen, Ausfälle des Wallet-Dienstes oder Netzwerkfehler entstehen.

---

### 6. Cashu-Tokens

Die App kann einen Cashu-Token einlösen, den Sie einfügen oder scannen. Der Token wird bei der Mint, die ihn ausgegeben hat, eingetauscht und an Ihre verbundene Lightning-Wallet ausgezahlt. Durch die Nutzung dieser Funktion erkennen Sie Folgendes an:

- **Mints sind unabhängige Dritte.** Der Entwickler steht in keiner Verbindung zu einer Mint, hat keine Kontrolle über sie und trägt keine Verantwortung für sie.
- **Das Einlösen kann fehlschlagen.** Wird die Auszahlung nicht abgeschlossen, verbleibt der Wert in der App auf Ihrem Gerät, bis Sie es erneut versuchen. Er wird nicht gesichert und geht verloren, wenn Sie die App oder ihre Daten löschen.
- Der Entwickler haftet nicht für Geldverluste, die durch eine Mint, ein fehlgeschlagenes Einlösen oder den Verlust der Daten auf Ihrem Gerät verursacht werden.

---

### 7. Verbotenes Verhalten und Moderation

**qiqstr duldet keinerlei anstößige Inhalte und missbräuchliche Nutzer.**

Durch die Nutzung von qiqstr verpflichten Sie sich, die App nicht dazu zu verwenden:

- Inhalte zu veröffentlichen, zu verbreiten oder deren Verbreitung zu erleichtern, die nach geltendem Recht rechtswidrig sind.
- Anstößige Inhalte einzustellen, einschließlich, aber nicht beschränkt auf: (i) sexuell explizites Material; (ii) obszöne, diffamierende, verleumderische, gewalttätige oder rechtswidrige Inhalte; (iii) Inhalte, die Rechte Dritter verletzen, einschließlich Urheber-, Marken- oder Persönlichkeitsrechten; (iv) Inhalte, die die Verwendung oder den Verkauf illegaler oder regulierter Substanzen, Tabakprodukte, Munition oder Schusswaffen bewerben; (v) illegale Inhalte im Zusammenhang mit Glücksspiel.
- Andere Personen zu belästigen, zu bedrohen oder ihnen zu schaden.
- Sich als eine andere Person oder Organisation auszugeben.
- Malware, Spam oder andere schädliche Inhalte zu verbreiten.
- Den Betrieb von Nostr-Relays oder anderer Netzwerkinfrastruktur zu stören oder zu beeinträchtigen.

Um die App sicher zu halten:

- **Melden.** Sie können jede Notiz, jedes Profil, jede Unterhaltung, jeden Livestream, jede Chatnachricht und jeden Artikel über das zugehörige Menü melden. Gemeldete Inhalte werden für Sie sofort ausgeblendet.
- **Blockieren.** Sie können jeden Nutzer stummschalten. Notizen, Antworten, Nachrichten und Benachrichtigungen eines stummgeschalteten Nutzers erscheinen nicht mehr bei Ihnen.
- **Filtern.** Als sensibel markierte Beiträge werden hinter einer Warnung ausgeblendet, und Spam-Filter sind standardmäßig aktiviert.
- **Prüfung innerhalb von 24 Stunden.** Der Entwickler prüft Meldungen und Beschwerden, die über den Kontakt in Abschnitt 15 eingehen, innerhalb von 24 Stunden und entfernt anstößige Inhalte sowie die verantwortlichen Konten aus den Teilen der App, die er kontrolliert.

Wenn Sie gegen diese Bedingungen verstoßen, endet Ihr Recht zur Nutzung der App mit sofortiger Wirkung.

---

### 8. App-Store-Bedingungen

Wenn Sie qiqstr aus dem App Store von Apple heruntergeladen haben, unterliegt Ihre Nutzung zusätzlich den Bedingungen von Apple, einschließlich der Apple Media Services Terms and Conditions. Apple ist weder für die App noch für ihre Inhalte verantwortlich und nicht zur Wartung oder Unterstützung der App verpflichtet.

---

### 9. Open Source und geistiges Eigentum

qiqstr ist Open-Source-Software, die unter der **MIT-Lizenz** lizenziert ist. Sie dürfen die Software gemäß der MIT-Lizenz frei nutzen, kopieren, ändern, zusammenführen, veröffentlichen, verbreiten, unterlizenzieren und/oder Kopien davon verkaufen.

Der Name qiqstr, das Logo und die zugehörigen Markenelemente sind Eigentum des Entwicklers. Die MIT-Lizenz gewährt keine Rechte, diese ohne vorherige schriftliche Genehmigung für Marken- oder Werbezwecke zu verwenden.

---

### 10. Gewährleistungsausschluss

DIE APP WIRD „WIE BESEHEN“ UND „WIE VERFÜGBAR“ BEREITGESTELLT, OHNE JEGLICHE AUSDRÜCKLICHE ODER STILLSCHWEIGENDE GEWÄHRLEISTUNG, EINSCHLIESSLICH, ABER NICHT BESCHRÄNKT AUF GEWÄHRLEISTUNGEN DER MARKTGÄNGIGKEIT, DER EIGNUNG FÜR EINEN BESTIMMTEN ZWECK UND DER NICHTVERLETZUNG VON RECHTEN.

DER ENTWICKLER GEWÄHRLEISTET NICHT, DASS:
- DIE APP UNTERBRECHUNGSFREI, FEHLERFREI ODER SICHER SEIN WIRD.
- MÄNGEL BEHOBEN WERDEN.
- DIE APP ODER DIE SERVER, DIE SIE BEREITSTELLEN, FREI VON VIREN ODER ANDEREN SCHÄDLICHEN BESTANDTEILEN SIND.

---

### 11. Haftungsbeschränkung

SOWEIT NACH GELTENDEM RECHT ZULÄSSIG, HAFTET DER ENTWICKLER NICHT FÜR MITTELBARE, ZUFÄLLIGE, BESONDERE, FOLGE- ODER STRAFSCHÄDEN, EINSCHLIESSLICH, ABER NICHT BESCHRÄNKT AUF:

- VERLUST VON GELDERN, BITCOIN ODER ANDEREN DIGITALEN VERMÖGENSWERTEN.
- VERLUST VON DATEN ODER PRIVATEN SCHLÜSSELN.
- UNBEFUGTEN ZUGRIFF AUF IHR KONTO ODER IHRE SCHLÜSSEL.
- SCHÄDEN, DIE AUS IHRER NUTZUNG DER APP ODER DER UNMÖGLICHKEIT IHRER NUTZUNG ENTSTEHEN.

DIESE BESCHRÄNKUNG GILT UNABHÄNGIG VON DER HAFTUNGSTHEORIE UND AUCH DANN, WENN DER ENTWICKLER AUF DIE MÖGLICHKEIT SOLCHER SCHÄDEN HINGEWIESEN WURDE.

---

### 12. Freistellung

Sie erklären sich bereit, den Entwickler von allen Ansprüchen, Verbindlichkeiten, Schäden, Verlusten und Kosten (einschließlich angemessener Rechtsanwaltskosten) freizustellen und schadlos zu halten, die aus oder im Zusammenhang mit Ihrer Nutzung der App, Ihrem Verstoß gegen diese Bedingungen oder Ihrer Verletzung von Rechten einer anderen Partei entstehen.

---

### 13. Änderungen dieser Bedingungen

Der Entwickler behält sich das Recht vor, diese Bedingungen jederzeit zu ändern. Änderungen werden durch die Aktualisierung des Datums „Gültig ab“ am Anfang dieses Dokuments kenntlich gemacht. Die fortgesetzte Nutzung der App nach Änderungen gilt als Annahme der überarbeiteten Bedingungen.

---

### 14. Anwendbares Recht

Diese Bedingungen unterliegen dem anwendbaren Recht und werden entsprechend ausgelegt. Streitigkeiten aus diesen Bedingungen werden, soweit gesetzlich zulässig, in der Rechtsordnung des Wohnsitzes des Entwicklers beigelegt.

---

### 15. Kontakt

Um einen Inhalt oder Nutzer zu melden, Fragen zu Ihren Daten zu stellen oder bei sonstigen Fragen zu dieser Datenschutzerklärung oder diesen Nutzungsbedingungen wenden Sie sich an den Entwickler unter [github.com/untreu2/qiqstr/issues](https://github.com/untreu2/qiqstr/issues). Derselbe Link ist in der App unter **Einstellungen > Support kontaktieren** verfügbar.
"""

    private val markdownTR = """
# Gizlilik Politikası ve Kullanım Koşulları

Bu metin kolaylık sağlamak amacıyla yapılmış bir çeviridir. İngilizce sürümle bu çeviri arasında fark olması halinde İngilizce sürüm geçerlidir.

**Uygulama:** qiqstr for iOS — Nostr İstemcisi
**Geliştirici:** emir yorulmaz
**Yürürlük Tarihi:** 13 Kasım 2026

---

## Gizlilik Politikası

### Genel Bakış

qiqstr, geliştiricinin kontrol ettiği sunucularda hiçbir kişisel bilgiyi toplamaz, işlemez veya saklamaz. Geliştirici, Uygulama için herhangi bir sunucu işletmez ve cihazınızdaki verilere erişimi yoktur. Hesabınız, yalnızca sizin elinizde bulunan bir kriptografik anahtar çiftidir.

Uygulama, Nostr ağı için bir istemcidir. Çalışabilmek için cihazınızdan doğrudan, aşağıda listelenen üçüncü tarafların işlettiği hizmetlere bağlanır. Bu hizmetler bu politikanın kapsamında değildir ve kendi koşulları ile gizlilik uygulamaları vardır.

---

### Toplamadığımız Bilgiler

qiqstr şunları toplamaz:

- Adınızı, e-posta adresinizi veya kişisel olarak tanımlanabilir herhangi bir bilgiyi
- Konum verilerinizi
- Özel anahtarınızı veya kurtarma ifadenizi (seed phrase) — bunlar cihazınızdan asla ayrılmaz
- Geliştiriciye gönderilen kullanım analizlerini veya çökme raporlarını
- Reklam, izleme veya profilleme amaçlı herhangi bir veriyi

---

### Uygulamanın Bağlandığı Hizmetler

Bağlandığınız her hizmet IP adresinizi görebilir. Ayrıca:

- **Nostr relay'leri.** Varsayılan olarak relay.damus.io, nos.lol, relay.primal.net ve vitor.nostr1.com; bunlara ek olarak sizin eklediğiniz relay'ler, takip ettiğiniz kişilerin kullandığı relay'ler ve herkese açık keşif, arama ve dizin relay'leri. Bunlar açık anahtarınızı, isteklerinizi ve yayınladığınız her şeyi alır. Notlar, tepkiler, yeniden paylaşımlar, takipler, profil bilgileri ve zap makbuzları herkese açıktır ve relay'ler tarafından süresiz olarak saklanabilir ve yeniden dağıtılabilir.
- **Primal önbellek hizmeti (cache2.primal.net).** Keşfet, trend içerikler ve öneriler için kullanılır. Sonuçların kişiselleştirilebilmesi için açık anahtarınızı alır.
- **nostr.wine.** Trend içerikler ve arama için kullanılır. Arama sorgularınızı alır.
- **Medya sunucuları (blossom.primal.net ve nostr.download).** Eklediğiniz fotoğraf ve videolar buralara yüklenir. Herkese açık notlardaki medyayı, bağlantıya sahip olan herkes açabilir. Doğrudan mesajlardaki medya, yüklenmeden önce cihazınızda şifrelenir.
- **Notlarda bağlantısı verilen web siteleri.** Bağlantı önizlemeleri, görseller ve videolar doğrudan bunları barındıran sitelerden yüklenir.
- **Cüzdanınız.** Nostr Wallet Connect ile bir cüzdan bağlarsanız, ödeme istekleri bağlantınızda belirtilen relay üzerinden cüzdana gönderilir. Bir zap gönderdiğinizde veya bir Lightning adresine ödeme yaptığınızda Uygulama, alıcının Lightning sağlayıcısıyla iletişime geçer. Bir Cashu token'ı bozdurmak, token'ı çıkaran mint ile iletişime geçer.
- **Kimlik sağlayıcıları.** Bir Nostr adresini (NIP-05) doğrulamak, o adresteki alan adıyla iletişime geçer.
- **mempool.space.** Bitcoin fiyatlarını yerel para biriminizde göstermek için kullanılır. Bunu Ayarlar'dan kapatabilirsiniz.

---

### Cihazınızda Saklanan Veriler

- Özel anahtarlarınız ve cüzdan bağlantınız iOS Anahtar Zinciri'nde (Keychain) tutulur.
- Doğrudan mesajlar, cihazınızda şifreli bir veritabanında saklanır.
- Notlar, profiller ve medya, Uygulama hızlı çalışsın diye önbelleğe alınır. Bu önbelleği Ayarlar'dan temizleyebilirsiniz.
- Tercihleriniz, taslaklarınız, sessize alma listeniz ve gizlenen gönderileriniz yerel olarak saklanır.

---

### Verilerinizi Silme

Hesabınızı istediğiniz zaman **Ayarlar > Hesabı Sil** bölümünden silebilirsiniz. Uygulama bunun ardından relay'lerden olaylarınızı silmelerini (NIP-09) ve hesabınızı kaldırmalarını (NIP-62 kaybolma isteği) ister; ayrıca hesabın anahtarlarını, mesajlarını, cüzdan bağlantısını ve diğer verilerini cihazınızdan siler.

Relay'ler üçüncü tarafların işlettiği sistemlerdir. Geliştirici, silme isteklerine uymaları için onları zorlayamaz ve başkalarının zaten kopyaladığı içerik geri alınamaz. Oturumu kapatmak, herhangi bir silme isteği göndermeden anahtarınızı cihazdan kaldırır.

---

### Çocuklar

Uygulama çocuklara yönelik değildir. App Store'daki Uygulama derecelendirmesinin ve ülkenizin yasalarının belirlediği asgari yaşı karşılamalısınız.

---

## Kullanım Koşulları

### 1. Koşulların Kabulü

qiqstr'yi ("Uygulama") indirerek, yükleyerek veya kullanarak bu Kullanım Koşulları'na bağlı olmayı kabul etmiş olursunuz. Kabul etmiyorsanız Uygulamayı kullanmayın.

---

### 2. Uygulamanın Tanımı

qiqstr, aşağıdakileri yapmanıza olanak tanıyan ücretsiz ve açık kaynaklı bir Nostr protokolü istemcisidir:

- Nostr ağında notlar, makaleler ve diğer içerikleri yayınlamak ve okumak
- Diğer kullanıcıları takip etmek ve sosyal grafiğinizi yönetmek
- Uçtan uca şifreli doğrudan mesajlar göndermek ve almak
- İçeriklere tepki vermek, yeniden paylaşmak ve alıntılamak
- Nostr Wallet Connect (NWC) ile bağladığınız bir cüzdan üzerinden Bitcoin Lightning ödemeleri göndermek ve almak
- Nostr ağındaki kimliğiniz için kriptografik anahtar çiftlerini yönetmek

Uygulama [MIT Lisansı](https://github.com/untreu2/qiqstr/blob/master/LICENSE) kapsamında yayımlanmıştır. Kaynak kodu herkese açıktır.

---

### 3. Nostr Protokolü ve Merkeziyetsizlik

qiqstr, merkeziyetsiz ve açık bir ağ olan **Nostr protokolü** için bir istemcidir:

- **Merkezi sunucu yoktur.** İçerik, bağımsız olarak işletilen relay'lere yayınlanır ve oradan alınır. Geliştirici bu relay'leri işletmez veya kontrol etmez.
- **Geliştiricinin tuttuğu hesap yoktur.** Nostr'daki kimliğiniz yalnızca sizin oluşturduğunuz ve kontrol ettiğiniz bir kriptografik anahtar çiftiyle belirlenir.
- **Moderasyon Uygulama içinde gerçekleşir.** Geliştirici, işletmediği relay'lerden veri silemez. Bu nedenle Uygulama gösterdiklerini filtreler ve size 7. Bölüm'de açıklanan araçları sunar.
- **İçerik varsayılan olarak herkese açıktır.** Notlar, tepkiler, yeniden paylaşımlar ve profil üst verileri, şifrelenmedikçe yayınladığınız relay'lere erişimi olan herkes tarafından görülebilir.

---

### 4. Kriptografik Anahtarlarınız

Nostr kimliğiniz tamamen özel anahtarınız (`nsec`) tarafından kontrol edilir. Şunlardan yalnızca siz sorumlusunuz:

- Özel anahtarınızı güvenli biçimde oluşturmak, saklamak ve yedeklemek.
- Özel anahtarınızla, sizin tarafınızdan veya ona erişen herhangi bir üçüncü taraf tarafından yapılan tüm işlemler.
- **Özel anahtarınızı kaybederseniz kimliğinizin kurtarılamayacağını** anlamak — ne geliştirici ne de herhangi bir relay işletmecisi bunu yapabilir.
- **Özel anahtarınız ele geçirilirse**, ona sahip olan herhangi bir tarafın Nostr ağında sizin adınıza hareket edebileceğini anlamak.

Uygulama, özel anahtarınızı cihazınızda işletim sisteminin sağladığı güvenli depolama ile yerel olarak saklar. Geliştirici özel anahtarınıza asla erişemez.

---

### 5. Bitcoin ve Lightning Ödemeleri

qiqstr, Nostr Wallet Connect (NWC) protokolü üzerinden Bitcoin Lightning ödemeleri gönderebilir ve talep edebilir. Cüzdan özelliklerini kullanarak şunları kabul edersiniz:

- Uygulama, sizin yapılandırdığınız harici bir cüzdan hizmetini veya düğümü uzaktan kontrol eder. Geliştirici herhangi bir cüzdan hizmeti işletmez; paranızı tutmaz, kontrol etmez ve ona erişimi yoktur.
- **Zap'ler isteğe bağlı hediyelerdir.** Zap, cüzdanınızdan başka bir kişinin cüzdanına doğrudan gönderilen isteğe bağlı bir ödemedir. Zap'ler Uygulamada herhangi bir içeriğin, özelliğin veya hizmetin kilidini açmaz ve geliştirici bunlardan hiçbir pay almaz.
- Bitcoin ve Lightning Network işlemleri **geri alınamaz**. Onaylamadan önce tüm ödeme bilgilerini doğrulayın.
- Geliştirici bir finans kuruluşu, para hizmetleri işletmesi veya ödeme işlemcisi değildir.
- Bulunduğunuz yargı bölgesinde kripto para kullanımına ilişkin geçerli yasalara uyumdan yalnızca siz sorumlusunuz.
- Geliştirici; hatalı işlemler, cüzdan hizmeti arızaları veya ağ hataları nedeniyle oluşan hiçbir para kaybından sorumlu değildir.

---

### 6. Cashu Token'ları

Uygulama, yapıştırdığınız veya taradığınız bir Cashu token'ını bozdurabilir. Token, onu çıkaran mint ile takas edilir ve bağlı Lightning cüzdanınıza ödenir. Bu özelliği kullanarak şunları kabul edersiniz:

- **Mint'ler bağımsız üçüncü taraflardır.** Geliştiricinin herhangi bir mint ile bağlantısı yoktur; onları kontrol etmez ve onlardan sorumlu değildir.
- **Bozdurma başarısız olabilir.** Ödeme tamamlanmazsa, siz yeniden deneyene kadar değer cihazınızdaki Uygulamada kalır. Yedeklenmez; Uygulamayı veya verilerini silerseniz kaybolur.
- Geliştirici; bir mint'in, başarısız bir bozdurmanın veya cihazınızdaki verilerin kaybının neden olduğu hiçbir para kaybından sorumlu değildir.

---

### 7. Yasaklı Davranışlar ve Moderasyon

**qiqstr, sakıncalı içeriğe ve kötüye kullanan kullanıcılara karşı sıfır tolerans uygular.**

qiqstr'yi kullanarak Uygulamayı şunlar için kullanmamayı kabul edersiniz:

- Geçerli yasalara göre yasa dışı olan içeriği yayınlamak, dağıtmak veya bunun kolaylaştırılmasına yardım etmek.
- Sakıncalı içerik göndermek; buna şunlar dahildir ancak bunlarla sınırlı değildir: (i) cinsel içerikli materyaller; (ii) müstehcen, itibar zedeleyici, iftira niteliğinde, şiddet içeren veya yasa dışı içerik; (iii) telif hakkı, ticari marka veya gizlilik hakları dahil olmak üzere herhangi bir üçüncü tarafın haklarını ihlal eden içerik; (iv) yasa dışı veya düzenlemeye tabi maddelerin, tütün ürünlerinin, mühimmatın veya ateşli silahların kullanımını ya da satışını teşvik eden içerik; (v) kumarla ilgili yasa dışı içerik.
- Diğer kişileri taciz etmek, tehdit etmek veya onlara zarar vermek.
- Herhangi bir kişiyi veya kuruluşu taklit etmek.
- Kötü amaçlı yazılım, spam veya diğer zararlı içerikleri dağıtmak.
- Nostr relay'lerinin veya diğer ağ altyapısının işleyişini bozmaya ya da düşürmeye çalışmak.

Uygulamayı güvenli tutmak için:

- **Bildirme.** Herhangi bir notu, profili, sohbeti, canlı yayını, sohbet mesajını veya makaleyi menüsünden bildirebilirsiniz. Bildirilen içerik sizin için hemen gizlenir.
- **Engelleme.** Herhangi bir kullanıcıyı sessize alabilirsiniz. Sessize alınan bir kullanıcının notları, yanıtları, mesajları ve bildirimleri artık sizde görünmez.
- **Filtreleme.** Hassas olarak işaretlenen gönderiler bir uyarının arkasında gizlenir ve spam filtreleri varsayılan olarak açıktır.
- **24 saat içinde inceleme.** Geliştirici, 15. Bölüm'deki iletişim adresi üzerinden aldığı bildirimleri ve şikâyetleri 24 saat içinde inceler; kuralları ihlal eden içeriği ve sorumlu hesapları, kontrol ettiği Uygulama bölümlerinden kaldırır.

Bu koşulları ihlal ederseniz Uygulamayı kullanma hakkınız derhal sona erer.

---

### 8. App Store Koşulları

qiqstr'yi Apple'ın App Store'undan indirdiyseniz, kullanımınız ayrıca Apple Media Services Şartları ve Koşulları dahil olmak üzere Apple'ın koşullarına tabidir. Apple, Uygulamadan veya içeriğinden sorumlu değildir ve Uygulamaya bakım veya destek sağlama yükümlülüğü yoktur.

---

### 9. Açık Kaynak ve Fikri Mülkiyet

qiqstr, **MIT Lisansı** altında lisanslanmış açık kaynaklı bir yazılımdır. MIT Lisansı'na uygun olarak yazılımı kullanmakta, kopyalamakta, değiştirmekte, birleştirmekte, yayımlamakta, dağıtmakta, alt lisanslamakta ve/veya kopyalarını satmakta özgürsünüz.

qiqstr adı, logosu ve ilgili marka unsurları geliştiricinin mülkiyetindedir. MIT Lisansı, önceden yazılı izin alınmadan bunların markalama veya tavsiye amaçlarıyla kullanılması için hak vermez.

---

### 10. Garanti Reddi

UYGULAMA, TİCARİ ELVERİŞLİLİK, BELİRLİ BİR AMACA UYGUNLUK VE HAK İHLALİ OLMAMASI GARANTİLERİ DAHİL OLMAK ANCAK BUNLARLA SINIRLI OLMAMAK ÜZERE, AÇIK VEYA ZIMNİ HİÇBİR GARANTİ VERİLMEKSİZİN "OLDUĞU GİBİ" VE "MEVCUT OLDUĞU ŞEKLİYLE" SUNULMAKTADIR.

GELİŞTİRİCİ ŞUNLARI GARANTİ ETMEZ:
- UYGULAMANIN KESİNTİSİZ, HATASIZ VEYA GÜVENLİ OLACAĞINI.
- HERHANGİ BİR KUSURUN GİDERİLECEĞİNİ.
- UYGULAMANIN VEYA ONU KULLANIMA SUNAN SUNUCULARIN VİRÜSLERDEN VEYA DİĞER ZARARLI BİLEŞENLERDEN ARINDIRILMIŞ OLDUĞUNU.

---

### 11. Sorumluluğun Sınırlandırılması

GEÇERLİ YASALARIN İZİN VERDİĞİ AZAMİ ÖLÇÜDE GELİŞTİRİCİ, AŞAĞIDAKİLER DAHİL OLMAK ANCAK BUNLARLA SINIRLI OLMAMAK ÜZERE, DOLAYLI, ARIZİ, ÖZEL, SONUÇSAL VEYA CEZAİ NİTELİKTEKİ HİÇBİR ZARARDAN SORUMLU OLMAYACAKTIR:

- PARA, BİTCOİN VEYA DİĞER DİJİTAL VARLIKLARIN KAYBI.
- VERİ VEYA ÖZEL ANAHTAR KAYBI.
- HESABINIZA VEYA ANAHTARLARINIZA YETKİSİZ ERİŞİM.
- UYGULAMAYI KULLANMANIZDAN VEYA KULLANAMAMANIZDAN KAYNAKLANAN HERHANGİ BİR ZARAR.

BU SINIRLAMA, SORUMLULUK TEORİSİNDEN BAĞIMSIZ OLARAK VE GELİŞTİRİCİYE BÖYLE ZARARLARIN OLASILIĞI BİLDİRİLMİŞ OLSA DAHİ GEÇERLİDİR.

---

### 12. Tazminat

Uygulamayı kullanmanızdan, bu Koşullar'ı ihlal etmenizden veya başka bir tarafın herhangi bir hakkını ihlal etmenizden kaynaklanan ya da bunlarla herhangi bir şekilde bağlantılı her türlü talep, yükümlülük, zarar, kayıp ve masraftan (makul hukuki ücretler dahil) geliştiriciyi tazmin etmeyi ve sorumsuz tutmayı kabul edersiniz.

---

### 13. Bu Koşullardaki Değişiklikler

Geliştirici, bu Koşullar'ı istediği zaman değiştirme hakkını saklı tutar. Değişiklikler, bu belgenin başındaki "Yürürlük Tarihi" güncellenerek yansıtılacaktır. Değişikliklerden sonra Uygulamayı kullanmaya devam etmek, güncellenmiş Koşullar'ın kabul edildiği anlamına gelir.

---

### 14. Uygulanacak Hukuk

Bu Koşullar, geçerli hukuka tabidir ve ona göre yorumlanır. Bu Koşullar kapsamında ortaya çıkan her türlü uyuşmazlık, yasaların izin verdiği ölçüde geliştiricinin ikamet ettiği yargı bölgesinde çözülecektir.

---

### 15. İletişim

Bir içeriği veya kullanıcıyı bildirmek, verilerinizle ilgili soru sormak ya da bu Gizlilik Politikası veya Kullanım Koşulları hakkında herhangi bir sorunuz için geliştiriciyle [github.com/untreu2/qiqstr/issues](https://github.com/untreu2/qiqstr/issues) adresinden iletişime geçin. Aynı bağlantıya Uygulamada **Ayarlar > Destekle iletişime geç** bölümünden de ulaşabilirsiniz.
"""
}
