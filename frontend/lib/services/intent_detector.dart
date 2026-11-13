/// Interprets a user message into a snapshot intent and business concepts.
///
/// Instead of first-match-wins substring checks, every intent is *scored*:
/// each matched keyword adds its weight (3 = distinctive phrase or strong
/// signal, 2 = strong word, 1 = weak/ambiguous word). The highest score wins
/// and ties are broken by priority:
///
///   inventory → finance → menu → sales → business → navigation → general
///
/// Navigation only wins when no business intent scored at all — never for
/// words that are also business questions (e.g. "show me my sales" → sales).
///
/// The analysis also extracts the requested time period and, when two
/// intents are nearly tied (e.g. "how are sales and stock?"), the secondary
/// intent's concepts so the AI knows the question spans both areas.
class IntentAnalysis {
  final String intent;
  final List<String> concepts;
  final String confidence;

  const IntentAnalysis({
    required this.intent,
    required this.concepts,
    required this.confidence,
  });
}

class IntentDetector {
  // ── Public API ──────────────────────────────────────────────────────────

  static const String intentNavigation = 'navigation';
  static const String intentInventory = 'inventory';
  static const String intentFinance = 'finance';
  static const String intentMenu = 'menu';
  static const String intentSales = 'sales';
  static const String intentBusiness = 'business';
  static const String intentGeneral = 'general';

  static String detectIntent(String message) {
    return analyze(message).intent;
  }

  static bool needsClarification(String message, IntentAnalysis analysis) {
    final words = message.trim().split(RegExp(r'\s+'));
    return analysis.intent == intentGeneral && words.length <= 2;
  }

  /// Returns a canned reply for greetings, thanks, farewells and
  /// identity/help questions, or null when the message needs the AI.
  /// Replies are picked from small variant pools so Sage never repeats the
  /// exact same line twice in a row.
  static String? smallTalkReply(String message) {
    final m = _normalize(message);
    final bare = m.replaceAll(RegExp(r'[.!?,]+'), '').trim();
    if (bare.isEmpty || bare.split(' ').length > 6) return null;

    if (_containsPhrase(bare, _greetings)) {
      return _pick([
        'Hey! Good to see you 😊 I\'ve been keeping an eye on your numbers — '
            'what would you like to dig into?',
        'Hi there! 🌿 Ready when you are. Ask me about sales, stock, your '
            'menu — anything about your restaurant.',
        'Hello! 👋 Fancy a quick look at how the business is doing, or did '
            'you have something specific in mind?',
      ]);
    }
    if (_matchesLoose(bare, _thanks)) {
      return _pick([
        'Anytime! 😊 That\'s what I\'m here for. Anything else you\'re '
            'curious about?',
        'You\'re so welcome! 💚 Happy to help — just shout if you need '
            'anything else.',
        'My pleasure! Let me know if you want to dig into anything else.',
      ]);
    }
    if (_containsPhrase(bare, _farewells)) {
      return _pick([
        'Take care! 👋 I\'ll be right here whenever you need me. Have a '
            'great day!',
        'See you soon 🌿 Good luck with the rush — come back any time!',
      ]);
    }
    if (_containsPhrase(bare, _identity)) {
      return 'I\'m Sage 🌿 — think of me as the business partner who never '
          'sleeps.\n\n'
          'I keep watch over your restaurant and I\'m good at things like:\n\n'
          '• Spotting sales trends and telling you what actually matters\n'
          '• Warning you before stock runs out\n'
          '• Calling out dishes that aren\'t pulling their weight\n'
          '• Watching your margins so surprises don\'t\n\n'
          'Try me with something like "How was this week?" 🚀';
    }
    return null;
  }

  static String _pick(List<String> variants) =>
      variants[DateTime.now().microsecondsSinceEpoch % variants.length];

