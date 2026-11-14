package me.untreu.qiqstr.ui.compose

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import me.untreu.qiqstr.App

data class PreparedImage(val bytes: ByteArray, val mimeType: String, val preview: Bitmap?, val width: Int, val height: Int)

object MediaSanitizer {
    suspend fun strippedVideo(input: Uri): ByteArray? = withContext(Dispatchers.IO) {
        val directory = scratchDirectory()
        try {
            directory.mkdirs()
            val output = File(directory, "out.mp4")
            if (!remux(input, output)) return@withContext null
            output.readBytes()
        } catch (_: Throwable) {
            null
        } finally {
            directory.deleteRecursively()
        }
    }

    suspend fun strippedVideo(data: ByteArray): ByteArray? = withContext(Dispatchers.IO) {
        val directory = scratchDirectory()
        try {
            directory.mkdirs()
            val input = File(directory, "in.mp4").apply { writeBytes(data) }
            strippedVideo(Uri.fromFile(input))
        } catch (_: Throwable) {
            null
        } finally {
            directory.deleteRecursively()
        }
    }

    fun strippedImage(data: ByteArray, mime: String): ByteArray? {
        val image = decode(data, Int.MAX_VALUE) ?: return null
        return when (mime) {
            "image/png" -> encode(image, Bitmap.CompressFormat.PNG, 100)
            "image/jpeg" -> encode(image, Bitmap.CompressFormat.JPEG, 90)
            else -> null
        }
    }

    fun prepareImage(data: ByteArray, mime: String): PreparedImage? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val rotation = orientation(data)
        val swapped = rotation == 90 || rotation == 270
        val width = if (swapped) bounds.outHeight else bounds.outWidth
        val height = if (swapped) bounds.outWidth else bounds.outHeight
        val preview = decode(data, 400)
        if (mime == "image/gif") return PreparedImage(data, mime, preview, width, height)
        val image = decode(data, 4096) ?: return null
        if (mime == "image/png" && data.size <= 4_000_000) {
            encode(image, Bitmap.CompressFormat.PNG, 100)?.let { return PreparedImage(it, "image/png", preview, image.width, image.height) }
        }
        val jpeg = encode(image, Bitmap.CompressFormat.JPEG, 86) ?: return null
        return PreparedImage(jpeg, "image/jpeg", preview, image.width, image.height)
    }

    fun decode(data: ByteArray, maxPixel: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        while (longest / (sample * 2) >= maxPixel) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val scale = minOf(1f, maxPixel.toFloat() / maxOf(decoded.width, decoded.height))
        val rotation = orientation(data)
        if (scale >= 1f && rotation == 0) return decoded
        val matrix = Matrix().apply {
            if (scale < 1f) postScale(scale, scale)
            if (rotation != 0) postRotate(rotation.toFloat())
        }
        return Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    }

    private fun encode(image: Bitmap, format: Bitmap.CompressFormat, quality: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        return if (image.compress(format, quality, out)) out.toByteArray() else null
    }

    private fun orientation(data: ByteArray): Int = runCatching {
        when (ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90, ExifInterface.ORIENTATION_TRANSPOSE -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270, ExifInterface.ORIENTATION_TRANSVERSE -> 270
            else -> 0
        }
    }.getOrDefault(0)

    private fun remux(input: Uri, output: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(App.context, input, null)
            val rotation = runCatching {
                MediaMetadataRetriever().run {
                    try {
                        setDataSource(App.context, input)
                        extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                    } finally {
                        release()
                    }
                }
            }.getOrDefault(0)
            val created = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = created
            val mapping = HashMap<Int, Int>()
            var bufferSize = 1 shl 20
            for (track in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(track)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(track)
                mapping[track] = created.addTrack(format)
                if (format.containsKey(android.media.MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    bufferSize = maxOf(bufferSize, format.getInteger(android.media.MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            if (mapping.isEmpty()) return false
            if (rotation != 0) created.setOrientationHint(rotation)
            created.start()
            val buffer = ByteBuffer.allocate(bufferSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val target = mapping[extractor.sampleTrackIndex]
                if (target != null) {
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = extractor.sampleTime
                    info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    created.writeSampleData(target, buffer, info)
                }
                extractor.advance()
            }
            created.stop()
            return true
        } catch (_: Throwable) {
            return false
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun scratchDirectory(): File = File(App.context.cacheDir, "media-${UUID.randomUUID()}")
}
