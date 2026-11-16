package me.untreu.qiqstr

import me.untreu.qiqstr.data.services.MuteEntry
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.data.services.VoiceRecorder
import me.untreu.qiqstr.ui.compose.ComposeDraftMedia
import me.untreu.qiqstr.ui.compose.ComposeDraftPoll
import me.untreu.qiqstr.ui.compose.ComposePublisher
import me.untreu.qiqstr.ui.compose.MediaUploadService
import me.untreu.qiqstr.ui.note.NoteAudioItem
import me.untreu.qiqstr.ui.note.NoteImeta
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaPortTest {
    private val hash = "885ed00726ced0fdb4240fc31c87b354d4cc7e513b90d56cc37e99e673a88932"

    @Test
    fun uploadUrlGetsExtensionForItsMimeType() {
        assertEquals("https://blossom.band/$hash.m4a", MediaUploadService.withExtension("https://blossom.band/$hash", "audio/mp4"))
        assertEquals("https://blossom.band/$hash.jpg", MediaUploadService.withExtension("https://blossom.band/$hash", "image/jpeg"))
        assertEquals("https://host.example/a/$hash.mov?x=1#f", MediaUploadService.withExtension("https://host.example/a/$hash?x=1#f", "video/quicktime"))
    }

    @Test
    fun uploadUrlWithExtensionOrUnknownMimeIsKept() {
        assertEquals("https://blossom.primal.net/$hash.png", MediaUploadService.withExtension("https://blossom.primal.net/$hash.png", "image/jpeg"))
        assertEquals("https://blossom.band/$hash", MediaUploadService.withExtension("https://blossom.band/$hash", "application/pdf"))
        assertEquals("https://blossom.band/dir/", MediaUploadService.withExtension("https://blossom.band/dir/", "image/png"))
        assertEquals("https://blossom.band", MediaUploadService.withExtension("https://blossom.band", "image/png"))
    }

    @Test
    fun voiceMessageImetaCarriesDurationAndWaveform() {
        val media = ComposeDraftMedia("https://nostr.download/$hash.m4a", hash, "audio/mp4", 4096, null, null, null, "", false, 12.4, listOf(0, 37, 100))
        assertTrue(media.isAudio)
        assertEquals(
            listOf("imeta", "url https://nostr.download/$hash.m4a", "m audio/mp4", "x $hash", "duration 12", "waveform 0 37 100"),
            ComposePublisher.imeta(media),
        )
    }

    @Test
    fun imageImetaKeepsDimensionsBlurhashAndAlt() {
        val media = ComposeDraftMedia("https://a.example/b.gif", "", "image/gif", 0, 480.0, 270.0, "LKO2?U%2Tw=w", " a cat ", false)
        assertFalse(media.isAudio)
        assertEquals(
            listOf("imeta", "url https://a.example/b.gif", "m image/gif", "dim 480x270", "blurhash LKO2?U%2Tw=w", "alt a cat"),
            ComposePublisher.imeta(media),
        )
    }

    @Test
    fun imetaParsesAudioFields() {
        val meta = NoteImeta.from(listOf("imeta", "url https://nostr.download/$hash.m4a", "m audio/mp4", "duration 12", "waveform 0 37 100"))!!
        assertEquals("audio/mp4", meta.mimeType)
        assertEquals(12.0, meta.duration!!, 0.0)
        assertEquals(listOf(0, 37, 100), meta.waveform)
        assertTrue(NoteAudioItem.isAudio(meta.url, meta.mimeType))
        assertFalse(NoteAudioItem.isAudio("https://a.example/b.m4a", "video/mp4"))
        val plain = NoteImeta.from(listOf("imeta", "url https://a.example/b.jpg", "m image/jpeg"))!!
        assertNull(plain.duration)
        assertTrue(plain.waveform.isEmpty())
    }

    @Test
    fun waveformIsBucketedToPeaks() {
        assertTrue(VoiceRecorder.waveform(emptyList()).isEmpty())
        assertEquals(listOf(10, 50, 100), VoiceRecorder.waveform(listOf(0.1f, 0.5f, 1f)))
        val levels = List(480) { index -> if (index % 10 == 9) 0.8f else 0.2f }
        val bars = VoiceRecorder.waveform(levels)
        assertEquals(VoiceRecorder.WAVEFORM_BARS, bars.size)
        assertTrue(bars.all { it == 80 })
        assertEquals(33, VoiceRecorder.waveform(List(97) { 0.5f }).size)
    }

    @Test
    fun durationsFormatAsMinutesAndSeconds() {
        assertEquals("0:00", VoiceRecorder.format(0.0))
        assertEquals("0:10", VoiceRecorder.format(9.6))
        assertEquals("5:00", VoiceRecorder.format(300.0))
        assertEquals("0:00", VoiceRecorder.format(Double.NaN))
    }

    @Test
    fun pollOptionsAreTrimmedAndDeduplicated() {
        assertEquals(listOf("Yes", "No"), ComposePublisher.pollOptions(ComposeDraftPoll(listOf(" Yes ", "", "yes", "No"), false, null)))
    }

    @Test
    fun muteEntriesNormalizeHashtagsAndWords() {
        assertEquals("nostr", MuteService.normalizedHashtag("  #Nostr "))
        assertEquals("", MuteService.normalizedHashtag(" # "))
        assertEquals(MuteEntry.HASHTAG, MuteEntry.from("t"))
        assertEquals(MuteEntry.THREAD, MuteEntry.from("e"))
        assertNull(MuteEntry.from("a"))
        assertEquals("bitcoin", MuteEntry.HASHTAG.normalized("Bitcoin"))
        assertEquals("ABCdef", MuteEntry.THREAD.normalized("ABCdef"))
    }
}
