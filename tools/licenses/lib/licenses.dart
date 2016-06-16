// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as system;

import 'cache.dart';
import 'patterns.dart';

const int kMaxSize = 512 * 1024; // only look for copyrights and licenses at the top of the file

class FetchedContentsOf extends Key { FetchedContentsOf(dynamic value) : super(value); }

enum LicenseType { unknown, bsd, gpl, lgpl, mpl, afl, mit, freetype, apache, apacheNotice, eclipse, ijg, zlib }

LicenseType convertLicenseNameToType(String name) {
  switch (name) {
    case 'Apache':
    case 'apache-license-2.0':
      return LicenseType.apache;
    case 'BSD':
    case 'BSD.txt':
      return LicenseType.bsd;
    case 'LICENSE-LGPL-2':
    case 'LICENSE-LGPL-2.1':
      return LicenseType.lgpl;
    case 'FTL.TXT':
      return LicenseType.freetype;
    case 'zlib.h':
      return LicenseType.zlib;
    // common file names that don't say what the type is
    case 'COPYING':
    case 'COPYING.txt':
    case 'COPYING.LIB': // lgpl usually
    case 'COPYING.RUNTIME': // gcc exception usually
    case 'LICENSE':
    case 'LICENSE.md':
    case 'license.html':
    case 'LICENSE.txt':
    case 'LICENSE.TXT':
    case 'NOTICE':
    case 'NOTICE.txt':
    case 'Copyright':
    case 'copyright':
      return LicenseType.unknown;
    // particularly weird file names
    case 'LICENSE-APPLE':
    case 'extreme.indiana.edu.license.TXT':
    case 'extreme.indiana.edu.license.txt':
    case 'javolution.license.TXT':
    case 'javolution.license.txt':
    case 'libyaml-license.txt':
    case 'license.patch':
    case 'mh-bsd-gcc':
    case 'pivotal.labs.license.txt':
      return LicenseType.unknown;
  }
  throw 'unknown license type: $name';
}

LicenseType convertBodyToType(String body) {
  if (body.startsWith(lrApache))
    return LicenseType.apache;
  if (body.startsWith(lrMPL))
    return LicenseType.mpl;
  if (body.startsWith(lrGPL))
    return LicenseType.gpl;
  if (body.contains(lrBSD))
    return LicenseType.bsd;
  if (body.contains(lrMIT))
    return LicenseType.mit;
  if (body.contains(lrZlib))
    return LicenseType.zlib;
  return LicenseType.unknown;
}

abstract class LicenseSource {
  List<License> nearestLicensesFor(String name);
  License nearestLicenseOfType(LicenseType type);
  License nearestLicenseWithName(String name, { String authors });
}

abstract class License {
  factory License.unique(String body, LicenseType type, { bool reformatted: false }) {
    if (!reformatted)
      body = _reformat(body);
    License result = _registry.putIfAbsent(body, () => new UniqueLicense._(body, type));
    assert(() {
      if (result is! UniqueLicense || result.type != type)
        throw 'tried to add a UniqueLicense $type, but it was a duplicate of a ${result.runtimeType} ${result.type}';
      return true;
    });
    return result;
  }

  factory License.template(String body, LicenseType type, { bool reformatted: false }) {
    if (!reformatted)
      body = _reformat(body);
    License result = _registry.putIfAbsent(body, () => new TemplateLicense._(body, type));
    assert(() {
      if (result is! TemplateLicense || result.type != type)
        throw 'tried to add a TemplateLicense $type, but it was a duplicate of a ${result.runtimeType} ${result.type}';
      return true;
    });
    return result;
  }

  factory License.message(String body, LicenseType type, { bool reformatted: false }) {
    if (!reformatted)
      body = _reformat(body);
    License result = _registry.putIfAbsent(body, () => new MessageLicense._(body, type));
    assert(() {
      if (result is! MessageLicense || result.type != type)
        throw 'tried to add a MessageLicense $type, but it was a duplicate of a ${result.runtimeType} ${result.type}';
      return true;
    });
    return result;
  }

