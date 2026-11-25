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
  late String _status;

  @override
  void initState() {
    super.initState();
    _isEditing = false;
    _positionController = TextEditingController(text: widget.position);
    _status = widget.status;
  }

  @override
  void dispose() {
    _positionController.dispose();
    super.dispose();
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
                backgroundColor: widget.isAdmin
                    ? AppTheme.sageBlue
                    : Colors.white.withValues(alpha: 0.14),
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
                        color: Colors.white.withValues(alpha: 0.6),
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

          _buildInfoRow(
            Icons.payments_outlined,
            'Pay rates',
            'Managed in Payroll',
          ),
          const SizedBox(height: 12),

          // Status
          _buildInfoRow(
            Icons.circle,
            'Status',
            widget.status.isNotEmpty ? widget.status : 'active',
            statusColor: widget.status == 'active'
                ? AppTheme.sageSuccess
                : Colors.white.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? statusColor}) {
    return Row(
      children: [
        Icon(icon,
            size: 20,
            color:
                statusColor ?? Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: statusColor ?? Colors.white,
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
    final errorColor = Theme.of(context).colorScheme.error;

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
              icon: Icon(Icons.delete_forever, color: errorColor),
              label: Text('Remove', style: TextStyle(color: errorColor)),
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
                dailyRate: widget.dailyRate,
                halfDayRate: widget.halfDayRate,
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
