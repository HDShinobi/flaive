package xyz.losslessmusic.app

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.util.concurrent.ConcurrentHashMap
import java.util.logging.Level
import java.util.logging.Logger
import org.json.JSONObject

/** A same-filesystem backup remains authoritative until full PCM verification succeeds. */
object FakeHiResGuard {
    const val FALLBACK_QUALITY = "cd"
    private const val MANIFEST = "original_path.txt"
    // Shared by worker instances, including a stopped worker with a blocking download.
    // The monitor makes reservation and orphan recovery atomic with each other.
    private val activeBackups = ConcurrentHashMap.newKeySet<String>()
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
        var reservation: String? = null
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
            synchronized(activeBackups) {
                require(activeBackups.add(dir.path)) { "Backup already active: $dir" }
                reservation = dir.path
                // Never overwrite an unrecovered backup from an earlier attempt.
                require(!dir.exists()) { "Unrecovered backup: $dir" }
                if (!dir.mkdirs()) throw IOException("Cannot create backup: $dir")
                directory = dir
            }
            // Write the recovery destination BEFORE the rename: a kill between
            // these operations must not leave an audio backup without its path.
            File(dir, MANIFEST).writeText(original.path)
            val saved = File(dir, original.name)
            if (!original.renameTo(saved)) throw IOException("Cannot back up $original")
            backup = saved
            val request = JSONObject(requestJson).put("quality", FALLBACK_QUALITY)
                .put("bypass_duplicate_check", true)
            // The callback can return an arbitrary output path. Snapshot existing
            // paths before calling it; never infer ownership from success alone.
            val canonicalRoot = backupRoot.canonicalFile
            val outputRoot = File(request.getString("output_dir").also {
                require(it.isNotBlank()) { "Missing output directory" }
            }).canonicalFile
            val excludedTrees = mutableListOf(canonicalRoot.toPath())
            val existingPaths = outputRoot.walkTopDown()
                .onEnter {
                    val canonical = it.canonicalFile.toPath()
                    if (canonical.startsWith(canonicalRoot.toPath()) || Files.isSymbolicLink(it.toPath())) {
                        excludedTrees.add(canonical)
                        false
                    } else true
                }
                .onFail { dir, error ->
                    // Contents of an unlistable tree have unknown ownership.
                    excludedTrees.add(dir.canonicalFile.toPath())
                    log.log(Level.WARNING, "Skipping unreadable output directory: $dir", error)
                }
                .map { it.canonicalPath }.toHashSet()
            val result = redownload(request.toString())
            val newPath = result.optString("file_path", "").trim()
            // already_exists belongs to the user and must never be cleaned up.
            if (result.optBoolean("already_exists", false)) return kept
            if (newPath.isNotEmpty() && !newPath.startsWith("content://")) {
                val candidate = File(newPath).canonicalFile
                if (candidate.toPath().startsWith(backupRoot.canonicalFile.toPath())) return kept
                val isOriginal = candidate == original.canonicalFile
                val isNewOutput = result.optBoolean("success", false) &&
                    candidate.toPath().startsWith(outputRoot.toPath()) &&
                    excludedTrees.none { candidate.toPath().startsWith(it) } &&
                    candidate.path !in existingPaths
                if (isOriginal || isNewOutput) replacement = candidate
                // Existing distinct files may be verified, but are never owned
                // by this transaction and must survive a failed verification.
                if (!result.optBoolean("success", false) || !candidate.isFile || isCancelled()) return kept
                val verified = JSONObject(check(saved.path,
                    JSONObject().put("verify_replacement_path", newPath).toString()))
                if (verified.has("error") || verified.opt("replacement_equivalent") != true ||
                    isCancelled()) return kept
            } else {
                return kept
            }
            // A cleanup error must not restore an original after it was deleted.
            if (!saved.delete()) throw IOException("Cannot retire verified backup: $saved")
            committed = true
            return Result(newPath, true)
        } catch (e: Exception) {
            log.log(Level.WARNING, "Keeping original after Hi-Res check/replacement failed: $path", e)
            return kept
        } finally {
            try {
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
            } finally {
                reservation?.let { activeBackups.remove(it) }
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
        val canonicalRoot: File
        val downloadRoot: java.nio.file.Path
        val directories = try {
            canonicalRoot = backupRoot.canonicalFile
            // Preserve the requested root boundary even if .fake-hires is a symlink.
            downloadRoot = requireNotNull(backupRoot.absoluteFile.parentFile).canonicalFile.toPath()
            backupRoot.listFiles().orEmpty().filter { it.isDirectory }
        }
        catch (e: Exception) {
            log.log(Level.SEVERE, "Cannot list backups: $backupRoot", e)
            return
        }
        for (dir in directories) {
            try {
                synchronized(activeBackups) {
                    if (dir.canonicalPath in activeBackups) return@synchronized
                    // Do not follow a planted item-directory or manifest symlink.
                    if (Files.isSymbolicLink(dir.toPath())) return@synchronized
                    val manifest = File(dir, MANIFEST)
                    if (!Files.isRegularFile(manifest.toPath(), NOFOLLOW_LINKS)) return@synchronized
                    val path = manifest.readText()
                    if (path.isBlank() || !File(path).isAbsolute) return@synchronized
                    val original = File(path).canonicalFile
                    if (!original.toPath().startsWith(downloadRoot) ||
                        original.toPath().startsWith(canonicalRoot.toPath()) ||
                        original.extension.lowercase() !in setOf("flac", "wav")) return@synchronized
                    val saved = File(dir, File(path).name)
                    // Invalid or missing backups are left untouched for inspection.
                    if (saved.extension.lowercase() !in setOf("flac", "wav") ||
                        Files.isSymbolicLink(saved.toPath()) ||
                        !Files.isRegularFile(saved.toPath(), NOFOLLOW_LINKS)) return@synchronized
                    if (restore(saved, original)) dir.deleteRecursively()
                }
            } catch (e: Exception) {
                log.log(Level.SEVERE, "Cannot recover backup: $dir", e)
            }
        }
    }
}
