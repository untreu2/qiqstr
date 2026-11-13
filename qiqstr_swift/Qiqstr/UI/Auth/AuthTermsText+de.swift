extension AuthTermsText {
    static let markdownDE = #"""
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

    - Ihre privaten Schlüssel und Ihre Wallet-Verbindung werden in der iOS-Schlüsselbund (Keychain) aufbewahrt.
    - Direktnachrichten werden in einer verschlüsselten Datenbank auf Ihrem Gerät gespeichert.
    - Notizen, Profile und Medien werden zwischengespeichert, damit die App schnell arbeitet. Diesen Cache können Sie in den Einstellungen leeren.
    - Ihre Einstellungen, Entwürfe, Stummschaltliste und ausgeblendeten Beiträge werden lokal gespeichert.

    ---

    ### Löschen Ihrer Daten

    Sie können Ihr Konto jederzeit unter **Einstellungen > Konto löschen** löschen. Die App fordert die Relays daraufhin auf, Ihre Ereignisse zu löschen (NIP-09) und Ihr Konto zu entfernen (NIP-62, Request to Vanish), und löscht die Schlüssel, Nachrichten, die Wallet-Verbindung und weitere Daten des Kontos von Ihrem Gerät.

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

    - Die App steuert einen von Ihnen konfigurierten externen Wallet-Dienst oder Node fern. Der Entwickler betreibt keinen Wallet-Dienst und verwahrt, kontrolliert oder hat keinen Zugriff auf Ihre Gelder.
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
    """#
}