  factory License.fromMultipleBlocks(List<String> bodies, LicenseType type) {
    final String body = bodies.map((String s) => _reformat(s)).join('\n\n');
    return _registry.putIfAbsent(body, () => new UniqueLicense._(body, type));
  }

  factory License.fromBodyAndType(String body, LicenseType type, { bool reformatted: false }) {
    if (!reformatted)
      body = _reformat(body);
    License result = _registry.putIfAbsent(body, () {
      switch (type) {
        case LicenseType.bsd:
        case LicenseType.mit:
        case LicenseType.zlib:
          return new TemplateLicense._(body, type);
        case LicenseType.unknown:
        case LicenseType.apacheNotice:
          return new UniqueLicense._(body, type);
        case LicenseType.afl:
        case LicenseType.mpl:
        case LicenseType.gpl:
        case LicenseType.lgpl:
        case LicenseType.freetype:
        case LicenseType.apache:
        case LicenseType.eclipse:
        case LicenseType.ijg:
          return new MessageLicense._(body, type);
      }
    });
    assert(result.type == type);
    return result;
  }

  factory License.fromBodyAndName(String body, String name) {
    body = _reformat(body);
    LicenseType type = convertLicenseNameToType(name);
    if (type == LicenseType.unknown)
      type = convertBodyToType(body);
    return new License.fromBodyAndType(body, type);
  }

  factory License.fromBody(String body) {
    body = _reformat(body);
    LicenseType type = convertBodyToType(body);
    return new License.fromBodyAndType(body, type, reformatted: true);
  }

  factory License.fromCopyrightAndLicense(String copyright, String template, LicenseType type) {
    String body = '$copyright\n\n$template';
    return _registry.putIfAbsent(body, () => new TemplateLicense._(body, type));
  }

  factory License.fromUrl(String url) {
    String body;
    LicenseType type = LicenseType.unknown;
    switch (url) {
      case 'http://www.apache.org/licenses/LICENSE-2.0':
        body = new system.File('data/apache-license-2.0').readAsStringSync();
        type = LicenseType.apache;
        break;
      case 'https://developers.google.com/open-source/licenses/bsd':
        body = new system.File('data/google-bsd').readAsStringSync();
        type = LicenseType.bsd;
        break;
      case 'http://polymer.github.io/LICENSE.txt':
        body = new system.File('data/polymer-bsd').readAsStringSync();
        type = LicenseType.bsd;
        break;
      case 'http://www.eclipse.org/legal/epl-v10.html':
        body = new system.File('data/eclipse-1.0').readAsStringSync();
        type = LicenseType.eclipse;
        break;
      case 'COPYING3:3':
        body = new system.File('data/gpl-3.0').readAsStringSync();
        type = LicenseType.gpl;
        break;
      case 'COPYING.LIB:2':
      case 'COPYING.LIother.m_:2': // blame hyatt
        body = new system.File('data/library-gpl-2.0').readAsStringSync();
        type = LicenseType.lgpl;
        break;
      case 'GNU Lesser:2':
        // there has never been such a license, but the authors said they meant the LGPL2.1
      case 'GNU Lesser:2.1':
        body = new system.File('data/lesser-gpl-2.1').readAsStringSync();
        type = LicenseType.lgpl;
        break;
      case 'COPYING.RUNTIME:3.1':
      case 'GCC Runtime Library Exception:3.1':
        body = new system.File('data/gpl-gcc-exception-3.1').readAsStringSync();
        break;
      case 'Academic Free License:3.0':
        body = new system.File('data/academic-3.0').readAsStringSync();
        type = LicenseType.afl;
        break;
      case 'http://mozilla.org/MPL/2.0/:2.0':
        body = new system.File('data/mozilla-2.0').readAsStringSync();
        type = LicenseType.mpl;
        break;
      default: throw 'unknown url $url';
    }
    return _registry.putIfAbsent(body, () => new License.fromBodyAndType(body, type));
  }

