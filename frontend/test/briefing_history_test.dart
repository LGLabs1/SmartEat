import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/briefing_history.dart';
import 'package:smarteat/widgets/sage_briefing_card.dart';

SageBriefingContent _briefing(String period, DateTime at) => SageBriefingContent(
      id: '${briefingDateKey(at)}_$period',
      title: 'title',
      summary: 'summary',
      periodLabel: 'label',
      generatedAt: at,
      recommendation: 'rec',
      businessHealth: 'Good (75/100)',
      detailText: 'detail',
      period: period,
    );

void main() {
  group('briefingDateKey', () {
    test('zero-pads month and day', () {
      expect(briefingDateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('is lexicographically sortable', () {
      final keys = [
        briefingDateKey(DateTime(2026, 3, 2)),
        briefingDateKey(DateTime(2026, 10, 1)),
        briefingDateKey(DateTime(2025, 12, 31)),
      ]..sort();
      expect(keys, ['2025-12-31', '2026-03-02', '2026-10-01']);
    });
  });

  group('period helpers', () {
    test('rank orders morning before afternoon before evening', () {
      expect(briefingPeriodRank('morning'), lessThan(briefingPeriodRank('afternoon')));
      expect(briefingPeriodRank('afternoon'), lessThan(briefingPeriodRank('evening')));
    });

    test('unknown period ranks after known ones', () {
      expect(briefingPeriodRank('midnight'), greaterThan(briefingPeriodRank('evening')));
    });

    test('short labels are presentable', () {
      expect(briefingPeriodShortLabel('morning'), 'Morning');
      expect(briefingPeriodShortLabel('afternoon'), 'Afternoon');
      expect(briefingPeriodShortLabel('evening'), 'Evening');
      expect(briefingPeriodShortLabel('other'), 'Briefing');
    });

    test('emoji fallback for unknown period', () {
      expect(briefingPeriodEmoji('other'), '✨');
    });
  });

  group('groupBriefingsByDate', () {
    test('groups by day and sorts each day by period', () {
      final grouped = groupBriefingsByDate([
        _briefing('evening', DateTime(2026, 5, 1, 18)),
        _briefing('morning', DateTime(2026, 5, 1, 7)),
        _briefing('afternoon', DateTime(2026, 5, 1, 13)),
        _briefing('morning', DateTime(2026, 5, 2, 7)),
      ]);

      expect(grouped.keys.toSet(), {'2026-05-01', '2026-05-02'});
      expect(
        grouped['2026-05-01']!.map((b) => b.period).toList(),
        ['morning', 'afternoon', 'evening'],
      );
      expect(grouped['2026-05-02']!.single.period, 'morning');
    });
  });

  group('sortedBriefingDateKeysDesc', () {
    test('returns newest day first', () {
      final grouped = groupBriefingsByDate([
        _briefing('morning', DateTime(2025, 12, 31, 7)),
        _briefing('morning', DateTime(2026, 1, 2, 7)),
        _briefing('morning', DateTime(2026, 1, 1, 7)),
      ]);
      expect(sortedBriefingDateKeysDesc(grouped), [
        '2026-01-02',
        '2026-01-01',
        '2025-12-31',
      ]);
    });
  });

  group('startedBriefingPeriods', () {
    test('nothing before 6am', () {
      expect(startedBriefingPeriods(DateTime(2026, 1, 1, 5)), isEmpty);
    });

    test('morning only from 6am', () {
      expect(startedBriefingPeriods(DateTime(2026, 1, 1, 6)), ['morning']);
      expect(startedBriefingPeriods(DateTime(2026, 1, 1, 11)), ['morning']);
    });

    test('afternoon from noon', () {
      expect(
        startedBriefingPeriods(DateTime(2026, 1, 1, 12)),
        ['morning', 'afternoon'],
      );
    });

    test('all three from 5pm', () {
      expect(
        startedBriefingPeriods(DateTime(2026, 1, 1, 17)),
        ['morning', 'afternoon', 'evening'],
      );
      expect(
        startedBriefingPeriods(DateTime(2026, 1, 1, 23)),
        ['morning', 'afternoon', 'evening'],
      );
    });
  });
}
