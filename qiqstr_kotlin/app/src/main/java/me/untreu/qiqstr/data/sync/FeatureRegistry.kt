package me.untreu.qiqstr.data.sync

import me.untreu.qiqstr.ui.articles.ArticlesFeature
import me.untreu.qiqstr.ui.auth.AuthFeature
import me.untreu.qiqstr.ui.compose.ComposeFeature
import me.untreu.qiqstr.ui.dm.DMFeature
import me.untreu.qiqstr.ui.explore.ExploreFeature
import me.untreu.qiqstr.ui.feed.NotesFeature
import me.untreu.qiqstr.ui.profile.ProfileFeature
import me.untreu.qiqstr.ui.wallet.WalletFeature

object FeatureRegistry {
    val all: List<FeatureHooks> = listOf(ProfileFeature, NotesFeature, ComposeFeature, ExploreFeature, ArticlesFeature, AuthFeature, DMFeature, WalletFeature)
}
