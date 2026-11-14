package me.untreu.qiqstr.ui.articles

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FindInPage
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.Highlight
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import java.text.DateFormat
import java.util.Date
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.Route
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.components.EmptyStateView
import me.untreu.qiqstr.core.components.LoadingView
import me.untreu.qiqstr.core.components.ProfileAvatar
import me.untreu.qiqstr.core.components.RemoteImage
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.domain.Article
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.data.services.MuteService
import me.untreu.qiqstr.ui.note.ReportSheet
import me.untreu.qiqstr.ui.note.ReportTarget

private val readableWidth = 720.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArticleDetailScreen(articleId: String? = null, naddr: String? = null) {
    val model: ArticleDetailViewModel = viewModel()
    val scope = rememberCoroutineScope()
    var progress by remember { mutableFloatStateOf(0f) }
    var restored by remember { mutableStateOf(false) }
    var showHighlights by remember { mutableStateOf(false) }
    var highlightDraft by remember { mutableStateOf<HighlightDraft?>(null) }
    var scrollTarget by remember { mutableStateOf<Int?>(null) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    LaunchedEffect(articleId, naddr) { model.load(articleId, naddr) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) ReadingProgressStore.persist() }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            ReadingProgressStore.persist()
        }
    }

    Scaffold(
        containerColor = AppColors.background,
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        Column {
                            Text(L("article"), maxLines = 1)
                            val article = model.article
                            if (article != null && model.phase == ArticlePhase.LOADED && restored) {
                                val timeLeft = if (progress >= ReadingProgressStore.FINISH_THRESHOLD) L("articleFinished")
                                else L("articleMinutesLeft", "count" to maxOf(1, ceil(article.readingMinutes * (1 - progress)).toInt()))
                                Text(timeLeft, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary, maxLines = 1)
                            }
                        }
                    },
                    navigationIcon = { IconButton(onClick = { Router.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("back")) } },
                    actions = { model.article?.let { ArticleToolbar(it, model) { showHighlights = true } } },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.background),
                )
                if (model.phase == ArticlePhase.LOADED) {
                    val percent = L("articlePercentRead", "percent" to (progress * 100).roundToInt())
                    val label = L("articleReadingProgress")
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .alpha(if (restored) 1f else 0f)
                            .semantics {
                                contentDescription = label
                                stateDescription = percent
                            }
                            .testTag("article-progress"),
                        color = AppColors.textPrimary,
                        trackColor = AppColors.tile,
                        gapSize = 0.dp,
                        drawStopIndicator = {},
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (model.phase) {
                ArticlePhase.LOADING -> LoadingView()
                ArticlePhase.FETCHING -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator(color = AppColors.textSecondary)
                    Text(L("exploreFetchingArticle"), Modifier.padding(top = 12.dp), color = AppColors.textSecondary)
                }
                ArticlePhase.MISSING -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    EmptyStateView(icon = Icons.Outlined.FindInPage, title = L("articleNotFound"), actionTitle = L("retry")) {
                        scope.launch { model.load(articleId, naddr) }
                    }
                }
                ArticlePhase.LOADED -> model.article?.let { article ->
                    ArticleContent(
                        article = article,
                        model = model,
                        scrollTarget = scrollTarget,
                        onScrollTargetHandled = { scrollTarget = null },
                        onRefresh = { model.load(articleId, naddr) },
                        onProgress = { value, didRestore -> progress = value; restored = didRestore },
                        highlighting = MarkdownHighlighting(
                            passages = model.highlights.map { it.content },
                            onHighlight = { highlightDraft = HighlightDraft(it) },
                            onShowHighlights = { showHighlights = true },
                        ),
                        onShowHighlights = { showHighlights = true },
                    )
                }
            }
        }
    }

    highlightDraft?.let { draft ->
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { highlightDraft = null }, sheetState = state, containerColor = AppColors.background) {
            HighlightComposerSheet(draft, onDismiss = { highlightDraft = null }) { text, comment ->
                model.publishHighlight(text, draft.passage, comment)
            }
        }
    }
    if (showHighlights) {
        ModalBottomSheet(onDismissRequest = { showHighlights = false }, containerColor = AppColors.background) {
            HighlightsSheet(model.highlights, model.isLoadingHighlights, onDismiss = { showHighlights = false }) { highlight ->
                model.blockIndex(highlight)?.let { scrollTarget = it }
            }
        }
    }
}

