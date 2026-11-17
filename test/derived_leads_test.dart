import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/controllers/channel_controller.dart';
import 'package:healthypi_studio/models/waveform_models.dart';
import 'package:healthypi_studio/services/live_data_pump.dart';

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

    test('are marked computed and never reach the recording bridge', () {
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
      expect(bridge.last!.keys, containsAll(['ecg1', 'ecg2']));
      expect(bridge.last!.containsKey('avr'), isFalse,
          reason: 'computed leads are rebuilt from Lead I and II on read');
      expect(controller.getChannel('avr')!.buffer.first.value,
          LiveDataPump.derivedLeads(1.0, 2.0)['avr'],
          reason: 'the channel itself still buffers the computed value');
    });
  });
}
