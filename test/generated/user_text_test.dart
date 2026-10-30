import 'dart:io';

import 'package:claudart/generated/user_text.g.dart';
import 'package:test/test.dart';

import '../../tool/generate_user_text.dart';

void main() {
  group('$UserText', () {
    test('the checked-in file is what text/user_text.json generates', () {
      expect(
        File('lib/generated/user_text.g.dart').readAsStringSync(),
        generateUserText(File('text/user_text.json').readAsStringSync()),
      );
    });

    test('generating escapes quotes, dollars and newlines', () {
      final source = generateUserText('{"k": "it\'s \$5\\nnext"}');
      expect(source, contains(r"k('it\'s \$5\nnext')"));
    });

    test('format fills each placeholder', () {
      expect(UserText.projectLine.format({'name': 'app'}), 'Project  : app');
    });

    test('a filled value that looks like a placeholder is not filled again', () {
      expect(
        UserText.projectLine.format({'name': '{name}'}),
        'Project  : {name}',
      );
    });

    test('format leaves text without placeholders alone', () {
      expect(
        UserText.notInGitRepository.format({'name': 'app'}),
        UserText.notInGitRepository.template,
      );
    });

    test('format leaves an unfilled placeholder visible', () {
      expect(UserText.projectLine.format(), UserText.projectLine.template);
    });
  });
}
