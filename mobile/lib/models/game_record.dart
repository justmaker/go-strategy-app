/// Game Record Model
///
/// Represents a saved Go game with moves, analysis, and metadata.
/// Supports both local storage and cloud sync.
library;

import 'package:uuid/uuid.dart';

/// Game record status
enum GameRecordStatus {
  /// Only exists locally
  local,

  /// Synced with cloud
  synced,

  /// Local changes not yet uploaded
  pendingUpload,

  /// Cloud has newer version
  pendingDownload,

  /// Conflict between local and cloud
  conflict,
}

/// Cloud storage provider for game records
enum CloudProvider {
  none,
  googleDrive,
  iCloud,
  oneDrive,
}

/// A single move in the game
class GameMove {
  final String player; // 'B' or 'W'
  final String coordinate; // GTP format: 'Q16', 'D4', or 'pass'
  final int moveNumber;
  final double? winrate; // Analysis winrate at this move
  final double? scoreLead; // Analysis score lead at this move
  final String? comment; // User comment

  const GameMove({
    required this.player,
    required this.coordinate,
    required this.moveNumber,
    this.winrate,
    this.scoreLead,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
        'player': player,
        'coordinate': coordinate,
        'moveNumber': moveNumber,
        if (winrate != null) 'winrate': winrate,
        if (scoreLead != null) 'scoreLead': scoreLead,
        if (comment != null) 'comment': comment,
      };

  factory GameMove.fromJson(Map<String, dynamic> json) => GameMove(
        player: json['player'] as String,
        coordinate: json['coordinate'] as String,
        moveNumber: json['moveNumber'] as int,
        winrate: json['winrate'] as double?,
        scoreLead: json['scoreLead'] as double?,
        comment: json['comment'] as String?,
      );

  /// Convert to SGF format (simplified, full conversion in GameRecord)
  String toSgfSimple() {
    if (coordinate.toLowerCase() == 'pass') {
      return '$player[]';
    }
    return ';$player[$coordinate]'; // Will be converted properly in GameRecord.toSgf()
  }
}

/// Game record containing all game data
class GameRecord {
  final String id;
  final String name;
  final int boardSize;
  final double komi;
  final int handicap;
  final List<GameMove> moves;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final GameRecordStatus status;
  final CloudProvider cloudProvider;
  final String? cloudFileId; // ID in cloud storage
  final String? cloudEtag; // For conflict detection

  // Metadata
  final String? blackPlayer;
  final String? whitePlayer;
  final String? result;
  final String? event;
  final String? notes;

