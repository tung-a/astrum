import 'package:astrum/features/astral/domain/birth_datetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data e hora validas', () {
    expect(birthDateTimeOf(birthDate: '05/03/1990', birthTime: '14:30'),
        DateTime(1990, 3, 5, 14, 30));
  });

  test('hora ausente vira 12:00', () {
    expect(birthDateTimeOf(birthDate: '05/03/1990', birthTime: ''),
        DateTime(1990, 3, 5, 12, 0));
  });

  test('hora nao numerica vira 12 e minuto nao numerico vira 0', () {
    expect(birthDateTimeOf(birthDate: '05/03/1990', birthTime: 'ab:cd'),
        DateTime(1990, 3, 5, 12, 0));
    expect(birthDateTimeOf(birthDate: '05/03/1990', birthTime: '7'),
        DateTime(1990, 3, 5, 7, 0));
    expect(birthDateTimeOf(birthDate: '05/03/1990', birthTime: '7:xx'),
        DateTime(1990, 3, 5, 7, 0));
  });

  test('data invalida ou vazia devolve null', () {
    expect(birthDateTimeOf(birthDate: '', birthTime: '10:00'), isNull);
    expect(
        birthDateTimeOf(birthDate: '31/02/1990', birthTime: '10:00'), isNull);
    expect(
        birthDateTimeOf(birthDate: '1990-03-05', birthTime: '10:00'), isNull);
  });
}
