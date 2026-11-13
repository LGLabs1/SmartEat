part of 'package:smarteat/screens/staff_management_screen.dart';

class _MealsTab extends StatefulWidget {
  final String eateryId;

  const _MealsTab({required this.eateryId});

  @override
  State<_MealsTab> createState() => _MealsTabState();
}

class _MealsTabState extends State<_MealsTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _mealOrders = [];
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String _statusFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMealOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMealOrders() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getStaffMealOrders(
        eateryId: widget.eateryId,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        setState(() {
          _mealOrders = List<Map<String, dynamic>>.from(response['data'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load meal orders: $e')),
        );
      }
    }
  }

  // Optimistic update helper
  void _updateMealOrderStatusLocal(String orderId, String status) {
    setState(() {
      _mealOrders = _mealOrders.map((order) {
        if (order['id'] == orderId) {
          return {...order, 'status': status};
        }
        return order;
      }).toList();
    });
  }

  List<Map<String, dynamic>> get _filteredOrders => _mealOrders
      .where((order) => staffMealMatchesFilter(
            order: order,
            statusFilter: _statusFilter,
            query: _searchQuery,
          ))
      .toList();

  int _countByStatus(String status) {
    return _mealOrders.where((order) {
      final value = (order['status'] ?? 'pending').toString().toLowerCase();
      return value == status;
    }).length;
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await ApiService.updateStaffMealOrderStatus(
        orderId,
        eateryId: widget.eateryId,
        status: status,
      );
      // Optimistic update - update status in local list without full refresh
      _updateMealOrderStatusLocal(orderId, status);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order $status')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update order: $e')),
        );
      }
    }
  }

  double _calculateTotalCost() {
    return _mealOrders
        .where((order) =>
            (order['status'] ?? '').toString().toLowerCase() != 'cancelled')
        .fold(0.0, (sum, order) => sum + staffMealOrderTotal(order));
  }

  Widget _buildStatusChip(String value, String label, int count) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: _statusFilter == value,
      onSelected: (_) => setState(() => _statusFilter = value),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = (order['items'] as List?) ?? [];
    final total = staffMealOrderTotal(order);
    final status = (order['status'] ?? 'pending').toString().toLowerCase();
    final statusColor = status == 'completed'
        ? Colors.green
        : status == 'cancelled'
            ? Colors.grey
            : Colors.orange;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order by ${order['staffName'] ?? 'Unknown'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: $status',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Date: ${order['createdAt'] ?? ''}'),
              if (order['notes'] != null &&
                  order['notes'].toString().isNotEmpty)
                Text('Notes: ${order['notes']}'),
              const SizedBox(height: 16),
              const Divider(),
              const Text('Items:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...items.map((item) => ListTile(
                    title: Text(item['name'] ?? 'Unknown'),
                    trailing: Text(
                      '${item['quantity']} x ₱${(item['price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                  )),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total: ₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (status == 'pending') ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateOrderStatus(order['id'], 'cancelled');
              },
              child: const Text('Cancel order'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateOrderStatus(order['id'], 'completed');
              },
              child: const Text('Mark Completed'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCost = _calculateTotalCost();
    final visibleOrders = _filteredOrders;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range picker and summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: _endDate,
                            );
                            if (date != null) {
                              setState(() => _startDate = date);
                              _loadMealOrders();
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'From',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _endDate,
                              firstDate: _startDate,
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() => _endDate = date);
                              _loadMealOrders();
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'To',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search staff, notes, or items',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatusChip('all', 'All', _mealOrders.length),
                      _buildStatusChip(
                        'pending',
                        'Pending',
                        _countByStatus('pending'),
                      ),
                      _buildStatusChip(
                        'completed',
                        'Completed',
                        _countByStatus('completed'),
                      ),
                      _buildStatusChip(
                        'cancelled',
                        'Cancelled',
                        _countByStatus('cancelled'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Showing ${visibleOrders.length} of ${_mealOrders.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total Cost: ₱${totalCost.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Meal orders list
          Expanded(
            child: _isLoading
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                      SkeletonListTile(hasLeading: true, hasSubtitle: true),
                    ],
                  )
                : visibleOrders.isEmpty
                    ? Center(
                        child: Text(
                          _mealOrders.isEmpty
                              ? 'No meal orders found'
                              : 'No meal orders match your filters',
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMealOrders,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visibleOrders.length,
                          itemBuilder: (context, index) {
                            final order = visibleOrders[index];
                            final items = (order['items'] as List?) ?? [];
                            final itemCount = items.fold(0, (sum, item) {
                              return sum +
                                  ((item['quantity'] as num?)?.toInt() ?? 0);
                            });
                            final total = staffMealOrderTotal(order);
                            final status = (order['status'] ?? 'pending')
                                .toString()
                                .toLowerCase();
                            final createdRaw =
                                (order['createdAt'] ?? '').toString();
                            final createdLabel = createdRaw.length >= 10
                                ? createdRaw.substring(0, 10)
                                : createdRaw;

                            late final Color statusColor;
                            late final IconData statusIcon;
                            late final String statusLabel;
                            if (status == 'completed') {
                              statusColor = Colors.green;
                              statusIcon = Icons.check;
                              statusLabel = 'Completed';
                            } else if (status == 'cancelled') {
                              statusColor = Colors.grey;
                              statusIcon = Icons.cancel;
                              statusLabel = 'Cancelled';
                            } else {
                              statusColor = Colors.orange;
                              statusIcon = Icons.access_time;
                              statusLabel = 'Pending';
                            }

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: statusColor,
                                  child: Icon(
                                    statusIcon,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(order['staffName'] ?? 'Unknown'),
                                subtitle: Text(
                                  '$itemCount items • '
                                  '₱${total.toStringAsFixed(2)} • '
                                  '$statusLabel',
                                ),
                                trailing: Text(
                                  createdLabel,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () => _showOrderDetails(order),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
