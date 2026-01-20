#!/usr/bin/env python3
import sys
print('Starting test...', flush=True)

from src.analyzer import GoAnalyzer

print('Creating analyzer...', flush=True)
with GoAnalyzer() as analyzer:
    print('Analyzing position...', flush=True)
    result = analyzer.analyze(board_size=9, moves=['B E5'])
    print(f'From cache: {result.from_cache}', flush=True)
    print('Top moves:', flush=True)
    for m in result.top_moves:
        print(f'  {m.move}: winrate={m.winrate:.1%}, score={m.score_lead:+.2f}, visits={m.visits}', flush=True)

print('Done!', flush=True)
