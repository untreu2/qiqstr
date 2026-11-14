package me.untreu.qiqstr.ui.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App
import me.untreu.qiqstr.core.CoreError
import me.untreu.qiqstr.core.Json
import me.untreu.qiqstr.core.L
import me.untreu.qiqstr.core.coreErrorMessage
import me.untreu.qiqstr.core.text
import me.untreu.qiqstr.data.services.ToastCenter
import me.untreu.qiqstr.data.services.ToastStyle
import me.untreu.qiqstr.data.sync.DataBus
import me.untreu.qiqstr.data.sync.ProfileCache
import me.untreu.qiqstr.data.sync.Session
import me.untreu.qiqstr.data.sync.SyncService
import me.untreu.qiqstr.domain.Profile
import me.untreu.qiqstr.ui.compose.MediaUploadService
import org.json.JSONObject

data class ProfileDraft(
    val name: String = "",
    val displayName: String = "",
    val about: String = "",
    val picture: String = "",
    val banner: String = "",
    val nip05: String = "",
    val lud16: String = "",
    val website: String = "",
    val location: String = "",
) {
    val trimmed: ProfileDraft
        get() = ProfileDraft(
            name.trim(), displayName.trim(), about.trim(), picture.trim(), banner.trim(),
            nip05.trim(), lud16.trim(), website.trim(), location.trim(),
        )

    fun merged(base: JSONObject, original: ProfileDraft): JSONObject {
        val m = JSONObject(base.toString())
        val d = trimmed
        val o = original.trimmed
        fun put(key: String, value: String, old: String) {
            if (value == old) return
            if (value.isEmpty()) m.remove(key) else m.put(key, value)
        }
        put("name", d.name, o.name)
        put("display_name", d.displayName, o.displayName)
        if (m.has("displayName")) put("displayName", d.displayName, o.displayName)
        if (m.has("username")) put("username", d.name, o.name)
        put("about", d.about, o.about)
        put("picture", d.picture, o.picture)
        if (m.has("image")) put("image", d.picture, o.picture)
        put("banner", d.banner, o.banner)
        put("nip05", d.nip05, o.nip05)
        put("lud16", d.lud16, o.lud16)
        put("website", d.website, o.website)
        put("location", d.location, o.location)
        return m
    }

    companion object {
        fun from(m: JSONObject): ProfileDraft {
            fun text(vararg keys: String): String = keys.firstNotNullOfOrNull { key -> (m.opt(key) as? String)?.ifEmpty { null } } ?: ""
            return ProfileDraft(
                name = text("name", "username"),
                displayName = text("display_name", "displayName"),
                about = text("about"),
                picture = text("picture", "image"),
                banner = text("banner"),
                nip05 = text("nip05"),
                lud16 = text("lud16"),
                website = text("website"),
                location = text("location"),
            )
        }
    }
}

enum class ProfileField { NAME, DISPLAY_NAME, ABOUT, PICTURE, BANNER, NIP05, LUD16, WEBSITE, LOCATION }

enum class MediaTarget { PICTURE, BANNER }

class EditProfileViewModel : ViewModel() {
    var draft by mutableStateOf(ProfileDraft())
    var original by mutableStateOf(ProfileDraft())
        private set
    var isLoading by mutableStateOf(true)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var uploadingPicture by mutableStateOf(false)
        private set
    var uploadingBanner by mutableStateOf(false)
        private set
    var savedCount by mutableIntStateOf(0)
        private set
    private var metadata = JSONObject()
    private var loaded = false

    val isDirty: Boolean get() = draft.trimmed != original.trimmed
    val isUploading: Boolean get() = uploadingPicture || uploadingBanner

    val errors: Map<ProfileField, String>
        get() {
            val e = HashMap<ProfileField, String>()
            val d = draft.trimmed
            if (d.name.length > 50) e[ProfileField.NAME] = L("profileNameTooLong")
            if (d.displayName.length > 50) e[ProfileField.DISPLAY_NAME] = L("profileNameTooLong")
            if (d.about.length > 1000) e[ProfileField.ABOUT] = L("profileAboutTooLong")
            if (d.location.length > 100) e[ProfileField.LOCATION] = L("locationTooLong")
            if (d.nip05.isNotEmpty() && !Nip05Verifier.isValid(d.nip05)) e[ProfileField.NIP05] = L("profileInvalidNip05")
            if (d.lud16.isNotEmpty() && !isLightningAddress(d.lud16)) e[ProfileField.LUD16] = L("profileInvalidLightningAddress")
            if (d.website.isNotEmpty() && !isWebsite(d.website)) e[ProfileField.WEBSITE] = L("profileInvalidWebsite")
            if (d.picture.isNotEmpty() && !isHTTP(d.picture)) e[ProfileField.PICTURE] = L("profileInvalidImageUrl")
            if (d.banner.isNotEmpty() && !isHTTP(d.banner)) e[ProfileField.BANNER] = L("profileInvalidImageUrl")
            return e
        }

