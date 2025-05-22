class Session {
  final String sessionId;
  final String timestamp;
  final List<SessionResult> results;
  final double? basalMetabolicRate;
  final int? measurementCount;

  Session({
    required this.sessionId,
    required this.timestamp,
    required this.results,
    this.basalMetabolicRate,
    this.measurementCount,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      sessionId: json['sessionId'],
      timestamp: json['timestamp'],
      results: (json['results'] as List)
          .map((result) => SessionResult.fromJson(result))
          .toList(),
      basalMetabolicRate: json['basalMetabolicRate']?.toDouble(),
      measurementCount: json['measurementCount'],
    );
  }
}

class SessionResult {
  final String timestamp;
  final double energyExpenditure;
  final int windowIndex;
  final int gaitCycleIndex;

  SessionResult({
    required this.timestamp,
    required this.energyExpenditure,
    required this.windowIndex,
    required this.gaitCycleIndex,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    return SessionResult(
      timestamp: json['timestamp'],
      energyExpenditure: json['energyExpenditure'].toDouble(),
      windowIndex: json['windowIndex'],
      gaitCycleIndex: json['gaitCycleIndex'],
    );
  }
}

class SessionSummary {
  final String sessionId;
  final String timestamp;
  final int measurementCount;

  SessionSummary({
    required this.sessionId,
    required this.timestamp,
    required this.measurementCount,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      sessionId: json['sessionId'],
      timestamp: json['timestamp'],
      measurementCount: json['measurementCount'],
    );
  }
}
