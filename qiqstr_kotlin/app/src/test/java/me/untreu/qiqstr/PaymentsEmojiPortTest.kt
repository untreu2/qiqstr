package me.untreu.qiqstr

import me.untreu.qiqstr.data.services.CashuMint
import me.untreu.qiqstr.data.services.CustomEmoji
import me.untreu.qiqstr.data.services.EmojiChoice
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.ZapGoal
import me.untreu.qiqstr.ui.wallet.ZapSplit
import org.junit.Assert.*
import org.junit.Test

class PaymentsEmojiPortTest {
    private val a = "a".repeat(64)
    private val b = "b".repeat(64)
    private val c = "c".repeat(64)

    @Test
    fun splitAmountsPreserveSatsAndGiveRemainderToLargestWeight() {
        val splits = ZapSplit.parse(listOf(listOf("zap", a, "", "1"), listOf("zap", b, "", "3"), listOf("zap", c, "", "2")))
        assertEquals(listOf(a to 1L, b to 6L, c to 3L), ZapSplit.shares(10, splits))
        assertEquals(listOf(b to 1L), ZapSplit.shares(1, splits))
        assertEquals(13, ZapSplit.percent(ZapSplit(a, 1.0), listOf(ZapSplit(a, 1.0), ZapSplit(b, 7.0))))
        for (amount in 1L..100L) assertEquals(amount, ZapSplit.shares(amount, splits).sumOf { it.second })
    }

    @Test
    fun unweightedAndInvalidSplitTagsMatchSwiftRules() {
        assertEquals(listOf(a to 3L, b to 2L), ZapSplit.shares(5, ZapSplit.parse(listOf(listOf("zap", a), listOf("zap", b), listOf("zap", a)))))
        val tags = listOf(listOf("zap", a), listOf("zap", b, "", "2"), listOf("zap", c, "", "NaN"), listOf("zap", a, "", "-1"))
        assertEquals(listOf(ZapSplit(b, 2.0)), ZapSplit.parse(tags))
        assertTrue(ZapSplit.shares(0, ZapSplit.parse(tags)).isEmpty())
    }

    @Test
    fun customEmojiRequireSafeShortcodesAndHttpsAndKeepFirstTag() {
        val first = listOf("emoji", "test_emoji-1", "https://example.com/a.png")
        val second = listOf("emoji", "test_emoji-1", "https://example.com/b.png")
        assertEquals(mapOf("test_emoji-1" to first[2]), CustomEmoji.map(listOf(first, second)))
        assertNull(CustomEmoji.from(listOf("emoji", "bad:code", first[2])))
        assertNull(CustomEmoji.from(listOf("emoji", "valid", "http://example.com/a.png")))
        assertNull(CustomEmoji.from(listOf("emoji", "é", first[2])))
        assertEquals("test_emoji-1", CustomEmoji.shortcode(" :test_emoji-1: "))
        val choice = EmojiChoice.Custom(CustomEmoji("test", first[2]))
        assertEquals(choice, EmojiChoice.from(choice.stored))
        assertEquals(EmojiChoice.Unicode("🫂"), EmojiChoice.from("🫂"))
    }

    @Test
    fun goalsReadMsatsAndRequireKind9041() {
        val note = Note("id", a, "Goal", 0, listOf(listOf("amount", "21000"), listOf("closed_at", "1")), kind = 9041)
        val goal = ZapGoal.from(note)!!
        assertEquals(21L, goal.targetSats)
        assertTrue(goal.isClosed)
        assertNull(ZapGoal.from(note.copy(kind = 1)))
        assertNull(ZapGoal.from(note.copy(tags = listOf(listOf("amount", "999")))))
    }

    @Test
    fun mintNormalizationPreservesCaseSensitivePathsAndRejectsNonHttps() {
        assertEquals("https://mint.minibits.cash/Bitcoin", CashuMint.normalized(" mint.minibits.cash/Bitcoin/ "))
        assertTrue(CashuMint.isValid("mint.example.com"))
        assertFalse(CashuMint.isValid("http://mint.example.com"))
        assertFalse(CashuMint.isValid("https://mint.example.com/a b"))
        assertEquals("mint.minibits.cash/Bitcoin", CashuMint.displayName(CashuMint.presets[0]))
    }
}
