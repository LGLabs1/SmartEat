import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// SageMarkdown — a tiny, selection-friendly "markdown-lite" renderer.
//
// Supports (what Sage is instructed to emit):
//   **bold**            key figures / takeaways   → bold + highlight color
//   *italic*            light emphasis            → italic
//   `code`              commands / paths          → monospace + soft chip
//   ## Heading          section heading           → larger, bold, highlight
//   - item  /  1. item  bullet or numbered list   → hanging-indent rows
//   > line              callout                   → tinted box, left border
//   ---                 divider                   → hairline rule
//
// Everything renders through Text.rich, so all of it is selectable and
// copyable under a SelectionArea ancestor.
// ---------------------------------------------------------------------------

@immutable
class SageInline {
  const SageInline(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.mono = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool mono;
}

abstract class SageBlock {
  const SageBlock();
}

class SageParagraph extends SageBlock {
  const SageParagraph(this.runs);
  final List<SageInline> runs;
}

class SageHeading extends SageBlock {
  const SageHeading(this.level, this.runs);
  final int level; // 1..4
  final List<SageInline> runs;
}

class SageBullet extends SageBlock {
  const SageBullet(this.marker, this.runs);
  final String marker; // '•' or '1.'
  final List<SageInline> runs;
}

class SageCallout extends SageBlock {
  const SageCallout(this.runs);
  final List<SageInline> runs;
}

class SageDivider extends SageBlock {
  const SageDivider();
}

/// Inline markers: ***bold italic***, **bold**, *italic*, `code`.
/// Underscore-italics are intentionally unsupported (snake_case safety), and
/// italic delimiters must hug their content (CommonMark-style flanking) so
/// text like "5 ** 6 * 7" stays literal.
final RegExp _inlineRe = RegExp(
  r'\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*([^*\s](?:[^*\n]*[^*\s])?)\*|`([^`\n]+)`',
);

/// Parses lite-markup text into renderable blocks. Pure — unit-testable.
List<SageBlock> parseSageMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <SageBlock>[];
  final paragraph = <String>[];
  final calloutLines = <String>[];

  final headingRe = RegExp(r'^(#{1,4})\s+(.*)$');
  final bulletRe = RegExp(r'^\s*[-•]\s+(.*)$');
  final starBulletRe = RegExp(r'^\s*\*\s+(.*)$');
  final numberedRe = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$');
  final calloutRe = RegExp(r'^\s*>\s?(.*)$');
  final dividerRe = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(SageParagraph(_parseInline(paragraph.join('\n'))));
    paragraph.clear();
  }

  void flushCallout() {
    if (calloutLines.isEmpty) return;
    blocks.add(SageCallout(_parseInline(calloutLines.join('\n'))));
    calloutLines.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();

    if (line.trim().isEmpty) {
      flushCallout();
      flushParagraph();
      continue;
    }

    if (dividerRe.hasMatch(line)) {
      flushCallout();
      flushParagraph();
      blocks.add(const SageDivider());
      continue;
    }

    final callout = calloutRe.firstMatch(line);
    if (callout != null) {
      flushParagraph();
      calloutLines.add(callout.group(1)!);
      continue;
    }
    flushCallout();

    final heading = headingRe.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(SageHeading(
        heading.group(1)!.length,
        _parseInline(heading.group(2)!),
      ));
      continue;
    }

    final numbered = numberedRe.firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(SageBullet(
        '${numbered.group(1)!}.',
        _parseInline(numbered.group(2)!),
      ));
      continue;
    }

    final bullet = bulletRe.firstMatch(line) ?? starBulletRe.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(SageBullet('•', _parseInline(bullet.group(1)!)));
      continue;
    }

    paragraph.add(line);
  }

  flushCallout();
  flushParagraph();
  return blocks;
}

