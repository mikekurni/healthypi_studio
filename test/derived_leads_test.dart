import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/controllers/channel_controller.dart';
import 'package:healthypi_studio/models/waveform_models.dart';
import 'package:healthypi_studio/services/live_data_pump.dart';
import 'package:healthypi_studio/theme/hpi_tokens.dart';

/// Captures what would have reached the recorder.
class _FakeBridge {
  Map<String, double>? last;

  void onDataAdded(Map<String, double> values) => last = values;
}

void main() {
  group('Derived leads', () {
    test('follow Einthoven and the Goldberger relations', () {
      final leads = LiveDataPump.derivedLeads(100, 300);
      expect(leads['lead_iii'], 200); // II - I
      expect(leads['avr'], -200); // -(I + II) / 2
      expect(leads['avl'], -50); // I - II / 2
      expect(leads['avf'], 250); // II - I / 2
    });

    test('are zero when both limb leads are zero', () {
      expect(
        LiveDataPump.derivedLeads(0, 0).values.every((v) => v == 0),
        isTrue,
      );
    });

    test('the seven ECG leads darken from Lead I to V1 in both themes', () {
      const ids = ['ecg1', 'ecg2', 'lead_iii', 'avr', 'avl', 'avf', 'ecg3'];
      for (final ramp in [HpiTraceRamp.dark, HpiTraceRamp.light]) {
        for (var i = 1; i < ids.length; i++) {
          expect(ramp.forChannel(ids[i]).computeLuminance(),
              lessThan(ramp.forChannel(ids[i - 1]).computeLuminance()),
              reason: '${ids[i]} must be darker than ${ids[i - 1]}');
        }
      }
    });

    test('are marked computed and recorded with the measured leads', () {
      final controller = ChannelController(
        initialChannels: [
          ChannelConfiguration(id: 'ecg1', label: 'Lead I', unit: 'mV'),
          ChannelConfiguration(id: 'ecg2', label: 'Lead II', unit: 'mV'),
          ChannelConfiguration(
            id: 'avr',
            label: 'aVR',
            unit: 'mV',
            computed: true,
          ),
        ],
      );
      final bridge = _FakeBridge();
      controller.setRecordingBridge(bridge);

      controller.addDataPointsSync({
        'ecg1': 1.0,
        'ecg2': 2.0,
        ...LiveDataPump.derivedLeads(1.0, 2.0),
      });

      expect(bridge.last, isNotNull);
      expect(bridge.last!.keys, containsAll(['ecg1', 'ecg2', 'avr']));
      expect(bridge.last!['avr'], LiveDataPump.derivedLeads(1.0, 2.0)['avr'],
          reason: 'a saved recording should open with the leads on screen');
      expect(controller.getChannel('avr')!.buffer.first.value,
          LiveDataPump.derivedLeads(1.0, 2.0)['avr'],
          reason: 'the channel itself still buffers the computed value');
    });
  });

  group('Gutter detail', () {
    // JetBrains Mono at 9.5px advances 5.7px per character. The gutter is
    // 118px wide with 10px of padding and a 1px border, so 97px of text room:
    // 17 characters measure 96.9px and already ellipsize.
    test('fits one line for every channel', () {
      for (final config in LiveDataPump.liveChannels) {
        expect(
          LiveDataPump.channelDetail(config.id).length,
          lessThanOrEqualTo(16),
          reason: '${config.id} detail must fit the gutter on one line',
        );
      }
    });

    test('marks the derived leads as computed', () {
      for (final id in ['lead_iii', 'avr', 'avl', 'avf']) {
        expect(LiveDataPump.channelDetail(id), contains('computed'));
      }
      expect(LiveDataPump.channelDetail('ecg1'), isNot(contains('computed')));
    });
  });
}
