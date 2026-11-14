package me.untreu.qiqstr.ui.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.PrimaryButton
import me.untreu.qiqstr.core.components.TextAction
import me.untreu.qiqstr.data.services.FollowService
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService

class SuggestedFollowsViewModel(
    initialInterests: Set<FollowInterest>,
    val minimumSelection: Int,
    private val preselectsFallback: Boolean,
) : ViewModel() {
    var interests by mutableStateOf(initialInterests)
        private set
    var packs by mutableStateOf<List<FollowPack>>(emptyList())
        private set
    var selected by mutableStateOf<Set<String>>(emptySet())
        private set
    var expanded by mutableStateOf<Set<String>>(emptySet())
        private set
    var isProcessing by mutableStateOf(false)
        private set
    var followedCount by mutableIntStateOf(0)
        private set
    var failureCount by mutableIntStateOf(0)
        private set
    var isRefreshing by mutableStateOf(false)
        private set
    private var deadlinePassed by mutableStateOf(false)
    private val requestedProfiles = HashSet<String>()
    private var didPreselectFallback = false

    val showsSkeleton: Boolean get() = packs.isEmpty() && !deadlinePassed && !FollowPackService.hasLoaded
    val canContinue: Boolean get() = selected.size >= minimumSelection && !isProcessing
    val remaining: Int get() = maxOf(minimumSelection - selected.size, 0)
    private val me: String? get() = Session.pubkey

    fun load() {
        viewModelScope.launch {
            FollowPackService.prefetch()
            FollowService.refresh()
            refreshPacks()
            val deadline = async {
                delay(DEADLINE)
                deadlinePassed = true
                refreshPacks()
            }
            val loaded = async { FollowPackService.waitUntilLoaded() }
            deadline.await()
            loaded.await()
            refreshPacks()
        }
    }

    fun reload() {
        viewModelScope.launch {
            isRefreshing = true
            FollowPackService.reload()
            refreshPacks()
            isRefreshing = false
        }
    }

    fun refreshPacks() {
        val ranked = FollowPackService.ranked(interests).take(MAXIMUM_PACKS)
        if (ranked.isEmpty() && !deadlinePassed && !FollowPackService.hasLoaded) {
            packs = emptyList()
            return
        }
        val fallback = fallbackPack()
        packs = ranked + fallback
        if (ranked.isEmpty()) preselectFallback(fallback)
        if (!isProcessing) selected = selected.filter { !FollowService.isFollowing(it) }.toSet()
        loadProfiles(packs.flatMap { it.members.take(5) })
        expanded.mapNotNull { id -> packs.firstOrNull { it.id == id } }.forEach { loadProfiles(it.members) }
    }

    private fun fallbackPack() = FollowPack(
        id = "qiqstr:suggested",
        kind = 0,
        author = "",
        title = L("authPackSuggestedTitle"),
        summary = L("authPackSuggestedSubtitle"),
        image = "",
        members = SuggestedUsers.pubkeys.filter { it != me },
        topics = emptyList(),
        createdAt = 0,
    )

    private fun preselectFallback(fallback: FollowPack) {
        if (!preselectsFallback || didPreselectFallback || selected.isNotEmpty()) return
        didPreselectFallback = true
        selected = candidates(fallback).toSet()
    }

    private fun loadProfiles(pubkeys: List<String>) {
        val wanted = (pubkeys.toSet() - requestedProfiles).take(150)
        if (wanted.isEmpty()) return
        requestedProfiles.addAll(wanted)
        viewModelScope.launch {
            ProfileCache.load(wanted, fetchMissing = false)
            val missing = wanted.filter { ProfileCache.profile(it) == null }
            if (missing.isEmpty()) return@launch
            SyncService.syncProfiles(missing)
            ProfileCache.load(missing, fetchMissing = false)
        }
    }

    fun toggleInterest(interest: FollowInterest) {
        interests = if (interest in interests) interests - interest else interests + interest
        FollowInterest.saved = interests
        refreshPacks()
    }

    fun candidates(pack: FollowPack): List<String> = pack.members.filter { it != me && !FollowService.isFollowing(it) }

    fun isPackSelected(pack: FollowPack): Boolean {
        val candidates = candidates(pack)
        return candidates.isNotEmpty() && selected.containsAll(candidates)
    }

    fun togglePack(pack: FollowPack) {
        if (isProcessing) return
        val candidates = candidates(pack)
        selected = if (selected.containsAll(candidates)) selected - candidates.toSet() else selected + candidates
    }

    fun toggle(pubkey: String) {
        if (isProcessing || FollowService.isFollowing(pubkey)) return
        selected = if (pubkey in selected) selected - pubkey else selected + pubkey
    }

    fun isExpanded(pack: FollowPack) = pack.id in expanded

    fun setExpanded(pack: FollowPack, value: Boolean) {
        if (value) {
            expanded = expanded + pack.id
            loadProfiles(pack.members)
        } else {
            expanded = expanded - pack.id
        }
    }

    fun followSelected(onSuccess: () -> Unit) {
        if (!canContinue) return
        isProcessing = true
        val targets = selected.toList()
        viewModelScope.launch {
            try {
                FollowService.followMany(targets)
                followedCount += 1
                ToastCenter.show(L("authFollowedPeople", "count" to targets.size), ToastStyle.SUCCESS)
                selected = emptySet()
                onSuccess()
            } catch (error: Throwable) {
                failureCount += 1
                ToastCenter.error(error)
            } finally {
                isProcessing = false
            }
        }
    }

    companion object {
        const val MAXIMUM_PACKS = 12
        const val DEADLINE = 4_000L
    }
}

