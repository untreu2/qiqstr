package me.untreu.qiqstr.ui.feed

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import me.untreu.qiqstr.App
import me.untreu.qiqstr.data.services.BookmarkService
import me.untreu.qiqstr.data.services.HashtagFollowService
import me.untreu.qiqstr.data.services.PinnedNotesService
import me.untreu.qiqstr.data.services.PollService
import me.untreu.qiqstr.data.sync.FeatureHooks
import me.untreu.qiqstr.data.sync.SessionHooks
import me.untreu.qiqstr.ui.note.NoteInteractionStore

object NotesFeature : FeatureHooks {
    override fun register() {
        SessionHooks.onTeardown {
            BookmarkService.reset()
            PinnedNotesService.reset()
            HashtagFollowService.reset()
            PollService.reset()
        }
        SessionHooks.onBootstrap { pubkey ->
            NoteInteractionStore.prepareForAccount()
            App.scope.launch { HashtagFollowService.load() }
            coroutineScope {
                val bookmarks = async { BookmarkService.load() }
                val pinned = async { PinnedNotesService.load(pubkey) }
                bookmarks.await()
                pinned.await()
            }
        }
    }
}
