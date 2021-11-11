import 'dart:io';

import 'package:mockito/mockito.dart';
import 'package:upgrader/src/appcast.dart';
import 'package:upgrader/src/upgrader.dart';

class FakeAppcast extends Fake implements Appcast {
  int callCount = 0;

  @override
  AppcastItem bestItem({String? packageInfoVersion}) {
    callCount++;

    return AppcastItem(
      versionString: '1.0.0',
      fileURL: 'http://some.fakewebsite.com',
      tags: [],
    );
  }

  @override
  Future<List<AppcastItem>> parseAppcastItemsFromFile(File file) async {
    callCount++;

    return [AppcastItem()];
  }

  @override
  Future<List<AppcastItem>> parseAppcastItemsFromUri(String appCastURL) async {
    callCount++;

    return [AppcastItem()];
  }

  @override
  List<AppcastItem> parseItemsFromXMLString(String xmlString) {
    callCount++;

    return [AppcastItem()];
  }

  AppcastConfiguration config =
      AppcastConfiguration(url: 'http://some.fakewebsite.com', supportedOS: [
    'linux',
    'macos',
    'windows',
    'android',
    'ios',
    'fuchsia',
  ]);

  @override
  List<AppcastItem>? items = [];

  @override
  String? osVersionString = '';
}
