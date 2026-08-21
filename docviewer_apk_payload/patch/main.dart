import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  runApp(const UniversalDocApp());
}

class UniversalDocApp extends StatelessWidget {
  const UniversalDocApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3157C8);
    final lightScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final darkScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    ThemeData theme(ColorScheme scheme) => ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          visualDensity: VisualDensity.standard,
          scaffoldBackgroundColor: scheme.brightness == Brightness.light ? const Color(0xFFF6F7FB) : const Color(0xFF101217),
          appBarTheme: const AppBarTheme(centerTitle: false, backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent),
          cardTheme: CardThemeData(
            color: scheme.brightness == Brightness.light ? Colors.white : scheme.surfaceContainerLow,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          searchBarTheme: SearchBarThemeData(
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest.withValues(alpha: .68)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          ),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مستنداتي',
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      theme: theme(lightScheme),
      darkTheme: theme(darkScheme),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
