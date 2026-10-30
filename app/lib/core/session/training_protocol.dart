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

  static const alfa = TrainingProtocol(
    id: 'alfa',
    dbName: 'Trening alfa',
    title: 'Trening alfa',
    subtitle: 'moc alfa 8–12 Hz, oczy otwarte',
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

  /// Treningi oferowane w aplikacji.
  static const all = [alfa];

  /// Wszystkie znane protokoly, takze wycofane, bo moga byc w starej historii.
  static const known = [alfa, skupienie];

  static TrainingProtocol byDbName(String name) =>
      known.firstWhere((p) => p.dbName == name, orElse: () => alfa);

  final String id;
  final String dbName;
  final String title;
  final String subtitle;
  final FeatureKind kind;
  final List<String> channels;
}