    val canSave: Boolean get() = isDirty && errors.isEmpty() && !isSaving && !isUploading && !isLoading

    fun load() {
        if (loaded) return
        loaded = true
        viewModelScope.launch {
            val me = Session.pubkey
            if (me == null) { isLoading = false; return@launch }
            apply(ProfileDataSource.rawMetadata(me))
            isLoading = false
            SyncService.syncProfile(me, force = true)
            val fresh = ProfileDataSource.rawMetadata(me)
            if (!isDirty && !isSaving && ProfileDraft.from(fresh) != original) apply(fresh)
            else if (!isDirty) metadata = fresh
        }
    }

    private fun apply(m: JSONObject) {
        metadata = m
        val next = ProfileDraft.from(m)
        original = next
        draft = next
    }

    fun upload(uri: Uri, target: MediaTarget) {
        setUploading(target, true)
        viewModelScope.launch {
            try {
                val maxPixel = if (target == MediaTarget.PICTURE) 1024 else 2048
                val (data, mime) = withContext(Dispatchers.IO) { prepare(uri, maxPixel) }
                val url = MediaUploadService.upload(data, mime)
                if (url.isEmpty()) throw CoreError(L("uploadFailed", "message" to ""))
                draft = when (target) {
                    MediaTarget.PICTURE -> draft.copy(picture = url)
                    MediaTarget.BANNER -> draft.copy(banner = url)
                }
            } catch (error: Throwable) {
                ToastCenter.show(L("uploadFailed", "message" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                setUploading(target, false)
            }
        }
    }

    private fun prepare(uri: Uri, maxPixel: Int): Pair<ByteArray, String> {
        val resolver = App.context.contentResolver
        val raw = resolver.openInputStream(uri)?.use { it.readBytes() } ?: throw CoreError(L("errorSelectingMedia"))
        val type = resolver.getType(uri)
        if (type == "image/gif") return raw to "image/gif"
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return raw to (type ?: "image/jpeg")
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixel) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return raw to (type ?: "image/jpeg")
        val longest = maxOf(decoded.width, decoded.height)
        val scaled = if (longest > maxPixel) {
            val ratio = maxPixel.toFloat() / longest
            Bitmap.createScaledBitmap(decoded, (decoded.width * ratio).toInt().coerceAtLeast(1), (decoded.height * ratio).toInt().coerceAtLeast(1), true)
        } else decoded
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 88, out)
        return out.toByteArray() to "image/jpeg"
    }

    private fun setUploading(target: MediaTarget, value: Boolean) {
        when (target) {
            MediaTarget.PICTURE -> uploadingPicture = value
            MediaTarget.BANNER -> uploadingBanner = value
        }
    }

    fun save(onSaved: () -> Unit) {
        val me = Session.pubkey ?: return
        if (!canSave) return
        isSaving = true
        viewModelScope.launch {
            try {
                val base = SyncService.latestEditableEvent(0, me, allowingNew = true)
                val latest = base?.let { Json.obj(it.text("content")) } ?: JSONObject()
                if (base != null && latest.length() == 0) throw CoreError(L("noRelayConnection"))
                val content = draft.merged(latest, original)
                ProfileDataSource.publishMetadata(content)
                metadata = content
                original = draft.trimmed
                draft = original
                ProfileCache.set(Profile.from(content, me).copy(pubkey = me))
                DataBus.profileChanged()
                savedCount += 1
                ToastCenter.show(L("profileSaved"), ToastStyle.SUCCESS)
                onSaved()
            } catch (error: Throwable) {
                ToastCenter.show(L("profileSaveFailed", "message" to coreErrorMessage(error)), ToastStyle.ERROR)
            } finally {
                isSaving = false
            }
        }
    }

    companion object {
        fun isLightningAddress(s: String): Boolean {
            val parts = s.split("@")
            return parts.size == 2 && parts[0].isNotEmpty() && parts[1].contains(".") && !parts[1].endsWith(".")
        }

        fun isWebsite(s: String): Boolean {
            val full = if (s.startsWith("http://") || s.startsWith("https://")) s else "https://$s"
            val host = runCatching { Uri.parse(full).host }.getOrNull() ?: return false
            return host.contains(".") && !s.contains(" ")
        }

        fun isHTTP(s: String): Boolean {
            val uri = runCatching { Uri.parse(s) }.getOrNull() ?: return false
            val scheme = uri.scheme?.lowercase() ?: return false
            return (scheme == "https" || scheme == "http") && !uri.host.isNullOrEmpty()
        }
    }
}
