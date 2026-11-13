import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/intent_detector.dart';

void main() {
  test('understands informal revenue language', () {
    final result = IntentDetector.analyze('How much came in this week?');

    expect(result.intent, IntentDetector.intentSales);
    expect(result.concepts, contains('sales'));
    expect(result.confidence, 'high');
  });

  test('routes short business questions to an overview', () {
    final result = IntentDetector.analyze('How is business?');

    expect(result.intent, IntentDetector.intentBusiness);
    expect(result.concepts, contains('business health'));
  });

  test('understands informal stock risk language', () {
    final result = IntentDetector.analyze('What are we about to run out of?');

    expect(result.intent, IntentDetector.intentInventory);
    expect(result.concepts, contains('stock risk'));
  });

  test('keeps unsupported profit questions in finance context', () {
    final result = IntentDetector.analyze('Are we making a profit?');

    expect(result.intent, IntentDetector.intentFinance);
    expect(result.concepts, contains('profitability'));
  });

  test('uses low confidence overview for unfamiliar business phrasing', () {
    final result = IntentDetector.analyze('Give me the pulse.');

    expect(result.intent, IntentDetector.intentGeneral);
    expect(result.concepts, contains('business overview'));
    expect(result.confidence, 'low');
  });

  test('asks for clarification only for very short unrecognized prompts', () {
    
    final unclear = IntentDetector.analyze('Help me');
    final clear = IntentDetector.analyze('Sales today');

    expect(IntentDetector.needsClarification('Help me', unclear), isTrue);
    expect(IntentDetector.needsClarification('Sales today', clear), isFalse);
  });

  test('understands widened vocabulary across intents', () {
    expect(IntentDetector.analyze('Where did the money go?').intent,
        IntentDetector.intentFinance);
    expect(IntentDetector.analyze('What is about to run out?').intent,
        IntentDetector.intentInventory);
    expect(IntentDetector.analyze('Which dishes are underperforming?').intent,
        IntentDetector.intentMenu);
    expect(IntentDetector.analyze('How many transactions did we have?').intent,
        IntentDetector.intentSales);
    expect(IntentDetector.analyze('What needs attention today?').intent,
        IntentDetector.intentBusiness);
  });

  test('does not match keywords inside other words', () {
    final result = IntentDetector.analyze('Please coordinate the delivery');

    expect(result.intent, IntentDetector.intentGeneral);
    expect(result.confidence, 'low');
  });

  test('extracts the requested time period into concepts', () {
    final result = IntentDetector.analyze('How were sales last month?');

    expect(result.intent, IntentDetector.intentSales);
    expect(result.concepts, contains('period: last month'));
  });

  test('keeps data questions as business questions, not navigation', () {
    expect(IntentDetector.analyze('show me my sales').intent,
        IntentDetector.intentSales);
    expect(IntentDetector.analyze('open the inventory screen').intent,
        IntentDetector.intentInventory);
    expect(IntentDetector.analyze('open the dashboard').intent,
        IntentDetector.intentNavigation);
  });

  test('surfaces a near-tied second intent as an extra concept', () {
    final result = IntentDetector.analyze('How are sales and stock levels?');

    expect(result.intent, IntentDetector.intentInventory);
    expect(result.concepts, contains('sales'));
    expect(result.concepts, contains('stock risk'));
  });

  test('answers greetings and thanks without calling the AI', () {
    expect(IntentDetector.smallTalkReply('Hello there!'), isNotNull);
    expect(IntentDetector.smallTalkReply('thank you so much'), isNotNull);
    expect(IntentDetector.smallTalkReply('who are you?'), isNotNull);
    expect(IntentDetector.smallTalkReply('How did I do yesterday?'), isNull);
    expect(IntentDetector.smallTalkReply('What is my profit margin?'), isNull);
  });
}
