import 'package:flutter/material.dart';
import '../../domain/usecases/health_score.dart';

class HealthScoreCard extends StatelessWidget {
  final HealthScoreResult result;

  const HealthScoreCard({Key? key, required this.result}) : super(key: key);

  Color _getColor() {
    if (result.band == 'Excellent') return Colors.green;
    if (result.band == 'Good') return Colors.lightGreen;
    if (result.band == 'Fair') return Colors.orange;
    if (result.band == 'Needs Attention') return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inventory Health Score', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(result.score.toStringAsFixed(0),
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(width: 12),
                Text(result.band, style: TextStyle(fontSize: 18, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            if (result.factors.isNotEmpty)
              Text('Factors: ' + result.factors.entries.map((e) => e.key + ': ' + e.value.toStringAsFixed(0)).join(', ')),
          ],
        ),
      ),
    );
  }
}