@Composable
fun SuggestedFollowsScreen(onFinish: (() -> Unit)? = null) {
    SuggestedFollowsContent(emptySet(), onFinish)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SuggestedFollowsContent(interests: Set<FollowInterest>, onFinish: (() -> Unit)?, onBack: (() -> Unit)? = null) {
    val isOnboarding = onFinish != null
    val model: SuggestedFollowsViewModel = viewModel {
        SuggestedFollowsViewModel(
            initialInterests = interests.ifEmpty { FollowInterest.saved },
            minimumSelection = if (isOnboarding) 3 else 1,
            preselectsFallback = isOnboarding,
        )
    }
    val haptics = rememberHaptics()
    LaunchedEffect(Unit) { model.load() }
    LaunchedEffect(FollowPackService.packs, FollowService.following) { model.refreshPacks() }
    LaunchedEffect(model.followedCount) { if (model.followedCount > 0) haptics.success() }
    LaunchedEffect(model.failureCount) { if (model.failureCount > 0) haptics.error() }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val continueTitle = if (isOnboarding) {
        if (model.remaining > 0) L("authSelectMore", "count" to model.remaining) else L("authFollowAndContinue", "count" to model.selected.size)
    } else {
        if (model.selected.isEmpty()) L("follow") else L("authFollowSelected", "count" to model.selected.size)
    }
    val finish = { onFinish?.invoke() ?: Router.pop(); Unit }

    Scaffold(
        containerColor = AppColors.background,
        modifier = if (isOnboarding) Modifier else Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            if (isOnboarding) {
                CenterAlignedTopAppBar(
                    title = { OnboardingStepIndicator(4) },
                    navigationIcon = {
                        if (onBack != null) IconButton(onClick = onBack, enabled = !model.isProcessing) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) }
                    },
                    actions = {
                        Box(Modifier.testTag("suggested-skip")) { TextAction(L("skip"), { onFinish?.invoke() }, enabled = !model.isProcessing) }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = AppColors.background),
                )
            } else {
                LargeTopAppBar(
                    title = { Text(L("suggestedFollows")) },
                    navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                    scrollBehavior = scrollBehavior,
                    colors = TopAppBarDefaults.largeTopAppBarColors(containerColor = AppColors.background),
                )
            }
        },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).navigationBarsPadding().padding(horizontal = 24.dp, vertical = 8.dp)) {
                PrimaryButton(continueTitle, { model.followSelected(finish) }, Modifier.fillMaxWidth().testTag("suggested-continue"), enabled = model.canContinue, loading = model.isProcessing)
            }
        },
    ) { padding ->
        PullToRefreshBox(isRefreshing = model.isRefreshing, onRefresh = { model.reload() }, modifier = Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(
                Modifier.fillMaxSize().testTag("suggested-list"),
                contentPadding = PaddingValues(bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item("header") {
                    Box(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                        if (isOnboarding) {
                            AuthHeader(L("authPacksTitle"), L("authPacksSubtitle"))
                        } else {
                            Text(L("authSuggestedBrowseSubtitle"), style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
                        }
                    }
                }
                item("interests") {
                    val ordered = FollowInterest.entries.filter { it in model.interests } + FollowInterest.entries.filter { it !in model.interests }
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.testTag("suggested-interests"),
                    ) {
                        items(ordered, key = { it.raw }) { interest ->
                            InterestChip(interest, interest in model.interests, compact = true, modifier = Modifier.animateItem()) {
                                haptics.selection()
                                model.toggleInterest(interest)
                            }
                        }
                    }
                }
                if (model.showsSkeleton) {
                    items(3) {
                        PackCard(Modifier.testTag("suggested-loading")) { FollowPackSkeleton() }
                    }
                } else {
                    items(model.packs, key = { it.id }) { pack ->
                        PackCard(Modifier.animateItem()) { PackSection(model, pack, haptics) }
                    }
                }
            }
        }
    }
}

@Composable
private fun PackCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(22.dp),
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp),
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) { content() }
    }
}

@Composable
private fun PackSection(model: SuggestedFollowsViewModel, pack: FollowPack, haptics: Haptics) {
    val expanded = model.isExpanded(pack)
    FollowPackHeader(pack, model.isPackSelected(pack), model.isProcessing || model.candidates(pack).isEmpty()) {
        haptics.selection()
        model.togglePack(pack)
    }
    HorizontalDivider(color = AppColors.divider)
    val rotation by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
    Row(
        Modifier.fillMaxWidth().clickableRow { model.setExpanded(pack, !expanded) }.padding(vertical = 12.dp).testTag("pack-expand"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            L("authPackPeople", "count" to pack.members.count { it in model.selected }),
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
            modifier = Modifier.weight(1f),
        )
        Icon(Icons.Filled.ExpandMore, null, Modifier.rotate(rotation), tint = AppColors.textSecondary)
    }
    AnimatedVisibility(expanded) {
        Column {
            pack.members.forEach { pubkey ->
                FollowPackMemberRow(
                    pubkey = pubkey,
                    isSelected = pubkey in model.selected,
                    alreadyFollowing = FollowService.isFollowing(pubkey),
                    enabled = !model.isProcessing,
                ) {
                    haptics.selection()
                    model.toggle(pubkey)
                }
            }
        }
    }
}
