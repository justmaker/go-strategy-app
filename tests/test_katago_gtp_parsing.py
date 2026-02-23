
import unittest
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.katago_gtp import KataGoGTP, KataGoConfig, MoveCandidate

class TestKataGoParsing(unittest.TestCase):
    def test_parse_kata_analyze_line_format(self):
        # Let's test _parse_kata_analyze_line logic directly to confirm my understanding
        config = KataGoConfig(
            katago_path="katago",
            model_path="model.bin.gz",
            config_path="config.cfg"
        )
        katago = KataGoGTP(config)

        # This line format simulates kata-analyze output
        line = "info move Q3 visits 45 winrate 0.52 scoreLead 0.31 info move R4 visits 38 winrate 0.51 scoreLead 0.28"
        candidates = katago._parse_kata_analyze_line(line, top_n=3)

        self.assertEqual(len(candidates), 2)
        self.assertEqual(candidates[0].move, "Q3")
        self.assertEqual(candidates[0].visits, 45)
        self.assertEqual(candidates[1].move, "R4")
        self.assertEqual(candidates[1].visits, 38)

if __name__ == '__main__':
    unittest.main()
