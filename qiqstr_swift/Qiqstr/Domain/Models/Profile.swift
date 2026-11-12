import Foundation

struct Profile: Identifiable, Hashable, Sendable {
    var pubkey: String
    var name: String
    var displayName: String
    var about: String
    var picture: String
    var banner: String
    var nip05: String
    var lud16: String
    var website: String
    var location: String

    var id: String { pubkey }

    var givenName: String? { displayName.nilIfEmpty ?? name.nilIfEmpty }

    var bestName: String {
        if !displayName.isEmpty { return displayName }
        if !name.isEmpty { return name }
        return Profile.shortNpub(pubkey)
    }

    init(pubkey: String, name: String = "", displayName: String = "", about: String = "", picture: String = "", banner: String = "", nip05: String = "", lud16: String = "", website: String = "", location: String = "") {
        self.pubkey = pubkey; self.name = name; self.displayName = displayName; self.about = about
        self.picture = picture; self.banner = banner; self.nip05 = nip05; self.lud16 = lud16
        self.website = website; self.location = location
    }

    init(json j: JSONObject, fallbackPubkey: String = "") {
        self.init(
            pubkey: j.str("pubkeyHex") ?? j.str("pubkey") ?? fallbackPubkey,
            name: j.str("name") ?? "",
            displayName: j.str("display_name") ?? j.str("displayName") ?? "",
            about: j.str("about") ?? "",
            picture: j.str("picture") ?? j.str("profileImage") ?? "",
            banner: j.str("banner") ?? "",
            nip05: j.str("nip05") ?? "",
            lud16: j.str("lud16") ?? "",
            website: j.str("website") ?? "",
            location: j.str("location") ?? ""
        )
    }

    var metadataJSON: String {
        var m: JSONObject = [:]
        if !name.isEmpty { m["name"] = name }
        if !displayName.isEmpty { m["display_name"] = displayName }
        if !about.isEmpty { m["about"] = about }
        if !picture.isEmpty { m["picture"] = picture }
        if !banner.isEmpty { m["banner"] = banner }
        if !nip05.isEmpty { m["nip05"] = nip05 }
        if !lud16.isEmpty { m["lud16"] = lud16 }
        if !website.isEmpty { m["website"] = website }
        if !location.isEmpty { m["location"] = location }
        return JSON.string(m)
    }

    static func shortNpub(_ hex: String) -> String {
        let npub = Nip19.npub(hex) ?? hex
        guard npub.count > 16 else { return npub }
        return "\(npub.prefix(10))…\(npub.suffix(6))"
    }
}
