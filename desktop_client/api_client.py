from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any

import requests


@dataclass
class ApiError(Exception):
    message: str
    status_code: int | None = None
    endpoint: str | None = None
    details: str | None = None

    def __str__(self) -> str:
        parts = [self.message]
        if self.status_code is not None:
            parts.append(f"status={self.status_code}")
        if self.endpoint:
            parts.append(f"endpoint={self.endpoint}")
        if self.details:
            parts.append(f"details={self.details}")
        return " | ".join(parts)


class ApiClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8000"):
        self.base_url = base_url.rstrip("/")
        self.access_token: str | None = None
        self.refresh_token: str | None = None

    def _headers(self) -> dict[str, str]:
        headers = {"Accept": "application/json"}
        if self.access_token:
            headers["Authorization"] = f"Bearer {self.access_token}"
        return headers

    def _request(self, method: str, endpoint: str, **kwargs: Any) -> Any:
        url = f"{self.base_url}{endpoint}"
        try:
            response = requests.request(method, url, timeout=12, **kwargs)
        except requests.exceptions.Timeout as exc:
            raise ApiError(
                message="انتهت مهلة الاتصال بالخادم",
                endpoint=endpoint,
                details=str(exc),
            ) from exc
        except requests.exceptions.ConnectionError as exc:
            raise ApiError(
                message="تعذر الاتصال بالخادم (تحقق من الشبكة أو SERVER_IP)",
                endpoint=endpoint,
                details=str(exc),
            ) from exc
        except requests.exceptions.RequestException as exc:
            raise ApiError(message="خطأ غير متوقع أثناء الاتصال", endpoint=endpoint, details=str(exc)) from exc

        if response.status_code >= 400:
            details = None
            try:
                payload = response.json()
                details = payload.get("detail") or json.dumps(payload, ensure_ascii=False)
            except ValueError:
                details = response.text[:300]
            raise ApiError(
                message="فشل الطلب من الخادم",
                status_code=response.status_code,
                endpoint=endpoint,
                details=details,
            )

        try:
            return response.json()
        except ValueError:
            return response.text

    def login(self, username: str, password: str, device_id: str = "pyqt-desktop") -> dict[str, Any]:
        data = self._request(
            "POST",
            "/login",
            json={"username": username, "password": password, "device_id": device_id},
        )
        self.access_token = data.get("access_token")
        self.refresh_token = data.get("refresh_token")
        return data

    def activate_device(self, device_id: str, customer_name: str, master_key: str) -> dict[str, Any]:
        return self._request(
            "POST",
            "/installations/activate",
            json={"device_id": device_id, "customer_name": customer_name},
            headers={"X-Master-Key": master_key},
        )

    def get_folders(self) -> list[dict[str, Any]]:
        return self._request("GET", "/folders", headers=self._headers())

    def my_tasks(self) -> list[dict[str, Any]]:
        return self._request("GET", "/tasks/my", headers=self._headers())