  License._(String body, this.type) : body = body, authors = _readAuthors(body) {
    assert(_reformat(body) == body);
    assert(() {
      try {
        switch (type) {
          case LicenseType.bsd:
          case LicenseType.mit:
          case LicenseType.zlib:
            assert(this is TemplateLicense);
            break;
          case LicenseType.unknown:
          case LicenseType.apacheNotice:
            assert(this is UniqueLicense);
            break;
          case LicenseType.afl:
          case LicenseType.mpl:
          case LicenseType.gpl:
          case LicenseType.lgpl:
          case LicenseType.freetype:
          case LicenseType.apache:
          case LicenseType.eclipse:
          case LicenseType.ijg:
            assert(this is MessageLicense);
            break;
        }
      } on AssertionError {
        throw 'incorrectly created a $runtimeType for a $type';
      }
      return true;
    });
    final LicenseType detectedType = convertBodyToType(body);
    if (detectedType != LicenseType.unknown && detectedType != type)
      throw 'Created a license of type $type but it looks like $detectedType\.';
    // if (type == LicenseType.unknown)
    //   print('need detector for:\n----\n$body\n----');
    bool isUTF8 = true;
    List<int> latin1Encoded;
    try {
      latin1Encoded = LATIN1.encode(body);
      isUTF8 = false;
    } on ArgumentError { }
    if (!isUTF8) {
      bool isAscii = false;
      try {
        ASCII.decode(latin1Encoded);
        isAscii = true;
      } on FormatException { }
      if (isAscii)
        return;
      try {
        UTF8.decode(latin1Encoded);
        isUTF8 = true;
      } on FormatException { }
      if (isUTF8)
        throw 'tried to create a License object with text that appears to have been misdecoded as Latin1 instead of as UTF-8:\n$body';
    }
  }

  final String body;
  final String authors;
  final LicenseType type;

  Iterable<String> get licensees => _licensees;
  List<String> _licensees = <String>[];
  bool _usedAsTemplate = false;

  bool get isUsed => _licensees.isNotEmpty || _usedAsTemplate;

  void markUsed(String filename) {
    filename != null;
    _licensees.add(filename);
  }

  Iterable<License> expandTemplate(String copyright);

  @override
  String toString() {
    return ('=' * 100) + '\n' +
           licensees.join('\n') + '\n' +
           ('-' * 100) + '\n' +
           body + '\n' +
           ('=' * 100);
  }

  static final RegExp _copyrightForAuthors = new RegExp(
    r'Copyright [-0-9 ,(cC)©]+\b(The .+ Authors)\.',
    caseSensitive: false
  );

  static String _readAuthors(String body) {
    final List<Match> matches = _copyrightForAuthors.allMatches(body).toList();
    if (matches.isEmpty)
      return null;
    if (matches.length > 1)
      throw 'found too many authors for this copyright:\n$body';
    return matches[0].group(1);
  }
}


final Map<String, License> _registry = <String, License>{};

final License missingLicense = new UniqueLicense._('<missing>', LicenseType.unknown);

String _reformat(String body) {
  // TODO(ianh): ensure that we're stripping the same amount of leading text on each line
  final List<String> lines = body.split('\n');
  while (lines.isNotEmpty && lines.first == '')
    lines.removeAt(0);
  while (lines.isNotEmpty && lines.last == '')
    lines.removeLast();
  if (lines.length > 2) {
    if (lines[0].startsWith(beginLicenseBlock) && lines.last.startsWith(endLicenseBlock)) {
      lines.removeAt(0);
      lines.removeLast();
    }
  } else if (lines.isEmpty) {
    return '';
  }
  final List<String> output = <String>[];
  int lastGood;
  String previousPrefix;
  bool lastWasEmpty = true;
  for (String line in lines) {
    final Match match = stripDecorations.firstMatch(line);
    final String prefix = match.group(1);
    String s = match.group(2);
    if (!lastWasEmpty || s != '') {
      if (s != '') {
        if (previousPrefix != null) {
          if (previousPrefix.length > prefix.length) {
            // TODO(ianh): Spot check files that hit this. At least one just
            // has a corrupt license block, which is why this is commented out.
            //if (previousPrefix.substring(prefix.length).contains(nonSpace))
            //  throw 'inconsistent line prefix: was "$previousPrefix", now "$prefix"\nfull body was:\n---8<---\n$body\n---8<---';
            previousPrefix = prefix;
          } else if (previousPrefix.length < prefix.length) {
            s = '${prefix.substring(previousPrefix.length)}$s';
          }
        } else {
          previousPrefix = prefix;
        }
        lastWasEmpty = false;
        lastGood = output.length + 1;
      } else {
        lastWasEmpty = true;
      }
      output.add(s);
    }
  }
  if (lastGood == null) {
    print('_reformatted to nothing:\n----\n|${body.split("\n").join("|\n|")}|\n----');
    assert(lastGood != null);
    throw 'reformatted to nothing:\n$body';
  }
  return output.take(lastGood).join('\n');
}

