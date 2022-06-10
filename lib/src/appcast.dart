// ignore_for_file: constant_identifier_names

/*
 * Copyright (c) 2018-2022 Larry Aasen. All rights reserved.
 */

import 'dart:convert' show utf8;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:version/version.dart';
import 'package:xml/xml.dart';

import 'upgrade_io.dart';

/// The [Appcast] class is used to download an Appcast, based on the Sparkle
/// framework by Andy Matuschak.
/// Documentation: https://sparkle-project.org/documentation/publishing/
/// An Appcast is an RSS feed with one channel that has a collection of items
/// that each describe one app version.
class Appcast {
  /// Provide an HTTP Client that can be replaced for mock testing.
  http.Client? client;

  Appcast({
    this.client,
  }) {
    client ??= http.Client();
  }

  /// The items in the Appcast.
  List<AppcastItem>? items;

  late AndroidDeviceInfo _androidInfo;
  late IosDeviceInfo _iosInfo;
  String? osVersionString;

  /// Returns the latest item in the Appcast based on OS, OS version, and app
  /// version.
  AppcastItem? bestItem({String? installedVersion}) {
    if (items == null) {
      return null;
    }

    AppcastItem? bestItem;
    items!.forEach((AppcastItem item) {
      if (item.hostSupportsItem(osVersion: osVersionString)) {
        if (item.packageInfoVersionSupportsItem(installedVersion: installedVersion)) {
          if (bestItem == null ||
              Version.parse(item.versionString!) > Version.parse(bestItem!.versionString!)) {
            bestItem = item;
          }
        }
      }
    });
    return bestItem;
  }

  /// Download the Appcast from [appCastURL].
  Future<List<AppcastItem>?> parseAppcastItemsFromUri(String appCastURL) async {
    http.Response response;
    try {
      response = await client!.get(Uri.parse(appCastURL));
    } catch (e) {
      print(e);
      return null;
    }
    final contents = utf8.decode(response.bodyBytes);
    return parseAppcastItems(contents);
  }

  /// Parse the Appcast from XML string.
  Future<List<AppcastItem>?> parseAppcastItems(String contents) async {
    await _getDeviceInfo();
    return parseItemsFromXMLString(contents);
  }

