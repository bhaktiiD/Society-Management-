import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme.dart';
import 'package:mobile/core/widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('StatusChip', () {
    testWidgets('renders label for every tone', (tester) async {
      for (final tone in ChipTone.values) {
        await tester.pumpWidget(_wrap(StatusChip('Label ${tone.name}', tone: tone)));
        expect(find.text('Label ${tone.name}'), findsOneWidget);
      }
    });
  });

  group('EmptyState', () {
    testWidgets('shows icon and message', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox(
        height: 300,
        child: EmptyState(icon: Icons.inbox, message: 'Nothing here'),
      )));
      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('Nothing here'), findsOneWidget);
    });
  });

  group('TileCard', () {
    testWidgets('shows content and fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(TileCard(
        title: 'Maintenance',
        subtitle: 'Due 24 Nov',
        trailing: const Text('₹2,500'),
        onTap: () => taps++,
      )));
      expect(find.text('Maintenance'), findsOneWidget);
      expect(find.text('Due 24 Nov'), findsOneWidget);
      expect(find.text('₹2,500'), findsOneWidget);
      await tester.tap(find.text('Maintenance'));
      expect(taps, 1);
    });
  });

  group('HeroCard', () {
    testWidgets('shows label, value and footer', (tester) async {
      await tester.pumpWidget(_wrap(const HeroCard(
        label: 'Total due',
        value: '₹4,570',
        footer: Text('3 charges'),
      )));
      expect(find.text('Total due'), findsOneWidget);
      expect(find.text('₹4,570'), findsOneWidget);
      expect(find.text('3 charges'), findsOneWidget);
    });
  });

  group('QuickActionsRow', () {
    testWidgets('four tiles fit one row at 360dp and each fires its own tap', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final taps = <String>[];
      const labels = ['Pay', 'Notices', 'Guests', 'Help'];
      await tester.pumpWidget(_wrap(QuickActionsRow(tiles: [
        for (final l in labels)
          QuickActionTile(
            icon: Icons.star,
            label: l,
            onTap: () => taps.add(l),
            color: Colors.green.shade800,
            gradient: const [Color(0xFFE9F8DA), Color(0xFFCDEFB0)],
          ),
      ])));

      expect(tester.takeException(), isNull);
      final tiles = find.byType(QuickActionTile);
      expect(tiles, findsNWidgets(4));
      final tops = [for (var i = 0; i < 4; i++) tester.getTopLeft(tiles.at(i)).dy];
      expect(tops.toSet(), hasLength(1));

      for (final l in labels) {
        await tester.tap(find.text(l));
      }
      expect(taps, labels);
    });
  });

  group('HighlightCard', () {
    testWidgets('featured and plain both render content', (tester) async {
      for (final featured in [true, false]) {
        await tester.pumpWidget(_wrap(HighlightCard(
          title: 'Water',
          amount: '₹300',
          caption: '2 days left',
          icon: Icons.water_drop,
          featured: featured,
        )));
        expect(find.text('Water'), findsOneWidget);
        expect(find.text('₹300'), findsOneWidget);
        expect(find.text('2 days left'), findsOneWidget);
        final material = tester.widget<Material>(
          find.descendant(of: find.byType(HighlightCard), matching: find.byType(Material)).first,
        );
        expect(material.color, featured ? AppColors.green : AppColors.surface);
      }
    });
  });

  group('SectionHeader', () {
    testWidgets('shows See all and fires onAction', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(SectionHeader('Upcoming', actionLabel: 'See all', onAction: () => taps++)));
      expect(find.text('Upcoming'), findsOneWidget);
      await tester.tap(find.text('See all'));
      expect(taps, 1);
    });

    testWidgets('hides action when onAction is missing', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('Upcoming', actionLabel: 'See all')));
      expect(find.text('See all'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
