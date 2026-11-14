package me.untreu.qiqstr.ui.note

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.textclassifier.TextClassificationManager
import android.view.textclassifier.TextLanguage
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Translate
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.app.Router
import me.untreu.qiqstr.core.AppColors
import me.untreu.qiqstr.core.AppLanguage
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.domain.Note
import java.util.Locale

object NoteLanguage {
    private const val UNDETERMINED = ""
    private val detected = mutableStateMapOf<String, String>()

    val appLanguage: String
        get() = baseCode(AppLanguage.stored ?: Locale.getDefault().language ?: "en")

    fun language(note: Note): String? = detected[note.id]?.takeIf { it != UNDETERMINED }

    fun needsTranslation(note: Note): Boolean {
        val code = language(note) ?: return false
        return code != appLanguage
    }

    fun text(note: Note): String = NoteContentCache.content(note).translatableText

    suspend fun detect(note: Note) {
        if (detected.containsKey(note.id)) return
        val code = withContext(Dispatchers.Default) { detect(text(note)) }
        if (detected.size > 3000) detected.clear()
        detected[note.id] = code ?: UNDETERMINED
    }

    private fun detect(text: String): String? {
        if (text.count { it.isLetter() } < 12) return null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return runCatching {
            val manager = App.context.getSystemService(TextClassificationManager::class.java) ?: return null
            val result = manager.textClassifier.detectLanguage(TextLanguage.Request.Builder(text).build())
            if (result.localeHypothesisCount == 0) return null
            val locale = result.getLocale(0)
            if (result.getConfidenceScore(locale) < 0.6f) return null
            baseCode(locale.toLanguageTag())
        }.getOrNull()
    }

    private fun baseCode(identifier: String): String = identifier.split('-', '_').first().lowercase()

    fun translate(context: Context, note: Note) {
        val text = text(note)
        if (text.isEmpty()) return
        val start: (Intent) -> Boolean = { intent ->
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: ActivityNotFoundException) {
                false
            } catch (_: SecurityException) {
                false
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && start(Intent(Intent.ACTION_TRANSLATE).putExtra(Intent.EXTRA_TEXT, text))) return
        val process = Intent(Intent.ACTION_PROCESS_TEXT).setType("text/plain")
            .putExtra(Intent.EXTRA_PROCESS_TEXT, text).putExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true)
            .setPackage("com.google.android.apps.translate")
        if (start(process)) return
        Router.openUrl("https://translate.google.com/?sl=auto&tl=$appLanguage&op=translate&text=${Uri.encode(text)}")
    }
}

@Composable
fun NoteTranslateButton(note: Note) {
    LaunchedEffect(note.id) { NoteLanguage.detect(note) }
    if (!NoteLanguage.needsTranslation(note)) return
    val context = androidx.compose.ui.platform.LocalContext.current
    TextButton(onClick = { NoteLanguage.translate(context, note) }, modifier = Modifier.testTag("thread-translate")) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Outlined.Translate, null, Modifier.size(18.dp), tint = AppColors.link)
            Text(L("feedTranslatePost"), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = AppColors.link)
        }
    }
}
