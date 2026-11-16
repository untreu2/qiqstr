package me.untreu.qiqstr.ui.note

import me.untreu.qiqstr.App
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.IconButton
import me.untreu.qiqstr.core.components.EmojiPickerSheet
import me.untreu.qiqstr.core.components.CustomEmojiImage
import me.untreu.qiqstr.data.services.EmojiChoice
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.launch
import me.untreu.qiqstr.app.AppSheet
import me.untreu.qiqstr.app.ComposeContext
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.Sats
import me.untreu.qiqstr.domain.Note
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

private const val LIKE_CONTENT = "+"

@Composable
fun InteractionBar(note: Note, model: NoteCountsModel, actions: NoteActionHandler, modifier: Modifier = Modifier, compact: Boolean = false) {
    val haptics = LocalHapticFeedback.current
    var replyTick by remember { mutableIntStateOf(0) }
    var repostTick by remember { mutableIntStateOf(0) }
    var likeTick by remember { mutableIntStateOf(0) }
    var showRepostMenu by remember { mutableStateOf(false) }
    var showReactions by remember { mutableStateOf(false) }
    var showEmojiPicker by remember { mutableStateOf(false) }
    var showMore by remember { mutableStateOf(false) }
    val counts = model.counts

    if (showEmojiPicker) EmojiPickerSheet(onDismiss = { showEmojiPicker = false }) { choice ->
        val content = if (choice.content == "❤️") LIKE_CONTENT else choice.content
        App.scope.launch { NoteInteractionStore.react(note, content, (choice as? EmojiChoice.Custom)?.emoji) }
    }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        InteractionButton(
            onClick = {
                replyTick++
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                Router.compose(ComposeContext.Reply(note))
            },
            description = L("reply"),
            state = if (counts.replies > 0) "${counts.replies}" else "",
            tag = "note-reply",
        ) {
            InteractionLabel(Icons.Outlined.ChatBubbleOutline, counts.replies, null, compact, bounceTick = replyTick)
        }
        Spacer(Modifier.weight(1f))
        Box {
            InteractionButton(
                onClick = { showRepostMenu = true },
                description = L("repost"),
                state = spoken(counts.reposts, if (counts.hasReposted) L("reposted") else null),
                tag = "note-repost",
            ) {
                InteractionLabel(Icons.Filled.Repeat, counts.reposts, if (counts.hasReposted) AppColors.repost else null, compact, popTick = repostTick, burstTick = repostTick, rotateTick = repostTick)
            }
            DropdownMenu(expanded = showRepostMenu, onDismissRequest = { showRepostMenu = false }) {
                val repost = {
                    showRepostMenu = false
                    repostTick++
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                }
                if (counts.hasReposted) {
                    DropdownMenuItem(
                        text = { Text(L("undoRepost")) },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.Undo, null) },
                        onClick = { showRepostMenu = false; App.scope.launch { NoteInteractionStore.toggleRepost(note) } },
                    )
                    DropdownMenuItem(
                        text = { Text(L("repostAgain")) },
                        leadingIcon = { Icon(Icons.Filled.Repeat, null) },
                        onClick = { repost(); App.scope.launch { NoteInteractionStore.repostAgain(note) } },
                    )
                } else {
                    DropdownMenuItem(
                        text = { Text(L("repost")) },
                        leadingIcon = { Icon(Icons.Filled.Repeat, null) },
                        onClick = { repost(); App.scope.launch { NoteInteractionStore.toggleRepost(note) } },
                    )
                }
                DropdownMenuItem(
                    text = { Text(L("quote")) },
                    leadingIcon = { Icon(Icons.Outlined.FormatQuote, null) },
                    onClick = { showRepostMenu = false; Router.compose(ComposeContext.Quote(note)) },
                )
            }
        }
        Spacer(Modifier.weight(1f))
        Box {
            val emoji = model.myReaction?.takeIf { counts.hasReacted && it != LIKE_CONTENT && it != "❤️" }
            InteractionButton(
                onClick = {
                    if (!model.isReacting) {
                        if (!counts.hasReacted) likeTick++
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        App.scope.launch { NoteInteractionStore.toggleReaction(note) }
                    }
                },
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showReactions = true
                },
                description = L("reaction"),
                state = spoken(counts.reactions, if (counts.hasReacted) L("liked") else null),
                tag = "note-like",
                customAction = L("reactWithEmoji") to { showReactions = true },
            ) {
                InteractionLabel(
                    if (counts.hasReacted) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    counts.reactions,
                    if (counts.hasReacted) AppColors.reaction else null,
                    compact,
                    emoji = emoji,
                    emojiURL = if (counts.hasReacted) model.myReactionEmoji?.url else null,
                    popTick = likeTick,
                    burstTick = likeTick,
                )
            }
            if (showReactions) {
                ReactionPicker(
                    selected = if (counts.hasReacted) model.myReaction ?: LIKE_CONTENT else null,
                    onDismiss = { showReactions = false },
                    onMore = { showReactions = false; showEmojiPicker = true },
                ) { picked ->
                    showReactions = false
                    val content = if (picked == "❤️") LIKE_CONTENT else picked
                    if (!(counts.hasReacted && (model.myReaction ?: LIKE_CONTENT) == content)) {
                        likeTick++
                        App.scope.launch { NoteInteractionStore.react(note, content) }
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        InteractionButton(
            onClick = { Router.present(AppSheet.Zap(note)) },
            description = L("zap"),
            state = if (counts.zapAmount > 0) L("notificationZapSatsCount", "count" to counts.zapAmount) else "",
            tag = "note-zap",
        ) {
            InteractionLabel(if (counts.hasZapped) Icons.Filled.Bolt else Icons.Outlined.Bolt, counts.zapAmount, if (counts.hasZapped) AppColors.zap else null, compact)
        }
        Spacer(Modifier.weight(1f))
        Box {
            InteractionButton(onClick = { showMore = true }, description = L("feedMoreActions"), state = "", tag = "note-more") {
                Box(Modifier.size(44.dp, 34.dp), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.MoreHoriz, null, Modifier.size(if (compact) 20.dp else 22.dp), tint = AppColors.textSecondary)
                }
            }
            DropdownMenu(expanded = showMore, onDismissRequest = { showMore = false }) {
                NoteMenuItems(note, actions) { showMore = false }
            }
        }
    }
}

