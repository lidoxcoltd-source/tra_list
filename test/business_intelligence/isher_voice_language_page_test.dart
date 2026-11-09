import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tra_list/business_intelligence/isher_voice_language_page.dart';
import 'package:tra_list/invoice/app_translations.dart';

void main() {
  testWidgets('download sample and select the same CSV for preview', (
    tester,
  ) async {
    Uint8List? downloaded;
    String? previewedCsv;
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherVoiceLanguagePage(
          saveSample: (bytes) async {
            downloaded = Uint8List.fromList(bytes);
            return 'isher_voice_sample.csv';
          },
          pickFile: () async => PlatformFile(
            name: 'isher_voice_sample.csv',
            size: downloaded!.length,
            bytes: downloaded,
          ),
          call: (name, data) async {
            if (name == 'previewIsherVoiceExamples') {
              previewedCsv = data['csv'] as String;
              return {
                'examples': [
                  {'number': '30000', 'spoken': 'shilingi elfu thelathini'},
                ],
              };
            }
            return {'activeId': null, 'versions': [], 'hasMore': false};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pakua mfano wa CSV'));
    await tester.pumpAndSettle();
    expect(downloaded, isNotNull);
    expect(utf8.decode(downloaded!), startsWith('number,spoken\n'));
    expect(find.text('Mfano wa CSV umehifadhiwa.'), findsOneWidget);
    await tester.tap(find.text('Chagua faili la CSV'));
    await tester.pumpAndSettle();
    expect(previewedCsv, utf8.decode(downloaded!));
    expect(find.text('30000 → shilingi elfu thelathini'), findsOneWidget);
  });

  testWidgets('download failure is visible', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherVoiceLanguagePage(
          saveSample: (_) async => throw StateError('save failed'),
          call: (_, _) async => {
            'activeId': null,
            'versions': [],
            'hasMore': false,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pakua mfano wa CSV'));
    await tester.pumpAndSettle();
    expect(
      find.text('Imeshindikana kupakua mfano wa CSV. Jaribu tena.'),
      findsOneWidget,
    );
  });

  testWidgets('review, save and activate a CSV version separately', (
    tester,
  ) async {
    final versions = <Map<String, dynamic>>[];
    String? active;
    final calls = <String>[];
    const csv = 'number,spoken\n30000,shilingi elfu thelathini';
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('sw', 'TZ'),
        home: IsherVoiceLanguagePage(
          pickFile: () async => PlatformFile(
            name: 'mfano.csv',
            size: utf8.encode(csv).length,
            bytes: Uint8List.fromList(utf8.encode(csv)),
          ),
          call: (name, data) async {
            calls.add(name);
            if (name == 'previewIsherVoiceExamples') {
              return {
                'examples': [
                  {'number': '30000', 'spoken': 'shilingi elfu thelathini'},
                ],
              };
            }
            if (name == 'saveIsherVoiceExamples') {
              versions.add({
                'id': 'version',
                'name': data['name'],
                'examples': [
                  {'number': '30000', 'spoken': 'shilingi elfu thelathini'},
                ],
              });
              return {'id': 'version'};
            }
            if (name == 'activateIsherVoiceExamples') {
              active = data['versionId'] as String?;
              return {'versionId': active};
            }
            return {'activeId': active, 'versions': versions, 'hasMore': false};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chagua faili la CSV'));
    await tester.pumpAndSettle();
    expect(find.text('30000 → shilingi elfu thelathini'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '30000');
    await tester.pump();
    expect(find.text('shilingi elfu thelathini'), findsOneWidget);
    await tester.ensureVisible(find.text('Hifadhi toleo'));
    await tester.tap(find.text('Hifadhi toleo'));
    await tester.pumpAndSettle();
    expect(active, isNull);
    expect(calls, isNot(contains('activateIsherVoiceExamples')));
    await tester.ensureVisible(find.text('Washa'));
    await tester.tap(find.text('Washa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Washa').last);
    await tester.pumpAndSettle();
    expect(active, 'version');
    expect(find.text('Linatumika'), findsOneWidget);
  });
}