List<SageInline> _parseInline(String text) {
  final runs = <SageInline>[];
  var last = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > last) {
      runs.add(SageInline(text.substring(last, m.start)));
    }
    if (m.group(1) != null) {
      runs.add(SageInline(m.group(1)!, bold: true, italic: true));
    } else if (m.group(2) != null) {
      runs.add(SageInline(m.group(2)!, bold: true));
    } else if (m.group(3) != null) {
      runs.add(SageInline(m.group(3)!, italic: true));
    } else {
      runs.add(SageInline(m.group(4)!, mono: true));
    }
    last = m.end;
  }
  if (last < text.length) {
    runs.add(SageInline(text.substring(last)));
  }
  return runs;
}

/// Renders lite-markup [text] as a selectable, visually structured column.
class SageMarkdown extends StatelessWidget {
  const SageMarkdown(
    this.text, {
    super.key,
    required this.style,
    this.highlightColor,
    this.bulletColor,
    this.calloutBackground,
    this.calloutBorder,
    this.codeColor,
  });

  final String text;
  final TextStyle style;

  /// Color for bold runs and headings (null → keep base color, still bold).
  final Color? highlightColor;

  /// Color for bullet / list markers (null → highlightColor).
  final Color? bulletColor;

  /// Callout box background (null → very light highlight wash).
  final Color? calloutBackground;

  /// Callout left border (null → highlightColor).
  final Color? calloutBorder;

  /// Monospace run color (null → base color).
  final Color? codeColor;

  @override
  Widget build(BuildContext context) {
    final blocks = parseSageMarkdown(text);
    final gap = (style.fontSize ?? 14) * 0.5;

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      children.add(_buildBlock(blocks[i]));
      if (i != blocks.length - 1) {
        children.add(SizedBox(height: gap));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlock(SageBlock block) {
    if (block is SageHeading) {
      final scale = switch (block.level) {
        1 => 1.35,
        2 => 1.18,
        3 => 1.08,
        _ => 1.0,
      };
      final fontSize = (style.fontSize ?? 14) * scale;
      return Padding(
        padding: EdgeInsets.only(top: (style.fontSize ?? 14) * 0.25),
        child: Text.rich(
          _richSpan(block.runs),
          style: style.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: highlightColor ?? style.color,
            height: 1.3,
            letterSpacing: fontSize > 18 ? -0.3 : null,
          ),
        ),
      );
    }

    if (block is SageBullet) {
      final markerColor = bulletColor ?? highlightColor ?? style.color;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              block.marker,
              style: style.copyWith(
                fontWeight: FontWeight.w800,
                color: markerColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              _richSpan(block.runs),
              style: style,
            ),
          ),
        ],
      );
    }

    if (block is SageCallout) {
      final border = calloutBorder ?? highlightColor;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: calloutBackground ??
              highlightColor?.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: border != null
              ? Border(
                  left: BorderSide(color: border, width: 3),
                )
              : null,
        ),
        child: Text.rich(
          _richSpan(block.runs),
          style: style.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    if (block is SageDivider) {
      return Container(
        height: 1,
        color: style.color?.withValues(alpha: 0.15),
      );
    }

    // SageParagraph
    return Text.rich(
      _richSpan((block as SageParagraph).runs),
      style: style,
    );
  }

  InlineSpan _richSpan(List<SageInline> runs) {
    return TextSpan(
      children: [
        for (final run in runs)
          if (run.text.isNotEmpty) _spanFor(run),
      ],
    );
  }

  TextSpan _spanFor(SageInline run) {
    var spanStyle = style;

    if (run.bold) {
      spanStyle = spanStyle.copyWith(
        fontWeight: FontWeight.w700,
        color: highlightColor ?? spanStyle.color,
      );
    }
    if (run.italic) {
      spanStyle = spanStyle.copyWith(fontStyle: FontStyle.italic);
    }
    if (run.mono) {
      final base = codeColor ?? style.color;
      spanStyle = spanStyle.copyWith(
        fontFamily: 'monospace',
        fontSize: (style.fontSize ?? 14) * 0.94,
        color: base,
        backgroundColor: base?.withValues(alpha: 0.10),
      );
    }

    return TextSpan(text: run.text, style: spanStyle);
  }
}