class _LineRange {
  _LineRange(this.start, this.end, this._body);
  final int start;
  final int end;
  final String _body;
  String _value;
  String get value {
    _value ??= _body.substring(start, end);
    return _value;
  }
}

Iterable<_LineRange> _walkLinesBackwards(String body, int start) sync* {
  int end;
  while (start > 0) {
    start -= 1;
    if (body[start] == '\n') {
      if (end != null)
        yield new _LineRange(start + 1, end, body);
      end = start;
    }
  }
  if (end != null)
    yield new _LineRange(start, end, body);
}

Iterable<_LineRange> _walkLinesForwards(String body, { int start: 0, int end }) sync* {
  int startIndex = start == 0 || body[start-1] == '\n' ? start : null;
  int endIndex = startIndex ?? start;
  end ??= body.length;
  while (endIndex < end) {
    if (body[endIndex] == '\n') {
      if (startIndex != null)
        yield new _LineRange(startIndex, endIndex, body);
      startIndex = endIndex + 1;
    }
    endIndex += 1;
  }
  if (startIndex != null)
    yield new _LineRange(startIndex, endIndex, body);
}

class _SplitLicense {
  _SplitLicense(this._body, this._split) {
    assert(this._split == 0 || this._split == this._body.length || this._body[this._split] == '\n');
  }
  final String _body;
  final int _split;
  String getCopyright() => _body.substring(0, _split);
  String getConditions() => _split >= _body.length ? '' : _body.substring(_split == 0 ? 0 : _split + 1);
}

_SplitLicense _splitLicense(String body, { bool verifyResults: true }) {
  Iterator<_LineRange> lines = _walkLinesForwards(body).iterator;
  if (!lines.moveNext())
    throw 'tried to split empty license';
  int end = 0;
  while (true) {
    final String line = lines.current.value;
    if (line == 'Author:' ||
        line == 'This code is derived from software contributed to Berkeley by' ||
        line == 'The Initial Developer of the Original Code is') {
      if (!lines.moveNext())
        throw 'unexpected end of block instead of author when looking for copyright';
      if (lines.current.value.trim() == '')
        throw 'unexpectedly blank line instead of author when looking for copyright';
      end = lines.current.end;
      if (!lines.moveNext())
        break;
    } else if (line.startsWith('Authors:') || line == 'Other contributors:') {
      if (line != 'Authors:') {
        // assume this line contained an author as well
        end = lines.current.end;
      }
      if (!lines.moveNext())
        throw 'unexpected end of license when reading list of authors while looking for copyright';
      final String firstAuthor = lines.current.value;
      int subindex = 0;
      while (subindex < firstAuthor.length && (firstAuthor[subindex] == ' ' ||
                                               firstAuthor[subindex] == '\t'))
        subindex += 1;
      if (subindex == 0 || subindex > firstAuthor.length)
        throw 'unexpected blank line instead of authors found when looking for copyright';
      end = lines.current.end;
      final String prefix = firstAuthor.substring(0, subindex);
      while (lines.moveNext() && lines.current.value.startsWith(prefix)) {
        final String nextAuthor = lines.current.value.substring(prefix.length);
        if (nextAuthor == '' || nextAuthor[0] == ' ' || nextAuthor[0] == '\t')
          throw 'unexpectedly ragged author list when looking for copyright';
        end = lines.current.end;
      }
      if (lines.current == null)
        break;
    } else if (line.contains(halfCopyrightPattern)) {
      do {
        if (!lines.moveNext())
          throw 'unexpected end of block instead of copyright holder when looking for copyright';
        if (lines.current.value.trim() == '')
          throw 'unexpectedly blank line instead of copyright holder when looking for copyright';
        end = lines.current.end;
      } while (lines.current.value.contains(trailingComma));
      if (!lines.moveNext())
        break;
    } else if (copyrightStatementPatterns.every((RegExp pattern) => !line.contains(pattern))) {
      break;
    } else {
      end = lines.current.end;
      if (!lines.moveNext())
        break;
    }
  }
  if (verifyResults && 'Copyright ('.allMatches(body, end).isNotEmpty)
    throw 'the license seems to contain a copyright:\n===copyright===\n${body.substring(0, end)}\n===license===\n${body.substring(end)}\n=========';
  return new _SplitLicense(body, end);
}

