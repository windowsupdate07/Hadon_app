import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'core/data/lookups.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'features/auth/auth_provider.dart';
import 'router/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = TokenStorage();
  final api = ApiClient(storage);
  final auth = AuthProvider(api, storage)..restore();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        Provider(create: (_) => Lookups(api)),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: HondaNtpApp(router: createRouter(auth)),
    ),
  );
}

class HondaNtpApp extends StatelessWidget {
  const HondaNtpApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      useMaterial3: true,
    );
    return MaterialApp.router(
      title: 'Honda NTP',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.k2dTextTheme(base.textTheme),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
