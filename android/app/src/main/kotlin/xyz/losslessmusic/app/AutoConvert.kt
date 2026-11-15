package xyz.losslessmusic.app

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.util.Locale

/** Native-worker only: Dart-fallback items (gate-rejected or stalled) are not converted. */
object AutoConvert {
    data class Target(val format: String, val bitrate: String, val maxBitDepth: Int, val maxSampleRate: Int)

    fun target(requestJson: String): Target? {
        val r = JSONObject(requestJson)
        if (!r.optBoolean("auto_convert_downloads", false)) return null
        return Target(
            r.optString("auto_convert_format", "flac").lowercase(Locale.ROOT)
                .takeIf { it in setOf("mp3", "aac", "opus", "flac", "alac") } ?: "flac",
            r.optString("auto_convert_bitrate", "320k")
                .takeIf { it in setOf("128k", "160k", "192k", "256k", "320k") } ?: "320k",
            r.optInt("auto_convert_max_bit_depth", 16).takeIf { it in setOf(0, 16, 24) } ?: 16,
            r.optInt("auto_convert_max_sample_rate", 48000)
                .takeIf { it in setOf(0, 44100, 48000, 96000, 192000) } ?: 48000)
    }

    fun alreadySatisfied(t: Target, srcExt: String, srcBits: Int?, srcRate: Int?): Boolean {
        val ext = srcExt.removePrefix(".").lowercase(Locale.ROOT)
        return t.format in setOf("flac", "alac") && ext == t.format &&
            (t.maxBitDepth == 0 || srcBits != null && srcBits > 0 && srcBits <= t.maxBitDepth) &&
            (t.maxSampleRate == 0 || srcRate != null && srcRate > 0 && srcRate <= t.maxSampleRate)
    }

    fun ffmpegArgs(t: Target, input: String, output: String, srcBits: Int?, srcRate: Int?): List<String> {
        val a = mutableListOf("-v", "error", "-hide_banner", "-i", input)
        if (t.format in setOf("flac", "alac")) {
            if (t.format == "flac") {
                a.addAll(listOf("-map", "0:a:0", "-map", "0:v?", "-map_metadata", "0",
                    "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic", "-compression_level", "5"))
            } else a.addAll(listOf("-map", "0:a", "-c:a", "alac"))
            // Unlike upstream's unknown-resolution fallback, caps never increase resolution.
            val depth = t.maxBitDepth.takeIf { it > 0 && srcBits != null && srcBits > it }
            val rate = t.maxSampleRate.takeIf { it > 0 && srcRate != null && srcRate > it }
            val sampleFormat = (if (depth != null && depth <= 16) "s16" else "s32") +
                (if (t.format == "alac") "p" else "")
            if (depth != null || rate != null) {
                val options = mutableListOf("resampler=swr")
                if (rate != null) options.add("osr=$rate")
                if (depth != null) options.add("osf=$sampleFormat")
                a.addAll(listOf("-af", "aresample=${options.joinToString(":")}"))
            }
            if (depth != null) {
                a.addAll(listOf("-sample_fmt", sampleFormat))
                if (depth > 16) a.addAll(listOf("-bits_per_raw_sample", "24"))
            }
            a.addAll(listOf("-f", if (t.format == "flac") "flac" else "mp4"))
        } else {
            when (t.format) {
                "opus" -> a.addAll(listOf("-codec:a", "libopus", "-b:a", t.bitrate,
                    "-vbr", "on", "-compression_level", "10", "-map", "0:a"))
                "aac" -> a.addAll(listOf("-codec:a", "aac", "-b:a", t.bitrate, "-map", "0:a", "-f", "mp4"))
                "mp3" -> a.addAll(listOf("-codec:a", "libmp3lame", "-b:a", t.bitrate,
                    "-map", "0:a", "-id3v2_version", "3"))
                else -> error("Unsupported conversion format")
            }
        }
        a.addAll(listOf(output, "-y"))
        return a
    }

    fun run(ctx: Context, path: String, requestJson: String, probe: (String) -> String,
            ffmpeg: (List<String>) -> Boolean): String = run(path, requestJson, probe, ffmpeg,
        embed = { NonFlacMetadataEmbedder.embed(ctx, it, requestJson) },
        warning = { Log.w("AutoConvert", "auto_conversion_warning: $it") })

    /** File transaction and policy are injectable; JVM tests never call Android APIs. */
    internal fun run(path: String, requestJson: String, probe: (String) -> String,
                     ffmpeg: (List<String>) -> Boolean, embed: (String) -> Unit = {},
                     warning: (String) -> Unit = {},
                     mover: (File, File, Boolean) -> Unit = NonFlacMetadataEmbedder::moveOutput): String {
        var staged: File? = null
        try {
            val t = target(requestJson) ?: return path
            if (JSONObject(requestJson).optBoolean("already_exists", false)) return path
            if (path.startsWith("content://")) return path
            val source = File(path)
            val ext = source.extension.lowercase(Locale.ROOT)
            if (ext !in setOf("flac", "wav", "alac", "m4a", "mp4") || !source.isFile) return path
            val q = JSONObject(probe(path))
            val codec = q.optString("codec", "").lowercase(Locale.ROOT)
            // M4A/MP4 may contain AAC: only measured ALAC is eligible.
            if (ext in setOf("m4a", "mp4") && codec != "alac") return path
            if (codec.isNotEmpty() && codec !in setOf("flac", "alac", "wav") && !codec.startsWith("pcm_")) return path
            val bits = q.optInt("bit_depth", 0).takeIf { it > 0 }
            val rate = q.optInt("sample_rate", 0).takeIf { it > 0 }
            if (alreadySatisfied(t, if (codec == "alac") "alac" else ext, bits, rate)) return path
            if (t.format in setOf("flac", "alac")) {
                check(t.maxBitDepth == 0 || bits != null) { "Cannot inspect source bit depth" }
                check(t.maxSampleRate == 0 || rate != null) { "Cannot inspect source sample rate" }
            }
            val outExt = if (t.format in setOf("aac", "alac")) "m4a" else t.format
            val output = File(source.parentFile, "${source.nameWithoutExtension}.$outExt")
            val samePath = output.canonicalFile == source.canonicalFile
            check(samePath || !output.exists()) { "Conversion destination already exists" }
            val staging = File(source.parentFile, "${source.nameWithoutExtension}.converting.$outExt")
            // Reserve before FFmpeg opens it: parallel sources may share a basename.
            Files.createFile(staging.toPath())
            staged = staging
            check(ffmpeg(ffmpegArgs(t, path, staging.path, bits, rate))) { "FFmpeg failed" }
            check(staging.isFile && staging.length() > 0) { "Converted output missing or empty" }
            if (t.format != "flac") embed(staging.path)
            check(staging.isFile && staging.length() > 0) { "Tagged output missing or empty" }
            // Reuse the Android 9 sdcardfs atomic/regular rename and copy fallback.
            // Never delete the source before replacement is in place.
            if (samePath) NonFlacMetadataEmbedder.replaceOutput(staging, output, mover)
            else Files.move(staging.toPath(), output.toPath())
            if (!samePath && !source.delete()) warning("Converted output adopted; source could not be deleted")
            return output.path
        } catch (e: Exception) {
            warning(e.message ?: e.javaClass.simpleName)
            return path
        } finally {
            staged?.delete()
        }
    }
}