class _PartialLicenseMatch {
  _PartialLicenseMatch(this._body, this.start, this.split, this.end, this._match) {
    assert(split >= start);
    assert(split == start || _body[split] == '\n');
  }
  final String _body;
  final int start;
  final int split;
  final int end;
  final Match _match;
  String group(int index) => _match.group(index);
  String getAuthors() {
    final Match match = authorPattern.firstMatch(getCopyrights());
    if (match != null)
      return match.group(1);
    return null;
  }
  String getCopyrights() => _body.substring(start, split);
  String getConditions() => _body.substring(split + 1, end);
  String getEntireLicense() => _body.substring(start, end);
}

Iterable<_PartialLicenseMatch> _findLicenseBlocks(String body, RegExp pattern, int firstPrefixIndex, int indentPrefixIndex, { bool needsCopyright: true }) sync* {
  // I tried doing this with one big RegExp initially, but that way lay madness.
  for (Match match in pattern.allMatches(body)) {
    assert(match.groupCount >= firstPrefixIndex);
    assert(match.groupCount >= indentPrefixIndex);
    int start = match.start;
    final String fullPrefix = '${match.group(firstPrefixIndex)}${match.group(indentPrefixIndex)}';
    // first we walk back to the start of the block that has the same prefix (e.g.
    // the start of this comment block)
    bool firstLineSpecialComment = false;
    bool lastWasBlank = false;
    bool foundNonBlank = false;
    for (_LineRange range in _walkLinesBackwards(body, start)) {
      String line = range.value;
      bool isBlockCommentLine;
      if (line.length > 3 && line.endsWith('*/')) {
        int index = line.length - 3;
        while (line[index] == ' ')
          index -= 1;
        line = line.substring(0, index + 1);
        isBlockCommentLine = true;
      } else {
        isBlockCommentLine = false;
      }
      if (line.isEmpty || fullPrefix.startsWith(line)) {
        // this is blank line
        if (lastWasBlank && (foundNonBlank || !needsCopyright))
          break;
        lastWasBlank = true;
      } else if (((!isBlockCommentLine && line.startsWith('/*')) ||
                 line.startsWith('<!--') ||
                 (range.start == 0 && line.startsWith('  $fullPrefix')))) {
        start = range.start;
        firstLineSpecialComment = true;
        break;
      } else if (fullPrefix.isNotEmpty && !line.startsWith(fullPrefix)) {
        break;
      } else if (licenseFragments.any((RegExp pattern) => line.contains(pattern))) {
        // we're running into another license, abort, abort!
        break;
      } else {
        lastWasBlank = false;
        foundNonBlank = true;
      }
      start = range.start;
    }
    // then we walk forward dropping anything until the first line that matches what
    // we think might be part of a copyright statement
    bool foundAny = false;
    for (_LineRange range in _walkLinesForwards(body, start: start, end: match.start)) {
      final String line = range.value;
      if (firstLineSpecialComment || line.startsWith(fullPrefix)) {
        String data;
        if (firstLineSpecialComment) {
          data = stripDecorations.firstMatch(line).group(2);
        } else {
          data = line.substring(fullPrefix.length);
        }
        if (copyrightStatementLeadingPatterns.any((RegExp pattern) => data.contains(pattern))) {
          start = range.start;
          foundAny = true;
          break;
        }
      }
      firstLineSpecialComment = false;
    }
    int split;
    if (!foundAny) {
      if (needsCopyright)
        throw 'could not find copyright before license\nlicense body was:\n---\n${body.substring(match.start, match.end)}\n---\nfile was:\n---\n$body\n---';
      start = match.start;
      split = match.start;
    } else {
      final String copyrights = body.substring(start, match.start);
      final String undecoratedCopyrights = _reformat(copyrights);
      final _SplitLicense sanityCheck = _splitLicense(undecoratedCopyrights, verifyResults: false);
      final String conditions = sanityCheck.getConditions();
      if (conditions != '')
        throw 'potential license text caught in _findLicenseBlocks dragnet:\n---\n$conditions\n---\nundecorated copyrights was:\n---\n$undecoratedCopyrights\n---\ncopyrights was:\n---\n$copyrights\n---\nblock was:\n---\n${body.substring(start, match.end)}\n---';
      if (!copyrights.contains(copyrightMentionPattern))
        throw 'could not find copyright before license block:\n---\ncopyrights was:\n---\n$copyrights\n---\nblock was:\n---\n${body.substring(start, match.end)}\n---';
      assert(body[match.start - 1] == '\n');
      split = match.start - 1;
    }
    yield new _PartialLicenseMatch(body, start, split, match.end, match);
  }
}