  List<AppcastItem>? parseItemsFromXMLString(String xmlString) {
    items = null;

    if (xmlString.isEmpty) {
      return null;
    }

    try {
      // Parse the XML
      final document = XmlDocument.parse(xmlString);

      // Ensure the root element is valid
      document.rootElement;

      var localItems = <AppcastItem>[];

      // look for all item elements in the rss/channel
      document.findAllElements('item').forEach((XmlElement itemElement) {
        String? title;
        String? itemDescription;
        String? dateString;
        String? fileURL;
        String? maximumSystemVersion;
        String? minimumSystemVersion;
        String? osString;
        String? releaseNotesLink;
        final tags = <String>[];
        String? newVersion;
        String? itemVersion;
        String? enclosureVersion;
        String? aturKulinerFromVersion;
        String? aturKulinerUntilVersion;

        /// LINE 161-165
        // final aturKulinerItem = <AturKulinerItem>[];

        itemElement.children.forEach((XmlNode childNode) {
          if (childNode is XmlElement) {
            final name = childNode.name.toString();
            if (name == AppcastConstants.ElementTitle) {
              title = childNode.text;
            } else if (name == AppcastConstants.ElementDescription) {
              itemDescription = childNode.text;
            } else if (name == AppcastConstants.ElementEnclosure) {
              childNode.attributes.forEach((XmlAttribute attribute) {
                if (attribute.name.toString() == AppcastConstants.AttributeVersion) {
                  enclosureVersion = attribute.value;
                } else if (attribute.name.toString() == AppcastConstants.AttributeOsType) {
                  osString = attribute.value;
                } else if (attribute.name.toString() == AppcastConstants.AttributeURL) {
                  fileURL = attribute.value;
                }
              });
            } else if (name == AppcastConstants.ElementMaximumSystemVersion) {
              maximumSystemVersion = childNode.text;
            } else if (name == AppcastConstants.ElementMinimumSystemVersion) {
              minimumSystemVersion = childNode.text;
            } else if (name == AppcastConstants.ElementPubDate) {
              dateString = childNode.text;
            } else if (name == AppcastConstants.ElementReleaseNotesLink) {
              releaseNotesLink = childNode.text;
            } else if (name == AppcastConstants.ElementTags) {
              childNode.children.forEach((XmlNode tagChildNode) {
                if (tagChildNode is XmlElement) {
                  final tagName = tagChildNode.name.toString();
                  tags.add(tagName);

                  /// Aturkuliner Tag inside 'Critical Update' Tags and support for LIST OF ATURKULINER TAGS UPDATE
                  /// <sparkle:criticalUpdate>
                  ///     <aturKuliner aturKuliner:from="1.5.0" aturKuliner:until="1.6.0" />
                  ///     <aturKuliner aturKuliner:from="1.7.0" aturKuliner:until="1.9.0" />
                  /// </sparkle:criticalUpdate>
                  // if (tagName == AppcastConstants.ElementCriticalUpdate) {
                  //   tagChildNode.children.forEach((XmlNode aturKuliner) {
                  //     if (aturKuliner is XmlElement) {
                  //       String? fromVersion;
                  //       String? untilVersion;
                  //
                  //       aturKuliner.attributes.forEach((XmlAttribute attribute) {
                  //         if (attribute.name.toString() ==
                  //             AppcastConstants.AttributeAturKulinerFrom) {
                  //           fromVersion = attribute.value;
                  //         } else if (attribute.name.toString() ==
                  //             AppcastConstants.AttributeAturKulinerUntil) {
                  //           untilVersion = attribute.value;
                  //         }
                  //       });
                  //
                  //       aturKulinerItem.add(
                  //         AturKulinerItem(
                  //           fromVersion: fromVersion,
                  //           untilVersion: untilVersion,
                  //         ),
                  //       );
                  //     }
                  //   });
                  // }
                }
              });
            } else if (name == AppcastConstants.ElementAturKuliner) {
              childNode.attributes.forEach((XmlAttribute attribute) {
                if (attribute.name.toString() == AppcastConstants.AttributeAturKulinerFrom) {
                  aturKulinerFromVersion = attribute.value;
                } else if (attribute.name.toString() ==
                    AppcastConstants.AttributeAturKulinerUntil) {
                  aturKulinerUntilVersion = attribute.value;
                }
              });
            } else if (name == AppcastConstants.AttributeVersion) {
              itemVersion = childNode.text;
            }
          }
        });

        if (itemVersion == null) {
          newVersion = enclosureVersion;
        } else {
          newVersion = itemVersion;
        }

        // There must be a version
        if (newVersion == null || newVersion.isEmpty) {
          return;
        }

        final item = AppcastItem(
          title: title,
          itemDescription: itemDescription,
          dateString: dateString,
          maximumSystemVersion: maximumSystemVersion,
          minimumSystemVersion: minimumSystemVersion,
          osString: osString,
          releaseNotesURL: releaseNotesLink,
          tags: tags,
          fileURL: fileURL,
          versionString: newVersion,
          aturKulinerFromVersion: aturKulinerFromVersion,
          aturKulinerUntilVersion: aturKulinerUntilVersion,

          ///  LINE 161-165
          // aturKulinerItem: aturKulinerItem,
        );
        localItems.add(item);
      });

      items = localItems;
    } catch (e) {
      print(e);
    }

    return items;
  }

  Future<bool> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (UpgradeIO.isAndroid) {
      _androidInfo = await deviceInfo.androidInfo;
      osVersionString = _androidInfo.version.baseOS;
    } else if (UpgradeIO.isIOS) {
      _iosInfo = await deviceInfo.iosInfo;
      osVersionString = _iosInfo.systemVersion;
    } else if (UpgradeIO.isWeb) {
      osVersionString = '0.0.0';
    }

    // If the OS version string is not valid, don't use it.
    try {
      Version.parse(osVersionString!);
    } catch (e) {
      osVersionString = null;
    }

    return true;
  }
}

class AturKulinerItem {
  final String? fromVersion;
  final String? untilVersion;

  AturKulinerItem({
    this.fromVersion,
    this.untilVersion,
  });

  Map<String, dynamic> toJson() => {
        'fromVersion': fromVersion,
        'untilVersion': untilVersion,
      };
}

class AppcastItem {
  final String? title;
  final String? dateString;
  final String? itemDescription;
  final String? releaseNotesURL;
  final String? minimumSystemVersion;
  final String? maximumSystemVersion;
  final String? fileURL;
  final int? contentLength;
  final String? versionString;
  final String? osString;
  final String? displayVersionString;
  final String? infoURL;
  final List<String>? tags;
  final String? aturKulinerFromVersion;
  final String? aturKulinerUntilVersion;

