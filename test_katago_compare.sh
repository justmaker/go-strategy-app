#!/bin/bash
# Compare ONNX vs KataGo for a given position

if [ $# -lt 1 ]; then
    echo "Usage: $0 <moves>"
    echo "Example: $0 'B G7 W F4 B C3 W F3'"
    exit 1
fi

MOVES="$1"
echo "Testing position: $MOVES"

# Create KataGo JSON query
cat > /tmp/katago_test.json << JSONEOF
{
  "id": "test",
  "initialStones": [],
  "moves": [$(echo "$MOVES" | awk '{
    for(i=1; i<=NF; i+=2) {
      if (i > 1) printf ","
      printf "[\"%s\",\"%s\"]", $i, $(i+1)
    }
  }')],
  "rules": "chinese",
  "komi": 7.5,
  "boardXSize": 9,
  "boardYSize": 9,
  "analyzeTurns": [$(echo "$MOVES" | wc -w | awk '{print $1/2}')],
  "maxVisits": 100
}
JSONEOF

echo ""
echo "=== KataGo Analysis ==="
cat /tmp/katago_test.json | \
katago analysis \
  -model /Users/rexhsu/Documents/go-strategy-app/mobile/assets/katago/model.bin.gz \
  -config /Users/rexhsu/Documents/go-strategy-app/mobile/assets/katago/analysis.cfg 2>&1 | \
python3 -c "
import sys, json
for line in sys.stdin:
    try:
        data = json.loads(line)
        if 'moveInfos' in data:
            print('Top 5 moves:')
            for i, info in enumerate(data['moveInfos'][:5], 1):
                wr = info['winrate'] * 100
                print(f\"  {i}. {info['move']}: {wr:.1f}% (visits: {info['visits']})\")
            print(f\"\nOverall winrate: {data['rootInfo']['winrate']*100:.1f}%\")
            break
    except:
        pass
"

echo ""
echo "=== ONNX Suggestion ==="
echo "Check mobile app for ONNX top move"
echo "(After playing these moves and waiting for opening book miss)"