class _LicenseMatch {
  _LicenseMatch(this.license, this.start, this.end, { this.debug: '', this.isDuplicate: false });
  final License license;
  final int start;
  final int end;
  final String debug;
  final bool isDuplicate;
}

int _debugCounter = 0;

Iterable<_LicenseMatch> _expand(License template, String copyright, int start, int end, { String debug: '' }) sync* {
  List<License> results = template.expandTemplate(_reformat(copyright)).toList();
  if (results.isEmpty)
    throw 'license could not be expanded';
  yield new _LicenseMatch(results.first, start, end, debug: 'expanding template for $debug');
  if (results.length > 1)
    yield* results.skip(1).map((License license) => new _LicenseMatch(license, start, end, isDuplicate: true, debug: 'expanding subsequent template for $debug'));
}

Iterable<_LicenseMatch> _tryNone(String body, String filename, RegExp pattern, LicenseSource parentDirectory) sync* {
  for (Match match in pattern.allMatches(body)) {
    final List<License> results = parentDirectory.nearestLicensesFor(filename);
    if (results == null || results.isEmpty)
      throw 'no default license file found';
    // TODO(ianh): use _expand if the license asks for the copyright to be included (e.g. BSD)
    yield new _LicenseMatch(results.first, match.start, match.end, debug: '_tryNone');
    if (results.length > 1)
      yield* results.skip(1).map((License license) => new _LicenseMatch(license, match.start, match.end, isDuplicate: true, debug: 'subsequent _tryNone'));
  }
}

Iterable<_LicenseMatch> _tryAttribution(String body, RegExp pattern) sync* {
  for (Match match in pattern.allMatches(body)) {
    assert(match.groupCount == 2);
    yield new _LicenseMatch(new License.unique('Thanks to ${match.group(2)}.', LicenseType.unknown), match.start, match.end, debug: '_tryAttribution');
  }
}

