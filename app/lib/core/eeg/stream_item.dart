class Channel {
  const Channel(this.name, {this.unit = 'uV'});

  final String name;
  final String unit;
}

class StreamInfo {
  const StreamInfo({
    this.contract = 1,
    required this.sourceId,
    required this.fs,
    required this.channels,
    required this.chunkSize,
  });

  final int contract;
  final String sourceId;
  final int fs;
  final List<Channel> channels;
  final int chunkSize;

  int channelIndex(String name) {
    final i = channels.indexWhere((c) => c.name == name);
    if (i < 0) throw StateError('Brak kanalu $name w strumieniu');
    return i;
  }
}

sealed class StreamItem {
  const StreamItem();
}

class SegmentStart extends StreamItem {
  const SegmentStart(this.info);

  final StreamInfo info;
}

class EegPacket extends StreamItem {
  const EegPacket({
    required this.firstSample,
    required this.tRecv,
    required this.samples,
    this.contact,
  });

  final int firstSample;
  final double tRecv;

  /// [kanal][probka]: czy elektroda ma kontakt ze skora. Brak, gdy zrodlo
  /// nie podaje kontaktu.
  final List<List<bool>>? contact;

  /// [kanal][probka], w uV.
  final List<List<double>> samples;

  int get length => samples.isEmpty ? 0 : samples.first.length;
}

class GapEvent extends StreamItem {
  const GapEvent({required this.firstSample, required this.count});

  final int firstSample;
  final int count;
}

class DisconnectedEvent extends StreamItem {
  const DisconnectedEvent({required this.reason, required this.tRecv});

  final String reason;
  final double tRecv;
}
