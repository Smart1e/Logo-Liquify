import subprocess
from pathlib import Path
import plistlib
import os
import shutil


class IconHandler:
    def __init__(
        self, appBundlePath, iconBundlePath, cliBased=True, verboseErrors=False
    ):
        """This class holds the functions to add a .icon file into a usable MacOS application

        Args:
            cliBased (bool, optional): Set False if this is the backend of a UI, leave as True for . Defaults to True.
            verboseErrors (bool, optional): Set True for verbose terminal messages. Please note, cliBased needs to be set as True.
        """
        # Sets some variables that other functions use
        self.cliBased = cliBased
        self.verboseErrors = verboseErrors

        self.appBundlePath = appBundlePath
        self.iconBundlePath = iconBundlePath

        self.validateData()

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
        try:
            shutil.rmtree("./OutputDir")
        except FileNotFoundError:
            # The directory does not exist so we can move straight to creating one
            pass
        os.mkdir("./OutputDir")

        if not self.validatePath(iconPath):
            # The path was reported as not valid
            return

        # If we are here the path worked, and now we run actool
        self.iconName = iconPath.split("/")[-1].split(".")[0]
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

            name, ext = os.path.splitext(file)  # keeps original extension
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
        if appBundlePath == "":
            appBundlePath = self.appBundlePath

        allOldFiles = os.listdir(f"{appBundlePath}/Contents/Resources")
        try:
            os.mkdir(f"{appBundlePath}/Contents/Resources/oldFiles")
        except FileExistsError:
            # Script has probs already ran but we canc ontinue
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
        return True


IconHandler("path/to/your.app", "path/to/your.icon")
