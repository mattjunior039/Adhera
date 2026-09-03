from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Dict, List, Optional

from rapidfuzz.distance import JaroWinkler

try:
    from backend_api.services.rxnorm_service import resolve_rxnorm
except ImportError:
    from services.rxnorm_service import resolve_rxnorm


KNOWN_DRUG_NAMES: List[str] = [
    "Fukitol",
    "Metformin",
    "Lisinopril",
    "Levothyroxine",
    "Atorvastatin",
    "Amlodipine",
    "Omeprazole",
    "Losartan",
    "Albuterol",
    "Amoxicillin",
    "Sertraline",
    "Gabapentin",
    "Hydrochlorothiazide",
    "Prednisone",
    "Ibuprofen",
    "Acetaminophen",
    "Azithromycin",
    "Simvastatin",
    "Warfarin",
    "Insulin Glargine",
]

CLINICAL_STOPWORDS = {
    "daily",
    "tablet",
    "tablets",
    "capsule",
    "capsules",
    "mouth",
    "times",
    "needed",
    "refill",
    "refills",
    "qty",
    "take",
    "by",
    "as",
    "to",
    "of",
    "and",
}


@dataclass(frozen=True)
class DrugMatchResult:
    raw_name: str
    snapped_name: str
    score: float
    matched: bool
    confidence: str
    source: str
    rxcui: str


def _name_tokens(value: str) -> list[str]:
    return re.findall(r"[a-zA-Z]+", value.lower())


def _looks_like_instruction_or_admin_text(raw: str) -> bool:
    cleaned = raw.strip().lower()
    if not cleaned:
        return True
    if cleaned.startswith("dr ") or cleaned.startswith("dr."):
        return True
    if any(marker in cleaned for marker in ("as needed", "by mouth", "times daily", "refill", "qty", "rx #")):
        return True

    tokens = _name_tokens(cleaned)
    if not tokens:
        return True
    non_stop = [t for t in tokens if t not in CLINICAL_STOPWORDS]
    # Require at least one clinically plausible token.
    return len(non_stop) == 0


def _apply_single_token_penalty(query: str, candidate: str, score: float) -> float:
    query_tokens = _name_tokens(query)
    candidate_tokens = _name_tokens(candidate)
    has_dose_context = bool(re.search(r"\b\d+(?:\.\d+)?\s*(mg|mcg|g|ml|iu|units?)\b", query.lower()))
    if len(query_tokens) == 1 and len(candidate_tokens) > 1 and not has_dose_context:
        return max(0.0, score - 8.0)
    return score


def _best_local_match(cleaned: str) -> tuple[str, float]:
    best_name = cleaned
    best_score = 0.0
    for candidate in KNOWN_DRUG_NAMES:
        score = JaroWinkler.normalized_similarity(cleaned.lower(), candidate.lower()) * 100.0
        score = _apply_single_token_penalty(cleaned, candidate, score)
        if score > best_score:
            best_score = score
            best_name = candidate
    return best_name, best_score


def validate_drug_name(raw_name: Optional[str], threshold: float = 85.0) -> DrugMatchResult:
    cleaned = (raw_name or "").strip()
    if not cleaned:
        return DrugMatchResult(
            raw_name="",
            snapped_name="",
            score=0.0,
            matched=False,
            confidence="low",
            source="none",
            rxcui="",
        )

    if _looks_like_instruction_or_admin_text(cleaned):
        return DrugMatchResult(
            raw_name=cleaned,
            snapped_name=cleaned,
            score=0.0,
            matched=False,
            confidence="low",
            source="blocked_stopwords",
            rxcui="",
        )

    local_name, local_score = _best_local_match(cleaned)
    rxnorm = resolve_rxnorm(cleaned, threshold=threshold)

    best_name = local_name
    best_score = local_score
    source = "local_dictionary"
    rxcui = ""

    if rxnorm is not None:
        rx_score = float(rxnorm.get("score") or 0.0)
        rx_name = str(rxnorm.get("name") or cleaned)
        rx_score = _apply_single_token_penalty(cleaned, rx_name, rx_score)
        if rx_score >= best_score:
            best_name = rx_name
            best_score = rx_score
            source = str(rxnorm.get("source") or "rxnorm")
            rxcui = str(rxnorm.get("rxcui") or "")

    matched = best_score >= threshold
    snapped_name = best_name if matched else cleaned
    confidence = "high" if matched else "low"

    return DrugMatchResult(
        raw_name=cleaned,
        snapped_name=snapped_name,
        score=round(best_score, 2),
        matched=matched,
        confidence=confidence,
        source=source,
        rxcui=rxcui,
    )


def match_to_dict(raw_name: Optional[str], threshold: float = 85.0) -> Dict[str, object]:
    result = validate_drug_name(raw_name, threshold=threshold)
    return {
        "raw_name": result.raw_name,
        "snapped_name": result.snapped_name,
        "score": result.score,
        "matched": result.matched,
        "confidence": result.confidence,
        "source": result.source,
        "rxcui": result.rxcui,
        "threshold": threshold,
    }
