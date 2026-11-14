package me.untreu.qiqstr.ui.note

import android.graphics.Bitmap
import android.util.LruCache
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

object BlurHash {
    private const val ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
    private val values: Map<Char, Int> = ALPHABET.withIndex().associate { it.value to it.index }
    private val cache = LruCache<String, Bitmap>(300)

    fun image(hash: String): Bitmap? {
        cache.get(hash)?.let { return it }
        val bitmap = decode(hash) ?: return null
        cache.put(hash, bitmap)
        return bitmap
    }

    fun decode(hash: String, width: Int = 32, height: Int = 32, punch: Float = 1f): Bitmap? {
        if (hash.length < 6) return null
        val sizeFlag = decode83(hash, 0, 1) ?: return null
        val numY = sizeFlag / 9 + 1
        val numX = sizeFlag % 9 + 1
        if (hash.length != 4 + 2 * numX * numY) return null
        val quantisedMaximum = decode83(hash, 1, 2) ?: return null
        val dc = decode83(hash, 2, 6) ?: return null
        val maximum = (quantisedMaximum + 1) / 166f * punch
        val colors = ArrayList<FloatArray>(numX * numY)
        colors.add(floatArrayOf(srgbToLinear(dc shr 16), srgbToLinear((dc shr 8) and 255), srgbToLinear(dc and 255)))
        for (index in 1 until numX * numY) {
            val start = 4 + index * 2
            val value = decode83(hash, start, start + 2) ?: return null
            colors.add(
                floatArrayOf(
                    signPow(((value / (19 * 19)).toFloat() - 9) / 9, 2f) * maximum,
                    signPow((((value / 19) % 19).toFloat() - 9) / 9, 2f) * maximum,
                    signPow(((value % 19).toFloat() - 9) / 9, 2f) * maximum,
                ),
            )
        }
        val cosX = Array(width) { x -> FloatArray(numX) { i -> cos(PI.toFloat() * x * i / width) } }
        val cosY = Array(height) { y -> FloatArray(numY) { j -> cos(PI.toFloat() * y * j / height) } }
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var r = 0f
                var g = 0f
                var b = 0f
                for (j in 0 until numY) {
                    for (i in 0 until numX) {
                        val basis = cosX[x][i] * cosY[y][j]
                        val color = colors[i + j * numX]
                        r += color[0] * basis
                        g += color[1] * basis
                        b += color[2] * basis
                    }
                }
                pixels[y * width + x] = (0xFF shl 24) or (linearToSrgb(r) shl 16) or (linearToSrgb(g) shl 8) or linearToSrgb(b)
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    fun encode(image: Bitmap, componentsX: Int = 4, componentsY: Int = 3): String? {
        val size = 32
        val scaled = runCatching { Bitmap.createScaledBitmap(image, size, size, true) }.getOrNull() ?: return null
        val argb = IntArray(size * size)
        scaled.getPixels(argb, 0, size, 0, 0, size, size)
        val linear = FloatArray(size * size * 3)
        for (index in argb.indices) {
            val pixel = argb[index]
            linear[index * 3] = srgbToLinear((pixel shr 16) and 255)
            linear[index * 3 + 1] = srgbToLinear((pixel shr 8) and 255)
            linear[index * 3 + 2] = srgbToLinear(pixel and 255)
        }
        val factors = ArrayList<FloatArray>()
        for (j in 0 until componentsY) {
            for (i in 0 until componentsX) {
                val normalisation = if (i == 0 && j == 0) 1f else 2f
                var r = 0f
                var g = 0f
                var b = 0f
                for (y in 0 until size) {
                    val cy = cos(PI.toFloat() * j * y / size)
                    for (x in 0 until size) {
                        val basis = normalisation * cos(PI.toFloat() * i * x / size) * cy
                        val offset = (y * size + x) * 3
                        r += basis * linear[offset]
                        g += basis * linear[offset + 1]
                        b += basis * linear[offset + 2]
                    }
                }
                val scale = 1f / (size * size)
                factors.add(floatArrayOf(r * scale, g * scale, b * scale))
            }
        }
        val dc = factors[0]
        val ac = factors.drop(1)
        val hash = StringBuilder(encode83((componentsX - 1) + (componentsY - 1) * 9, 1))
        val maximum: Float
        val actual = ac.maxOfOrNull { max(abs(it[0]), max(abs(it[1]), abs(it[2]))) }
        if (actual != null) {
            val quantised = max(0f, min(82f, floor(actual * 166 - 0.5f))).toInt()
            maximum = (quantised + 1) / 166f
            hash.append(encode83(quantised, 1))
        } else {
            maximum = 1f
            hash.append(encode83(0, 1))
        }
        hash.append(encode83((linearToSrgb(dc[0]) shl 16) + (linearToSrgb(dc[1]) shl 8) + linearToSrgb(dc[2]), 4))
        val quant = { value: Float -> max(0f, min(18f, floor(signPow(value / maximum, 0.5f) * 9 + 9.5f))).toInt() }
        for (factor in ac) hash.append(encode83(quant(factor[0]) * 19 * 19 + quant(factor[1]) * 19 + quant(factor[2]), 2))
        return hash.toString()
    }

    private fun decode83(s: String, from: Int, to: Int): Int? {
        var value = 0
        for (index in from until to) {
            val digit = values[s[index]] ?: return null
            value = value * 83 + digit
        }
        return value
    }

    private fun encode83(value: Int, length: Int): String {
        val result = StringBuilder()
        var divisor = 1
        repeat(max(length, 1) - 1) { divisor *= 83 }
        repeat(length) {
            result.append(ALPHABET[(value / divisor) % 83])
            divisor = max(divisor / 83, 1)
        }
        return result.toString()
    }

    private fun srgbToLinear(value: Int): Float {
        val v = value / 255f
        return if (v <= 0.04045f) v / 12.92f else ((v + 0.055f) / 1.055f).pow(2.4f)
    }

    private fun linearToSrgb(value: Float): Int {
        val v = max(0f, min(1f, value))
        val srgb = if (v <= 0.0031308f) v * 12.92f else 1.055f * v.pow(1 / 2.4f) - 0.055f
        return max(0, min(255, (srgb * 255 + 0.5f).toInt()))
    }

    private fun signPow(value: Float, exponent: Float): Float = (if (value < 0) -1f else 1f) * abs(value).pow(exponent)
}
