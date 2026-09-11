import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// Top-level tab shell: Home / Stats / Settings behind a Material 3
/// [NavigationBar].
///
/// Each tab keeps its own [Scaffold] and [AppBar] and is nested inside this
/// one; that is the intended structure. Tabs live in an [IndexedStack] so
/// scroll position, form state and in-flight async work survive switching.
///
/// `extendBody` is deliberately left at its default (`false`). With that, the
/// outer [Scaffold] lays the body out *above* the bar and strips the bottom
/// [MediaQuery] padding, so nested lists never end up under the bar and
/// `HakariSpacing.fabClearance` stays a pure "FAB height + margin" value.
/// A widget test pins this; do not flip `extendBody` without revisiting
/// every scrolling list in the app.
///
/// Flows that sit on top of the tabs (add-entry sheet, scale pairing) are
/// pushed or presented over the shell; they are not destinations.
class RootShell extends StatefulWidget {
  const RootShell({super.key, this.initialIndex = 0})
    : assert(
        initialIndex >= 0 && initialIndex < 3,
        'initialIndex must address one of the three tabs',
      );

  /// Tab shown first. Defaults to Home.
  final int initialIndex;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index = widget.initialIndex;

  static const _tabs = <Widget>[HomeScreen(), StatsScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
