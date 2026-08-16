"""Build a precision-first Young Adam subtitle corpus from a user-owned SRT.

The extractor deliberately promotes only dialogue explicitly labelled
``[young Adam ...]``.  Nearby unlabelled cues are emitted into a review queue,
never into the training corpus, because dialogue alternation becomes ambiguous
as soon as Young Adam, adult Adam, and a third character share a scene.

The released film's speaker-attributed first-meeting excerpt is also encoded as
cue/turn coordinates.  It contributes confirmed dialogue without copying any
screenplay text into source control; the words still come from the user's SRT.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path


TIMING = re.compile(
    r"(?P<start>\d{2}:\d{2}:\d{2},\d{3})\s+-->\s+"
    r"(?P<end>\d{2}:\d{2}:\d{2},\d{3})"
)
YOUNG_ADAM = re.compile(r"\[young\s+Adam(?P<action>[^\]]*)\]", re.I)
ANY_SPEAKER = re.compile(r"\[(?![^\]]*(?:music|laugh|sigh|gasp|grunt|groan|"
                         r"pant|yell|cough|whisper|chuckle|sob|sniff|yelps?))"
                         r"[^\]]+\]", re.I)
HTML_TAG = re.compile(r"<[^>]+>")
STAGE_ONLY = re.compile(
    r"^(?:[\s\-–—]*\[[^\]]+\][\s\-–—]*)+$",
    re.I,
)

# (cue index, turn within cue).  ``None`` means the whole cue.  Consecutive
# coordinates in one group form one utterance.  These are limited to the
# first-meeting scene covered by the speaker-attributed screenplay excerpt.
CONFIRMED_FIRST_MEETING: tuple[tuple[tuple[int, int | None], ...], ...] = (
    ((183, None), (184, 1)),
    ((190, 0),),
    ((191, 0),),
    ((195, 0),),
    ((197, 1),),
    ((200, 0),),
    ((204, 0),),
    ((206, None), (207, None)),
    ((209, 0),),
    ((210, None),),
    ((211, 1),),
    ((213, 0),),
    ((215, 1),),
    ((216, 1),),
    ((217, 1),),
    ((227, None),),
    ((238, None), (239, None), (240, None)),
    ((242, None), (243, None), (244, None), (245, None),
     (246, None), (247, None), (249, None)),
    ((250, None),),
)


@dataclass(frozen=True)
class Cue:
    index: int
    start: str
    end: str
    lines: list[str]

    @property
    def raw_text(self) -> str:
        return "\n".join(self.lines)


@dataclass(frozen=True)
class Attribution:
    cue_index: int
    start: str
    end: str
    text: str
    confidence: str
    evidence: str
    performance_note: str


def parse_srt(text: str) -> list[Cue]:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    cues: list[Cue] = []
    for block in re.split(r"\n{2,}", normalized.strip()):
        lines = [line for line in block.split("\n") if line.strip()]
        if len(lines) < 3 or not lines[0].strip().isdigit():
            continue
        timing = TIMING.fullmatch(lines[1].strip())
        if timing is None:
            continue
        cues.append(
            Cue(
                index=int(lines[0].strip()),
                start=timing.group("start"),
                end=timing.group("end"),
                lines=lines[2:],
            )
        )
    return cues


def clean_dialogue(value: str) -> str:
    value = html.unescape(HTML_TAG.sub("", value))
    value = YOUNG_ADAM.sub("", value)
    value = value.replace("\u00a0", " ")
    value = re.sub(r"^[\s\-–—]+", "", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def cue_turns(cue: Cue) -> list[str]:
    """Collapse wrapped lines while retaining dash-delimited speaker turns."""
    turns: list[list[str]] = []
    for raw_line in cue.lines:
        line = HTML_TAG.sub("", html.unescape(raw_line)).strip()
        if re.match(r"^-", line):
            turns.append([re.sub(r"^-\s*", "", line)])
        elif turns:
            turns[-1].append(line)
        else:
            turns.append([line])
    return [clean_dialogue(" ".join(lines)) for lines in turns]


def confirmed_first_meeting(cues: list[Cue]) -> list[Attribution]:
    by_index = {cue.index: cue for cue in cues}
    results: list[Attribution] = []
    for group in CONFIRMED_FIRST_MEETING:
        pieces: list[str] = []
        used: list[Cue] = []
        for cue_index, turn_index in group:
            cue = by_index[cue_index]
            turns = cue_turns(cue)
            if turn_index is None:
                pieces.extend(turns)
            else:
                pieces.append(turns[turn_index])
            used.append(cue)
        spoken = clean_dialogue(" ".join(pieces))
        if not spoken:
            continue
        results.append(
            Attribution(
                cue_index=used[0].index,
                start=used[0].start,
                end=used[-1].end,
                text=spoken,
                confidence="high",
                evidence="Young Adam label in speaker-attributed screenplay excerpt",
                performance_note="spoken",
            )
        )
    return results


def explicit_young_adam(cue: Cue) -> list[Attribution]:
    results: list[Attribution] = []
    active = False
    active_action = ""
    collected: list[str] = []

    def flush() -> None:
        nonlocal collected
        spoken = clean_dialogue(" ".join(collected))
        collected = []
        if not spoken or STAGE_ONLY.fullmatch(spoken):
            return
        results.append(
            Attribution(
                cue_index=cue.index,
                start=cue.start,
                end=cue.end,
                text=spoken,
                confidence="high",
                evidence="explicit [young Adam] caption label",
                performance_note=active_action.strip(" -") or "spoken",
            )
        )

    for raw_line in cue.lines:
        line = HTML_TAG.sub("", html.unescape(raw_line)).strip()
        match = YOUNG_ADAM.search(line)
        if match:
            flush()
            active = True
            active_action = match.group("action")
            remainder = line[match.end():]
            if remainder.strip():
                collected.append(remainder)
            continue

        # A new dash-prefixed turn or a different named speaker ends the span.
        if active and (re.match(r"^\s*-", line) or ANY_SPEAKER.search(line)):
            flush()
            active = False
            active_action = ""
            continue
        if active:
            collected.append(line)

    flush()
    return results


def nearby_review(cues: list[Cue], explicit_indices: set[int]) -> list[dict]:
    by_position = {cue.index: pos for pos, cue in enumerate(cues)}
    candidates: dict[int, dict] = {}
    for cue_index in explicit_indices:
        pos = by_position[cue_index]
        for offset in (-2, -1, 1, 2):
            candidate_pos = pos + offset
            if candidate_pos < 0 or candidate_pos >= len(cues):
                continue
            cue = cues[candidate_pos]
            if cue.index in explicit_indices:
                continue
            raw = clean_dialogue(cue.raw_text)
            if not raw or STAGE_ONLY.fullmatch(raw):
                continue
            candidates.setdefault(
                cue.index,
                {
                    "cue_index": cue.index,
                    "start": cue.start,
                    "end": cue.end,
                    "text": raw,
                    "confidence": "unverified",
                    "evidence": (
                        "near an explicit Young Adam cue; requires scene/turn review"
                    ),
                },
            )
    return [candidates[key] for key in sorted(candidates)]


def write_outputs(cues: list[Cue], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    explicit = [item for cue in cues for item in explicit_young_adam(cue)]
    confirmed = confirmed_first_meeting(cues)
    by_text: dict[str, Attribution] = {}
    for item in [*explicit, *confirmed]:
        by_text.setdefault(item.text.casefold(), item)
    attributions = sorted(by_text.values(), key=lambda item: (item.start, item.text))
    explicit_indices = {item.cue_index for item in explicit}
    review = nearby_review(cues, explicit_indices)

    with (output / "young_adam_high_confidence.csv").open(
        "w", encoding="utf-8-sig", newline=""
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(attributions[0])))
        writer.writeheader()
        writer.writerows(asdict(item) for item in attributions)

    (output / "young_adam_high_confidence.json").write_text(
        json.dumps([asdict(item) for item in attributions], indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (output / "young_adam_review_queue.json").write_text(
        json.dumps(review, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    summary = {
        "source_cues": len(cues),
        "explicit_young_adam_cues": len(explicit_indices),
        "screenplay_confirmed_additions": len(attributions) - len(explicit),
        "high_confidence_spoken_lines": len(attributions),
        "unverified_nearby_cues": len(review),
        "training_rule": (
            "Only high-confidence rows are eligible. Review-queue rows are excluded."
        ),
    }
    (output / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    report = [
        "# Young Adam / Walker Scobell subtitle attribution",
        "",
        "This is a precision-first extraction from a user-provided subtitle track.",
        "Dialogue is promoted only when the captions label `[young Adam]`, or",
        "when the released speaker-attributed screenplay excerpt confirms the turn.",
        "Nearby dialogue is quarantined in the review queue and is not training data.",
        "",
        f"- Source cues: {len(cues)}",
        f"- Explicit Young Adam cues: {len(explicit_indices)}",
        f"- Screenplay-confirmed additions: {len(attributions) - len(explicit)}",
        f"- High-confidence spoken lines: {len(attributions)}",
        f"- Unverified nearby cues: {len(review)}",
        "",
        "## High-confidence index",
        "",
        "| Cue | Time | Performance | Text |",
        "|---:|---|---|---|",
    ]
    for item in attributions:
        safe = item.text.replace("|", "\\|").replace("\n", " ")
        report.append(
            f"| {item.cue_index} | {item.start} | {item.performance_note} | {safe} |"
        )
    (output / "review.md").write_text("\n".join(report) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    cues = parse_srt(args.source.read_text(encoding="utf-8-sig"))
    if not cues:
        raise SystemExit("No SRT cues found")
    write_outputs(cues, args.output)


if __name__ == "__main__":
    main()
