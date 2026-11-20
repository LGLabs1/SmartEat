class DashboardBackHandler {
  const DashboardBackHandler({
    required this.canUnwind,
    required this.unwind,
  });

  final bool Function() canUnwind;
  final bool Function() unwind;
}

class DashboardTabHistory {
  DashboardTabHistory(int initialTab) : _tabs = <int>[initialTab];

  final List<int> _tabs;

  int get current => _tabs.last;

  bool get canGoBack => _tabs.length > 1;

  List<int> get snapshot => List<int>.unmodifiable(_tabs);

  void push(int tab) {
    if (tab == current) return;
    _tabs.add(tab);
  }

  bool back() {
    if (!canGoBack) return false;
    _tabs.removeLast();
    return true;
  }

  void reset(int tab) {
    _tabs
      ..clear()
      ..add(tab);
  }
}

typedef DashboardBackHandlerChanged = void Function(
  DashboardBackHandler? handler,
);