  static IntentAnalysis analyze(String message) {
    final m = _normalize(message);

    // ── Score every intent ────────────────────────────────────────────────
    final scores = <String, int>{};
    for (final entry in _vocab.entries) {
      var score = 0;
      for (final (keyword, weight) in entry.value) {
        if (_matches(m, keyword)) score += weight;
      }
      scores[entry.key] = score;
    }
    scores[intentNavigation] = _navigationScore(m);

    // ── Winner: highest score, ties broken by priority order ──────────────
    var winner = intentGeneral;
    var best = 0;
    for (final intent in _businessPriority) {
      final score = scores[intent] ?? 0;
      if (score > best) {
        best = score;
        winner = intent;
      }
    }
    if (best == 0) {
      // Navigation only fires when no business intent matched at all.
      if ((scores[intentNavigation] ?? 0) > 0) {
        return _result(intentNavigation, _baseConcepts[intentNavigation]!);
      }
      return _result(intentGeneral, _baseConcepts[intentGeneral]!, 'low');
    }

    // ── Runner-up (for confidence + secondary concepts) ───────────────────
    var second = 0;
    String? secondIntent;
    for (final entry in scores.entries) {
      if (entry.key == winner) continue;
      if (entry.value > second) {
        second = entry.value;
        secondIntent = entry.key;
      }
    }
    final margin = best - second;

    final concepts = <String>[..._baseConcepts[winner]!];

    // Time period the user asked about — helps the AI answer in context.
    final period = _detectPeriod(m);
    if (period != null) concepts.add('period: $period');

    // Nearly tied intents mean the question spans two areas
    // (e.g. "how are sales and stock levels?").
    if (secondIntent != null && second >= 2 && _hasConnective(m)) {
      for (final c in _baseConcepts[secondIntent] ?? const <String>[]) {
        if (!concepts.contains(c)) concepts.add(c);
      }
    }

    return _result(
      winner,
      concepts,
      margin >= 2 ? 'high' : 'medium',
    );
  }

  static IntentAnalysis _result(
    String intent,
    List<String> concepts, [
    String confidence = 'high',
  ]) =>
      IntentAnalysis(
        intent: intent,
        concepts: concepts,
        confidence: confidence,
      );

  // ── Vocabulary ──────────────────────────────────────────────────────────
  // Keyword syntax:
  //   'multi word phrase' → plain substring match (covers plurals)
  //   'word'              → whole-word match ('order' ≠ 'coordinate')
  //   'stem*'             → prefix match ('expir*' covers expired/expiring)

  static const List<String> _businessPriority = [
    intentInventory,
    intentFinance,
    intentMenu,
    intentSales,
    intentBusiness,
  ];

