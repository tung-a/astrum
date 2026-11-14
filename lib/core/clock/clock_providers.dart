import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relogio injetavel: controllers leem "agora" por aqui para que os testes
/// fixem o dia (check-in, tarot e horoscopo diarios).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);
