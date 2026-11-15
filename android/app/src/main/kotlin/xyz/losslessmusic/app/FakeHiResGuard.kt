package xyz.losslessmusic.app

import java.io.File
import java.io.IOException
import java.util.logging.Level
import java.util.logging.Logger
import org.json.JSONObject

/** A same-filesystem backup remains authoritative until full PCM verification succeeds. */
object FakeHiResGuard {
    const val FALLBACK_QUALITY = "cd"
    private const val MANIFEST = "original_path.txt"
    private val log = Logger.getLogger("FakeHiResGuard")
    data class Result(val path: String, val replaced: Boolean)

    fun shouldCheck(path: String, alreadyExists: Boolean, bits: Int?, rate: Int?): Boolean =
        !alreadyExists && !path.startsWith("content://") &&
            File(path).extension.lowercase() in setOf("flac", "wav") &&
            ((bits ?: 0) > 16 || (rate ?: 0) > 44100)

    fun run(
        itemId: String, path: String, requestJson: String, backupRoot: File,
        check: (String, String) -> String, redownload: (String) -> JSONObject,
        isCancelled: () -> Boolean,
    ): Result {
        val kept = Result(path, false)
        var backup: File? = null
        var directory: File? = null
        var replacement: File? = null
        var committed = false
        try {
            if (isCancelled()) return kept
            val verdict = JSONObject(check(path, "{}"))
            if (verdict.has("error") || verdict.optString("verdict") != "fake_hires" ||
                verdict.opt("redownload_safe") != true) {
                log.info("Keeping original: $path; verdict=$verdict")
                return kept
            }
            if (isCancelled()) return kept
            val original = File(path).absoluteFile
            val dir = File(backupRoot, itemId).canonicalFile
            require(dir.parentFile == backupRoot.canonicalFile) { "Invalid backup item id" }
            // Never overwrite an unrecovered backup from an earlier attempt.
            require(!dir.exists()) { "Unrecovered backup: $dir" }
            if (!dir.mkdirs()) throw IOException("Cannot create backup: $dir")
            directory = dir
            // Write the recovery destination BEFORE the rename: a kill between
            // these operations must not leave an audio backup without its path.
            File(dir, MANIFEST).writeText(original.path)
            val saved = File(dir, original.name)
            if (!original.renameTo(saved)) throw IOException("Cannot back up $original")
            backup = saved
            val request = JSONObject(requestJson).put("quality", FALLBACK_QUALITY)
                .put("bypass_duplicate_check", true)
            val result = redownload(request.toString())
            val newPath = result.optString("file_path", "").trim()
            // already_exists belongs to the user and must never be cleaned up.
            if (result.optBoolean("already_exists", false)) return kept
            if (newPath.isNotEmpty() && !newPath.startsWith("content://")) {
                val candidate = File(newPath).canonicalFile
                if (candidate.toPath().startsWith(backupRoot.canonicalFile.toPath())) return kept
                replacement = candidate
            }
            val newFile = replacement
            if (!result.optBoolean("success", false) || newFile == null ||
                !newFile.isFile || isCancelled()) return kept
            val verified = JSONObject(check(saved.path,
                JSONObject().put("verify_replacement_path", newPath).toString()))
            if (verified.has("error") || verified.opt("replacement_equivalent") != true ||
                isCancelled()) return kept
            // A cleanup error must not restore an original after it was deleted.
            if (!saved.delete()) throw IOException("Cannot retire verified backup: $saved")
            committed = true
            return Result(newPath, true)
        } catch (e: Exception) {
            log.log(Level.WARNING, "Keeping original after Hi-Res check/replacement failed: $path", e)
            return kept
        } finally {
            val saved = backup
            if (!committed && saved != null) {
                try {
                    replacement?.let {
                        if (it.isFile && !it.delete()) log.warning("Cannot delete unverified replacement: $it")
                    }
                } catch (e: Exception) {
                    log.log(Level.WARNING, "Cannot remove unverified replacement", e)
                }
                // renameTo replaces a same-path unverified file without first
                // deleting it. Failure retains both the backup and manifest.
                if (restore(saved, File(path))) cleanup(directory)
            } else {
                cleanup(directory)
            }
        }
    }

    private fun cleanup(directory: File?) {
        try {
            if (directory != null && !directory.deleteRecursively()) {
                log.warning("Backup directory cleanup incomplete: $directory")
            }
        } catch (e: Exception) { log.log(Level.WARNING, "Backup directory cleanup failed", e) }
    }

    private fun restore(backup: File, original: File): Boolean = try {
        if (!backup.renameTo(original)) throw IOException("Cannot restore $backup to $original")
        true
    } catch (e: Exception) {
        log.log(Level.SEVERE, "Original retained in backup: $backup", e)
        false
    }

    fun recoverOrphans(backupRoot: File) {
        val directories = try { backupRoot.listFiles().orEmpty().filter { it.isDirectory } }
        catch (e: Exception) {
            log.log(Level.SEVERE, "Cannot list backups: $backupRoot", e)
            return
        }
        for (dir in directories) {
            try {
                val manifest = File(dir, MANIFEST)
                if (!manifest.isFile) continue
                val path = manifest.readText()
                if (path.isBlank() || !File(path).isAbsolute) continue
                val saved = File(dir, File(path).name)
                // Manifest-only means killed before rename or after verification.
                if (!saved.exists() || restore(saved, File(path))) dir.deleteRecursively()
            } catch (e: Exception) {
                log.log(Level.SEVERE, "Cannot recover backup: $dir", e)
            }
        }
    }
}