Iterable<_LicenseMatch> _tryReferenceByFilename(String body, LicenseFileReferencePattern pattern, LicenseSource parentDirectory) sync* {
  if (pattern.copyrightIndex != null) {
    for (Match match in pattern.pattern.allMatches(body)) {
      final String copyright = match.group(pattern.copyrightIndex);
      final String authors = pattern.authorIndex != null ? match.group(pattern.authorIndex) : null;
      final String filename = match.group(pattern.fileIndex);
      final License template = parentDirectory.nearestLicenseWithName(filename, authors: authors);
      if (template == null)
        throw 'failed to find template $filename in $parentDirectory (authors=$authors)';
      assert(_reformat(copyright) != '');
      yield* _expand(template, copyright, match.start, match.end, debug: '_tryAuthorsReference');
    }
  } else {
    for (_PartialLicenseMatch match in _findLicenseBlocks(body, pattern.pattern, pattern.firstPrefixIndex, pattern.indentPrefixIndex, needsCopyright: pattern.needsCopyright)) {
      final String authors = match.getAuthors();
      final License template = parentDirectory.nearestLicenseWithName(match.group(pattern.fileIndex), authors: authors);
      if (template == null)
        throw 'failed to find accompanying "${match.group(3)}" in $parentDirectory';
      if (match.getCopyrights() == '') {
        yield new _LicenseMatch(template, match.start, match.end, debug: '_tryReferenceByFilename looking for ${match.group(3)} $_debugCounter');
      } else {
        yield* _expand(template, match.getCopyrights(), match.start, match.end, debug: '_tryReferenceByFilename looking for ${match.group(3)} $_debugCounter');
      }
    }
  }
}

Iterable<_LicenseMatch> _tryReferenceByType(String body, RegExp pattern, LicenseSource parentDirectory) sync* {
  for (_PartialLicenseMatch match in _findLicenseBlocks(body, pattern, 1, 2)) {
    final LicenseType type = convertLicenseNameToType(match.group(3));
    final License template = parentDirectory.nearestLicenseOfType(type);
    if (template == null)
      throw 'failed to find accompanying $type license in $parentDirectory';
    assert(_reformat(match.getCopyrights()) != '');
    yield* _expand(template, match.getCopyrights(), match.start, match.end, debug: '_tryReferenceByType');
  }
}

Iterable<_LicenseMatch> _tryReferenceByUrl(String body, MultipleVersionedLicenseReferencePattern pattern, LicenseSource parentDirectory) sync* {
  for (_PartialLicenseMatch match in _findLicenseBlocks(body, pattern.pattern, 1, 2, needsCopyright: false)) {
    bool isDuplicate = false;
    for (int index in pattern.licenseIndices) {
      License result = pattern.checkLocalFirst ? parentDirectory.nearestLicenseWithName(match.group(index)) : null;
      if (result == null) {
        String suffix = '';
        if (pattern.versionIndicies != null && pattern.versionIndicies.containsKey(index))
          suffix = ':${match.group(pattern.versionIndicies[index])}';
        result = new License.fromUrl('${match.group(index)}$suffix');
      }
      yield new _LicenseMatch(result, match.start, match.end, isDuplicate: isDuplicate, debug: '_tryReferenceByUrl');
      isDuplicate = true;
    }
  }
}

Iterable<_LicenseMatch> _tryInline(String body, RegExp pattern, { bool needsCopyright }) sync* {
  assert(needsCopyright != null);
  for (_PartialLicenseMatch match in _findLicenseBlocks(body, pattern, 1, 2, needsCopyright: needsCopyright)) {
    // we use a template license here (not unique) because it's not uncommon for files
    // to reference license blocks in other files, but with their own copyrights.
    yield new _LicenseMatch(new License.fromBody(match.getEntireLicense()), match.start, match.end, debug: '_tryInline');
  }
}

Iterable<_LicenseMatch> _tryForwardReferencePattern(String fileContents, ForwardReferencePattern pattern, License template) sync* {
  for (_PartialLicenseMatch match in _findLicenseBlocks(fileContents, pattern.pattern, pattern.firstPrefixIndex, pattern.indentPrefixIndex)) {
    if (!template.body.contains(pattern.targetPattern))
      throw 'forward license reference to unexpected license';
    yield* _expand(template, match.getCopyrights(), match.start, match.end, debug: '_tryForwardReferencePattern');
  }
}