private fun spoken(count: Int, state: String?): String = listOfNotNull(state, if (count > 0) "$count" else null).joinToString(", ")

@Composable
private fun InteractionButton(
    onClick: () -> Unit,
    description: String,
    state: String,
    tag: String,
    onLongClick: (() -> Unit)? = null,
    customAction: Pair<String, () -> Unit>? = null,
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.86f else 1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMediumLow), label = "press")
    Box(
        Modifier
            .graphicsLayer { scaleX = scale; scaleY = scale }
            .combinedClickable(
                interactionSource = interaction,
                indication = null,
                role = Role.Button,
                onLongClick = onLongClick,
                onClick = onClick,
            )
            .semantics {
                contentDescription = description
                if (state.isNotEmpty()) stateDescription = state
                customAction?.let { (label, action) -> customActions = listOf(CustomAccessibilityAction(label) { action(); true }) }
            }
            .testTag(tag),
    ) { content() }
}

@Composable
fun InteractionLabel(
    icon: ImageVector,
    count: Int,
    tint: Color?,
    compact: Boolean = false,
    emoji: String? = null,
    emojiURL: String? = null,
    popTick: Int = 0,
    burstTick: Int = 0,
    rotateTick: Int = 0,
    bounceTick: Int = 0,
) {
    val color by animateColorAsState(tint ?: AppColors.textSecondary, tween(180), label = "tint")
    val iconSize = if (compact) 20.dp else 24.dp
    val pop = remember { Animatable(1f) }
    val rotation = remember { Animatable(0f) }
    val bounce = remember { Animatable(0f) }
    LaunchedEffect(popTick) {
        if (popTick == 0) return@LaunchedEffect
        pop.animateTo(1f, keyframes {
            durationMillis = 580
            0.55f at 90 using FastOutSlowInEasing
            1.3f at 260
            1f at 580
        })
    }
    LaunchedEffect(rotateTick) {
        if (rotateTick == 0) return@LaunchedEffect
        rotation.snapTo(0f)
        rotation.animateTo(360f, tween(420, easing = FastOutSlowInEasing))
        rotation.snapTo(0f)
    }
    LaunchedEffect(bounceTick) {
        if (bounceTick == 0) return@LaunchedEffect
        bounce.animateTo(0f, keyframes {
            durationMillis = 360
            -6f at 120
            0f at 360
        })
    }
    Row(
        Modifier.widthIn(min = 48.dp).heightIn(min = 34.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(contentAlignment = Alignment.Center) {
            ReactionBurst(burstTick, color, if (compact) 34.dp else 40.dp)
            Box(
                Modifier.size(iconSize).graphicsLayer {
                    scaleX = pop.value
                    scaleY = pop.value
                    rotationZ = rotation.value
                    translationY = bounce.value * density
                },
                contentAlignment = Alignment.Center,
            ) {
                AnimatedContent(
                    targetState = emoji to icon,
                    transitionSpec = { (scaleIn(initialScale = 0.3f) + fadeIn()) togetherWith fadeOut(tween(90)) },
                    label = "icon",
                ) { (currentEmoji, currentIcon) ->
                    if (emojiURL != null) {
                        CustomEmojiImage(emojiURL, if (compact) 18.dp else 20.dp)
                    } else if (currentEmoji != null) {
                        Text(currentEmoji, style = if (compact) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodyLarge)
                    } else {
                        Icon(currentIcon, null, Modifier.size(iconSize), tint = color)
                    }
                }
            }
        }
        if (count > 0) {
            AnimatedContent(
                targetState = count,
                transitionSpec = {
                    val up = targetState > initialState
                    (slideInVertically { if (up) it else -it } + fadeIn()) togetherWith (slideOutVertically { if (up) -it else it } + fadeOut())
                },
                label = "count",
            ) { value ->
                Text(
                    Sats.compact(value.toLong()),
                    style = if (compact) MaterialTheme.typography.labelSmall else MaterialTheme.typography.labelMedium,
                    fontWeight = if (tint == null) FontWeight.Normal else FontWeight.SemiBold,
                    color = color,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
fun ReactionBurst(trigger: Int, color: Color, size: Dp) {
    val progress = remember { Animatable(1f) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        progress.snapTo(0f)
        progress.animateTo(1f, tween(540, easing = LinearEasing))
    }
    val p = progress.value
    if (p >= 1f) return
    val density = LocalDensity.current
    Canvas(Modifier.size(size)) {
        val center = Offset(this.size.width / 2, this.size.height / 2)
        val radius = this.size.minDimension / 2
        val ringT = (p / 0.6f).coerceIn(0f, 1f)
        val ringAlpha = if (p < 0.26f) 0.85f else (0.85f * (1f - ((p - 0.26f) / 0.37f))).coerceIn(0f, 0.85f)
        val ringWidth = with(density) { (7.dp * (1f - ringT)).toPx() }.coerceAtLeast(0.1f)
        val ringScale = 0.3f + 0.75f * FastOutSlowInEasing.transform(ringT)
        if (ringAlpha > 0f) {
            drawCircle(color.copy(alpha = ringAlpha), radius = (radius * ringScale - ringWidth / 2).coerceAtLeast(0f), center = center, style = Stroke(ringWidth))
        }
        val spreadT = ((p - 0.19f) / 0.78f).coerceIn(0f, 1f)
        val spread = with(density) { 8.dp.toPx() } + (radius * 1.24f - with(density) { 8.dp.toPx() }) * FastOutSlowInEasing.transform(spreadT)
        val dotsAlpha = when {
            p < 0.19f -> 0f
            p < 0.6f -> 1f
            else -> (1f - (p - 0.6f) / 0.37f).coerceIn(0f, 1f)
        }
        val dotScale = if (p < 0.56f) 1f else (1f - 0.8f * ((p - 0.56f) / 0.44f)).coerceIn(0.2f, 1f)
        if (dotsAlpha > 0f) {
            for (index in 0 until 8) {
                val angle = index / 8.0 * 2 * PI - PI / 2
                val even = index % 2 == 0
                val r = spread * if (even) 1f else 0.78f
                val dot = with(density) { (if (even) 2.dp else 1.5.dp).toPx() } * dotScale
                drawCircle(
                    color.copy(alpha = dotsAlpha * if (even) 1f else 0.6f),
                    radius = dot,
                    center = Offset(center.x + (cos(angle) * r).toFloat(), center.y + (sin(angle) * r).toFloat()),
                )
            }
        }
    }
}

val reactionEmojis = listOf("❤️", "🤙", "🔥", "😂", "🫂", "👀", "⚡️", "💜")

@Composable
fun ReactionPicker(selected: String?, onDismiss: () -> Unit, onMore: () -> Unit = {}, onPick: (String) -> Unit) {
    val gap = with(LocalDensity.current) { 8.dp.roundToPx() }
    val haptics = LocalHapticFeedback.current
    val positioner = remember(gap) { AbovePositionProvider(gap) }
    Popup(popupPositionProvider = positioner, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Surface(shape = RoundedCornerShape(28.dp), shadowElevation = 8.dp, tonalElevation = 3.dp, modifier = Modifier.testTag("reaction-picker")) {
            Row(Modifier.padding(horizontal = 6.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                reactionEmojis.forEachIndexed { index, emoji ->
                    val isSelected = selected != null && (selected == emoji || (emoji == "❤️" && selected == LIKE_CONTENT))
                    val appear = remember { Animatable(0.1f) }
                    LaunchedEffect(Unit) {
                        kotlinx.coroutines.delay(index * 25L)
                        appear.animateTo(1f, spring(dampingRatio = 0.58f, stiffness = Spring.StiffnessMedium))
                    }
                    val interaction = remember { MutableInteractionSource() }
                    val pressed by interaction.collectIsPressedAsState()
                    val pressScale by animateFloatAsState(if (pressed) 1.4f else 1f, spring(dampingRatio = 0.55f), label = "emoji-press")
                    Box(
                        Modifier.size(36.dp, 46.dp)
                            .graphicsLayer {
                                scaleX = appear.value * pressScale
                                scaleY = appear.value * pressScale
                                translationY = (1f - appear.value) * 12.dp.toPx() - if (pressed) 8.dp.toPx() else 0f
                                alpha = appear.value.coerceIn(0f, 1f)
                            }
                            .combinedClickable(interactionSource = interaction, indication = null, onClick = {
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                onPick(emoji)
                            })
                            .semantics { contentDescription = emoji; this.selected = isSelected }
                            .testTag("reaction-$index"),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isSelected) Box(Modifier.size(40.dp).background(AppColors.tile, CircleShape))
                        Text(emoji, style = MaterialTheme.typography.headlineSmall)
                    }
                }
                IconButton(onClick = onMore, modifier = Modifier.size(40.dp, 46.dp).testTag("reaction-more")) { Icon(Icons.Outlined.Add, L("emojiMore")) }
            }
        }
    }
}

private class AbovePositionProvider(private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val centered = anchorBounds.left + (anchorBounds.width - popupContentSize.width) / 2
        val x = centered.coerceIn(gap, maxOf(gap, windowSize.width - popupContentSize.width - gap))
        val above = anchorBounds.top - popupContentSize.height - gap
        val y = if (above >= 0) above else anchorBounds.bottom + gap
        return IntOffset(x, y)
    }
}
