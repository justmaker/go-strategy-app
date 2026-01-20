BEGIN TRANSACTION;
CREATE TABLE analysis_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    board_hash TEXT UNIQUE NOT NULL,
    moves_sequence TEXT,
    board_size INTEGER NOT NULL,
    komi REAL NOT NULL,
    analysis_result TEXT NOT NULL,
    engine_visits INTEGER NOT NULL,
    model_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO "analysis_cache" VALUES(2,'7faf2a598d2d6ad5','B[E5]',9,7.5,'[{"move": "C4", "winrate": 0.0843161, "score_lead": -0.68059, "visits": 21}, {"move": "C6", "winrate": 0.0843161, "score_lead": -0.68059, "visits": 21}, {"move": "G4", "winrate": 0.0843161, "score_lead": -0.68059, "visits": 21}]',500,'KataGo','2026-01-21T01:36:02.215359');
INSERT INTO "analysis_cache" VALUES(3,'2b59acaec460339b','B[E5];W[H7]',9,7.5,'[{"move": "G6", "winrate": 0.830164, "score_lead": 1.78098, "visits": 14}, {"move": "E7", "winrate": 0.776218, "score_lead": 1.34071, "visits": 8}, {"move": "F7", "winrate": 0.609249, "score_lead": 0.761728, "visits": 1}]',500,'KataGo','2026-01-21T01:36:50.244866');
INSERT INTO "analysis_cache" VALUES(4,'4882eb582c8ae99e','B[E5];W[H5]',9,7.5,'[{"move": "C5", "winrate": 0.44813, "score_lead": 0.205899, "visits": 13}, {"move": "G6", "winrate": 0.408353, "score_lead": -0.0627998, "visits": 11}, {"move": "G4", "winrate": 0.408353, "score_lead": -0.0627998, "visits": 11}]',500,'KataGo','2026-01-21T01:41:44.350933');
INSERT INTO "analysis_cache" VALUES(5,'2a1f955ad499da99','',9,7.5,'[{"move": "E5", "winrate": 0.0919861, "score_lead": -0.704197, "visits": 21}, {"move": "F5", "winrate": 0.0664456, "score_lead": -1.00874, "visits": 4}, {"move": "D5", "winrate": 0.0664456, "score_lead": -1.00874, "visits": 4}]',500,'KataGo','2026-01-21T01:45:18.687575');
INSERT INTO "analysis_cache" VALUES(6,'1074e53db06ef806','B[E5]',9,7.0,'[{"move": "C4", "winrate": 0.417403, "score_lead": -0.175787, "visits": 13}, {"move": "C6", "winrate": 0.417403, "score_lead": -0.175787, "visits": 13}, {"move": "G4", "winrate": 0.417403, "score_lead": -0.175787, "visits": 13}]',500,'KataGo','2026-01-21T01:57:46.810424');
INSERT INTO "analysis_cache" VALUES(7,'7059c867ada7dd68','B[E5];W[C6]',9,7.0,'[{"move": "D7", "winrate": 0.425037, "score_lead": -0.14307, "visits": 21}, {"move": "E7", "winrate": 0.410477, "score_lead": -0.0873099, "visits": 4}, {"move": "C4", "winrate": 0.38146, "score_lead": -0.164144, "visits": 1}]',500,'KataGo','2026-01-21T01:57:53.788902');
INSERT INTO "analysis_cache" VALUES(8,'c1becbcbee01d226','B[E5];W[C6];B[E7]',9,7.0,'[{"move": "G4", "winrate": 0.388536, "score_lead": -0.327388, "visits": 16}, {"move": "C4", "winrate": 0.42232, "score_lead": -0.092451, "visits": 8}, {"move": "F3", "winrate": 0.413096, "score_lead": -0.159214, "visits": 3}]',500,'KataGo','2026-01-21T01:58:00.733569');
INSERT INTO "analysis_cache" VALUES(9,'ff172c73d4e45e70','B[E5];W[C6];B[D7]',9,7.0,'[{"move": "C4", "winrate": 0.439421, "score_lead": -0.306571, "visits": 22}, {"move": "F7", "winrate": 0.43091, "score_lead": -0.170923, "visits": 22}, {"move": "G6", "winrate": 0.512073, "score_lead": 0.194419, "visits": 1}]',500,'KataGo','2026-01-21T01:58:08.033779');
DELETE FROM "sqlite_sequence";
INSERT INTO "sqlite_sequence" VALUES('analysis_cache',9);
CREATE INDEX idx_board_hash ON analysis_cache(board_hash);
COMMIT;
