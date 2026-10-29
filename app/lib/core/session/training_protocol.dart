enum FeatureKind {
  /// ln(P_alfa / P0), usrednione po kanalach.
  alphaPower,

  /// ln(P_beta / (P_alfa + P_theta)), usrednione po kanalach.
  betaOverAlphaTheta,
}

/// Definicja treningu: cecha EEG i kanaly. Nazwa w bazie identyfikuje protokol.
class TrainingProtocol {
  const TrainingProtocol({
    required this.id,
    required this.dbName,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.channels,
  });

  static const relaks = TrainingProtocol(
    id: 'relaks',
    dbName: 'Trening alfa',
    title: 'Relaks',
    subtitle: 'alfa 8–12 Hz, O1 O2',
    kind: FeatureKind.alphaPower,
    channels: ['O1', 'O2'],
  );

  static const skupienie = TrainingProtocol(
    id: 'skupienie',
    dbName: 'Trening skupienia',
    title: 'Skupienie',
    subtitle: 'β/(α+θ), F3 F4 C3 C4',
    kind: FeatureKind.betaOverAlphaTheta,
    channels: ['F3', 'F4', 'C3', 'C4'],
  );

  static const all = [relaks, skupienie];

  static TrainingProtocol byDbName(String name) =>
      all.firstWhere((p) => p.dbName == name, orElse: () => relaks);

  final String id;
  final String dbName;
  final String title;
  final String subtitle;
  final FeatureKind kind;
  final List<String> channels;
}