  GameRecord({
    String? id,
    required this.name,
    required this.boardSize,
    this.komi = 7.5,
    this.handicap = 0,
    List<GameMove>? moves,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.status = GameRecordStatus.local,
    this.cloudProvider = CloudProvider.none,
    this.cloudFileId,
    this.cloudEtag,
    this.blackPlayer,
    this.whitePlayer,
    this.result,
    this.event,
    this.notes,
  })  : id = id ?? const Uuid().v4(),
        moves = moves ?? [],
        createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  /// Create a copy with updated fields
  GameRecord copyWith({
    String? name,
    int? boardSize,
    double? komi,
    int? handicap,
    List<GameMove>? moves,
    DateTime? modifiedAt,
    GameRecordStatus? status,
    CloudProvider? cloudProvider,
    String? cloudFileId,
    String? cloudEtag,
    String? blackPlayer,
    String? whitePlayer,
    String? result,
    String? event,
    String? notes,
  }) {
    return GameRecord(
      id: id,
      name: name ?? this.name,
      boardSize: boardSize ?? this.boardSize,
      komi: komi ?? this.komi,
      handicap: handicap ?? this.handicap,
      moves: moves ?? this.moves,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
      status: status ?? this.status,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudEtag: cloudEtag ?? this.cloudEtag,
      blackPlayer: blackPlayer ?? this.blackPlayer,
      whitePlayer: whitePlayer ?? this.whitePlayer,
      result: result ?? this.result,
      event: event ?? this.event,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'boardSize': boardSize,
        'komi': komi,
        'handicap': handicap,
        'moves': moves.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'status': status.name,
        'cloudProvider': cloudProvider.name,
        if (cloudFileId != null) 'cloudFileId': cloudFileId,
        if (cloudEtag != null) 'cloudEtag': cloudEtag,
        if (blackPlayer != null) 'blackPlayer': blackPlayer,
        if (whitePlayer != null) 'whitePlayer': whitePlayer,
        if (result != null) 'result': result,
        if (event != null) 'event': event,
        if (notes != null) 'notes': notes,
      };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        boardSize: json['boardSize'] as int,
        komi: (json['komi'] as num).toDouble(),
        handicap: json['handicap'] as int? ?? 0,
        moves: (json['moves'] as List<dynamic>?)
                ?.map((m) => GameMove.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        status: GameRecordStatus.values
            .byName(json['status'] as String? ?? GameRecordStatus.local.name),
        cloudProvider: CloudProvider.values.byName(
            json['cloudProvider'] as String? ?? CloudProvider.none.name),
        cloudFileId: json['cloudFileId'] as String?,
        cloudEtag: json['cloudEtag'] as String?,
        blackPlayer: json['blackPlayer'] as String?,
        whitePlayer: json['whitePlayer'] as String?,
        result: json['result'] as String?,
        event: json['event'] as String?,
        notes: json['notes'] as String?,
      );

  /// Convert to SGF format
  String toSgf() {
    final buffer = StringBuffer();
    buffer.writeln('(;GM[1]FF[4]CA[UTF-8]');
    buffer.writeln('SZ[$boardSize]');
    buffer.writeln('KM[$komi]');
    if (handicap > 0) buffer.writeln('HA[$handicap]');
    if (blackPlayer != null) buffer.writeln('PB[$blackPlayer]');
    if (whitePlayer != null) buffer.writeln('PW[$whitePlayer]');
    if (result != null) buffer.writeln('RE[$result]');
    if (event != null) buffer.writeln('EV[$event]');
    buffer.writeln('DT[${createdAt.toIso8601String().substring(0, 10)}]');
    buffer.writeln('AP[GoStrategy:1.0]');
    if (notes != null) buffer.writeln('GC[$notes]');

    for (final move in moves) {
      if (move.coordinate.toLowerCase() == 'pass') {
        buffer.write(';${move.player}[]');
      } else {
        final sgfCoord = _gtpToSgf(move.coordinate, boardSize);
        buffer.write(';${move.player}[$sgfCoord]');
      }
      if (move.comment != null) {
        buffer.write('C[${move.comment}]');
      }
    }

    buffer.writeln(')');
    return buffer.toString();
  }

  /// Convert GTP coordinate to SGF format
  String _gtpToSgf(String gtp, int size) {
    final col = gtp[0].toUpperCase();
    final row = int.parse(gtp.substring(1));

    // GTP columns: A-T (skipping I)
    int colIndex = col.codeUnitAt(0) - 'A'.codeUnitAt(0);
    if (col.codeUnitAt(0) > 'I'.codeUnitAt(0)) colIndex--;

    // SGF rows: 'a' is top row
    final sgfRow = size - row;

    return String.fromCharCode('a'.codeUnitAt(0) + colIndex) +
        String.fromCharCode('a'.codeUnitAt(0) + sgfRow);
  }

  /// Parse SGF content into a GameRecord
  static GameRecord? fromSgf(String sgf, {String? name}) {
    try {
      // Basic SGF parsing
      int boardSize = 19;
      double komi = 7.5;
      int handicap = 0;
      String? blackPlayer;
      String? whitePlayer;
      String? result;
      String? event;
      final moves = <GameMove>[];

      // Extract properties
      final sizeMatch = RegExp(r'SZ\[(\d+)\]').firstMatch(sgf);
      if (sizeMatch != null) boardSize = int.parse(sizeMatch.group(1)!);

      final komiMatch = RegExp(r'KM\[([\d.]+)\]').firstMatch(sgf);
      if (komiMatch != null) komi = double.parse(komiMatch.group(1)!);

      final haMatch = RegExp(r'HA\[(\d+)\]').firstMatch(sgf);
      if (haMatch != null) handicap = int.parse(haMatch.group(1)!);

      final pbMatch = RegExp(r'PB\[([^\]]*)\]').firstMatch(sgf);
      if (pbMatch != null) blackPlayer = pbMatch.group(1);

      final pwMatch = RegExp(r'PW\[([^\]]*)\]').firstMatch(sgf);
      if (pwMatch != null) whitePlayer = pwMatch.group(1);

      final reMatch = RegExp(r'RE\[([^\]]*)\]').firstMatch(sgf);
      if (reMatch != null) result = reMatch.group(1);

      final evMatch = RegExp(r'EV\[([^\]]*)\]').firstMatch(sgf);
      if (evMatch != null) event = evMatch.group(1);

      // Extract moves
      final movePattern = RegExp(r';([BW])\[([a-s]{0,2})\]');
      int moveNum = 0;
      for (final match in movePattern.allMatches(sgf)) {
        moveNum++;
        final player = match.group(1)!;
        final sgfCoord = match.group(2)!;

        String gtpCoord;
        if (sgfCoord.isEmpty) {
          gtpCoord = 'pass';
        } else {
          gtpCoord = _sgfToGtp(sgfCoord, boardSize);
        }

        moves.add(GameMove(
          player: player,
          coordinate: gtpCoord,
          moveNumber: moveNum,
        ));
      }

      return GameRecord(
        name: name ?? 'Imported Game',
        boardSize: boardSize,
        komi: komi,
        handicap: handicap,
        moves: moves,
        blackPlayer: blackPlayer,
        whitePlayer: whitePlayer,
        result: result,
        event: event,
      );
    } catch (e) {
      return null;
    }
  }

  /// Convert SGF coordinate to GTP format
  static String _sgfToGtp(String sgf, int size) {
    if (sgf.length != 2) return 'pass';

    int colIndex = sgf[0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    int rowIndex = sgf[1].codeUnitAt(0) - 'a'.codeUnitAt(0);

    // GTP columns skip 'I'
    String col = String.fromCharCode(
        'A'.codeUnitAt(0) + colIndex + (colIndex >= 8 ? 1 : 0));
    int row = size - rowIndex;

    return '$col$row';
  }

  @override
  String toString() => 'GameRecord($id, $name, ${moves.length} moves)';
}

/// User's cloud sync preferences
/// Cloud sync preferences
/// Login automatically enables sync - no separate enable/disable needed
class CloudSyncPreferences {
  final CloudProvider provider;
  final bool autoSync;
  final bool syncOnWifiOnly;
  final DateTime? lastSyncTime;

  const CloudSyncPreferences({
    this.provider = CloudProvider.none,
    this.autoSync = true,
    this.syncOnWifiOnly = false,
    this.lastSyncTime,
  });

  CloudSyncPreferences copyWith({
    CloudProvider? provider,
    bool? autoSync,
    bool? syncOnWifiOnly,
    DateTime? lastSyncTime,
  }) {
    return CloudSyncPreferences(
      provider: provider ?? this.provider,
      autoSync: autoSync ?? this.autoSync,
      syncOnWifiOnly: syncOnWifiOnly ?? this.syncOnWifiOnly,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'autoSync': autoSync,
        'syncOnWifiOnly': syncOnWifiOnly,
        if (lastSyncTime != null)
          'lastSyncTime': lastSyncTime!.toIso8601String(),
      };

  factory CloudSyncPreferences.fromJson(Map<String, dynamic> json) {
    return CloudSyncPreferences(
      provider: CloudProvider.values
          .byName(json['provider'] as String? ?? CloudProvider.none.name),
      autoSync: json['autoSync'] as bool? ?? true,
      syncOnWifiOnly: json['syncOnWifiOnly'] as bool? ?? false,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'] as String)
          : null,
    );
  }
}
