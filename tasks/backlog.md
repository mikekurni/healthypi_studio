# Backlog

Features and improvements noted but not yet planned.

## Calipers (measurement tool) on the Live canvas

- Status: next feature
- Location: `lib/screens/studio/live_screen.dart` (toolbar, `_MarkerButton` neighbour), `lib/widgets/hpi/hpi_wave.dart` (`HpiWaveTrace`)
- Needs: cursor painting in `HpiWaveTrace`, pointer handling, snap-to-sample, readout widget
- Effort: ~half a day
- Notes: a `showCursors` flag already exists but no painter reads it, so the toolbar button is disabled. Remove the placeholder or implement the tool.