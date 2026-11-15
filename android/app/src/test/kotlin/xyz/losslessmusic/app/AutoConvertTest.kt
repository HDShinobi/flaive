package xyz.losslessmusic.app

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class AutoConvertTest {
    @get:Rule val temp = TemporaryFolder()
    private val caps = AutoConvert.Target("flac", "320k", 16, 48000)
    private fun args(format: String = "flac", bits: Int = 24, rate: Int = 96000) =
        AutoConvert.ffmpegArgs(caps.copy(format = format), "in.flac", "out", bits, rate)
    @Test fun `flac cap 24-bit 96k source to 16-48 yields s16 and osr 48000`() {
        val a = args()
        assertEquals("s16", a[a.indexOf("-sample_fmt") + 1])
        assertTrue(a.contains("aresample=resampler=swr:osr=48000:osf=s16"))
    }
    @Test fun `no upsampling when source below cap`() {
        val a = args(bits = 16, rate = 44100)
        assertFalse(a.contains("-af")); assertFalse(a.contains("-sample_fmt"))
    }
    @Test fun `alreadySatisfied for 16-44 flac with 16-48 caps`() {
        assertTrue(AutoConvert.alreadySatisfied(caps, "flac", 16, 44100))
        assertFalse(AutoConvert.alreadySatisfied(caps, "wav", 16, 44100))
        assertFalse(AutoConvert.alreadySatisfied(caps, "flac", null, null))
    }
    @Test fun `mp3 args map audio only with id3v2 3`() {
        val a = args("mp3")
        assertEquals("0:a", a[a.indexOf("-map") + 1])
        assertEquals("3", a[a.indexOf("-id3v2_version") + 1])
        assertTrue(a.contains("libmp3lame"))
    }
    @Test fun `opus args use libopus vbr`() {
        val a = args("opus")
        assertTrue(a.contains("libopus")); assertEquals("on", a[a.indexOf("-vbr") + 1])
    }
    @Test fun `alac args keep lossless and apply caps`() {
        val a = args("alac")
        assertEquals("alac", a[a.indexOf("-c:a") + 1])
        assertEquals("0:a", a[a.indexOf("-map") + 1])
        assertTrue(a.contains("aresample=resampler=swr:osr=48000:osf=s16"))
    }
    @Test fun `24-bit cap uses s32 and raw sample bits`() {
        val a = AutoConvert.ffmpegArgs(caps.copy(maxBitDepth = 24), "in", "out", 32, 96000)
        assertEquals("s32", a[a.indexOf("-sample_fmt") + 1])
        assertEquals("24", a[a.indexOf("-bits_per_raw_sample") + 1])
    }
    @Test fun `disabled returns null target`() { assertNull(AutoConvert.target("{}")) }
    @Test fun `enabled defaults to flac caps`() {
        assertEquals(caps, AutoConvert.target("""{"auto_convert_downloads":true}"""))
    }
    private fun run(source: File, ffmpeg: (List<String>) -> Boolean,
                    probe: String = """{"bit_depth":24,"sample_rate":96000,"codec":"flac"}""",
                    embed: (String) -> Unit = {}) = AutoConvert.run(
        source.path, """{"auto_convert_downloads":true,"auto_convert_format":"mp3"}""",
        { probe }, ffmpeg, embed)
    @Test fun `run keeps source when ffmpeg fails`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        assertEquals(src.path, run(src, { false })); assertEquals("original", src.readText())
    }
    @Test fun `run deletes source and returns new path when extension changes`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        var tagged = false
        val path = run(src, { a ->
            val staged = File(a[a.indexOf("-y") - 1])
            assertEquals("song.converting.mp3", staged.name)
            staged.writeText("converted"); true
        }, embed = { assertTrue(src.exists()); tagged = true })
        assertEquals(File(temp.root, "song.mp3").path, path)
        assertTrue(tagged); assertFalse(src.exists()); assertEquals("converted", File(path).readText())
    }
    @Test fun `missing output keeps source`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        assertEquals(src.path, run(src, { true })); assertEquals("original", src.readText())
    }
    @Test fun `retag failure keeps source and removes staging`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        assertEquals(src.path, run(src, { a -> File(a[a.indexOf("-y") - 1]).writeText("new"); true },
            embed = { error("tag failed") }))
        assertEquals("original", src.readText()); assertFalse(File(temp.root, "song.converting.mp3").exists())
    }
    @Test fun `destination collision preserves both files`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        val dst = temp.newFile("song.mp3").apply { writeText("existing") }
        assertEquals(src.path, run(src, { error("must skip") }))
        assertEquals("original", src.readText()); assertEquals("existing", dst.readText())
    }
    @Test fun `lossy source skips conversion`() {
        val src = temp.newFile("song.m4a")
        assertEquals(src.path, run(src, { error("must skip") },
            probe = """{"codec":"aac","bit_depth":16,"sample_rate":44100}"""))
    }

    @Test fun `same-extension FLAC cap replaces source only after conversion`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        val path = AutoConvert.run(src.path, """{"auto_convert_downloads":true}""",
            { """{"codec":"flac","bit_depth":24,"sample_rate":96000}""" },
            { a ->
                assertEquals("original", src.readText())
                File(a[a.indexOf("-y") - 1]).writeText("capped"); true
            })
        assertEquals(src.path, path); assertEquals("capped", src.readText())
    }
    @Test fun `failed rename preserves source and colliding destination`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        val dst = File(temp.root, "song.mp3")
        val path = run(src, { a ->
            File(a[a.indexOf("-y") - 1]).writeText("converted")
            dst.writeText("racing file"); true
        })
        assertEquals(src.path, path); assertEquals("original", src.readText())
        assertEquals("racing file", dst.readText())
        assertFalse(File(temp.root, "song.converting.mp3").exists())
    }
    @Test fun `preexisting staging is never overwritten or deleted`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        val staging = temp.newFile("song.converting.mp3").apply { writeText("other conversion") }
        assertEquals(src.path, run(src, { error("must skip") }))
        assertEquals("other conversion", staging.readText()); assertEquals("original", src.readText())
    }
    @Test fun `ALAC in m4a converts and is retagged`() {
        val src = temp.newFile("song.m4a").apply { writeText("ALAC") }
        val path = run(src, { a -> File(a[a.indexOf("-y") - 1]).writeText("mp3"); true },
            probe = """{"codec":"alac","bit_depth":24,"sample_rate":96000}""")
        assertEquals("mp3", File(path).readText()); assertFalse(src.exists())
    }
    @Test fun `keep caps and below-cap source never add resampling`() {
        val a = AutoConvert.ffmpegArgs(caps.copy(maxBitDepth = 0, maxSampleRate = 0), "in", "out", 32, 384000)
        assertFalse(a.contains("-af")); assertFalse(a.contains("-sample_fmt"))
    }
    @Test fun `unknown source resolution keeps source with warning`() {
        val src = temp.newFile("song.flac").apply { writeText("original") }
        val warnings = mutableListOf<String>()
        assertEquals(src.path, AutoConvert.run(src.path, """{"auto_convert_downloads":true}""",
            { "{}" }, { error("must skip") }, warning = { warnings.add(it) }))
        assertEquals("original", src.readText()); assertEquals(1, warnings.size)
    }
    @Test fun `already exists skips even probe`() {
        val src = temp.newFile("song.flac")
        assertEquals(src.path, AutoConvert.run(src.path,
            """{"auto_convert_downloads":true,"already_exists":true}""",
            { error("must skip") }, { error("must skip") }))
    }
    @Test fun `AAC output uses mp4 muxer and selected bitrate`() {
        val a = AutoConvert.ffmpegArgs(caps.copy(format = "aac", bitrate = "192k"), "in", "out", 24, 96000)
        assertTrue(a.contains("aac")); assertEquals("192k", a[a.indexOf("-b:a") + 1])
        assertEquals("mp4", a[a.indexOf("-f") + 1]); assertEquals("0:a", a[a.indexOf("-map") + 1])
    }

    @Test fun `concurrent sources sharing a basename cannot share conversion staging`() {
        val first = temp.newFile("song.flac").apply { writeText("first") }
        val second = temp.newFile("song.wav").apply { writeText("second") }
        val started = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        var firstPath: String? = null
        val thread = Thread {
            firstPath = run(first, { a ->
                started.countDown()
                check(release.await(5, java.util.concurrent.TimeUnit.SECONDS))
                File(a[a.indexOf("-y") - 1]).writeText("first converted"); true
            })
        }
        thread.start()
        try {
            assertTrue(started.await(5, java.util.concurrent.TimeUnit.SECONDS))
            var secondConverted = false
            assertEquals(second.path, run(second, { secondConverted = true; false }))
            assertFalse("Staging must be reserved before FFmpeg starts", secondConverted)
            assertEquals("second", second.readText())
        } finally {
            release.countDown(); thread.join(6000)
        }
        assertFalse(thread.isAlive)
        assertEquals("first converted", File(requireNotNull(firstPath)).readText())
    }
}
