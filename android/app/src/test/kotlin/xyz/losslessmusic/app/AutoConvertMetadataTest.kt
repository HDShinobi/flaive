package xyz.losslessmusic.app

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException

class AutoConvertMetadataTest {
    @get:Rule val temp = TemporaryFolder()
    @Test fun `metadata ffmpeg failure is surfaced so auto conversion preserves source`() {
        val original = temp.newFile("song.converting.mp3").apply { writeText("audio") }
        val tagged = temp.newFile("tagged.mp3").apply { writeText("partial") }
        assertThrows(IOException::class.java) {
            NonFlacMetadataEmbedder.runAndReplace(emptyList(), tagged.path, original.path) { false }
        }
        assertEquals("audio", original.readText())
        assertFalse(tagged.exists())
    }
    @Test fun `M1 promotion failure preserves original and finished metadata output`() {
        val original = temp.newFile("song.m4a").apply { writeText("original") }
        val tagged = temp.newFile("tagged.m4a").apply { writeText("tagged") }
        assertThrows(IOException::class.java) {
            NonFlacMetadataEmbedder.runAndReplace(emptyList(), tagged.path, original.path,
                mover = { _, _, _ -> throw IOException("injected move failure") }) { true }
        }
        assertEquals("original", original.readText())
        assertEquals("tagged", tagged.readText())
    }
    @Test fun `metadata success promotes tagged file`() {
        val original = temp.newFile("song.converting.m4a").apply { writeText("audio") }
        val tagged = temp.newFile("tagged.m4a").apply { writeText("tagged audio") }
        NonFlacMetadataEmbedder.runAndReplace(emptyList(), tagged.path, original.path) { true }
        assertEquals("tagged audio", original.readText())
        assertFalse(tagged.exists())
    }
}
