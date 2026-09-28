# NOTICE

This is a **modified version** of ServerPackCreator. It is not the official build, and it is
not endorsed by or affiliated with the upstream author.

## Upstream

- Project: ServerPackCreator
- Author: Griefed
- Upstream source: https://github.com/Griefed/ServerPackCreator
- Version this build is derived from: **8.1.2**
- License: GNU Lesser General Public License v2.1 — see [LICENSE](LICENSE)

## Modifications

The following changes were made to the upstream 8.1.2 sources. Every change is confined to
startup behaviour; the server-pack generation logic is untouched.

| File | Change |
| --- | --- |
| `serverpackcreator-api/.../utilities/common/WebUtilities.kt` | Added a `WebUtilities.openConnection()` helper that applies a 5 s connect timeout and a 15 s read timeout, and routed the five existing HTTP call sites through it. Upstream used `URL.openConnection()` / `URL.openStream()` with the JVM default of *no* timeout, so an unresponsive host could block the calling thread indefinitely. |
| `serverpackcreator-api/.../versionmeta/VersionMeta.kt` | `checkManifest()` no longer issues a separate `isReachable()` HTTP GET before downloading a manifest — a single request now serves both purposes, halving the number of requests issued at startup. `updateManifest(File, URL)` now returns a `Boolean` so the caller can still report an unreachable host. |
| `serverpackcreator-api/.../ApiProperties.kt` | The fallback mod-list update (`updateFallback()`) is no longer executed on the calling thread during `loadProperties()`. It is scheduled on a daemon thread via `updateFallbackAsync()`; the lists are populated from local properties immediately and replaced if the remote lists differ. The list replacement now assigns a fresh `TreeSet` instead of mutating a shared one, avoiding a concurrent-modification hazard. |
| `serverpackcreator-api/.../ApiProperties.kt` | The fallback-list download now goes through `WebUtilities.openConnection()`, so it honours the timeouts above. |
| `serverpackcreator-app/.../updater/UpdateChecker.kt` | The initial GitHub release query, previously performed in the constructor, is now prefetched on a daemon thread and awaited via a `Future`. Callers that need the result still get it; startup no longer waits. |
| `serverpackcreator-app/.../gui/window/UpdateDialogs.kt` | The initial update check now runs on a background thread and updates the update button on the event-dispatch-thread when it completes, instead of blocking main-window construction. |
| `serverpackcreator-app/.../updater/versionchecker/VersionChecker.kt` | `getResponse()` now uses `WebUtilities.openConnection()` so update checks honour the timeouts above. |

### Rationale

On a slow or unreliable connection to GitHub and the various Maven repositories,
ServerPackCreator 8.1.2 spent roughly 13 seconds in blocking network calls before the main
window appeared — about 6.4 s of that with no splash screen displayed at all. Together with
the absent timeouts, an unreachable host could stall startup far longer than that. The changes
above move that work off the startup path and bound every network wait.

## Corresponding source

The complete corresponding source code for this build is published at:

    https://github.com/compound0921/ServerPackCreator-Patch

If you received this build without that source, the LGPL requires the distributor to provide
it on request.

## No warranty

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Lesser General Public License for more details.
