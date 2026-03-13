import json
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
import plistlib
import os
import shutil


class IconHandler:
    ICON_SIZES = [
        ("16x16", 1, 16),
        ("16x16", 2, 32),
        ("32x32", 1, 32),
        ("32x32", 2, 64),
        ("128x128", 1, 128),
        ("128x128", 2, 256),
        ("256x256", 1, 256),
        ("256x256", 2, 512),
        ("512x512", 1, 512),
        ("512x512", 2, 1024),
    ]

    def __init__(
        self, appBundlePath: str, iconBundlePath: str, cliBased=True, verboseErrors=False, experimental=False
    ):
        """This class holds the functions to add a .icon file into a usable MacOS application

        Args:
            cliBased (bool, optional): Set False if this is the backend of a UI, leave as True for . Defaults to True.
            verboseErrors (bool, optional): Set True for verbose terminal messages. Please note, cliBased needs to be set as True.
            experimental (bool, optional): Set True to use the experimental path that passes
                the .icon file directly to actool. When False (default), uses the xcassets
                pipeline with sips resizing to match the build_macos_nuitka approach.
        """
        # Sets some variables that other functions use
        self.cliBased = cliBased
        self.verboseErrors = verboseErrors
        self.experimental = experimental

        self.appBundlePath = appBundlePath
        self.iconBundlePath = iconBundlePath
        self.iconName = Path(iconBundlePath).stem

        self.validateData()

        if self.experimental:
            self.compileIconExperimental(self.iconBundlePath)
            self.updateInfoPlist(f"{self.appBundlePath}/Contents/Info.plist")
            self.moveIconToAppExperimental()
        else:
            self.compileIcon(self.iconBundlePath)
            self.updateInfoPlist(f"{self.appBundlePath}/Contents/Info.plist")
            self.moveIconToApp()

        self.resignAppForLocalUse()

    def logMessage(self, simpleMessage, verboseMessage=""):
        """This function controls the logging. By using this instead of print or a log to file, we can change how all our logging works at once.

        Args:
            simpleMessage (str): A simple message that will show on the terminal if an error occurs to point the user in the right direction.
            verboseMessage (str, optional): A second message that shows after the simpleMessage. Only shows if verbose logs are enabled. Defaults to "".
        """

        if self.logMessage:
            print(simpleMessage)
            if self.verboseErrors and verboseMessage != "":
                print(f"    {verboseMessage}")

    def clearScreen(self):
        """Cleares the terminal"""
        subprocess.run(["clear"])

    def validateData(self, appBundlePath=""):
        """This function validates necessary requirements are installed, past python modules.

        Args:
            appBundlePath (str, optional): The path of the app bundle, leave blank to use the class defined variables. Defaults to "".
        """

        if appBundlePath == "":
            appBundlePath = self.appBundlePath

        self.clearScreen()

        # Check actool is mentioned
        actoolsCMD = subprocess.run(["actool"], capture_output=True, text=True)
        if (
            actoolsCMD.stderr
            == "Error: No arguments specified, please consult `man actool` in Terminal."
        ):
            actoolsInstalled = False
            self.logMessage(
                "Please install Xcode command line tools",
                'Error finding "actool" please ensure Xcode is fully installed. It may need a re-install.',
            )
        else:
            actoolsInstalled = True
            self.logMessage(
                "Xcode CLI Tools installed already.", "Actool has been located."
            )

        self.validatePath(f"{appBundlePath}/Contents")

    def validatePath(self, filePath):
        try:
            Path(filePath).resolve(strict=False)
            return True
        except (OSError, RuntimeError, ValueError) as e:
            self.logMessage(f"Error finding the path {filePath}", f"The error was: {e}")
            return False

    def compileIcon(self, iconPath):
        """Compile icon by extracting PNGs from .icon bundle, resizing with sips, and building xcassets."""
        iconPath = Path(iconPath)
        if not self.validatePath(str(iconPath)):
            return

        # Find the base PNG from the .icon bundle
        if iconPath.is_dir():
            pngs = list(iconPath.rglob("*.png"))
            if not pngs:
                self.logMessage(f"No PNG assets found inside icon bundle: {iconPath}")
                return
            basePng = max(pngs, key=lambda p: p.stat().st_size)
        else:
            basePng = iconPath

        if not basePng.is_file():
            self.logMessage(f"Base icon PNG not found: {basePng}")
            return

        sipsPath = shutil.which("sips")
        if not sipsPath:
            self.logMessage("sips not found; it is required to resize icon assets.")
            return

        actoolPath = shutil.which("actool")
        if not actoolPath:
            self.logMessage("actool not found. Install Xcode or Xcode Command Line Tools.")
            return

        # Clean and create staging directory
        try:
            shutil.rmtree("./OutputDir")
        except FileNotFoundError:
            pass
        os.mkdir("./OutputDir")

        with TemporaryDirectory() as tmpdir:
            xcassetsDir = Path(tmpdir) / "Assets.xcassets"
            appIconsetDir = xcassetsDir / f"{self.iconName}.appiconset"
            compiledDir = Path(tmpdir) / "compiled"
            appIconsetDir.mkdir(parents=True, exist_ok=True)
            compiledDir.mkdir(parents=True, exist_ok=True)

            # Resize base PNG to all required macOS icon sizes
            entries = []
            for sizeStr, scale, pixels in self.ICON_SIZES:
                dest = appIconsetDir / f"icon_{sizeStr}@{scale}x.png"
                subprocess.run(
                    [sipsPath, "-z", str(pixels), str(pixels), str(basePng), "--out", str(dest)],
                    capture_output=True, text=True,
                )
                entries.append({
                    "size": sizeStr, "idiom": "mac",
                    "scale": f"{scale}x", "filename": dest.name,
                })

            contentsJson = {"images": entries, "info": {"version": 1, "author": "xcode"}}
            (appIconsetDir / "Contents.json").write_text(json.dumps(contentsJson, indent=2))

            partialInfoPlist = compiledDir / "assetcatalog_generated_info.plist"
            actoolResult = subprocess.run(
                [
                    actoolPath, str(xcassetsDir),
                    "--compile", str(compiledDir),
                    "--platform", "macosx",
                    "--minimum-deployment-target", "13.0",
                    "--app-icon", self.iconName,
                    "--output-partial-info-plist", str(partialInfoPlist),
                ],
                capture_output=True, text=True,
            )

            self.logMessage(
                "Icon compiled via xcassets pipeline",
                f"stdout: {actoolResult.stdout}\n\nstderr: {actoolResult.stderr}",
            )

            compiledCar = compiledDir / "Assets.car"
            if not compiledCar.is_file():
                self.logMessage("actool did not produce Assets.car; ensure the .icon file is valid.")
                return

            # Stage Assets.car for moveIconToApp
            shutil.copy2(compiledCar, "./OutputDir/Assets.car")

        self.logMessage("Assets.car staged in ./OutputDir")

    def compileIconExperimental(self, iconPath):
        """[Experimental] Pass .icon file directly to actool without manual PNG extraction."""
        try:
            shutil.rmtree("./OutputDir")
        except FileNotFoundError:
            pass
        os.mkdir("./OutputDir")

        if not self.validatePath(iconPath):
            return

        actoolResponse = subprocess.run(
            [
                "actool",
                iconPath,
                "--compile",
                "./OutputDir",
                "--app-icon",
                self.iconName,
                "--platform",
                "macosx",
                "--output-partial-info-plist",
                "assetcatalog_generated_info.plist",
                "--minimum-deployment-target",
                "26.0",
                "--enable-on-demand-resources",
                "NO",
                "--include-all-app-icons",
            ],
            capture_output=True,
            text=True,
        )

        self.logMessage(
            "Icon compiled in ./OutputDir",
            f"stdout: {actoolResponse.stdout}\n\nstderr: {actoolResponse.stderr}",
        )

        path = "./OutputDir"
        files = os.listdir(path)
        for index, file in enumerate(files):
            old_path = os.path.join(path, file)

            name, ext = os.path.splitext(file)
            new_name = f"AppIcon{ext}"

            new_path = os.path.join(path, new_name)

            if ext != ".car":
                os.rename(old_path, new_path)

    def findInfoPlist(self, bundlePath):
        pass

    def updateInfoPlist(self, infoPlistPath, fallbackIconFile=""):
        """Set icon metadata without disturbing other plist keys."""
        with open(infoPlistPath, "rb") as plistFile:
            plistData = plistlib.load(plistFile)

        plistData["CFBundleIconName"] = self.iconName
        if fallbackIconFile:
            plistData["CFBundleIconFile"] = fallbackIconFile

        with open(infoPlistPath, "wb") as plistFile:
            plistlib.dump(plistData, plistFile)

    def moveIconToApp(self, appBundlePath=""):
        """Copy only Assets.car into the app bundle's Resources directory."""
        if appBundlePath == "":
            appBundlePath = self.appBundlePath

        resourcesDir = Path(appBundlePath) / "Contents" / "Resources"
        if not resourcesDir.is_dir():
            self.logMessage(f"Resources directory not found: {resourcesDir}")
            return

        stagedCar = Path("./OutputDir/Assets.car")
        if not stagedCar.is_file():
            self.logMessage("No Assets.car found in OutputDir; compile step may have failed.")
            return

        targetCar = resourcesDir / "Assets.car"
        shutil.copy2(stagedCar, targetCar)
        self.logMessage(f"Copied Assets.car to {targetCar}")

        # Clean up staging directory
        try:
            shutil.rmtree("./OutputDir")
        except FileNotFoundError:
            pass

    def moveIconToAppExperimental(self, appBundlePath=""):
        """[Experimental] Replace all resources with compiled output."""
        if appBundlePath == "":
            appBundlePath = self.appBundlePath

        allOldFiles = os.listdir(f"{appBundlePath}/Contents/Resources")
        try:
            os.mkdir(f"{appBundlePath}/Contents/Resources/oldFiles")
        except FileExistsError:
            pass
        for f in allOldFiles:
            if "oldFiles" not in f:
                shutil.move(
                    f"{appBundlePath}/Contents/Resources/{f}",
                    f"{appBundlePath}/Contents/Resources/oldFiles/{f}",
                )

        allFiles = os.listdir("./OutputDir")
        for f in allFiles:
            shutil.move(f"./OutputDir/{f}", f"{appBundlePath}/Contents/Resources/{f}")

    def resignAppForLocalUse(self, appBundlePath="", identity="-"):
        """Remove stale signatures and re-sign the app bundle for local use.

        Args:
            appBundlePath (str, optional): Override bundle path; defaults to class value.
            identity (str, optional): codesign identity, '-' for ad-hoc. Defaults to '-'.

        Returns:
            bool: True on success, False if codesign is unavailable or fails.
        """

        if appBundlePath == "":
            appBundlePath = self.appBundlePath

        bundlePath = Path(appBundlePath)
        if not self.validatePath(bundlePath):
            return False

        codesignPath = shutil.which("codesign")
        if not codesignPath:
            self.logMessage(
                "codesign not found. Please install Xcode Command Line Tools.",
                "Install Xcode or run `xcode-select --install`.",
            )
            return False

        # Remove existing signature to avoid validation errors after modifications
        codeSigDir = bundlePath / "Contents" / "_CodeSignature"
        if codeSigDir.exists():
            shutil.rmtree(codeSigDir, ignore_errors=True)

        # Clean extended attributes that can break codesign
        xattrPath = shutil.which("xattr")
        if xattrPath:
            subprocess.run([xattrPath, "-cr", str(bundlePath)], capture_output=True)

        cmd = [codesignPath, "--force", "--deep", "--sign", identity, str(bundlePath)]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            self.logMessage(
                "Failed to re-sign the application.",
                f"stdout: {result.stdout}\n\nstderr: {result.stderr}",
            )
            return False

        self.logMessage(
            "App re-signed for local use.",
            f"stdout: {result.stdout}\n\nstderr: {result.stderr}",
        )

        # Verify the signature
        verifyResult = subprocess.run(
            [codesignPath, "--verify", "--deep", "--strict", str(bundlePath)],
            capture_output=True, text=True,
        )
        if verifyResult.returncode != 0:
            self.logMessage(
                "Codesign verification failed.",
                f"stdout: {verifyResult.stdout}\n\nstderr: {verifyResult.stderr}",
            )
        else:
            self.logMessage("Codesign verification succeeded.")

        return True

if __name__ == "__main__":
    IconHandler("path/to/your.app", "path/to/your.icon")
