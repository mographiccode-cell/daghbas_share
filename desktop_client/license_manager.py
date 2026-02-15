import hashlib
import json
from pathlib import Path
import platform
import uuid

import requests

from .api_client import ApiError


LICENSE_PATH = Path.home() / ".daghbas_share_license.json"


def generate_device_id() -> str:
    raw = f"{platform.system()}-{platform.node()}-{uuid.getnode()}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def load_license() -> dict | None:
    if not LICENSE_PATH.exists():
        return None
    try:
        return json.loads(LICENSE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return None


def save_license(data: dict) -> None:
    LICENSE_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def validate_license(base_url: str, device_id: str, license_token: str) -> tuple[bool, str]:
    try:
        res = requests.post(
            f"{base_url.rstrip('/')}/installations/validate",
            json={"device_id": device_id, "license_token": license_token},
            timeout=10,
        )
    except requests.exceptions.Timeout as exc:
        raise ApiError("انتهت مهلة التحقق من الترخيص", endpoint="/installations/validate", details=str(exc)) from exc
    except requests.exceptions.ConnectionError as exc:
        raise ApiError(
            "تعذر الوصول إلى خادم التحقق من الترخيص",
            endpoint="/installations/validate",
            details=str(exc),
        ) from exc
    except requests.exceptions.RequestException as exc:
        raise ApiError("فشل طلب التحقق من الترخيص", endpoint="/installations/validate", details=str(exc)) from exc

    if res.status_code != 200:
        raise ApiError(
            "فشل التحقق من الترخيص",
            status_code=res.status_code,
            endpoint="/installations/validate",
            details=res.text[:300],
        )

    body = res.json()
    return bool(body.get("valid")), body.get("message", "")
