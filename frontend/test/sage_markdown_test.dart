import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/sage_markdown.dart';

void main() {
  group('parseSageMarkdown', () {
    test('splits paragraphs on blank lines and keeps line breaks', () {
      final blocks = parseSageMarkdown('First line\nstill first\n\nSecond');
      expect(blocks, hasLength(2));
      expect(blocks[0], isA<SageParagraph>());
      expect((blocks[0] as SageParagraph).runs.single.text,
          'First line\nstill first');
      expect((blocks[1] as SageParagraph).runs.single.text, 'Second');
    });

    test('parses headings with their level', () {
      final blocks = parseSageMarkdown('## The takeaway');
      expect(blocks.single, isA<SageHeading>());
      expect((blocks.single as SageHeading).level, 2);
      expect((blocks.single as SageHeading).runs.single.text, 'The takeaway');
    });

    test('parses bullets and numbered items into markers', () {
      final blocks = parseSageMarkdown('- first\n2) second');
      expect(blocks, hasLength(2));
      expect((blocks[0] as SageBullet).marker, '•');
      expect((blocks[0] as SageBullet).runs.single.text, 'first');
      expect((blocks[1] as SageBullet).marker, '2.');
      expect((blocks[1] as SageBullet).runs.single.text, 'second');
    });

    test('merges consecutive callout lines into one block', () {
      final blocks = parseSageMarkdown('> line one\n> line two\nplain');
      expect(blocks, hasLength(2));
      expect(blocks[0], isA<SageCallout>());
      expect((blocks[0] as SageCallout).runs.single.text,
          'line one\nline two');
      expect(blocks[1], isA<SageParagraph>());
    });

    test('recognizes dividers but not words containing dashes', () {
      final blocks = parseSageMarkdown('---\nsome-day');
      expect(blocks[0], isA<SageDivider>());
      expect(blocks[1], isA<SageParagraph>());
    });

    test('splits inline bold, italic, and code into styled runs', () {
      final blocks = parseSageMarkdown(
        'Made **₱1,200** up *a lot* with `npm run dev`.',
      );
      final runs = (blocks.single as SageParagraph).runs;
      expect(runs[0].text, 'Made ');
      expect(runs[1].text, '₱1,200');
      expect(runs[1].bold, isTrue);
      expect(runs[3].text, 'a lot');
      expect(runs[3].italic, isTrue);
      expect(runs[5].text, 'npm run dev');
      expect(runs[5].mono, isTrue);
      expect(runs[6].text, '.');
    });

    test('keeps unclosed markers as literal text', () {
      final blocks = parseSageMarkdown('5 ** 6 * 7');
      final runs = (blocks.single as SageParagraph).runs;
      expect(runs.single.text, '5 ** 6 * 7');
      expect(runs.single.bold, isFalse);
    });

    test('does not treat a line starting with *italic* as a bullet', () {
      final blocks = parseSageMarkdown('*just emphasis*');
      expect(blocks.single, isA<SageParagraph>());
      expect((blocks.single as SageParagraph).runs.single.italic, isTrue);
    });
  });

  group('SageMarkdown widget', () {
    testWidgets('renders bold runs with the highlight color',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SageMarkdown(
              'Made **₱1,200** today',
              style: const TextStyle(fontSize: 13, color: Colors.black),
              highlightColor: Colors.blue,
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text).first);
      final span = text.textSpan!;
      final children = (span as TextSpan).children!;
      final bold = children
          .cast<TextSpan>()
          .firstWhere((s) => s.style?.fontWeight == FontWeight.w700);
      expect(bold.text, '₱1,200');
      expect(bold.style?.color, Colors.blue);
    });

    testWidgets('renders a callout as a distinct container',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SageMarkdown(
              '> Do this next',
              style: const TextStyle(fontSize: 13, color: Colors.black),
              highlightColor: Colors.green,
              calloutBackground: const Color(0x1100FF00),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.textContaining('Do this next'),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.decoration, isA<BoxDecoration>());
      final deco = container.decoration! as BoxDecoration;
      expect((deco.border as Border?)?.left.width, 3);
      expect(deco.color, const Color(0x1100FF00));
    });

    testWidgets('renders plain text unchanged in one paragraph',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: SageMarkdown(
              'No markup here at all.',
              style: TextStyle(fontSize: 13, color: Colors.black),
            ),
          ),
        ),
      );

      expect(find.text('No markup here at all.'), findsOneWidget);
      expect(find.byType(Column), findsOneWidget);
    });
  });
}