@Composable
private fun ArticleToolbar(article: Article, model: ArticleDetailViewModel, onShowHighlights: () -> Unit) {
    var settings by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    var reportTarget by remember { mutableStateOf<ReportTarget?>(null) }
    reportTarget?.let { target ->
        ReportSheet(target, onDismiss = { reportTarget = null }) { finished ->
            if (MuteService.isMuted(finished.pubkey)) Router.pop()
        }
    }
    val haptics = LocalHapticFeedback.current
    fun copy(text: String) {
        ArticleActions.copy(text)
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    Box {
        IconButton(onClick = { settings = true }, modifier = Modifier.testTag("article-reader-settings")) {
            Icon(Icons.Outlined.FormatSize, L("readerSettings"))
        }
        DropdownMenu(expanded = settings, onDismissRequest = { settings = false }) { ReaderSettingsPanel() }
    }
    article.naddr?.let { naddr ->
        IconButton(onClick = { ArticleActions.share("nostr:$naddr") }, modifier = Modifier.testTag("article-share")) {
            Icon(Icons.Outlined.Share, L("share"))
        }
    }
    Box {
        IconButton(onClick = { more = true }, modifier = Modifier.testTag("article-more")) {
            Icon(Icons.Outlined.MoreVert, L("exploreMoreOptions"))
        }
        DropdownMenu(expanded = more, onDismissRequest = { more = false }) {
            val highlightsTitle = if (model.highlights.isEmpty()) L("highlightsTitle") else L("highlightsCount", "count" to model.highlights.size)
            MenuItem(highlightsTitle, Icons.Outlined.Highlight) { more = false; onShowHighlights() }
            article.naddr?.let { naddr ->
                MenuItem(L("exploreCopyArticleLink"), Icons.Outlined.Link) { more = false; copy("nostr:$naddr") }
            }
            MenuItem(L("exploreCopyMarkdown"), Icons.Outlined.ContentCopy) { more = false; copy(article.content) }
            article.shareURL?.let { url ->
                MenuItem(L("exploreOpenInBrowser"), Icons.Outlined.OpenInBrowser) { more = false; Router.openUrl(url) }
            }
            HorizontalDivider()
            MenuItem(L("exploreViewAuthor"), Icons.Outlined.AccountCircle) { more = false; Router.push(Route.Profile(article.pubkey)) }
            if (article.pubkey != Session.pubkey) {
                HorizontalDivider()
                MenuItem(L("feedMuteAuthor"), Icons.Outlined.VolumeOff, destructive = true, tag = "article-mute-author") {
                    more = false
                    ArticleActions.mute(article.pubkey) { Router.pop() }
                }
                MenuItem(L("report"), Icons.Outlined.Flag, destructive = true, tag = "article-report") {
                    more = false
                    reportTarget = ReportTarget(article.pubkey, article.id, name = article.authorName)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun ArticleContent(
    article: Article,
    model: ArticleDetailViewModel,
    scrollTarget: Int?,
    onScrollTargetHandled: () -> Unit,
    onRefresh: suspend () -> Unit,
    onProgress: (Float, Boolean) -> Unit,
    highlighting: MarkdownHighlighting,
    onShowHighlights: () -> Unit,
) {
    val scroll = rememberScrollState()
    val anchors = remember { MarkdownAnchors() }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(article.progressKey) {
        var restored = false
        var restoring = false
        snapshotFlow { scroll.value to scroll.maxValue }.collect { (offset, max) ->
            if (restoring || max == Int.MAX_VALUE) return@collect
            val progress = if (max <= 1) 1f else (offset.toFloat() / max).coerceIn(0f, 1f)
            if (!restored) {
                restored = true
                val saved = ReadingProgressStore.progress(article)
                if (max > 0 && saved != null && saved >= ReadingProgressStore.START_THRESHOLD && saved < ReadingProgressStore.FINISH_THRESHOLD) {
                    restoring = true
                    onProgress(saved.toFloat(), true)
                    launch {
                        delay(300)
                        scroll.scrollTo((saved * scroll.maxValue).toInt())
                        delay(200)
                        restoring = false
                    }
                    return@collect
                }
            }
            onProgress(progress, true)
            ReadingProgressStore.record(article, progress.toDouble())
        }
    }

    LaunchedEffect(scrollTarget) {
        val target = scrollTarget ?: return@LaunchedEffect
        delay(350)
        anchors.offsets[target]?.let { scroll.animateScrollTo(it.toInt()) }
        onScrollTargetHandled()
    }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                onRefresh()
                refreshing = false
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        CompositionLocalProvider(LocalReaderStyle provides ReaderSettings.style) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scroll)
                    .onGloballyPositioned { anchors.content = it }
                    .navigationBarsPadding(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                article.image?.ifEmpty { null }?.let { image ->
                    RemoteImage(
                        image,
                        Modifier
                            .widthIn(max = readableWidth)
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .padding(top = 8.dp)
                            .aspectRatio(3f / 2f)
                            .clip(RoundedCornerShape(20.dp))
                            .testTag("article-hero"),
                    )
                }
                Column(
                    Modifier
                        .widthIn(max = readableWidth)
                        .fillMaxWidth()
                        .padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 60.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        val reader = LocalReaderStyle.current
                        val titleStyle = MaterialTheme.typography.headlineLarge
                        SelectionContainer {
                            Text(
                                article.displayTitle,
                                style = titleStyle.copy(fontSize = titleStyle.fontSize * reader.textScale, lineHeight = titleStyle.lineHeight * reader.textScale, fontFamily = reader.fontFamily ?: titleStyle.fontFamily),
                                fontWeight = FontWeight.SemiBold,
                                color = AppColors.textPrimary,
                                modifier = Modifier.semantics { heading() }.testTag("article-title"),
                            )
                        }
                        article.summary?.ifEmpty { null }?.let { summary ->
                            val summaryStyle = MaterialTheme.typography.titleLarge
                            Text(
                                summary,
                                style = summaryStyle.copy(fontSize = summaryStyle.fontSize * reader.textScale, lineHeight = summaryStyle.lineHeight * reader.textScale, fontFamily = reader.fontFamily ?: summaryStyle.fontFamily),
                                fontWeight = FontWeight.Normal,
                                color = AppColors.textSecondary,
                            )
                        }
                    }
                    AuthorRow(article)
                    if (article.hashtags.isNotEmpty()) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            article.hashtags.forEach { tag ->
                                SuggestionChip(
                                    onClick = { Router.push(Route.Hashtag(tag)) },
                                    label = { Text("#$tag") },
                                    shape = RoundedCornerShape(50),
                                    colors = SuggestionChipDefaults.suggestionChipColors(labelColor = AppColors.textPrimary),
                                    modifier = Modifier.testTag("article-hashtag-$tag"),
                                )
                            }
                        }
                    }
                    if (model.highlights.isNotEmpty()) {
                        AssistChip(
                            onClick = onShowHighlights,
                            label = { Text(L("highlightsCount", "count" to model.highlights.size)) },
                            leadingIcon = { Icon(Icons.Outlined.Highlight, null, Modifier.size(18.dp)) },
                            shape = RoundedCornerShape(50),
                            colors = AssistChipDefaults.assistChipColors(labelColor = AppColors.textPrimary, leadingIconContentColor = AppColors.textPrimary),
                            modifier = Modifier.wrapContentWidth().testTag("article-highlights"),
                        )
                    }
                    HorizontalDivider(color = AppColors.divider)
                    CompositionLocalProvider(LocalMarkdownHighlighting provides highlighting) {
                        MarkdownView(model.blocks, Modifier.testTag("article-body"), anchors = anchors)
                    }
                }
            }
        }
    }
}

@Composable
private fun AuthorRow(article: Article) {
    val name = ProfileCache.profiles[article.pubkey]?.bestName ?: article.authorName?.ifEmpty { null } ?: Profile.shortNpub(article.pubkey)
    val date = remember(article.publishedAt) {
        DateFormat.getDateInstance(DateFormat.MEDIUM, AppLanguage.locale).format(Date(article.publishedAt * 1000))
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { Router.push(Route.Profile(article.pubkey)) }
            .testTag("article-author"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ProfileAvatar(article.pubkey, size = 40.dp, fallbackUrl = article.authorImage)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = AppColors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                "$date · ${L("exploreMinRead", "count" to article.readingMinutes)}",
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
                maxLines = 1,
            )
        }
        Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null, tint = AppColors.textTertiary)
    }
}
