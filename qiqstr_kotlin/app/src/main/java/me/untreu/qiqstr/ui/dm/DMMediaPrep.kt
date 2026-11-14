package me.untreu.qiqstr.ui.dm

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.provider.OpenableColumns
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App

class DMPickedMedia(val data: ByteArray, val mimeType: String, val thumbnail: Bitmap?)

class DMMediaError(val tooLarge: Boolean) : Exception()

object DMMediaPrep {
    private val resolver get() = App.context.contentResolver

    fun mimeType(uri: Uri): String? = resolver.getType(uri)

    private fun size(uri: Uri): Long? {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getLong(0)
        }
        return runCatching { resolver.openAssetFileDescriptor(uri, "r")?.use { it.length } }.getOrNull()?.takeIf { it >= 0 }
    }

    suspend fun load(uri: Uri, isVideo: Boolean): DMPickedMedia = withContext(Dispatchers.IO) {
        size(uri)?.let { if (it > DMService.MAX_FILE_SIZE) throw DMMediaError(tooLarge = true) }
        if (isVideo) loadVideo(uri) else loadImage(uri)
    }

    private fun loadVideo(uri: Uri): DMPickedMedia {
        val directory = File(App.context.cacheDir, "picked-${UUID.randomUUID()}")
        try {
            directory.mkdirs()
            val input = File(directory, "in")
            val stream = resolver.openInputStream(uri) ?: throw DMMediaError(tooLarge = false)
            stream.use { source -> input.outputStream().use { source.copyTo(it) } }
            if (input.length() > DMService.MAX_FILE_SIZE) throw DMMediaError(tooLarge = true)
            val output = File(directory, "out.mp4")
            if (!strippedVideo(input, output)) throw DMMediaError(tooLarge = false)
            return DMPickedMedia(output.readBytes(), "video/mp4", null)
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun strippedVideo(input: File, output: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(input.path)
            val created = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = created
            val tracks = HashMap<Int, Int>()
            var bufferSize = 1 shl 20
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(index)
                tracks[index] = created.addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) bufferSize = maxOf(bufferSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
            }
            if (tracks.isEmpty()) return false
            val rotation = runCatching {
                MediaMetadataRetriever().run {
                    try {
                        setDataSource(input.path)
                        extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                    } finally {
                        release()
                    }
                }
            }.getOrDefault(0)
            created.setOrientationHint(rotation)
            created.start()
            val buffer = ByteBuffer.allocate(bufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val track = tracks[extractor.sampleTrackIndex]
                if (track != null) {
                    info.set(0, size, extractor.sampleTime, if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                    created.writeSampleData(track, buffer, info)
                }
                extractor.advance()
            }
            created.stop()
            true
        } catch (_: Throwable) {
            false
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun loadImage(uri: Uri): DMPickedMedia {
        val data = resolver.openInputStream(uri)?.use { it.readBytes() } ?: throw DMMediaError(tooLarge = false)
        if (data.size > DMService.MAX_FILE_SIZE) throw DMMediaError(tooLarge = true)
        val thumbnail = decode(data, 240)
        val bytes = data.take(4).map { it.toInt() and 0xFF }
        fun startsWith(vararg prefix: Int) = bytes.size >= prefix.size && prefix.indices.all { bytes[it] == prefix[it] }
        if (startsWith(0x47, 0x49, 0x46)) return DMPickedMedia(data, "image/gif", thumbnail)
        if (startsWith(0x89, 0x50, 0x4E, 0x47)) return DMPickedMedia(encode(data, Bitmap.CompressFormat.PNG, 100, 8192) ?: data, "image/png", thumbnail)
        if (startsWith(0xFF, 0xD8, 0xFF)) return DMPickedMedia(encode(data, Bitmap.CompressFormat.JPEG, 90, 8192) ?: data, "image/jpeg", thumbnail)
        encode(data, Bitmap.CompressFormat.JPEG, 88, 4096)?.let { return DMPickedMedia(it, "image/jpeg", thumbnail) }
        return DMPickedMedia(data, mimeType(uri) ?: "application/octet-stream", thumbnail)
    }

    private fun encode(data: ByteArray, format: Bitmap.CompressFormat, quality: Int, maxPixel: Int): ByteArray? {
        val bitmap = decode(data, maxPixel) ?: return null
        return ByteArrayOutputStream().use { stream ->
            if (!bitmap.compress(format, quality, stream)) return null
            stream.toByteArray()
        }
    }

    fun decode(data: ByteArray, maxPixel: Int): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxPixel) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val longest = maxOf(decoded.width, decoded.height)
        val scaled = if (longest > maxPixel) {
            val factor = maxPixel.toFloat() / longest
            Bitmap.createScaledBitmap(decoded, (decoded.width * factor).toInt().coerceAtLeast(1), (decoded.height * factor).toInt().coerceAtLeast(1), true)
        } else {
            decoded
        }
        oriented(scaled, data)
    }.getOrNull()

    private fun oriented(bitmap: Bitmap, data: ByteArray): Bitmap {
        val orientation = runCatching {
            ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    fun imageSize(file: File): Pair<Int, Int>? {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        val orientation = runCatching {
            ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val swapped = orientation in setOf(ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSPOSE, ExifInterface.ORIENTATION_TRANSVERSE)
        return if (swapped) options.outHeight to options.outWidth else options.outWidth to options.outHeight
    }
}
