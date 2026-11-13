import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'presentation/providers/inventory_notifier.dart';
import 'presentation/providers/purchase_list_notifier.dart';
import 'presentation/screens/inventory_feature_screen.dart';

class InventoryModule extends StatelessWidget {
  const InventoryModule({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryNotifier()),
        ChangeNotifierProvider(create: (_) => PurchaseListNotifier()),
      ],
      child: const InventoryFeatureScreen(),
    );
  }
}