  static const Map<String, List<(String, int)>> _vocab = {
    // ── Inventory / stock ───────────────────────────────────────────────
    intentInventory: [
      ('inventory', 2),
      ('stock', 2),
      ('stock level', 3),
      ('stock out', 3),
      ('out of stock', 3),
      ('low stock', 3),
      ('low on stock', 3),
      ('in stock', 2),
      ('restock*', 3),
      ('reorder', 3),
      ('re-order', 3),
      ('reorder point', 3),
      ('par level', 2),
      ('minimum stock', 3),
      ('ingredient*', 2),
      ('expir*', 3),
      ('use by', 3),
      ('best before', 3),
      ('suppl*', 2),
      ('how much stock', 3),
      ('how many stock', 3),
      ('running low', 3),
      ('running out', 3),
      ('run out', 3),
      ('ran out', 3),
      ('running short', 3),
      ('nearly gone', 3),
      ('almost out', 3),
      ('on hand', 2),
      ('stocktake*', 3),
      ('stock take', 3),
      ('spoil*', 3),
      ('waste*', 2),
      ('shrinkage', 3),
      ('raw material*', 2),
      ('purchase order', 2),
      ('storage', 1),
      ('shelf life', 3),
      ('running dry', 3),
      ('what are we low on', 3),
      ('need to buy', 2),
      ('order from supplier', 3),
      ('waste cost', 3), ('waste qty', 3), ('consumption*', 3), ('inventory value', 3),
      ('damaged', 2), ('actual consumption', 3),
    ],

    // ── Finance / costs / profit ────────────────────────────────────────
    intentFinance: [
      ('expense*', 2),
      ('bill', 2),
      ('bills', 2),
      ('payable*', 2),
      ('payment*', 2),
      ('budget*', 2),
      ('cost', 2),
      ('costs', 2),
      ('overhead', 2),
      ('operating cost', 3),
      ('profit*', 3),
      ('margin*', 2),
      ('cash flow', 3),
      ('cashflow', 3),
      ('money left', 3),
      ('take-home', 3),
      ('take home', 3),
      ('taking home', 3),
      ('bottom line', 3),
      ('losing money', 3),
      ('lose money', 3),
      ('lost money', 3),
      ('finance*', 2),
      ('net sales', 3), ('gross sales', 3), ('gross sale', 3), ('net sale', 3),
      ('discount*', 2), ('cogs', 3), ('cost of goods', 3), ('actual cogs', 3), ('estimated cogs', 3),
      ('menu costing', 3), ('recipe cost*', 3), ('cost per serving', 3), ('gross margin', 3),
      ('operating expense*', 3), ('operating cost*', 3), ('net profit', 3), ('profit margin', 3),
      ('net margin', 3), ('revenue growth', 3), ('expense growth', 3), ('growth', 2),
      ('aov', 3), ('average order value', 3), ('avg order', 3), ('average selling price', 3), ('avg selling price', 3),
      ('payable*', 2), ('outstanding payable*', 3), ('overdue payable*', 3), ('bills due', 3), ('due today', 2), ('due this week', 2), ('due this month', 2),
      ('daily sales', 3), ('weekly sales', 3), ('yearly sales', 3), ('ytd', 3), ('daily revenue', 3), ('weekly revenue', 3), ('yearly revenue', 3),
      ('forecast profit', 3), ('forecast ingredient*', 3), ('ingredient cost forecast', 3), ('estimated profit', 3),
      ('accounting', 2),
      ('bookkeep*', 2),
      ('spend*', 2),
      ('spent', 2),
      ('spending', 2),
      ('outgoing*', 2),
      ('wage*', 2),
      ('salary', 2),
      ('payroll', 2),
      ('rent', 2),
      ('utilit*', 1),
      ('electric*', 1),
      ('tax*', 1),
      ('debt', 2),
      ('loan', 2),
      ('capital', 1),
      ('funds', 1),
      ('how much does it cost', 3),
      ('how much is', 1),
      ('burn', 1),
      ('running cost', 3),
      ('monthly spend', 3),
      ('where did the money go', 3),
      ('money go', 2),
    ],

    // ── Menu / items ────────────────────────────────────────────────────
    intentMenu: [
      ('menu', 2),
      ('menus', 2),
      ('dish*', 2),
      ('food item', 3),
      ('item', 1),
      ('product*', 1),
      ('categor*', 1),
      ('recipe*', 2),
      ('price', 1),
      ('pricing', 2),
      ('beverage*', 2),
      ('drink', 1),
      ('dessert*', 2),
      ('combo*', 1),
      ('meal*', 1),
      ('cuisine', 1),
      ('portion', 1),
      ('what do i sell', 3),
      ('what are my items', 3),
      ('unsold', 3),
      ('not selling', 3),
      ('slow mover', 3),
      ('slow moving', 3),
      ('slow-selling', 3),
      ('popular dish', 3),
      ('what is moving', 3),
      ("what's moving", 3),
      ('selling well', 3),
      ('selling poorly', 3),
      ('selling slowly', 3),
      ('underperform*', 3),
      ('performing best', 3),
      ('performing worst', 3),
      ('what should i remove', 3),
      ('remove from menu', 3),
      ('add to menu', 3),
      ('add to the menu', 3),
      ('delist', 3),
      ('discontinue*', 2),
      ('fan favorite', 2),
      ('fan favourite', 2),
      ('customer favorite', 3),
      ('which dish', 3),
      ('which item', 3),
      ('food', 1),
      ('special of the day', 3),
      ('daily special', 2),
      ('worth keeping', 3),
      ('dead menu', 3),
      ('highest profit', 3), ('lowest profit', 3), ('most profitable', 3), ('least profitable', 3),
      ('menu profit*', 3), ('item profit*', 3), ('item cogs', 3), ('menu costing', 3), ('recipe costing', 3),
      ('cost per serving', 3), ('gross margin by menu', 3),
    ],

    // ── Sales / revenue / orders ────────────────────────────────────────
    intentSales: [
      ('sale', 2),
      ('sales', 2),
      ('revenue', 2),
      ('income', 2),
      ('takings', 3),
      ('turnover', 2),
      ('earn*', 2),
      ('net sales', 3), ('gross sales', 3), ('discount*', 2),
      ('aov', 3), ('average order value', 3), ('average selling price', 3),
      ('daily', 2), ('weekly', 2), ('yearly', 2), ('ytd', 2),
      ('sales forecast', 3), ('forecast*', 2),
      ('gross', 1),
      ('money made', 3),
      ('money coming in', 3),
      ('came in', 3),
      ('how much money', 3),
      ('order*', 2),
      ('how many order', 3),
      ('completed order', 3),
      ('pending order', 3),
      ('cancelled order', 3),
      ('canceled order', 3),
      ('voided order', 3),
      ('refund*', 2),
      ('analytics', 2),
      ('trend*', 2),
      ('growth', 2),
      ('growing', 2),
      ('forecast*', 3),
      ('predict*', 3),
      ('best seller', 3),
      ('best-selling', 3),
      ('bestsell*', 3),
      ('top selling', 3),
      ('top-selling', 3),
      ('worst seller', 3),
      ('worst-selling', 3),
      ('peak hour', 3),
      ('peak time', 3),
      ('busiest', 3),
      ('rush', 2),
      ('busy period', 3),
      ('how busy', 3),
      ('average order', 3),
      ('average spend', 3),
      ('spend per customer', 3),
      ('ticket size', 3),
      ('average basket', 3),
      ('transaction*', 2),
      ('ticket', 1),
      ('tickets', 1),
      ('sell', 2),
      ('sold', 2),
      ('how much did i make', 3),
      ('how much have i made', 3),
      ('did i sell', 3),
      ('how did i do', 3),
      ('how was', 2),
      ('today\'s total', 3),
      ('today total', 3),
      ('weekly total', 3),
      ('monthly total', 3),
      ('sales figures', 3),
      ('numbers today', 3),
      ('traffic', 1),
      ('customer', 1),
      // Weak period words — only count when nothing stronger matches.
      ('today', 1),
      ('todays', 1),
      ('today\'s', 1),
      ('yesterday', 1),
      ('this week', 1),
      ('this month', 1),
      ('last week', 1),
      ('last month', 1),
      ('month to date', 1),
      ('month-to-date', 1),
      ('mtd', 1),
      ('past 7 days', 1),
      ('last 7 days', 1),
    ],

    // ── Business overview / advice ──────────────────────────────────────
    intentBusiness: [
      ('business', 2),
      ('restaurant', 1),
      ('eatery', 1),
      ('cafe', 1),
      ('overall', 2),
      ('summary', 2),
      ('status', 2),
      ('health', 2),
      ('score', 1),
      ('overview', 2),
      ('performance', 1),
      ('performing', 1),
      ('insight*', 2),
      ('recommendation*', 2),
      ('advice', 2),
      ('suggest*', 1),
      ('how is my restaurant', 3),
      ('how is my eatery', 3),
      ('how am i doing', 3),
      ('how are we doing', 3),
      ('give me a report', 3),
      ('give me a summary', 3),
      ('what\'s happening', 3),
      ('whats happening', 3),
      ('what is happening', 3),
      ('how is business', 3),
      ('how\'s business', 3),
      ('how is everything', 3),
      ('how are things', 3),
      ('what needs attention', 3),
      ('what should i worry about', 3),
      ('restaurant doing', 3),
      ('business doing', 3),
      ('big picture', 3),
      ('at a glance', 3),
      ('where do i stand', 3),
      ('state of my', 3),
      ('shape am i in', 3),
      ('status update', 3),
      ('health check', 3),
      ('how is the shop', 3),
      ('daily report', 3),
      ('how did today go', 3),
      ('what happened', 2),
      ('check up', 2),
      ('check-up', 2),
    ],
  };

