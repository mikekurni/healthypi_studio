import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/export_models.dart';
import '../models/recording_models.dart';
import 'biosignal_file_reader.dart';
import 'data_parser.dart';

/// Service for exporting .hpd recording files to various formats
class RecordingExportService extends ChangeNotifier {
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _error;
  String _currentOperation = '';

  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  String? get error => _error;
  String get currentOperation => _currentOperation;

  /// Export a recording file to CSV format.
  ///
  /// Streams the `.hpd` a block at a time through `BiosignalFileReader` rather
  /// than loading it: an hour of seven channels at 500 Hz is millions of rows,
  /// and the writer is sequential anyway.
  /// [outputDirectory] overrides the default `PortaCardio_Exports` folder. The
  /// app never passes it; tests do, because `path_provider` needs a platform
  /// channel that a unit test does not have.
  Future<String?> exportToCSV({
    required String inputFilePath,
    required String outputFileName,
    CSVExportOptions? options,
    Directory? outputDirectory,
  }) async {
    final CSVExportOptions opts = options ?? CSVExportOptions();
    _isExporting = true;
    _exportProgress = 0.0;
    _error = null;
    _currentOperation = 'Reading recording file...';
    notifyListeners();

    IOSink? sink;
    BiosignalFileReader? reader;
    try {
      final inputFile = File(inputFilePath);
      if (!await inputFile.exists()) {
        throw Exception('Recording file not found: $inputFilePath');
      }

      _currentOperation = 'Loading recording metadata...';
      _exportProgress = 0.1;
      notifyListeners();

      reader = BiosignalFileReader(inputFile);
      await reader.open();
      final metadata = await reader.readHeader();

      // Which channels, in the file's own order so the header row and every
      // data row cannot drift apart.
      final channels = opts.channelsToExport == null
          ? metadata.channels
          : metadata.channels
              .where((c) => opts.channelsToExport!.contains(c.id))
              .toList();
      if (channels.isEmpty) {
        throw Exception('No matching channels in ${path.basename(inputFilePath)}');
      }

      final exportDir = outputDirectory ??
          Directory(path.join((await getApplicationDocumentsDirectory()).path,
              'PortaCardio_Exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final outputPath = path.join(exportDir.path, outputFileName);

      sink = File(outputPath).openWrite();
      final String eol = opts.lineEnding;
      final String sep = opts.delimiter;

      if (opts.includeMetadata) {
        sink.write('# PortaStudio Export$eol');
        sink.write('# Source File: ${path.basename(inputFilePath)}$eol');
        sink.write('# Device: ${metadata.deviceId}$eol');
        sink.write('# Created: ${metadata.createdAt.toIso8601String()}$eol');
        sink.write(
            '# Duration: ${_formatDuration(metadata.recordingDuration)}$eol');
        sink.write('# Total Samples: ${metadata.totalSamples}$eol');
        final subject = metadata.subjectMetadata;
        if (subject != null) {
          if (subject.subjectId != null && subject.subjectId!.isNotEmpty) {
            sink.write('# Subject ID: ${subject.subjectId}$eol');
          }
          if (subject.age != null) {
            sink.write('# Subject Age: ${subject.age}$eol');
          }
          if (subject.gender != null && subject.gender!.isNotEmpty) {
            sink.write('# Subject Gender: ${subject.gender}$eol');
          }
          if (subject.condition != null && subject.condition!.isNotEmpty) {
            sink.write('# Subject Condition: ${subject.condition}$eol');
          }
          if (subject.notes != null && subject.notes!.isNotEmpty) {
            sink.write('# Subject Notes: ${subject.notes}$eol');
          }
        }
        final sessionMeta = metadata.sessionMetadata;
        if (sessionMeta != null) {
          if (sessionMeta.protocolName.isNotEmpty) {
            sink.write('# Protocol: ${sessionMeta.protocolName}$eol');
          }
          if (sessionMeta.location != null && sessionMeta.location!.isNotEmpty) {
            sink.write('# Location: ${sessionMeta.location}$eol');
          }
          if (sessionMeta.operator != null && sessionMeta.operator!.isNotEmpty) {
            sink.write('# Operator: ${sessionMeta.operator}$eol');
          }
          if (sessionMeta.notes != null && sessionMeta.notes!.isNotEmpty) {
            sink.write('# Session Notes: ${sessionMeta.notes}$eol');
          }
          if (sessionMeta.customTags.isNotEmpty) {
            sink.write('# Tags: ${sessionMeta.customTags}$eol');
          }
        }
        sink.write('#$eol');
      }

      final headers = <String>[
        if (opts.includeTimestamps)
          opts.useRelativeTime ? 'Time (s)' : 'Timestamp',
        for (final c in channels) '${c.name} (${c.unit})',
      ];
      sink.write('${headers.join(sep)}$eol');

      _currentOperation = 'Writing samples...';
      _exportProgress = 0.2;
      notifyListeners();

      // `totalSamples` drives the progress bar only; a file whose header
      // disagrees with its blocks still exports every row it actually has.
      final int expected = metadata.totalSamples;
      final DateTime start = metadata.createdAt;
      int read = 0;
      int written = 0;

      await for (final MultiChannelSample sample in reader.readSamples()) {
        read++;
        if (opts.downsampleFactor > 1 &&
            (read - 1) % opts.downsampleFactor != 0) {
          continue;
        }
        // Samples may carry either recording-relative microseconds (files
        // written after the bridge was fixed) or absolute wall-clock ones
        // (older files). Normalise to relative so the range filter and the
        // timestamp column both work either way.
        final int baseMicros = start.microsecondsSinceEpoch;
        final int relativeMicros = sample.timestampMicros >= baseMicros
            ? sample.timestampMicros - baseMicros
            : sample.timestampMicros;
        final Duration t = Duration(microseconds: relativeMicros);
        if (t < opts.timeRange.startTime) continue;
        // Rows arrive in time order, so the first sample past the end is the
        // end of the export, not a row to skip.
        if (t > opts.timeRange.endTime) break;

        final row = <String>[
          if (opts.includeTimestamps)
            opts.useRelativeTime
                ? (relativeMicros / 1e6)
                    .toStringAsFixed(opts.decimalPrecision)
                : start
                    .add(Duration(microseconds: relativeMicros))
                    .toIso8601String(),
          // NaN marks a sample the channel did not carry; write it as an empty
          // cell rather than the text "NaN".
          for (final c in channels) _cell(sample.values[c.id], opts),
        ];
        sink.write('${row.join(sep)}$eol');
        written++;

        // Progress and the event loop both need a breath; every 5000 rows is
        // often enough to animate and rare enough not to dominate the export.
        if (written % 5000 == 0) {
          _exportProgress =
              expected > 0 ? 0.2 + 0.75 * (read / expected).clamp(0, 1) : 0.5;
          notifyListeners();
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (opts.includeMarkers) {
        final List<EventMarker> events = await reader.readEvents();
        if (events.isNotEmpty) {
          sink.write('#$eol# Markers & events$eol');
          sink.write('# Time (s)${sep}Type${sep}Description$eol');
          for (final EventMarker e in events) {
            sink.write('# ${(e.timestampMicros / 1e6).toStringAsFixed(3)}'
                '$sep${e.type}$sep${e.description}$eol');
          }
        }
      }

      await reader.close();
      reader = null;

      if (written == 0) {
        throw Exception('Recording contains no samples in the selected range');
      }

      await sink.flush();
      await sink.close();
      sink = null;

      _currentOperation = 'Export complete!';
      _exportProgress = 1.0;
      _isExporting = false;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('✅ Exported $written rows to CSV: $outputPath');
      }
      return outputPath;
    } catch (e) {
      _error = 'Export failed: $e';
      _isExporting = false;
      _exportProgress = 0.0;
      notifyListeners();
      if (kDebugMode) debugPrint('❌ Export error: $e');
      return null;
    } finally {
      await reader?.close();
      await sink?.close();
    }
  }

  /// A CSV cell for one channel value. A channel that carried no sample is
  /// written as NaN by the recorder, so it becomes an empty cell.
  static String _cell(double? value, CSVExportOptions opts) =>
      value == null || !value.isFinite
          ? ''
          : value.toStringAsFixed(opts.decimalPrecision);

  /// Export HRV packets to CSV format
  ///
  /// Exports HRV data in a standardized CSV format with the following columns:
  /// timestamp_ms, heart_rate, rr_interval_ms, sdnn_ms, rmssd_ms, pnn50,
  /// signal_quality, hrv_valid, mean_rr_ms, arrhythmia_flags, lf_hf,
  /// hr_from_ppg, vitals_flags
  Future<String?> exportHRVToCSV({
    required List<HRVPacketData> hrvPackets,
    required String outputFileName,
    String? sessionName,
    DateTime? recordingStart,
  }) async {
    if (hrvPackets.isEmpty) {
      _error = 'No HRV data to export';
      notifyListeners();
      return null;
    }

    _isExporting = true;
    _exportProgress = 0.0;
    _error = null;
    _currentOperation = 'Preparing HRV CSV export...';
    notifyListeners();

    try {
      // Get output directory
      final directory = await getApplicationDocumentsDirectory();
      final exportDir = Directory(path.join(directory.path, 'PortaCardio_Exports'));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final outputPath = path.join(exportDir.path, outputFileName);
      final file = File(outputPath);
      final sink = file.openWrite();

      try {
        // Write metadata header
        sink.writeln('# PortaStudio HRV Export');
        sink.writeln('# Session: ${sessionName ?? "Unknown"}');
        sink.writeln('# Recording Start: ${recordingStart?.toIso8601String() ?? "Unknown"}');
        sink.writeln('# Export Time: ${DateTime.now().toIso8601String()}');
        sink.writeln('# Total HRV Packets: ${hrvPackets.length}');
        sink.writeln('#');
        sink.writeln('# Column Descriptions:');
        sink.writeln('#   timestamp_ms: Device uptime when HRV was calculated');
        sink.writeln('#   heart_rate: ECG-derived heart rate in BPM');
        sink.writeln('#   rr_interval_ms: Most recent R-R interval in milliseconds');
        sink.writeln('#   sdnn_ms: Standard deviation of NN intervals');
        sink.writeln('#   rmssd_ms: Root mean square of successive differences');
        sink.writeln('#   pnn50: Percentage of intervals > 50ms difference (0-100)');
        sink.writeln('#   signal_quality: ECG signal quality (0-100%)');
        sink.writeln('#   hrv_valid: 1 if HRV data is valid, 0 if in learning phase');
        sink.writeln('#   mean_rr_ms: Mean R-R interval from buffer');
        sink.writeln('#   arrhythmia_flags: Bit flags (0x08=bradycardia, 0x10=tachycardia)');
        sink.writeln('#   lf_hf: LF/HF ratio (empty = not computed by the device)');
        sink.writeln('#   hr_from_ppg: 1 if heart_rate is a PPG pulse rate, not ECG');
        sink.writeln('#   vitals_flags: 0x01 HR from PPG, 0x02 ECG lead off, 0x04 PPG weak, 0x08 motion');
        sink.writeln('#   Empty cells were not reported by the device.');
        sink.writeln('#');

        _currentOperation = 'Writing HRV data...';
        _exportProgress = 0.3;
        notifyListeners();

        // Write CSV header
        sink.writeln(
          'timestamp_ms,heart_rate,rr_interval_ms,sdnn_ms,rmssd_ms,'
          'pnn50,signal_quality,hrv_valid,mean_rr_ms,arrhythmia_flags,'
          'lf_hf,hr_from_ppg,vitals_flags'
        );

        // Write data rows
        for (int i = 0; i < hrvPackets.length; i++) {
          final packet = hrvPackets[i];
          sink.writeln(
            '${packet.timestampMs},'
            '${packet.heartRate},'
            '${packet.rrIntervalMs == 0 ? '' : packet.rrIntervalMs},'
            '${packet.sdnnMs},'
            '${packet.rmssdMs},'
            '${packet.pnn50},'
            '${packet.signalQuality},'
            '${packet.hrvValid ? 1 : 0},'
            '${packet.meanRrMs == 0 ? '' : packet.meanRrMs},'
            '${packet.arrhythmiaFlags},'
            '${packet.lfHf?.toStringAsFixed(1) ?? ''},'
            '${packet.hrFromPpg ? 1 : 0},'
            '${packet.vitalsFlags}'
          );

          // Update progress periodically
          if (i % 10 == 0) {
            _exportProgress = 0.3 + (0.6 * i / hrvPackets.length);
            notifyListeners();
          }
        }

        await sink.close();

        _currentOperation = 'HRV export complete!';
        _exportProgress = 1.0;
        notifyListeners();

        if (kDebugMode) {
          debugPrint('✅ Exported HRV to CSV: $outputPath');
          debugPrint('   Total packets: ${hrvPackets.length}');
        }

        _isExporting = false;
        notifyListeners();

        return outputPath;
      } catch (e) {
        await sink.close();
        rethrow;
      }
    } catch (e) {
      _error = 'HRV export failed: $e';
      _isExporting = false;
      _exportProgress = 0.0;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('❌ HRV export error: $e');
      }

      return null;
    }
  }

  /// Get the exports directory
  Future<Directory> getExportsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDir = Directory(path.join(directory.path, 'PortaCardio_Exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'Unknown';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
