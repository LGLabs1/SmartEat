part of 'package:smarteat/screens/staff_management_screen.dart';

class _StaffProfileResult {
  final String position;
  final double dailyRate;
  final double halfDayRate;
  final String status;

  _StaffProfileResult({
    required this.position,
    required this.dailyRate,
    required this.halfDayRate,
    required this.status,
  });
}

class _StaffProfileDialog extends StatefulWidget {
  final String userName;
  final String email;
  final bool isAdmin;
  final String joinedDate;
  final String position;
  final double dailyRate;
  final double halfDayRate;
  final String status;
  final VoidCallback? onRemove;

  const _StaffProfileDialog({
    required this.userName,
    required this.email,
    required this.isAdmin,
    required this.joinedDate,
    required this.position,
    required this.dailyRate,
    required this.halfDayRate,
    required this.status,
    this.onRemove,
  });

  @override
  State<_StaffProfileDialog> createState() => _StaffProfileDialogState();
}

class _StaffProfileDialogState extends State<_StaffProfileDialog> {
  late bool _isEditing;
  late TextEditingController _positionController;
  late TextEditingController _dailyRateController;
  late TextEditingController _halfDayRateController;
  late String _status;

  @override
  void initState() {
    super.initState();
    _isEditing = false;
    _positionController = TextEditingController(text: widget.position);
    _dailyRateController = TextEditingController(
      text: widget.dailyRate > 0 ? widget.dailyRate.toStringAsFixed(2) : '',
    );
    _halfDayRateController = TextEditingController(
      text: widget.halfDayRate > 0 ? widget.halfDayRate.toStringAsFixed(2) : '',
    );
    _status = widget.status;
  }

  @override
  void dispose() {
    _positionController.dispose();
    _dailyRateController.dispose();
    _halfDayRateController.dispose();
    super.dispose();
  }

  double _parseDouble(String value) {
    if (value.trim().isEmpty) return 0.0;
    return double.tryParse(value.trim()) ?? 0.0;
  }

  Widget _buildReadOnlyView() {
    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info header
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    widget.isAdmin ? Colors.indigo : Colors.grey.shade400,
                child: Icon(
                  widget.isAdmin
                      ? Icons.admin_panel_settings
                      : Icons.badge_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.email.isNotEmpty ? widget.email : 'No email',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Joined date
          _buildInfoRow(Icons.calendar_today, 'Joined', widget.joinedDate),
          const SizedBox(height: 12),

          // Role
          _buildInfoRow(
            widget.isAdmin ? Icons.admin_panel_settings : Icons.badge_outlined,
            'Role',
            widget.isAdmin ? 'Admin' : 'Staff',
          ),
          const SizedBox(height: 12),

          // Position
          _buildInfoRow(Icons.work_outline, 'Position',
              widget.position.isNotEmpty ? widget.position : 'Not set'),
          const SizedBox(height: 12),

          // Daily rate
          _buildInfoRow(
            Icons.attach_money,
            'Daily Rate',
            widget.dailyRate > 0
                ? '₱${widget.dailyRate.toStringAsFixed(2)}'
                : 'Not set',
          ),
          const SizedBox(height: 12),

          // Half-day rate (now exact amount)
          _buildInfoRow(
            Icons.timer_outlined,
            'Half-Day Rate',
            widget.halfDayRate > 0
                ? '₱${widget.halfDayRate.toStringAsFixed(2)}'
                : 'Not set',
          ),
          const SizedBox(height: 12),

          // Status
          _buildInfoRow(
            Icons.circle,
            'Status',
            widget.status.isNotEmpty ? widget.status : 'active',
            statusColor: widget.status == 'active' ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? statusColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: statusColor ?? Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: statusColor ?? Colors.grey.shade900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditView() {
    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _positionController,
            decoration: const InputDecoration(
              labelText: 'Position',
              prefixIcon: Icon(Icons.work_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dailyRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daily rate (₱)',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _halfDayRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Half-day rate (₱) - exact amount',
              prefixIcon: Icon(Icons.timer_outlined),
              helperText: 'Enter exact amount (not percentage)',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _status = v);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.circle_outlined),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Staff profile: ${widget.userName}'),
      content: _isEditing ? _buildEditView() : _buildReadOnlyView(),
      actions: [
        if (!_isEditing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (widget.onRemove != null)
            TextButton.icon(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          FilledButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
          ),
        ] else ...[
          TextButton(
            onPressed: () => setState(() => _isEditing = false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final result = _StaffProfileResult(
                position: _positionController.text.trim(),
                dailyRate: _parseDouble(_dailyRateController.text),
                halfDayRate: _parseDouble(_halfDayRateController.text),
                status: _status,
              );
              Navigator.of(context).pop(result);
            },
            child: const Text('Save'),
          ),
        ],
      ],
    );
  }
}

