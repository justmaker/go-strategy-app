# Opening Book Generation Log

This document records all opening book generation runs for tracking and reproducibility.

---

## Platform Information

| Key | Value |
|-----|-------|
| **Machine** | MacBook Air |
| **Chip** | Apple M2 |
| **Cores** | 8 (4 performance + 4 efficiency) |
| **Memory** | 16 GB |
| **KataGo** | Homebrew (CPU/Metal) |

---

## Generation Runs

### Run #1: 9x9 Opening Book (2026-01-22) ❌ DEPRECATED

| Parameter | Value |
|-----------|-------|
| **Board Size** | 9x9 |
| **Komi** | 7.5 |
| **Handicap** | 0 |
| **Visits** | 300 |
| **Max Depth** | 10 |
| **Time Limit** | None (unlimited) |
| **KataGo Threads** | 2 |
| **Total Run Time** | ~12 minutes |
| **Nodes Processed** | 3,084 |
| **Cache Entries** | 3,084 |
| **Database Size** | ~1.3 MB |

**Notes**: 
- Used canonical hash for symmetry-aware deduplication
- BFS with Top 3 branching and 10% winrate pruning

---

### Run #2: 13x13 Opening Book (2026-01-22) ❌ DEPRECATED

| Parameter | Value |
|-----------|-------|
| **Board Size** | 13x13 |
| **Komi** | 7.5 |
| **Handicap** | 0 |
| **Visits** | 300 |
| **Max Depth** | 10 |
| **Time Limit** | None (unlimited) |
| **KataGo Threads** | 2 (tested 4 and 8, 2 was fastest) |
| **Total Run Time** | ~64 minutes |
| **Nodes Processed** | 18,336 |
| **Cache Entries (new)** | 11,453 |
| **Total Database Entries** | 21,483 |
| **Database Size** | 9.1 MB |
| **Seed SQL Size** | 8.6 MB |

**Notes**: 
- Multiple restarts during thread optimization testing (2→8→4→2)
- Previous runs contributed 6,883 cache hits
- 13x13 has significantly larger search space than 9x9
- Future optimization: group symmetric moves to reduce branching

---

## Thread Performance Testing (M2 MacBook Air)

| Threads | Speed (new nodes/sec) | Notes |
|---------|----------------------|-------|
| 2 | ~3.5-3.8 | **Best for this workload** |
| 4 | ~3.3 | Slightly slower |
| 8 | ~2.2 | Slowest, sync overhead |

**Conclusion**: For KataGo CPU mode on M2, 2 threads is optimal for sequential analysis.

---

### Run #3: 19x19 Opening Book (2026-01-22) ✅ COMPLETED

| Parameter | Value |
|-----------|-------|
| **Board Size** | 19x19 |
| **Komi** | 7.5 |
| **Handicap** | 0 |
| **Visits** | 100 |
| **Max Depth** | 10 |
| **Time Limit** | None |
| **KataGo Threads** | 2 |
| **Total Run Time** | 10m 25s |
| **Nodes Processed** | 1,818 |
| **Cache Entries (new)** | 1,818 |
| **Total Database Entries** | 23,307 |

**Notes**:
- **First run with Symmetry Pruning optimization**
- Significant reduction in node count due to grouping symmetric moves
- Visits set to 100 for speed (proof of concept for 19x19 feasibility)
- GUI updated to recognize 19x19@100v as a valid opening book

---

### Run #4: 9x9 Opening Book (Regenerated) (2026-01-22) ✅ COMPLETED

| Parameter | Value |
|-----------|-------|
| **Board Size** | 9x9 |
| **Komi** | 7.5 |
| **Handicap** | 0 |
| **Visits** | 500 |
| **Max Depth** | 10 |
| **Time Limit** | None |
| **KataGo Threads** | 2 |
| **Total Run Time** | 11m 43s |
| **Nodes Processed** | 2,945 |
| **Cache Entries (new)** | 2,945 |
| **Total Database Entries** | 4,765 |

**Notes**:
- **Regenerated with Symmetry Pruning**
- Increased visits to 500 (vs 300 in Run #1) for higher quality
- Replaced Run #1 data

---

### Run #5: 13x13 Opening Book (Regenerated) (2026-01-22) ✅ COMPLETED

| Parameter | Value |
|-----------|-------|
| **Board Size** | 13x13 |
| **Komi** | 7.5 |
| **Handicap** | 0 |
| **Visits** | 300 |
| **Max Depth** | 10 |
| **Time Limit** | None |
| **KataGo Threads** | 2 |
| **Total Run Time** | 13m 06s |
| **Nodes Processed** | 3,004 |
| **Cache Entries (new)** | 3,004 |
| **Total Database Entries** | 7,769 |
| **Final Database Size** | 3.3 MB |

**Notes**:
- **Regenerated with Symmetry Pruning**
- Dramatic reduction in nodes (18,336 -> 3,004) while maintaining same depth/visits
- Replaced Run #2 data

---

## Template for Future Runs

```markdown
### Run #N: [Board Size] Opening Book (YYYY-MM-DD)

| Parameter | Value |
|-----------|-------|
| **Board Size** | NxN |
| **Komi** | X.X |
| **Handicap** | N |
| **Visits** | N |
| **Max Depth** | N |
| **Time Limit** | None / X seconds |
| **KataGo Threads** | N |
| **Total Run Time** | X minutes |
| **Nodes Processed** | N |
| **Cache Entries** | N |
| **Database Size** | X MB |

**Notes**: 
- Any special configuration or observations
```
