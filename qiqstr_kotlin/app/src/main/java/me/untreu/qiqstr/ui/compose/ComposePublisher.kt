package me.untreu.qiqstr.ui.compose

import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.data.services.InteractionService
import me.untreu.qiqstr.data.services.SearchService
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Note
import me.untreu.qiqstr.ui.note.NoteInteractionStore
import me.untreu.qiqstr.ui.note.NoteRepository

object ComposePublisher {
    suspend fun publish(draft: ComposeDraft) {
        if (SearchService.containsSecret(draft.text)) throw CoreError(L("composeSecretBlocked"))
        val urls = draft.media.map { it.url }
        val extraTags = draft.media.map(::imeta).toMutableList()
        if (draft.contentWarningEnabled) {
            val reason = draft.contentWarningReason.trim()
            extraTags.add(if (reason.isEmpty()) listOf("content-warning") else listOf("content-warning", reason))
        }
        val content = finalContent(draft)
        for ((code, url) in draft.emojis.toSortedMap()) if (content.contains(":$code:")) extraTags.add(listOf("emoji", code, url))
        when (draft.kind) {
            ComposeDraft.Kind.NEW_NOTE -> {
                val poll = draft.poll
                val goal = draft.goal
                if (goal != null) {
                    if (goal.amountSats <= 0) throw CoreError(L("enterValidAmount"))
                    InteractionService.publishGoal(content, goal.amountSats, goal.closesAt, urls, extraTags)
                } else if (poll != null) {
                    val options = pollOptions(poll)
                    if (options.size < 2) throw CoreError(L("feedPollNeedsOptions"))
                    InteractionService.publishPoll(content, options, poll.multiple, poll.endsAt, urls, extraTags)
                } else {
                    InteractionService.publishNote(content, urls, extraTags)
                }
            }
            ComposeDraft.Kind.REPLY -> {
                val note = target(draft)
                InteractionService.publishReply(note, content, urls, extraTags)
                NoteInteractionStore.markReplied(note.id)
            }
            ComposeDraft.Kind.QUOTE -> InteractionService.publishQuote(target(draft), content, urls, extraTags)
        }
        DataBus.feedChanged()
    }

    fun pollOptions(poll: ComposeDraftPoll): List<String> {
        val seen = HashSet<String>()
        return poll.options.map { it.trim() }.filter { it.isNotEmpty() && seen.add(it.lowercase()) }
    }

    private suspend fun target(draft: ComposeDraft): Note {
        val account = Session.pubkey
        val note = draft.targetId?.let { NoteRepository.ensureNote(it) }
        if (note == null || Session.pubkey != account) throw CoreError(L("eventNotFound"))
        return note
    }

    private fun finalContent(draft: ComposeDraft): String {
        var content = draft.text
        for (key in draft.mentions.keys.sortedByDescending { it.length }) {
            draft.mentions[key]?.let { content = content.replace(key, it) }
        }
        return content.trim()
    }

    fun imeta(item: ComposeDraftMedia): List<String> {
        val tag = mutableListOf("imeta", "url ${item.url}", "m ${item.mimeType}")
        if (item.sha256.isNotEmpty()) tag.add("x ${item.sha256}")
        if (item.width != null && item.height != null) tag.add("dim ${item.width.toInt()}x${item.height.toInt()}")
        item.blurhash?.let { tag.add("blurhash $it") }
        val alt = item.altText.trim()
        if (alt.isNotEmpty()) tag.add("alt $alt")
        if (item.duration != null && item.duration > 0) tag.add("duration ${Math.round(item.duration)}")
        if (!item.waveform.isNullOrEmpty()) tag.add("waveform ${item.waveform.joinToString(" ")}")
        return tag
    }
}
