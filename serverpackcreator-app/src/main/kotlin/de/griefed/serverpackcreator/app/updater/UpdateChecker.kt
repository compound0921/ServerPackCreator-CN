/* Copyright (C) 2025 Griefed
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
 * USA
 *
 * The full license can be found at https:github.com/Griefed/ServerPackCreator/blob/main/LICENSE
 */
package de.griefed.serverpackcreator.app.updater

import de.griefed.serverpackcreator.api.ApiProperties
import de.griefed.serverpackcreator.app.updater.versionchecker.GitHubChecker
import de.griefed.serverpackcreator.app.updater.versionchecker.Update
import org.apache.logging.log4j.kotlin.cachedLoggerOf
import java.io.IOException
import java.util.*
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Initialize our GitHub and GitLab instances with the corresponding repository addresses, so we can
 * then run our update checks later on.
 *
 * @author Griefed
 */
class UpdateChecker(private val apiProperties: ApiProperties) {
    private val log by lazy { cachedLoggerOf(this.javaClass) }

    /**
     * The initial GitHub-check is performed in the background. Doing it in the constructor blocked
     * every startup until GitHub answered, even though nothing needs the result right away.
     *
     * Callers which do need it await this future via [gitHub].
     */
    private val gitHubPrefetch: Future<GitHubChecker?> =
        REFRESH_EXECUTOR.submit(Callable { initGitHub() })

    /**
     * Initialize our [GitHubChecker].
     *
     * @return The initialized checker, or `null` if GitHub could not be reached.
     * @author Griefed
     */
    private fun initGitHub(): GitHubChecker? = try {
        GitHubChecker("Griefed/ServerPackCreator").refresh()
    } catch (ex: IOException) {
        log.error(
            "Either GitHub is currently unreachable, or the GitHub user/repository you set resulted in a malformed URL. "
                    + ex.message
        )
        null
    }

    /**
     * Our [GitHubChecker], awaiting the background prefetch should it not have finished yet.
     *
     * @return Our [GitHubChecker], or `null` if GitHub could not be reached.
     * @author Griefed
     */
    private fun gitHub(): GitHubChecker? = try {
        gitHubPrefetch.get()
    } catch (ex: Exception) {
        log.error("Error acquiring GitHub-checker.", ex)
        null
    }

    /**
     * Refresh the GitHub, GitLab and GitGriefed instances, so we get the most current releases.
     *
     * @author Griefed
     */
    private fun refresh() {
        val checker = gitHub()
        if (checker == null) {
            log.warn("Not checking for updates. GitHub Checking not initialized.")
            return
        }
        try {
            checker.refresh()
        } catch (ex: Exception) {
            log.error("Error refreshing GitHub.", ex)
        }

    }

    /**
     * Check our GitLab, GitGriefed and GitHub instances for updates, sequentially, and then return
     * the update.
     *
     * @param version         The version for which to check for updates.
     * @param preReleaseCheck Whether to check pre-releasesDescending as well. Use `true` to
     * check pre-releasesDescending as well, `false` to only check with
     * regular releases.
     * @return The update, if available, as well as the download URL.
     * @author Griefed
     */
    fun checkForUpdate(version: String, preReleaseCheck: Boolean): Optional<Update> {
        val checker = gitHub()
        if (version.equals("dev", ignoreCase = true) || checker == null) {
            log.warn("Not checking for updates. Either using a dev-version, or GitHub Checking is not initialized.")
            return Optional.empty()
        }
        log.debug("Checking GitHub for updates...")
        return checker.check(version, preReleaseCheck)
    }

    /**
     * Check for update-availability. If an update is present, information about said update is
     * printed to the console.
     *
     * @param logToConsole Whether to log update information to console or to logs.
     * @author Griefed
     */
    fun updateCheck(logToConsole: Boolean = false): Boolean {
        refresh()
        val update: Optional<Update> = checkForUpdate(
            apiProperties.apiVersion,
            apiProperties.isCheckingForPreReleasesEnabled
        )
        if (logToConsole) {
            println()
            if (update.isPresent) {
                println("Update available!")
                println("    ${update.get().version()}")
                println("    ${update.get().url()}")
            } else {
                println("No updates available.")
            }
        } else {
            if (update.isPresent) {
                log.info("Update available!")
                log.info("    ${update.get().version()}")
                log.info("    ${update.get().url()}")
            } else {
                log.info("No updates available.")
            }
        }

        return update.isPresent
    }

    companion object {
        /**
         * Executor used to perform the initial GitHub-check in the background, so it does not block
         * the startup of ServerPackCreator.
         */
        private val REFRESH_EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "ServerPackCreator-update-check").apply { isDaemon = true }
        }
    }
}