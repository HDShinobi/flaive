package xyz.losslessmusic.app

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class FakeHiResGuardTest {
    @get:Rule val temp = TemporaryFolder()
    private val original get() = File(temp.root, "song.flac")
    private val root get() = File(temp.root, ".fake-hires")
    private fun verdict(fake: Boolean = true, safe: Boolean = true) =
        JSONObject().put("verdict", if (fake) "fake_hires" else "genuine_hires")
            .put("redownload_safe", safe).toString()
    private fun success(path: String) = JSONObject().put("success", true).put("file_path", path)
    private fun run(
        first: String = verdict(), equivalent: Boolean = true,
        cancelled: () -> Boolean = { false },
        download: (String) -> JSONObject = { original.writeText("CD"); success(original.path) },
        check: ((String, String) -> String)? = null,
    ): FakeHiResGuard.Result {
        original.writeText("original")
        return FakeHiResGuard.run("item", original.path, "{\"quality\":\"hires\",\"isrc\":\"ABC\"}", root,
            check ?: { path, options ->
                if (JSONObject(options).has("verify_replacement_path")) {
                    assertEquals("original", File(path).readText())
                    JSONObject().put("replacement_equivalent", equivalent).toString()
                } else first
            }, download, cancelled)
    }
    private fun assertRestored(result: FakeHiResGuard.Result) {
        assertEquals(original.path, result.path)
        assertFalse(result.replaced)
        assertEquals("original", original.readText())
        assertFalse(File(root, "item").exists())
    }
    @Test fun `keeps original when verdict not fake`() {
        assertRestored(run(first = verdict(fake = false), download = { error("must not download") }))
    }
    @Test fun `keeps original when fake but not redownload_safe`() {
        assertRestored(run(first = verdict(safe = false), download = { error("must not download") }))
    }
    @Test fun `replaces when fake safe and equivalent`() {
        val result = run(download = {
            val request = JSONObject(it)
            assertEquals("cd", request.getString("quality"))
            assertEquals("ABC", request.getString("isrc"))
            assertTrue(request.getBoolean("bypass_duplicate_check"))
            assertFalse(original.exists())
            original.writeText("CD")
            success(original.path)
        })
        assertTrue(result.replaced)
        assertEquals(original.path, result.path)
        assertEquals("CD", original.readText())
        assertFalse(File(root, "item").exists())
    }
    @Test fun `replacement may have a different path`() {
        val replacement = File(temp.root, "cd.flac")
        val result = run(download = { replacement.writeText("CD"); success(replacement.path) })
        assertTrue(result.replaced)
        assertEquals(replacement.path, result.path)
        assertFalse(original.exists())
    }
    @Test fun `restores original when replacement not equivalent`() {
        val replacement = File(temp.root, "cd.flac")
        assertRestored(run(equivalent = false, download = { replacement.writeText("CD"); success(replacement.path) }))
        assertFalse(replacement.exists())
    }
    @Test fun `restores original when redownload fails`() {
        assertRestored(run(download = { original.writeText("partial"); JSONObject().put("success", false).put("file_path", original.path) }))
    }
    @Test fun `restores original when redownload reports already_exists`() {
        val existing = File(temp.root, "existing.flac").apply { writeText("user file") }
        assertRestored(run(download = { success(existing.path).put("already_exists", true) }))
        assertEquals("user file", existing.readText())
    }
    @Test fun `restores original when new path is inside backup dir`() {
        assertRestored(run(download = { success(File(root, "item/song.flac").path) }))
    }
    @Test fun `restores original when path is backup dir`() {
        assertRestored(run(download = { success(File(root, "item").path) }))
    }
    @Test fun `restores original when new path empty`() {
        assertRestored(run(download = { success("") }))
    }
    @Test fun `restores original when cancelled`() {
        var cancelled = false
        assertRestored(run(cancelled = { cancelled }, download = {
            original.writeText("CD"); cancelled = true; success(original.path)
        }))
    }
    @Test fun `cancel during verification restores original`() {
        var cancelled = false
        assertRestored(run(cancelled = { cancelled }, check = { _, options ->
            if (JSONObject(options).has("verify_replacement_path")) {
                cancelled = true; "{\"replacement_equivalent\":true}"
            } else verdict()
        }))
    }
    @Test fun `checker exception keeps original`() {
        assertRestored(run(check = { _, _ -> error("check failed") }))
    }
    @Test fun `verification exception restores original`() {
        assertRestored(run(check = { _, options ->
            if (JSONObject(options).has("verify_replacement_path")) error("verify failed") else verdict()
        }))
    }
    @Test fun `download exception restores original`() {
        assertRestored(run(download = { original.writeText("partial"); error("network failed") }))
    }
    @Test fun `restore failure retains recoverable backup`() {
        val result = run(download = {
            original.mkdir()
            File(original, "block").writeText("blocks rename")
            JSONObject().put("success", false)
        })
        assertFalse(result.replaced)
        assertEquals("original", File(root, "item/song.flac").readText())
        assertEquals(original.path, File(root, "item/original_path.txt").readText())
    }
    private fun orphan() {
        val dir = File(root, "item").apply { mkdirs() }
        File(dir, "song.flac").writeText("original")
        File(dir, "original_path.txt").writeText(original.path)
    }
    @Test fun `recoverOrphans restores backup when original missing`() {
        orphan(); FakeHiResGuard.recoverOrphans(root)
        assertEquals("original", original.readText())
        assertFalse(File(root, "item").exists())
    }
    @Test fun `recoverOrphans prefers backup when both exist`() {
        orphan(); original.writeText("unverified"); FakeHiResGuard.recoverOrphans(root)
        assertEquals("original", original.readText())
        assertFalse(File(root, "item").exists())
    }
    @Test fun `recoverOrphans retains backup if restore blocked`() {
        orphan(); original.mkdir(); File(original, "block").writeText("block")
        FakeHiResGuard.recoverOrphans(root)
        assertEquals("original", File(root, "item/song.flac").readText())
    }
    @Test fun `shouldCheck uses actual format and resolution`() {
        assertFalse(FakeHiResGuard.shouldCheck("s.flac", false, 16, 44100))
        assertFalse(FakeHiResGuard.shouldCheck("s.mp3", false, 24, 96000))
        assertFalse(FakeHiResGuard.shouldCheck("content://s.flac", false, 24, 96000))
        assertFalse(FakeHiResGuard.shouldCheck("s.flac", true, 24, 96000))
        assertFalse(FakeHiResGuard.shouldCheck("s.flac", false, null, null))
        assertTrue(FakeHiResGuard.shouldCheck("s.FLAC", false, 24, 44100))
        assertTrue(FakeHiResGuard.shouldCheck("s.wav", false, 16, 48000))
    }
}
