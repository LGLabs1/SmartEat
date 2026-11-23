import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';
import '../widgets/sage_header_button.dart';
import '../widgets/smart_eat_header.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SmartEatHeader(
        titleText: 'About',
        actions: const [SageHeaderButton(), SizedBox(width: 8)],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(height: 96),
              const SizedBox(height: 20),
              Text(
                'SmartEat',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Eatery Management System',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
