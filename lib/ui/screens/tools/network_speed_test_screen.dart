import 'package:flutter/material.dart';
import '../../../services/network_speed_test_service.dart';

class NetworkSpeedTestScreen extends StatefulWidget {
  const NetworkSpeedTestScreen({super.key});

  @override
  State<NetworkSpeedTestScreen> createState() => _NetworkSpeedTestScreenState();
}

class _NetworkSpeedTestScreenState extends State<NetworkSpeedTestScreen> {
  final _speedService = NetworkSpeedTestService.instance;

  @override
  void initState() {
    super.initState();
    _speedService.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speedService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  Future<void> _startTest() async {
    try {
      await _speedService.runFullTest();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = _speedService.currentStage;
    final isTesting = stage == SpeedTestStage.testingPing ||
        stage == SpeedTestStage.testingDownload ||
        stage == SpeedTestStage.testingUpload;
    final result = _speedService.lastResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Speed Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Gauge & Live Speed Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Circular Speedometer Indicator
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 190,
                        child: CircularProgressIndicator(
                          value: isTesting
                              ? (_speedService.currentSpeedMbps / 150).clamp(0.05, 1.0)
                              : (result != null ? (result.downloadMbps / 150).clamp(0.05, 1.0) : 0.0),
                          strokeWidth: 10,
                          backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          color: _getStageColor(stage, theme),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isTesting
                                ? _speedService.currentSpeedMbps.toStringAsFixed(1)
                                : (result != null ? result.downloadMbps.toStringAsFixed(1) : '0.0'),
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1,
                            ),
                          ),
                          const Text(
                            'Mbps',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Stage Label
                  Text(
                    _getStageLabel(stage),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _getStageColor(stage, theme),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Metrics Row: Ping, Jitter, Download, Upload
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Ping',
                    value: isTesting || result != null ? '${_speedService.currentPingMs} ms' : '--',
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Jitter',
                    value: isTesting || result != null ? '${_speedService.currentJitterMs} ms' : '--',
                    icon: Icons.alt_route_outlined,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Download',
                    value: result != null ? '${result.downloadMbps} Mbps' : '--',
                    icon: Icons.arrow_downward_rounded,
                    highlightColor: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricTile(
                    theme,
                    title: 'Upload',
                    value: result != null ? '${result.uploadMbps} Mbps' : '--',
                    icon: Icons.arrow_upward_rounded,
                    highlightColor: Colors.purpleAccent,
                  ),
                ),
              ],
            ),

            // Connection Rating Banner if completed
            if (result != null && !isTesting) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade700, width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Connection Quality',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            result.rating,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Start / Retest Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isTesting ? () => _speedService.cancel() : _startTest,
                icon: Icon(isTesting ? Icons.stop : Icons.speed),
                label: Text(
                  isTesting ? 'Cancel Speed Test' : (result != null ? 'Test Again' : 'Start Speed Test'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: isTesting ? Colors.redAccent : theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    ThemeData theme, {
    required String title,
    required String value,
    required IconData icon,
    Color? highlightColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: highlightColor ?? Colors.grey),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: highlightColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStageLabel(SpeedTestStage stage) {
    switch (stage) {
      case SpeedTestStage.testingPing:
        return 'Measuring Latency & Jitter...';
      case SpeedTestStage.testingDownload:
        return 'Testing Download Speed...';
      case SpeedTestStage.testingUpload:
        return 'Testing Upload Speed...';
      case SpeedTestStage.completed:
        return 'Test Completed';
      case SpeedTestStage.failed:
        return 'Test Interrupted';
      case SpeedTestStage.idle:
      default:
        return 'Tap "Start Speed Test" to begin';
    }
  }

  Color _getStageColor(SpeedTestStage stage, ThemeData theme) {
    switch (stage) {
      case SpeedTestStage.testingPing:
        return Colors.orangeAccent;
      case SpeedTestStage.testingDownload:
        return Colors.blueAccent;
      case SpeedTestStage.testingUpload:
        return Colors.purpleAccent;
      case SpeedTestStage.completed:
        return Colors.green;
      case SpeedTestStage.failed:
        return Colors.redAccent;
      case SpeedTestStage.idle:
      default:
        return theme.colorScheme.primary;
    }
  }
}
