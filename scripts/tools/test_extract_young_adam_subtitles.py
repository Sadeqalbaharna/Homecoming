import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_young_adam_subtitles import Cue, clean_dialogue, cue_turns, explicit_young_adam


class YoungAdamSubtitleExtractionTest(unittest.TestCase):
    def test_explicit_label_promotes_only_young_adam_turn(self) -> None:
        cue = Cue(
            index=7,
            start="00:00:01,000",
            end="00:00:03,000",
            lines=["-[young Adam] Wait.", "-No."],
        )

        result = explicit_young_adam(cue)

        self.assertEqual([item.text for item in result], ["Wait."])

    def test_turn_parser_keeps_wrapped_lines_together(self) -> None:
        cue = Cue(
            index=8,
            start="00:00:04,000",
            end="00:00:06,000",
            lines=["-First wrapped", "line.", "-Second turn."],
        )

        self.assertEqual(cue_turns(cue), ["First wrapped line.", "Second turn."])

    def test_clean_dialogue_removes_young_adam_label(self) -> None:
        self.assertEqual(clean_dialogue("[young Adam] Who are you?"), "Who are you?")


if __name__ == "__main__":
    unittest.main()