  /// LINE 161-165
  // final List<AturKulinerItem>? aturKulinerItem;

  AppcastItem({
    this.title,
    this.dateString,
    this.itemDescription,
    this.releaseNotesURL,
    this.minimumSystemVersion,
    this.maximumSystemVersion,
    this.fileURL,
    this.contentLength,
    this.versionString,
    this.osString,
    this.displayVersionString,
    this.infoURL,
    this.tags,
    this.aturKulinerFromVersion,
    this.aturKulinerUntilVersion,
    // this.aturKulinerItem, LINE 161-165
  });

  /// Returns true if the tags ([AppcastConstants.ElementTags]) contains
  /// critical update ([AppcastConstants.ElementCriticalUpdate]).
  bool get isCriticalUpdate =>
      tags == null ? false : tags!.contains(AppcastConstants.ElementCriticalUpdate);

  bool hostSupportsItem({String? osVersion, String? currentPlatform}) {
    var supported = true;
    if (osString != null && osString!.isNotEmpty) {
      final platformEnum = 'TargetPlatform.' + osString!;
      currentPlatform = currentPlatform == null
          ? defaultTargetPlatform.toString()
          : 'TargetPlatform.' + currentPlatform;
      supported = platformEnum.toLowerCase() == currentPlatform.toLowerCase();
    }

    if (supported && osVersion != null && osVersion.isNotEmpty) {
      Version osVersionValue;
      try {
        osVersionValue = Version.parse(osVersion);
      } catch (e) {
        print('appcast.hostSupportsItem: invalid osVerion: $e');
        return false;
      }
      if (maximumSystemVersion != null) {
        final maxVersion = Version.parse(maximumSystemVersion!);
        if (osVersionValue > maxVersion) {
          supported = false;
        }
      }
      if (supported && minimumSystemVersion != null) {
        final minVersion = Version.parse(minimumSystemVersion!);
        if (osVersionValue < minVersion) {
          supported = false;
        }
      }
    }
    return supported;
  }

  bool packageInfoVersionSupportsItem({String? installedVersion}) {
    var supported = true;

    if (installedVersion == null ||
        aturKulinerFromVersion == null ||
        aturKulinerFromVersion!.isEmpty ||
        aturKulinerUntilVersion == null ||
        aturKulinerUntilVersion!.isEmpty) {
      supported = false;
      return supported;
    }

    var fromVersion = Version.parse(aturKulinerFromVersion);
    var untilVersion = Version.parse(aturKulinerUntilVersion);
    var installedVersionParse = Version.parse(installedVersion);

    if (installedVersionParse >= fromVersion && installedVersionParse <= untilVersion) {
      supported = true;
    } else {
      supported = false;
    }

    return supported;
  }
}

/// These constants taken from:
/// https://github.com/sparkle-project/Sparkle/blob/master/Sparkle/SUConstants.m
class AppcastConstants {
  static const String AttributeDeltaFrom = 'sparkle:deltaFrom';
  static const String AttributeDSASignature = 'sparkle:dsaSignature';
  static const String AttributeEDSignature = 'sparkle:edSignature';
  static const String AttributeShortVersionString = 'sparkle:shortVersionString';
  static const String AttributeVersion = 'sparkle:version';
  static const String AttributeOsType = 'sparkle:os';

  static const String ElementCriticalUpdate = 'sparkle:criticalUpdate';
  static const String ElementDeltas = 'sparkle:deltas';
  static const String ElementMinimumSystemVersion = 'sparkle:minimumSystemVersion';
  static const String ElementMaximumSystemVersion = 'sparkle:maximumSystemVersion';
  static const String ElementReleaseNotesLink = 'sparkle:releaseNotesLink';
  static const String ElementTags = 'sparkle:tags';

  static const String AttributeURL = 'url';
  static const String AttributeLength = 'length';

  static const String ElementDescription = 'description';
  static const String ElementEnclosure = 'enclosure';
  static const String ElementLink = 'link';
  static const String ElementPubDate = 'pubDate';
  static const String ElementTitle = 'title';

  //ATURKULINER
  static const String AttributeAturKulinerFrom = 'aturKuliner:from';
  static const String AttributeAturKulinerUntil = 'aturKuliner:until';

  static const String ElementAturKuliner = 'aturKuliner';
}
