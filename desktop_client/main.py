import logging
import sys
from pathlib import Path

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFont, QFontDatabase
from PyQt6.QtWidgets import (
    QApplication,
    QLabel,
    QLineEdit,
    QListWidget,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from .api_client import ApiClient, ApiError
from .license_manager import generate_device_id, load_license, save_license, validate_license

LOG_PATH = Path.home() / "daghbas_share_client.log"
logging.basicConfig(filename=LOG_PATH, level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")


def format_error(exc: Exception, context: str) -> str:
    if isinstance(exc, ApiError):
        return f"{context}\n{exc}"
    return f"{context}\n{type(exc).__name__}: {exc}"


class ActivationWindow(QWidget):
    def __init__(self, api: ApiClient, device_id: str, on_success):
        super().__init__()
        self.api = api
        self.device_id = device_id
        self.on_success = on_success
        self.setWindowTitle("تفعيل الجهاز - Daghbas Share")
        self.setMinimumWidth(500)

        layout = QVBoxLayout()
        title = QLabel("تفعيل الجهاز لأول مرة")
        title.setStyleSheet("font-size:18px;font-weight:700;")
        layout.addWidget(title)

        layout.addWidget(QLabel(f"معرّف الجهاز: {device_id}"))

        layout.addWidget(QLabel("اسم العميل/الشركة"))
        self.customer_name = QLineEdit()
        self.customer_name.setPlaceholderText("مثال: شركة الدغباس")
        layout.addWidget(self.customer_name)

        layout.addWidget(QLabel("مفتاح الشركة للتفعيل (للمسؤول فقط)"))
        self.master_key = QLineEdit()
        self.master_key.setEchoMode(QLineEdit.EchoMode.Password)
        layout.addWidget(self.master_key)

        self.error_label = QLabel("")
        self.error_label.setStyleSheet("color:#b00020;")
        self.error_label.setWordWrap(True)
        layout.addWidget(self.error_label)

        self.activate_btn = QPushButton("تفعيل")
        self.activate_btn.clicked.connect(self.activate)
        layout.addWidget(self.activate_btn)
        self.setLayout(layout)

    def activate(self):
        self.activate_btn.setEnabled(False)
        self.error_label.setText("")
        try:
            response = self.api.activate_device(
                self.device_id,
                self.customer_name.text().strip() or "Unknown Customer",
                self.master_key.text().strip(),
            )
            save_license(response)
            QMessageBox.information(self, "تم", "تم تفعيل الجهاز بنجاح")
            self.on_success()
            self.close()
        except Exception as exc:
            logging.exception("Activation failed")
            msg = format_error(exc, "فشل تفعيل الجهاز")
            self.error_label.setText(msg)
        finally:
            self.activate_btn.setEnabled(True)


class LoginWindow(QWidget):
    def __init__(self, api: ApiClient, device_id: str, on_success):
        super().__init__()
        self.api = api
        self.device_id = device_id
        self.on_success = on_success
        self.setWindowTitle("تسجيل الدخول - نظام المشاركة الداخلي")
        self.setMinimumWidth(460)

        layout = QVBoxLayout()
        title = QLabel("مرحبًا بك في نظام المشاركة الداخلي")
        title.setStyleSheet("font-size:18px;font-weight:700;")
        layout.addWidget(title)

        layout.addWidget(QLabel("اسم المستخدم"))
        self.username = QLineEdit()
        self.username.setPlaceholderText("admin")
        layout.addWidget(self.username)

        layout.addWidget(QLabel("كلمة المرور"))
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.password.setPlaceholderText("admin123")
        layout.addWidget(self.password)

        self.error_label = QLabel("")
        self.error_label.setStyleSheet("color:#b00020;")
        self.error_label.setWordWrap(True)
        layout.addWidget(self.error_label)

        self.login_btn = QPushButton("دخول")
        self.login_btn.clicked.connect(self.handle_login)
        layout.addWidget(self.login_btn)
        self.setLayout(layout)

    def handle_login(self):
        self.login_btn.setEnabled(False)
        self.error_label.setText("")
        try:
            self.api.login(self.username.text().strip(), self.password.text().strip(), self.device_id)
            self.on_success()
            self.close()
        except Exception as exc:
            logging.exception("Login failed")
            self.error_label.setText(format_error(exc, "فشل تسجيل الدخول"))
        finally:
            self.login_btn.setEnabled(True)


class DashboardWindow(QMainWindow):
    def __init__(self, api: ApiClient):
        super().__init__()
        self.api = api
        self.setWindowTitle("لوحة التحكم - إدارة الملفات والمهام")
        self.resize(980, 640)

        tabs = QTabWidget()
        tabs.addTab(self._build_folders_tab(), "المجلدات")
        tabs.addTab(self._build_tasks_tab(), "مهامي")

        container = QWidget()
        layout = QVBoxLayout()
        layout.addWidget(tabs)
        container.setLayout(layout)
        self.setCentralWidget(container)

    def _build_folders_tab(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout()
        self.folders_list = QListWidget()
        self.folder_error = QLabel("")
        self.folder_error.setStyleSheet("color:#b00020;")
        self.folder_error.setWordWrap(True)
        refresh_btn = QPushButton("تحديث المجلدات")
        refresh_btn.clicked.connect(self.load_folders)
        layout.addWidget(refresh_btn)
        layout.addWidget(self.folder_error)
        layout.addWidget(self.folders_list)
        widget.setLayout(layout)
        return widget

    def _build_tasks_tab(self) -> QWidget:
        widget = QWidget()
        layout = QVBoxLayout()
        self.tasks_list = QListWidget()
        self.task_error = QLabel("")
        self.task_error.setStyleSheet("color:#b00020;")
        self.task_error.setWordWrap(True)
        refresh_btn = QPushButton("تحديث المهام")
        refresh_btn.clicked.connect(self.load_tasks)
        layout.addWidget(refresh_btn)
        layout.addWidget(self.task_error)
        layout.addWidget(self.tasks_list)
        widget.setLayout(layout)
        return widget

    def load_folders(self):
        self.folders_list.clear()
        self.folder_error.setText("")
        try:
            for folder in self.api.get_folders():
                parent = folder.get("parent_id")
                parent_text = f" (الأب: {parent})" if parent else ""
                self.folders_list.addItem(f"{folder['name']}  |  #{folder['id']}{parent_text}")
            if self.folders_list.count() == 0:
                self.folders_list.addItem("لا توجد مجلدات حتى الآن")
        except Exception as exc:
            logging.exception("Load folders failed")
            self.folder_error.setText(format_error(exc, "تعذر تحميل المجلدات"))

    def load_tasks(self):
        self.tasks_list.clear()
        self.task_error.setText("")
        try:
            for task in self.api.my_tasks():
                self.tasks_list.addItem(f"{task['title']} - الحالة: {task['status']}")
            if self.tasks_list.count() == 0:
                self.tasks_list.addItem("لا توجد مهام مسندة لك")
        except Exception as exc:
            logging.exception("Load tasks failed")
            self.task_error.setText(format_error(exc, "تعذر تحميل المهام"))


def setup_arabic_theme(app: QApplication):
    app.setLayoutDirection(Qt.LayoutDirection.RightToLeft)
    font_path = Path("assets/fonts/IBMPlexSansArabic-Regular.ttf")
    if font_path.exists():
        font_id = QFontDatabase.addApplicationFont(str(font_path))
        families = QFontDatabase.applicationFontFamilies(font_id)
        if families:
            app.setFont(QFont(families[0], 11))
            return
    app.setFont(QFont("IBM Plex Sans Arabic", 11))


def run():
    app = QApplication(sys.argv)
    setup_arabic_theme(app)

    api = ApiClient()
    device_id = generate_device_id()
    dashboard = DashboardWindow(api)

    def show_dashboard():
        dashboard.show()
        dashboard.load_folders()
        dashboard.load_tasks()

    def open_login():
        login = LoginWindow(api, device_id, show_dashboard)
        login.show()
        return login

    try:
        license_data = load_license()
        if not license_data:
            activation = ActivationWindow(api, device_id, open_login)
            activation.show()
            sys.exit(app.exec())

        valid, message = validate_license(api.base_url, device_id, license_data.get("license_token", ""))
        if not valid:
            QMessageBox.critical(None, "خطأ التفعيل", f"الترخيص غير صالح: {message}")
            activation = ActivationWindow(api, device_id, open_login)
            activation.show()
            sys.exit(app.exec())

        _login_window = open_login()
        sys.exit(app.exec())
    except Exception as exc:
        logging.exception("Fatal startup error")
        QMessageBox.critical(None, "خطأ فادح", format_error(exc, "تعذر تشغيل التطبيق"))
        sys.exit(1)


if __name__ == "__main__":
    run()
