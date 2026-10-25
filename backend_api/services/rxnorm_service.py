from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, List, Optional, Set

import httpx
from rapidfuzz.distance import JaroWinkler

RXNORM_API_BASE = "https://rxnav.nlm.nih.gov/REST"


def _allowed_ttys() -> Set[str]:
    raw = os.getenv("RXNORM_ALLOWED_TTYS", "SCD,SBD,IN,BN")
    allowed = {token.strip().upper() for token in raw.split(",") if token.strip()}
    return allowed or {"SCD", "SBD", "IN", "BN"}


def _extract_name_items(payload: object) -> List[Dict[str, str]]:
    items: List[Dict[str, str]] = []

    def walk(node: object) -> None:
        if isinstance(node, str):
            value = node.strip()
            if value:
                items.append({"name": value, "rxcui": ""})
            return
        if isinstance(node, dict):
            name = node.get("name") or node.get("rxnorm_name") or node.get("display_name")
            if isinstance(name, str) and name.strip():
                rxcui = node.get("rxcui")
                tty_raw = node.get("tty") or node.get("term_type")
                items.append(
                    {
                        "name": name.strip(),
                        "rxcui": str(rxcui).strip() if rxcui is not None else "",
                        "tty": str(tty_raw).strip().upper() if tty_raw is not None else "",
                    }
                )
            for value in node.values():
                walk(value)
            return
        if isinstance(node, list):
            for child in node:
                walk(child)

    walk(payload)

    dedup: Dict[str, Dict[str, str]] = {}
    for item in items:
        key = item["name"].lower()
        if key not in dedup:
            dedup[key] = item
    return list(dedup.values())


def _load_local_rxnorm_items() -> List[Dict[str, str]]:
    local_path = os.getenv("RXNORM_LOCAL_PATH", "").strip()
    if not local_path:
        return []
    path = Path(local_path)
    if not path.exists() or not path.is_file():
        return []

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    return _extract_name_items(data)


_LOCAL_RXNORM_ITEMS = _load_local_rxnorm_items()


def local_rxnorm_match(term: str, threshold: float = 85.0) -> Optional[Dict[str, object]]:
    cleaned = term.strip()
    if not cleaned:
        return None
    if not _LOCAL_RXNORM_ITEMS:
        return None

    best_item: Optional[Dict[str, str]] = None
    best_score = 0.0
    allowed_ttys = _allowed_ttys()
    for item in _LOCAL_RXNORM_ITEMS:
        item_tty = str(item.get("tty") or "").upper()
        if item_tty and item_tty not in allowed_ttys:
            continue
        score = JaroWinkler.normalized_similarity(cleaned.lower(), item["name"].lower()) * 100.0
        if score > best_score:
            best_score = score
            best_item = item

    if best_item is None or best_score < threshold:
        return None

    return {
        "name": best_item["name"],
        "rxcui": best_item.get("rxcui", ""),
        "score": round(best_score, 2),
        "source": "rxnorm_local",
    }


def api_rxnorm_match(term: str, threshold: float = 85.0) -> Optional[Dict[str, object]]:
    cleaned = term.strip()
    if not cleaned:
        return None

    timeout = float(os.getenv("RXNORM_API_TIMEOUT_SECONDS", "4.0"))
    allowed_ttys = _allowed_ttys()
    try:
        with httpx.Client(timeout=timeout) as client:
            approx = client.get(
                f"{RXNORM_API_BASE}/approximateTerm.json",
                params={"term": cleaned, "maxEntries": 5},
            )
            approx.raise_for_status()
            payload = approx.json()
    except Exception:
        return None

    candidates = (payload.get("approximateGroup") or {}).get("candidate") or []
    best: Optional[Dict[str, object]] = None
    best_score = 0.0

    for candidate in candidates:
        rxcui = str((candidate or {}).get("rxcui") or "").strip()
        if not rxcui:
            continue

        canonical = cleaned
        tty = ""
        try:
            with httpx.Client(timeout=timeout) as client:
                properties = client.get(f"{RXNORM_API_BASE}/rxcui/{rxcui}/properties.json")
                properties.raise_for_status()
                body = properties.json()
            prop = body.get("properties") or {}
            if isinstance(prop.get("name"), str) and prop["name"].strip():
                canonical = prop["name"].strip()
            tty = str(prop.get("tty") or "").strip().upper()
        except Exception:
            continue

        if tty and tty not in allowed_ttys:
            continue

        similarity_score = JaroWinkler.normalized_similarity(cleaned.lower(), canonical.lower()) * 100.0
        if similarity_score > best_score:
            best_score = similarity_score
            best = {
                "name": canonical,
                "rxcui": rxcui,
                "score": round(similarity_score, 2),
                "source": "rxnorm_api",
                "tty": tty,
            }

    if best is None or best_score < threshold:
        return None
    return best


def resolve_rxnorm(term: str, threshold: float = 85.0) -> Optional[Dict[str, object]]:
    mode = os.getenv("RXNORM_LOOKUP_MODE", "both").strip().lower()

    if mode in ("local", "both"):
        local = local_rxnorm_match(term, threshold=threshold)
        if local is not None:
            return local

    if mode in ("api", "both"):
        api = api_rxnorm_match(term, threshold=threshold)
        if api is not None:
            return api

    return None
