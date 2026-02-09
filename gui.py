import os
from PyQt6.QtCore import pyqtSignal, Qt
from PyQt6.QtWidgets import QFrame, QLabel, QVBoxLayout, QFileDialog, QApplication, QWidget


class FileDropBox(QFrame):
    fileSelected = pyqtSignal(str, str)  # emits the file path and file extenstion

    def __init__(self, parent=None, dialogCaption="Select a file", fileFilter="All Files (*)", fileExtenstion=""):
        super().__init__(parent)
        self.dialogCaption = dialogCaption
        self.fileFilter = fileFilter
        self._path = ""
        self.fileExtenstion = fileExtenstion.lower()

        self.setAcceptDrops(True)
        self.setCursor(Qt.CursorShape.PointingHandCursor)

        self.setStyleSheet("""
        QFrame {
            border: 2px dashed #888;
            border-radius: 10px;
            background: transparent;
        }
        QFrame:hover {
            border-color: #555;
        }
        """)

        self.label = QLabel("Drop an app file here\nor click to browse")
        self.label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.label.setStyleSheet("border: none; color: #666;")  # important: no nested border

        layout = QVBoxLayout(self)
        layout.addWidget(self.label)

    def setPath(self, path: str):
        path = path.strip()
        if not path or not os.path.exists(path):
            return

        if path.replace("/", "")[-4:].lower() != self.fileExtenstion:
            # We gonna ignore these as we are looking for apps
            pass
        else:
            self._path = path
            self.label.setText(os.path.basename(path))
            self.fileSelected.emit(path, self.fileExtenstion)

    def path(self) -> str:
        return self._path

    # --- Drag & Drop ---
    def dragEnterEvent(self, event): # pyright: ignore[reportIncompatibleMethodOverride]
        if event.mimeData().hasUrls():
            # accept if any url is a local file
            for url in event.mimeData().urls():
                if url.isLocalFile():
                    event.acceptProposedAction()
                    self.label.setText("Drop it like its hot")
                    return
        event.ignore()

    def dragLeaveEvent(self, event): # pyright: ignore[reportIncompatibleMethodOverride]
        self.label.setText("Drop a file here\nor click to browse")

    def dropEvent(self, event): # pyright: ignore[reportIncompatibleMethodOverride]
        urls = event.mimeData().urls()
        if not urls:
            return

        # pick first local file
        for url in urls:
            if url.isLocalFile():
                self.setPath(url.toLocalFile())
                break

        self.label.setText(os.path.basename(self._path) if self._path else "Drop a file here\nor click to browse")
        event.acceptProposedAction()

    # --- Click to open dialog ---
    def mousePressEvent(self, event): # pyright: ignore[reportIncompatibleMethodOverride]
        if event.button() == Qt.MouseButton.LeftButton:
            file_path, _ = QFileDialog.getOpenFileName(
                self,
                self.dialogCaption,
                "",
                self.fileFilter
            )
            if file_path:
                self.setPath(file_path)
        super().mousePressEvent(event)

def onFileDrop(path: str, fileType: str):
    print(f"{fileType} File")

app = QApplication([])

# Create a window, and then show it
window = QWidget()
window.show()
window.setWindowTitle("Logo Liquify")

layout = QVBoxLayout(window)


appBundleDrop = FileDropBox(dialogCaption="Pick an app bundle", fileFilter="App Bundle (*.app);;All Files (*)", fileExtenstion=".app")
appBundleDrop.fileSelected.connect(onFileDrop)

layout.addWidget(appBundleDrop)
# Start the event loop
app.exec()
