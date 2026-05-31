import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class DamagedItemsScreen extends StatefulWidget {
  const DamagedItemsScreen({Key? key}) : super(key: key);

  @override
  State<DamagedItemsScreen> createState() => _DamagedItemsScreenState();
}

class _DamagedItemsScreenState extends State<DamagedItemsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadDamagedItems();
  }

  Future<void> _loadDamagedItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.getDamagedItems();
      final items = (response['data'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double get _totalDamagedCost {
    return _items.fold(0.0, (sum, item) {
      final cost = (item['totalCost'] ?? 0).toDouble();
      return sum + cost;
    });
  }

  String _formatCurrency(double value) {
    return '₱${value.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Damaged Items'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDamagedItems,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Failed to load damaged items.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error ?? '',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadDamagedItems,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Damaged Cost',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatCurrency(_totalDamagedCost),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.report_problem_outlined,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_items.length} records',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _items.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 56,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No damaged items recorded yet.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  final name = (item['name'] ?? '').toString();
                                  final qty = (item['quantity'] ?? 0).toString();
                                  final unit = (item['unit'] ?? '').toString();
                                  final cost = (item['totalCost'] ?? 0).toDouble();
                                  final reason = (item['reason'] ?? '').toString();
                                  final recordedAt = item['createdAt'];
                                  String dateLabel = '';
                                  if (recordedAt is String) {
                                    dateLabel = recordedAt;
                                  } else if (recordedAt is DateTime) {
                                    dateLabel = recordedAt.toLocal().toString();
                                  } else if (recordedAt is Timestamp) {
                                    dateLabel = recordedAt.toDate().toLocal().toString();
                                  }

                                  return Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      'Quantity: $qty$unit',
                                                      style: TextStyle(
                                                        color: Colors.grey.shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _formatCurrency(cost),
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Reason: ${reason.isEmpty ? 'Damaged item' : reason}',
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                          if (dateLabel.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Recorded: $dateLabel',
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
