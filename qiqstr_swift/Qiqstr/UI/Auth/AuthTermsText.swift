import Foundation

enum AuthTermsText {
    static let supportURL = "https://github.com/untreu2/qiqstr/issues"

    static var localized: String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if language.hasPrefix("tr") { return markdownTR }
        if language.hasPrefix("de") { return markdownDE }
        return markdown
    }

    static let markdown = #"""
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
    """#
}
