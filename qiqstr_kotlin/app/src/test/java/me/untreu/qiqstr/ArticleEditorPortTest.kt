package me.untreu.qiqstr

import me.untreu.qiqstr.ui.articles.*
import org.junit.Assert.*
import org.junit.Test

class ArticleEditorPortTest {
    @Test fun formattingWrapsSelectionAndPlacesEmptyCaretInsideMarkers() {
        assertEquals(MarkdownEdit("**hello** world", 9), MarkdownEdit.apply(MarkdownStyle.BOLD, "hello world", 0, 5))
        assertEquals(MarkdownEdit("****", 2), MarkdownEdit.apply(MarkdownStyle.BOLD, "", 0))
        assertEquals(MarkdownEdit("*hello*", 7), MarkdownEdit.apply(MarkdownStyle.ITALIC, "hello", 5, 0))
        assertEquals(MarkdownEdit("a ``", 3), MarkdownEdit.apply(MarkdownStyle.CODE, "a ", 2))
    }
    @Test fun lineFormattingTogglesAtCurrentLineStart() {
        val heading = MarkdownEdit.apply(MarkdownStyle.HEADING, "first\nsecond", 8)
        assertEquals(MarkdownEdit("first\n## second", 11), heading)
        assertEquals(MarkdownEdit("first\nsecond", 8), MarkdownEdit.apply(MarkdownStyle.HEADING, heading.text, heading.caret))
        assertEquals(MarkdownEdit("> quote", 2), MarkdownEdit.apply(MarkdownStyle.QUOTE, "quote", 0))
        assertEquals(MarkdownEdit("- item", 2), MarkdownEdit.apply(MarkdownStyle.BULLET, "item", 0))
        assertEquals(MarkdownEdit("1. item", 3), MarkdownEdit.apply(MarkdownStyle.NUMBERED, "item", 0))
    }
    @Test fun linkInsertionPutsCaretInMissingLabelOrUrl() {
        assertEquals(MarkdownEdit("[](https://example.com)", 1), MarkdownEdit.apply(MarkdownStyle.LINK, "https://example.com", 0, 19))
        assertEquals(MarkdownEdit("[label](https://)", 16), MarkdownEdit.apply(MarkdownStyle.LINK, "label", 0, 5))
        assertEquals(MarkdownEdit("[](https://)", 1), MarkdownEdit.apply(MarkdownStyle.LINK, "", 0))
    }
    @Test fun inlineImagesMaintainParagraphSpacingAndReplaceSelection() {
        assertEquals(MarkdownEdit("text\n\n![](url)\n\n", 16), MarkdownEdit.image("url", "text", 4))
        assertEquals("text\n\n![](url)\n\n", MarkdownEdit.image("url", "text\n", 5).text)
        assertEquals("text\n\n![](url)\n\n", MarkdownEdit.image("url", "text\n\n", 6).text)
        assertEquals("![](url)\n\n", MarkdownEdit.image("url", "replace me", 0, 10).text)
    }
    @Test fun editingUsesUtf16SelectionWithoutBreakingEmoji() {
        assertEquals(MarkdownEdit("🙂 **hello**", 12), MarkdownEdit.apply(MarkdownStyle.BOLD, "🙂 hello", 3, 8))
    }
    @Test fun slugFoldsDiacriticsCapsAndPunctuationAndHasFixedSuffix() {
        assertEquals("my-first-article-abc123", ArticleIdentifier.make("  My first article! ", "abc123"))
        assertEquals("cafe-uber-istanbul-abc123", ArticleIdentifier.make("Café über İstanbul", "abc123"))
        assertEquals("abc123", ArticleIdentifier.make("😎 日本語", "abc123"))
        val slug = ArticleIdentifier.make("a".repeat(80), "abc123")
        assertEquals("a".repeat(48) + "-abc123", slug)
        assertTrue(ArticleIdentifier.make("Hello").matches(Regex("hello-[0-9a-f]{6}")))
    }
    @Test fun hashtagsAreTrimmedLowercasedAndDeduplicated() {
        assertEquals(listOf("nostr", "bitcoin", "writing"), ArticleIdentifier.hashtags("nostr, #Bitcoin writing NOSTR, ##bitcoin##"))
        assertTrue(ArticleIdentifier.hashtags(" , ##  ").isEmpty())
    }
    @Test fun draftsRequireTitleAndTextAndDetectBlankFields() {
        assertTrue(ArticleDraft(updatedAt = 1).isBlank)
        assertFalse(ArticleDraft(title = "Title", updatedAt = 1).canPublish)
        assertTrue(ArticleDraft(title = "Title", content = "Content", updatedAt = 1).canPublish)
        val edit = ArticleDraft(dTag = "fixed", publishedAt = 123, title = "Changed", content = "a b\nc", updatedAt = 1)
        assertEquals(3, edit.wordCount); assertTrue(edit.isEditingPublished); assertEquals("fixed", edit.dTag)
    }
}
