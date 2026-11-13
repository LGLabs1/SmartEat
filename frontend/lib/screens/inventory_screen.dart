import 'package:flutter/material.dart';
import '../features/inventory/inventory_module.dart';

class InventoryScreen extends StatefulWidget {
  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onBackNeeded;
  final bool isInDetailView;
  final Function(VoidCallback resetFn)? onResetRequest;

  const InventoryScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onBackNeeded,
    this.isInDetailView = false,
    this.onResetRequest,
  }) : super(key: key);

  @override
  State<InventoryScreen> createState() => InventoryScreenState();
}

class InventoryScreenState extends State<InventoryScreen> {
  @override
  Widget build(BuildContext context) {
    return const InventoryModule();
  }
}
