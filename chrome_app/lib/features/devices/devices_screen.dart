import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../data/api_service.dart';
import '../../data/models.dart';
import '../../data/supabase_service.dart';

/// Manage cameras / monitoring devices for the signed-in user.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Device> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final userId = context.read<SupabaseService>().userId;
    if (userId == null) return;
    setState(() => _loading = true);
    final devices = await ApiService.listDevices(userId);
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _openEditor({Device? existing}) async {
    final userId = context.read<SupabaseService>().userId;
    if (userId == null) return;

    final result = await showModalBottomSheet<_DeviceFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceFormSheet(existing: existing),
    );
    if (result == null) return;

    if (existing == null) {
      final newDevice = Device(
        deviceId: '',
        userId: userId,
        deviceName: result.name,
        deviceType: result.type,
        streamUrl: result.streamUrl,
        location: result.location,
        status: result.status,
      );
      await ApiService.createDevice(newDevice);
    } else {
      await ApiService.updateDevice(existing.deviceId, {
        'device_name': result.name,
        'device_type': result.type,
        'stream_url': result.streamUrl,
        'location': result.location,
        'status': result.status,
      });
    }
    await _refresh();
  }

  Future<void> _delete(Device d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text('Remove "${d.deviceName}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.deleteDevice(d.deviceId);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
        backgroundColor: AppColors.accentPrimary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_outlined,
                            size: 64,
                            color: isDark ? Colors.white24 : Colors.black26),
                        const SizedBox(height: 16),
                        const Text('No devices yet',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                          'Add a camera or stream to monitor.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _devices.length,
                    itemBuilder: (_, i) => _DeviceCard(
                      device: _devices[i],
                      onEdit: () => _openEditor(existing: _devices[i]),
                      onDelete: () => _delete(_devices[i]),
                      onStatusChanged: _refresh,
                    ),
                  ),
                ),
    );
  }
}

// ─── Device card ─────────────────────────────────────────────────────────────

class _DeviceCard extends StatefulWidget {
  final Device device;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStatusChanged;

  const _DeviceCard({
    required this.device,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
  });

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  String _monitorStatus = 'stopped';
  bool _toggling = false;

  Device get device => widget.device;

  @override
  void initState() {
    super.initState();
    _pollStatus();
  }

  Future<void> _pollStatus() async {
    final status = await ApiService.getDeviceMonitorStatus(device.deviceId);
    if (mounted) setState(() => _monitorStatus = status);
  }

  Future<void> _toggleMonitor() async {
    setState(() => _toggling = true);
    bool ok;
    if (_monitorStatus == 'monitoring' || _monitorStatus == 'connecting') {
      ok = await ApiService.stopDeviceMonitor(device.deviceId);
      if (ok && mounted) setState(() => _monitorStatus = 'stopped');
    } else {
      ok = await ApiService.startDeviceMonitor(device.deviceId);
      if (ok && mounted) setState(() => _monitorStatus = 'connecting');
      // Poll after a short delay to confirm it started
      await Future.delayed(const Duration(seconds: 2));
      await _pollStatus();
    }
    if (mounted) setState(() => _toggling = false);
    widget.onStatusChanged();
  }

  Color _statusColor() {
    switch (_monitorStatus) {
      case 'monitoring':
        return AppColors.accentGreen;
      case 'connecting':
        return AppColors.warning;
      case 'error':
        return AppColors.danger;
      default:
        // Fall back to device DB status
        if (device.status == 'active') return AppColors.accentGreen;
        if (device.status == 'offline') return AppColors.danger;
        return Colors.grey;
    }
  }

  String _statusLabel() {
    switch (_monitorStatus) {
      case 'monitoring':
        return 'Monitoring';
      case 'connecting':
        return 'Connecting…';
      case 'error':
        return 'Error';
      default:
        return device.status;
    }
  }

  IconData _typeIcon() {
    switch (device.deviceType) {
      case 'rtsp':
        return Icons.stream;
      case 'mobile':
        return Icons.phone_android;
      case 'camera':
        return Icons.videocam_outlined;
      default:
        return Icons.devices_other;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasStream = device.streamUrl != null && device.streamUrl!.isNotEmpty;
    final isRunning = _monitorStatus == 'monitoring' || _monitorStatus == 'connecting';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRunning
              ? AppColors.accentGreen.withValues(alpha: 0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(), color: AppColors.accentPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.deviceName,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _statusColor(),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _statusLabel(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        if (device.location != null &&
                            device.location!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.place_outlined,
                              size: 12,
                              color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              device.location!,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) =>
                    v == 'edit' ? widget.onEdit() : widget.onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          // ── Start / Stop toggle ──────────────────────────────────────
          if (hasStream) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: _toggling
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _toggleMonitor,
                      icon: Icon(
                        isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
                        size: 18,
                        color: isRunning ? AppColors.danger : AppColors.accentGreen,
                      ),
                      label: Text(
                        isRunning ? 'Stop monitoring' : 'Start monitoring',
                        style: TextStyle(
                          fontSize: 13,
                          color: isRunning ? AppColors.danger : AppColors.accentGreen,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: (isRunning ? AppColors.danger : AppColors.accentGreen)
                              .withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Form result & bottom sheet ──────────────────────────────────────────────

class _DeviceFormResult {
  final String name;
  final String type;
  final String? streamUrl;
  final String? location;
  final String status;
  _DeviceFormResult({
    required this.name,
    required this.type,
    required this.streamUrl,
    required this.location,
    required this.status,
  });
}

class _DeviceFormSheet extends StatefulWidget {
  final Device? existing;
  const _DeviceFormSheet({this.existing});

  @override
  State<_DeviceFormSheet> createState() => _DeviceFormSheetState();
}

class _DeviceFormSheetState extends State<_DeviceFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _stream;
  late final TextEditingController _location;
  late String _type;
  late String _status;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.deviceName ?? '');
    _stream = TextEditingController(text: e?.streamUrl ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _type = e?.deviceType ?? 'camera';
    _status = e?.status ?? 'inactive';
  }

  @override
  void dispose() {
    _name.dispose();
    _stream.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  widget.existing == null ? 'Add device' : 'Edit device',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Device name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                      value: 'camera', child: Text('Camera')),
                  DropdownMenuItem(
                      value: 'rtsp', child: Text('RTSP stream')),
                  DropdownMenuItem(
                      value: 'mobile', child: Text('Mobile')),
                  DropdownMenuItem(
                      value: 'other', child: Text('Other')),
                ],
                onChanged: (v) =>
                    setState(() => _type = v ?? 'camera'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stream,
                decoration: const InputDecoration(
                  labelText: 'Stream URL (optional)',
                  hintText: 'rtsp://… or https://…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  hintText: 'Living room, Kitchen, …',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(
                      value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                      value: 'inactive', child: Text('Inactive')),
                  DropdownMenuItem(
                      value: 'offline', child: Text('Offline')),
                ],
                onChanged: (v) =>
                    setState(() => _status = v ?? 'inactive'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (_name.text.trim().isEmpty) return;
                        Navigator.pop(
                          context,
                          _DeviceFormResult(
                            name: _name.text.trim(),
                            type: _type,
                            streamUrl: _stream.text.trim().isEmpty
                                ? null
                                : _stream.text.trim(),
                            location: _location.text.trim().isEmpty
                                ? null
                                : _location.text.trim(),
                            status: _status,
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentPrimary),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
