# ServerPackCreator — improved build

A modified build of [ServerPackCreator](https://github.com/Griefed/ServerPackCreator) 8.1.2 with
a faster startup. See [NOTICE.md](NOTICE.md) for the exact list of changes and for the upstream
attribution.

The short version: upstream blocks the startup thread on several network calls to GitHub and
various Maven repositories, with no connect or read timeouts configured. On a slow connection
that is roughly 6 seconds of the application doing nothing at all before the splash screen
appears. This build moves that work off the startup path and bounds every network wait.

## Requirements

- **Windows**
- **Java 21 or newer.** The installer checks for one and tells you where to get it if you do
  not have it. It does not bundle or download a Java runtime itself.

You do **not** need to download any source code or build anything.

## Install

Download **`ServerPackCreator-Setup.bat`** and double-click it.

    https://github.com/compound0921/ServerPackCreator-CN/releases/latest/download/ServerPackCreator-Setup.bat

That single file is the whole installer. It asks where to install, checks for Java, downloads
the application, and creates the launchers and a Start Menu entry. No administrator rights are
needed.

The suggested location is `D:\ServerPackCreator`. On a machine without a writable `D:` drive
the suggestion falls back to `%LOCALAPPDATA%\ServerPackCreator`.

The download shows progress, so a slow connection does not look like a hang:

```
  [############------------------]  41%     29.8 / 72.5 MB     8.1 MB/s
```

> **Windows may warn you first.** A `.bat` file downloaded from the internet carries a "mark of
> the web" and SmartScreen will offer to block it. To allow it, right-click the file, choose
> **Properties**, tick **Unblock** at the bottom, then OK. You can read the whole installer
> first — it is a plain text file.

### Choosing where it goes

Just press Enter to accept the suggested location, or type another one. To skip the question —
from a command prompt, in the folder you saved the file to:

```
ServerPackCreator-Setup.bat -InstallDir "D:\ServerPackCreator"
```

Scripts and unattended runs should pass `-InstallDir`. When input is not a terminal the
question is skipped automatically and the default is used.

### Other options

```
ServerPackCreator-Setup.bat -JavaPath "C:\Program Files\Microsoft\jdk-21.0.8.9-hotspot\bin\java.exe"
ServerPackCreator-Setup.bat -JarPath ".\serverpackcreator-app.jar"
ServerPackCreator-Setup.bat -Uninstall
ServerPackCreator-Setup.bat -NoPause          (for scripts and CI; skips the final keypress)
ServerPackCreator-Setup.bat -help
```

## Use

Everything lives in a single folder, `<InstallDir>` — the application, the launchers and all
the working directories, with nothing nested inside:

```
D:\ServerPackCreator\
  serverpackcreator-app.jar
  ServerPackCreator.bat            GUI
  ServerPackCreator-CLI.bat        command line
  ServerPackCreator-WebService.bat web service
  NOTICE.md  LICENSE
  configs\  logs\  manifests\  modpacks\
  plugins\  server-packs\  server_files\  themes\  work\
```

That folder is ServerPackCreator's *home*. The launchers pass it explicitly with `--home`, so
the installation keeps working if you move the whole folder somewhere else.

## Uninstall

```
ServerPackCreator-Setup.bat -Uninstall -InstallDir "D:\ServerPackCreator"
```

Or just run the same file with `-Uninstall` if you installed to the default location. It
deletes the installation directory, the Start Menu entry, and the stored home-directory
preference. **Server packs and configurations inside the installation directory go with it** —
copy anything you want to keep first.

## Files in this directory

| File | Purpose |
| --- | --- |
| `ServerPackCreator-Setup.bat` | The installer. This is the one file users download. |
| `NOTICE.md` | LGPL notice: upstream attribution and the list of modifications. |
| `README.md` | This file. |
| `LICENSE` | LGPL-2.1 text, copied from the repository root. |
| `startup-speedup.patch` | The startup changes as a patch against upstream `8.1.2`. Verified to apply cleanly with `git apply`. |

`ServerPackCreator-Setup.bat` is self-contained: the first few lines are a batch bootstrap that
hands the rest of the file to PowerShell, so there is exactly one file to download and the whole
thing is readable in a text editor.

## Maintaining this on a fork (recommended)

This source tree is not a git repository, so it has no upstream history. Publishing it as a
standalone repo would work, but you would lose the ability to pull upstream fixes and would
have to hand-merge every future release.

Better: fork `Griefed/ServerPackCreator` on GitHub, clone your fork at tag `8.1.2`, apply the
patch, and commit.

```bash
git clone https://github.com/<you>/ServerPackCreator.git
cd ServerPackCreator
git checkout 8.1.2
git apply /path/to/packaging/startup-speedup.patch
git checkout -b faster-startup
git add -A && git commit -m "Move blocking network calls off the startup path"
git push -u origin faster-startup
```

Then copy `packaging/` into the fork and publish releases from there. Your modifications stay a
clean, reviewable diff on top of upstream, and `git merge upstream/main` keeps working.

> **Do not rename this folder to `dist/`.** Upstream's `.gitignore` has a root-anchored `/dist`
> rule, which would silently exclude every file in it from the repository.

## Building a release

For the maintainer. From the repository root:

```bash
# 1. Build the JAR. The -Pversion override matters: gradle.properties defaults to
#    version=dev, which makes the app think it is a development build.
JAVA_HOME="/c/Program Files/Microsoft/jdk-21.0.8.9-hotspot" \
  ./gradlew :serverpackcreator-app:bootJar -Pversion=8.1.2 -x test

# 2. Rename to the stable asset name the installer expects. The installer always
#    fetches /releases/latest/download/serverpackcreator-app.jar, so the asset name
#    must not contain the version - otherwise every new release breaks existing links.
cp serverpackcreator-app/build/libs/serverpackcreator-app-8.1.2.jar \
   serverpackcreator-app.jar

# 3. Publish all four assets together. The installer fetches every one of them from
#    /releases/latest/download/, so they must all be attached to the same release -
#    LICENSE and NOTICE.md included, because the installer has to place them next to
#    the application for the LGPL notice to travel with the binary.
gh release create v8.1.2 \
  serverpackcreator-app.jar \
  packaging/ServerPackCreator-Setup.bat \
  packaging/LICENSE \
  packaging/NOTICE.md \
  --title "8.1.2" --notes "See NOTICE.md for the changes in this build."
```

Users then get `.../releases/latest/download/ServerPackCreator-Setup.bat`, which resolves to the
newest release without anyone having to know the version number.

Note that `packaging/LICENSE` is the upstream LGPL-2.1 text kept in step with the repository
root. Upload the file from `packaging/` (or the identical one at the root) - they are copies of
each other.

## Licence

GNU Lesser General Public License v2.1 — see [LICENSE](LICENSE). This build is distributed
without any warranty. It is not the official ServerPackCreator release and is not endorsed by
its author.
