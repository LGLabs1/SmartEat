import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'presentation/providers/inventory_notifier.dart';
import 'presentation/providers/purchase_list_notifier.dart';
import 'presentation/screens/inventory_feature_screen.dart';
import '../../widgets/dashboard/dashboard_back_handler.dart';

class InventoryModule extends StatelessWidget {
  const InventoryModule({Key? key, this.onBackHandlerChanged})
      : super(key: key);

  final DashboardBackHandlerChanged? onBackHandlerChanged;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryNotifier()),
        ChangeNotifierProvider(create: (_) => PurchaseListNotifier()),
      ],
      child: InventoryFeatureScreen(
        onBackHandlerChanged: onBackHandlerChanged,
      ),
    );
  }
}
