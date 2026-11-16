package me.untreu.qiqstr

import me.untreu.qiqstr.ui.communities.*
import me.untreu.qiqstr.ui.dm.MarmotGroup
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CommunityPortTest {
    private val owner = "a".repeat(64)
    private val other = "b".repeat(64)
    private fun event(kind: Int, id: String = "room", author: String = owner, time: Long = 10, content: String = "hello", tags: List<List<String>> = emptyList()) = JSONObject().put("kind", kind).put("id", id).put("pubkey", author).put("created_at", time).put("content", content).put("tags", JSONArray(tags))

    @Test fun sexualizedMinorsAreHiddenWithEitherSensitiveSetting() {
        listOf("teen porn", "NSFW: children", "under-18 nude", "schoolgirl pics", "cp xxx").forEach { title ->
            assertFalse(title, CommunitySafety.allows(title, sensitive = false))
            assertFalse(title, CommunitySafety.allows(title, sensitive = true))
        }
        assertFalse(CommunitySafety.allows("Family teens", "nude pics", sensitive = true))
    }
    @Test fun adultRoomsRequireSensitiveContent() {
        assertFalse(CommunitySafety.allows("NSFW room", sensitive = false))
        assertTrue(CommunitySafety.allows("NSFW room", sensitive = true))
        assertFalse(CommunitySafety.allows("18+", sensitive = false))
    }
    @Test fun safetyMatchesWholeTermsAndAllowsNonsexualTopics() {
        assertTrue(CommunitySafety.allows("Kids coding club", sensitive = false))
        assertTrue(CommunitySafety.allows("Sussex technology", sensitive = false))
        assertTrue(CommunitySafety.allows("Bitcoin discussions", sensitive = false))
    }
    @Test fun trustNeverDefaultsToOpenBeforeWebOfTrustIsReady() {
        assertFalse(CommunitySafety.isTrusted(other, owner, emptySet(), false, true))
        assertFalse(CommunitySafety.isTrusted(other, owner, emptySet(), true, false))
        assertTrue(CommunitySafety.isTrusted(other, owner, emptySet(), true, true))
        assertTrue(CommunitySafety.isTrusted(other, owner, setOf(other), false, false))
        assertTrue(CommunitySafety.isTrusted(owner, owner, emptySet(), false, false))
    }
    @Test fun relayAndGroupLinksNormalizeWithoutLosingGroupIdentifier() {
        assertEquals("wss://relay.example", normalizedRelay(" relay.example/// "))
        assertEquals("ws://relay.example:8080", normalizedRelay("ws://relay.example:8080/"))
        assertNull(normalizedRelay("https://relay.example"))
        assertNull(normalizedRelay("not a relay"))
        assertNull(normalizedRelay("wss://localhost"))
        val group = RelayGroup.link(" relay.example'book-club ")!!
        assertEquals("wss://relay.example'book-club", group.id)
        assertNull(RelayGroup.link("relay.example'"))
    }
    @Test fun groupMetadataReadsAccessFlagsAndRequiresCorrectKindAndIdentifier() {
        val meta = event(39000, tags = listOf(listOf("d", "books"), listOf("name", "Book club"), listOf("about", "Reading"), listOf("private"), listOf("closed")))
        val group = RelayGroup.from(meta, "relay.example")!!
        assertEquals("Book club", group.displayName)
        assertEquals("Reading", group.about)
        assertTrue(group.isPrivate); assertTrue(group.isClosed)
        assertNull(RelayGroup.from(event(1, tags = listOf(listOf("d", "books"))), "relay.example"))
        assertNull(RelayGroup.from(event(39000), "relay.example"))
    }
    @Test fun communityCoordinatesPreserveColonsInIdentifier() {
        assertEquals(owner to "books:fiction", Community.parse("34550:$owner:books:fiction"))
        assertNull(Community.parse("30023:$owner:books"))
        assertNull(Community.parse("34550:invalid:books"))
        val community = Community.from(event(34550, tags = listOf(listOf("d", "books:fiction"), listOf("moderator", other), listOf("moderator", other), listOf("relay", "relay.example"), listOf("rules", "Be kind"))))!!
        assertEquals("34550:$owner:books:fiction", community.coordinate)
        assertEquals(listOf(owner, other), community.team)
        assertEquals(listOf("wss://relay.example"), community.relays)
        assertEquals("Be kind", community.rules)
        assertNull(Community.from(event(1)))
    }
    @Test fun channelMetadataCanOnlyBeChangedByCreatorForItsOwnRoot() {
        val original = PublicChannel.from(event(40, content = """{"name":"Original","about":"About","relays":["relay.example"]}"""))!!
        val root = listOf(listOf("e", "room", "", "root"))
        assertEquals(original, original.metadata(event(41, author = other, time = 30, content = """{"name":"Spoof"}""", tags = root)))
        assertEquals(original, original.metadata(event(41, time = 30, content = """{"name":"Other room"}""", tags = listOf(listOf("e", "another")))))
        val renamed = original.metadata(event(41, time = 20, content = """{"name":"Updated"}""", tags = root))
        assertEquals("Updated", renamed.name)
        assertEquals("About", renamed.about)
        assertEquals(listOf("wss://relay.example"), renamed.relays)
        assertEquals(renamed, renamed.metadata(event(41, time = 15, content = """{"name":"Stale"}""", tags = root)))
    }
    @Test fun channelRootPrefersExplicitRootOverReply() {
        assertEquals("root", channelRoot(event(42, tags = listOf(listOf("e", "reply"), listOf("e", "root", "", "root")))))
        assertEquals("legacy", channelRoot(event(42, tags = listOf(listOf("e", "legacy")))))
        assertNull(channelRoot(event(42)))
    }
    @Test fun communityPostsOnlyIncludeTopLevelModernAndLegacyEvents() {
        val coordinate = "34550:$owner:books"
        assertTrue(isCommunityPost(event(1111, tags = listOf(listOf("A", coordinate), listOf("k", "34550"))), coordinate))
        assertFalse(isCommunityPost(event(1111, tags = listOf(listOf("A", coordinate), listOf("k", "1111"))), coordinate))
        assertFalse(isCommunityPost(event(1111, tags = listOf(listOf("A", "34550:$other:other"), listOf("k", "34550"))), coordinate))
        assertTrue(isCommunityPost(event(1, tags = listOf(listOf("a", coordinate))), coordinate))
        assertFalse(isCommunityPost(event(1, tags = listOf(listOf("a", coordinate), listOf("e", "reply"))), coordinate))
    }
    @Test fun chatParsingDeduplicatesSortsAndRejectsBlankOrWrongKind() {
        val values = listOf(event(42, id = "b", time = 20), event(42, id = "a", time = 20), event(42, id = "first", time = 1), event(42, id = "b", time = 20), event(9), event(42, id = "blank", content = " \n "))
        assertEquals(listOf("first", "a", "b"), CommunityChatMessage.list(values, 42).map { it.id })
    }
    @Test fun marmotNamedTwoPersonGroupsKeepGroupIdentityAndAdminMembership() {
        fun group(name: String, members: List<String>) = MarmotGroup.from(JSONObject().put("id", "mls-id").put("nostrGroupId", "nostr-id").put("name", name).put("state", "active").put("members", JSONArray(members)).put("admins", JSONArray(listOf(owner))).put("relays", JSONArray(listOf("wss://relay.example"))))!!
        val named = group("Friends", listOf(owner, other))
        assertTrue(named.isGroupChat); assertTrue(named.isAdmin(owner)); assertFalse(named.isAdmin(other))
        assertNull(named.peer(owner)); assertEquals("group:mls-id", named.conversationKey(owner))
        assertNull(named.conversationKey("c".repeat(64)))
        val direct = group("", listOf(owner, other))
        assertFalse(direct.isGroupChat); assertEquals(other, direct.peer(owner)); assertEquals(other, direct.conversationKey(owner))
        assertTrue(group("", listOf(owner, other, "c".repeat(64))).isGroupChat)
    }
}
