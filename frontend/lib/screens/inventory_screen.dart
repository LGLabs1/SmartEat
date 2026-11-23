import 'package:flutter/material.dart';
import '../features/inventory/inventory_module.dart';
import '../theme.dart';
import '../widgets/dashboard/dashboard_back_handler.dart';
import '../widgets/smart_eat_header.dart';

class InventoryScreen extends StatefulWidget {
  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onBackNeeded;
  final bool isInDetailView;
  final Function(VoidCallback resetFn)? onResetRequest;
  final DashboardBackHandlerChanged? onBackHandlerChanged;

  const InventoryScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onBackNeeded,
    this.isInDetailView = false,
    this.onResetRequest,
    this.onBackHandlerChanged,
  }) : super(key: key);

  @override
  State<InventoryScreen> createState() => InventoryScreenState();
}

class InventoryScreenState extends State<InventoryScreen> {
  @override
  Widget build(BuildContext context) {
    final content = InventoryModule(
      onBackHandlerChanged: widget.onBackHandlerChanged,
    );
    if (!widget.showAppBar) return content;
    return Scaffold(
      backgroundColor: AppTheme.sageNavy,
      appBar: SmartEatHeader(
        titleText: 'Inventory',
        leading: widget.onOpenDrawer != null
            ? IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        showBackButton: widget.onOpenDrawer == null,
        actions: const [SizedBox(width: 4)],
      ),
      body: content,
    );
  }
}