  static const Map<String, List<String>> _baseConcepts = {
    intentInventory: ['inventory', 'stock risk'],
    intentFinance: ['finance', 'profitability'],
    intentMenu: ['menu performance', 'item performance'],
    intentSales: ['sales', 'revenue'],
    intentBusiness: ['business overview', 'business health'],
    intentNavigation: ['navigation'],
    intentGeneral: ['business overview'],
  };

  // ── Matching helpers ────────────────────────────────────────────────────

  static final Map<String, RegExp> _regexCache = {};

  static String _normalize(String message) {
    var m = message.toLowerCase();
    m = m
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"');
    return m.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _matches(String message, String keyword) {
    if (keyword.endsWith('*')) {
      final stem = keyword.substring(0, keyword.length - 1);
      return _regex(r'\b' + RegExp.escape(stem)).hasMatch(message);
    }
    if (keyword.contains(' ')) return message.contains(keyword);
    return _regex(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(message);
  }

  static RegExp _regex(String pattern) =>
      _regexCache.putIfAbsent(pattern, () => RegExp(pattern));

  static bool _containsPhrase(String message, List<String> phrases) {
    for (final p in phrases) {
      if (message == p) return true;
    }
    return false;
  }

  /// Exact match, or the message starts with the phrase — so
  /// "thank you so much" and "see you later" still count.
  static bool _matchesLoose(String message, List<String> phrases) {
    for (final p in phrases) {
      if (message == p || message.startsWith(p)) return true;
    }
    return false;
  }

  /// True when the message explicitly links topics with "and", "&", "plus",
  /// "also" — a signal that one snapshot section may not cover the question.
  static bool _hasConnective(String m) {
    return m.contains(' and ') ||
        m.contains(' & ') ||
        m.contains(' plus ') ||
        m.contains(' as well') ||
        m.contains(' also ') ||
        RegExp(r'\band\b').hasMatch(m) ||
        RegExp(r'\balso\b').hasMatch(m);
  }

  // ── Time period extraction ──────────────────────────────────────────────

  static const List<String> _periods = [
    'past 30 days',
    'last 30 days',
    'past 7 days',
    'last 7 days',
    'this morning',
    'this afternoon',
    'this evening',
    'last night',
    'this week',
    'last week',
    'past week',
    'previous week',
    'next week',
    'this month',
    'last month',
    'past month',
    'next month',
    'this year',
    'last year',
    'this quarter',
    'last quarter',
    'year to date',
    'month to date',
    'month-to-date',
    'all time',
    'all day',
    'so far',
    'lately',
    'recently',
    'tonight',
    'today',
    'yesterday',
    'mtd',
    'ytd',
  ];

  static String? _detectPeriod(String m) {
    for (final p in _periods) {
      if (m.contains(p)) return p;
    }
    return null;
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  /// Navigation intent only fires on explicit "go to X" style commands and
  /// never competes with business questions — it is only consulted when no
  /// business intent scored anything.
  static int _navigationScore(String m) {
    var score = 0;

    for (final phrase in [
      'go to ',
      'navigate to ',
      'take me to ',
      'switch to ',
      'jump to ',
      'head to ',
      'bring up ',
      'open the ',
    ]) {
      if (m.contains(phrase)) score += 3;
    }

    // "open X" / "show me X" only if X is a screen name, not a data concept.
    final screenWords = [
      'inventory screen',
      'inventory page',
      'inventory tab',
      'menu screen',
      'menu page',
      'menu tab',
      'analytics screen',
      'analytics page',
      'analytics tab',
      'report',
      'reports screen',
      'finance screen',
      'finance page',
      'finance tab',
      'staff screen',
      'staff page',
      'staff tab',
      'dashboard',
      'pos screen',
      'pos page',
      'pos tab',
      'orders screen',
      'sales screen',
      'settings',
      'profile',
      'home screen',
      'help page',
      'insights screen',
    ];
    if (m.startsWith('open ') ||
        m.startsWith('show me the ') ||
        m.startsWith('show me my ')) {
      for (final sw in screenWords) {
        if (m.contains(sw)) score += 3;
      }
    }

    return score;
  }

  // ── Small talk ──────────────────────────────────────────────────────────

  static const List<String> _greetings = [
    'hi',
    'hey',
    'hello',
    'yo',
    'howdy',
    'hiya',
    'hi there',
    'hey there',
    'hello there',
    'good morning',
    'good afternoon',
    'good evening',
    'good day',
    'morning',
    'greetings',
  ];

  static const List<String> _thanks = [
    'thanks',
    'thank you',
    'thank you very much',
    'thanks a lot',
    'thanks alot',
    'thx',
    'ty',
    'appreciate it',
    'much appreciated',
    'cheers',
  ];

  static const List<String> _farewells = [
    'bye',
    'bye bye',
    'goodbye',
    'see you',
    'see you later',
    'see you soon',
    'see ya',
    'catch you later',
    'talk later',
    'talk to you later',
    'good night',
    'goodnight',
    'later',
  ];

  static const List<String> _identity = [
    'who are you',
    'who r you',
    'what are you',
    'what can you do',
    'what do you do',
    'what should i ask',
    'what can i ask',
    'tell me about yourself',
    'about yourself',
    'help',
    'help me',
    'what are your skills',
    'introduce yourself',
  ];

  /// Returns a human-readable label for a given intent code.
  static String intentLabel(String intent) {
    switch (intent) {
      case intentNavigation:
        return 'Navigation';
      case intentInventory:
        return 'Inventory';
      case intentFinance:
        return 'Finance';
      case intentMenu:
        return 'Menu Performance';
      case intentSales:
        return 'Sales & Revenue';
      case intentBusiness:
        return 'Business Overview';
      default:
        return 'General';
    }
  }
}
