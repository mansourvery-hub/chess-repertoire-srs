import 'package:app_settings/app_settings.dart';
import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/settings/account_preferences_screen.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:chess_srs/src/view/settings/board_settings_screen.dart';
import 'package:chess_srs/src/view/settings/engine_settings_screen.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:chess_srs/src/view/settings/sound_settings_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/view/settings/theme_settings_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:chess_srs/src/widgets/misc.dart';
import 'package:chess_srs/src/widgets/platform.dart';
import 'package:chess_srs/src/widgets/settings.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Route<dynamic> buildRoute() {
    return SrsSettingsScreen.buildRoute();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final generalPrefs = ref.watch(generalPreferencesProvider);
    final packageInfo = ref.read(preloadedDataProvider).requireValue.packageInfo;
    final authUser = ref.watch(authControllerProvider);
    final signOutState = ref.watch(signOutMutation);
    final dbSize = ref.watch(getDbSizeInBytesProvider);

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.settingsSettings)),
      body: ListView(
        children: [
          if (authUser != null)
            ListSection(
              hasLeading: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: Text(context.l10n.mobileAccountPreferences),
                  enabled: isOnline,
                  onTap: () {
                    Navigator.of(context).push(AccountPreferencesScreen.buildRoute());
                  },
                ),
              ],
            ),
          ListSection(
            hasLeading: true,
            children: [
              SettingsListTile(
                icon: const Icon(Icons.music_note_outlined),
                settingsLabel: Text(context.l10n.sound),
                settingsValue:
                    '${soundThemeL10n(context, generalPrefs.soundTheme)} (${volumeLabel(generalPrefs.masterVolume)})',
                onTap: () {
                  Navigator.of(context).push(SoundSettingsScreen.buildRoute());
                },
              ),
              SettingsListTile(
                enabled: !generalPrefs.isForcedDarkMode,
                icon: const Icon(Icons.brightness_medium_outlined),
                settingsLabel: Text(context.l10n.background),
                settingsValue: generalPrefs.isForcedDarkMode
                    ? BackgroundThemeMode.dark.title(context.l10n)
                    : generalPrefs.themeMode.title(context.l10n),
                onTap: () {
                  showChoicePicker(
                    context,
                    choices: BackgroundThemeMode.values,
                    selectedItem: generalPrefs.themeMode,
                    labelBuilder: (t) => Text(t.title(context.l10n)),
                    onSelectedItemChanged: (BackgroundThemeMode? value) => ref
                        .read(generalPreferencesProvider.notifier)
                        .setBackgroundThemeMode(value ?? BackgroundThemeMode.system),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(context.l10n.mobileTheme),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context).push(ThemeSettingsScreen.buildRoute());
                },
              ),
              ListTile(
                leading: const Icon(Symbols.chess_pawn),
                title: Text(context.l10n.mobileBoardSettings, overflow: TextOverflow.ellipsis),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context).push(BoardSettingsScreen.buildRoute());
                },
              ),
              SettingsListTile(
                icon: const Icon(Symbols.schedule_rounded),
                settingsLabel: const Text('Spaced repetition (SRS)'),
                settingsValue: ref.watch(
                  studyPreferencesProvider.select((p) => p.schedulerType.label),
                ),
                onTap: () {
                  Navigator.of(context).push(SrsSettingsScreen.buildRoute());
                },
              ),
              ListTile(
                leading: const Icon(Icons.memory_outlined),
                title: const Text('Chess engine'),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context).push(EngineSettingsScreen.buildRoute());
                },
              ),
              SettingsListTile(
                icon: const Icon(Icons.language_outlined),
                settingsLabel: Text(context.l10n.language),
                settingsValue: localeToLocalizedName(
                  generalPrefs.locale ?? Localizations.localeOf(context),
                ),
                onTap: () {
                  if (Theme.of(context).platform == TargetPlatform.android) {
                    showChoicePicker<Locale>(
                      context,
                      choices: localesSortedByLocalizedName(AppLocalizations.supportedLocales),
                      selectedItem: generalPrefs.locale ?? Localizations.localeOf(context),
                      labelBuilder: (t) => Text(localeToLocalizedName(t)),
                      onSelectedItemChanged: (Locale? locale) =>
                          ref.read(generalPreferencesProvider.notifier).setLocale(locale),
                    );
                  } else {
                    AppSettings.openAppSettings(type: AppSettingsType.appLocale);
                  }
                },
              ),
            ],
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Local database size'),
                trailing: dbSize.hasValue ? Text(_getSizeString(dbSize.value)) : null,
              ),
              ListTile(
                leading: const Icon(Icons.http),
                title: const Text('HTTP logs'),
                onTap: () => Navigator.push(context, HttpLogScreen.buildRoute()),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('App Logs'),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context).push(AppLogSettingsScreen.buildRoute());
                },
              ),
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Rate this app'),
                onTap: () async {
                  final isAndroid = Theme.of(context).platform == TargetPlatform.android;
                  final links = androidAppStoreLinks();
                  final launched = await launchUrl(
                    isAndroid ? links.native : appStoreListingUrl(isAndroid: false),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && isAndroid) {
                    launchUrl(links.web, mode: LaunchMode.externalApplication);
                  }
                },
                trailing: const OpenInNewIcon(),
              ),
            ],
          ),
          if (authUser != null)
            ListSection(
              hasLeading: true,
              children: [
                switch (signOutState) {
                  MutationPending() => const ListTile(
                    leading: Icon(Icons.logout_outlined),
                    enabled: false,
                    title: Center(child: ButtonLoadingIndicator()),
                  ),
                  _ => ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: Text(context.l10n.logOut),
                    enabled: isOnline,
                    onTap: () => _showSignOutConfirmDialog(context, ref),
                  ),
                },
              ],
            ),
          Padding(
            padding: Styles.bodySectionPadding,
            child: Text('v${packageInfo.version}', style: TextTheme.of(context).bodySmall),
          ),
        ],
      ),
    );
  }

  Future<void> _showSignOutConfirmDialog(BuildContext context, WidgetRef ref) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return showCupertinoActionSheet(
        context: context,
        actions: [
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.logOut),
            isDestructiveAction: true,
            onPressed: () async {
              await signOutMutation.run(ref, (tsx) async {
                await tsx.get(authControllerProvider.notifier).signOut();
              });
            },
          ),
        ],
      );
    }
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.logOut),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await signOutMutation.run(ref, (tsx) async {
                  await tsx.get(authControllerProvider.notifier).signOut();
                });
              },
              child: Text(context.l10n.mobileOkButton),
            ),
          ],
        );
      },
    );
  }

  String _getSizeString(int? bytes) => '${_bytesToMB(bytes ?? 0).toStringAsFixed(2)}MB';

  double _bytesToMB(int bytes) => bytes * 0.000001;
}
