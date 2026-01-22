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

### Consolidated Generation Log

| Run | Date | Board | Visits | Nodes | Time | DB Size | Status / Notes |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| **#4** | 2026-01-22 | 9x9 | 500 | 2,945 | 11m 43s | ~2.0 MB | ✅ **COMPLETED**<br>Regenerated & Optimized |
| **#5** | 2026-01-22 | 13x13 | 300 | 3,004 | 13m 06s | 3.3 MB | ✅ **COMPLETED**<br>Regenerated & Optimized<br>Final Total Size: 3.3 MB |
| **#3** | 2026-01-22 | 19x19 | 100 | 1,818 | 10m 25s | ~9.6 MB* | ✅ **COMPLETED**<br>First run with Symmetry Pruning<br>*(Size before cleanup)* |
| **#1** | 2026-01-22 | 9x9 | 300 | 3,084 | ~12m | ~1.3 MB | ❌ **DEPRECATED**<br>Unoptimized (No symmetry pruning) |
| **#2** | 2026-01-22 | 13x13 | 300 | 18,336 | ~64m | 9.1 MB | ❌ **DEPRECATED**<br>Unoptimized (No symmetry pruning) |

---

## Thread Performance Testing (M2 MacBook Air)

| Threads | Speed (new nodes/sec) | Notes |
|---------|----------------------|-------|
| 2 | ~3.5-3.8 | **Best for this workload** |
| 4 | ~3.3 | Slightly slower |
| 8 | ~2.2 | Slowest, sync overhead |

**Conclusion**: For KataGo CPU mode on M2, 2 threads is optimal for sequential analysis.