List<License> determineLicensesFor(String fileContents, String filename, LicenseSource parentDirectory) {
  if (fileContents.length > kMaxSize)
    fileContents = fileContents.substring(0, kMaxSize);
  List<_LicenseMatch> results = <_LicenseMatch>[];
  fileContents = fileContents.replaceAll('\t', ' ');
  fileContents = fileContents.replaceAll(newlinePattern, '\n');
  results.addAll(csNoCopyrights.expand((RegExp pattern) => _tryNone(fileContents, filename, pattern, parentDirectory)));
  results.addAll(csAttribution.expand((RegExp pattern) => _tryAttribution(fileContents, pattern)));
  results.addAll(csReferencesByFilename.expand((LicenseFileReferencePattern pattern) => _tryReferenceByFilename(fileContents, pattern, parentDirectory)));
  results.addAll(csReferencesByType.expand((RegExp pattern) => _tryReferenceByType(fileContents, pattern, parentDirectory)));
  results.addAll(csReferencesByUrl.expand((MultipleVersionedLicenseReferencePattern pattern) => _tryReferenceByUrl(fileContents, pattern, parentDirectory)));
  results.addAll(csLicenses.expand((RegExp pattern) => _tryInline(fileContents, pattern, needsCopyright: true)));
  results.addAll(csNotices.expand((RegExp pattern) => _tryInline(fileContents, pattern, needsCopyright: false)));
  if (results.isEmpty) {
    // we failed to find a license, so let's just look for simple copyrights
    // print('bailing on: $filename'); // TODO(ianh): spot-check these
    // TODO(ianh): look for common license fragments in these files to make sure we're not missing anything
    results.addAll(csFallbacks.expand((RegExp pattern) => _tryNone(fileContents, filename, pattern, parentDirectory)));
    if (results.isEmpty) {
      if (fileContents.contains(copyrightMentionPattern))
        throw 'Failed to find license in file containing copyright.';
    }
  }
  if (results.length == 1) {
    final License target = results.single.license;
    results.addAll(csForwardReferenceLicenses.expand((ForwardReferencePattern pattern) => _tryForwardReferencePattern(fileContents, pattern, target)));
  }
  results.sort((_LicenseMatch a, _LicenseMatch b) {
    int result = a.start - b.start;
    if (result != 0)
      return result;
    return a.end - b.end;
  });
  int position = 0;
  for (_LicenseMatch m in results) {
    if (m.isDuplicate)
      continue; // some text expanded into multiple licenses, so overlapping is expected
    if (position > m.start) {
      for (_LicenseMatch n in results)
        print('license match: ${n.start}..${n.end}, ${n.debug}, first line: ${n.license.body.split("\n").first}');
      throw 'overlapping licenses in $filename (one ends at $position, another starts at ${m.start})';
    }
    if (position < m.start) {
      final String substring = fileContents.substring(position, m.start);
      if ((substring.contains(copyrightMentionPattern) || substring.contains(licenseMentionPattern)) && !substring.contains(copyrightMentionOkPattern))
        throw 'unmatched potential copyright or license statements in $filename:\n  $position..${m.start}: "$substring"';
    }
    position = m.end;
  }
  return results.map((_LicenseMatch entry) => entry.license).toList();
}

// the kind of license that just wants to show a message (e.g. the JPEG one)
class MessageLicense extends License {
  MessageLicense._(String body, LicenseType type) : super._(body, type);
  @override
  Iterable<License> expandTemplate(String copyright) sync* {
    yield new License.unique(copyright, LicenseType.unknown);
    yield this;
  }
}

// the kind of license that says to include the copyright and the license text (e.g. BSD)
class TemplateLicense extends License {
  TemplateLicense._(String body, LicenseType type) : super._(body, type) {
    assert(!body.startsWith('Apache License'));
  }

  String _conditions;

  @override
  Iterable<License> expandTemplate(String copyright) sync* {
    _usedAsTemplate = true;
    _conditions ??= _splitLicense(body).getConditions();
    yield new License.fromCopyrightAndLicense(copyright, _conditions, type);
  }
}

// the kind of license that should not be combined with separate copyright notices
class UniqueLicense extends License {
  UniqueLicense._(String body, LicenseType type) : super._(body, type);
  @override
  Iterable<License> expandTemplate(String copyright) sync* {
    throw 'attempted to expand non-template license with "$copyright"\ntemplate was: $this';
  }
}
