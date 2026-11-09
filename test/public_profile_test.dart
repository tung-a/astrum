import 'package:astrum/services/public_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hashEmail: 64 hex, lowercase e trim', () {
    final h = hashEmail('a@x.com');
    expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(hashEmail('  A@X.Com '), h);
  });

  test('hashEmail: valor conhecido (SHA-256 de test@example.com)', () {
    expect(hashEmail(' Test@Example.COM '),
        '973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b');
  });

  test('buildPublicProfile: so name, avatar, emailHash', () {
    final p =
        buildPublicProfile(name: ' Ana ', avatar: null, email: 'a@x.com')!;
    expect(p.keys.toSet(), {'name', 'avatar', 'emailHash'});
    expect(p['name'], 'Ana');
    expect(p['avatar'], '');
    expect(buildPublicProfile(name: 'Ana', avatar: '', email: ' '), isNull);
  });
}
