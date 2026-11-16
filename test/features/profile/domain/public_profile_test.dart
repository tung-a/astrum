import 'package:astrum/features/profile/domain/public_profile.dart';
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

  group('publicAvatarFor (M1)', () {
    test('signo oculto: avatar zodiacal vira vazio', () {
      expect(publicAvatarFor('pfp_zodiac_leao', false), '');
    });
    test('signo exibido: avatar zodiacal publicado', () {
      expect(publicAvatarFor('pfp_zodiac_leao', true), 'pfp_zodiac_leao');
    });
    test('avatar comprado nao revela o signo: sempre publicado', () {
      expect(publicAvatarFor('pfp_rare_x', false), 'pfp_rare_x');
    });
    test('nulo ou vazio vira vazio', () {
      expect(publicAvatarFor(null, true), '');
      expect(publicAvatarFor('', false), '');
    });
  });
}
