import 'package:astrum/core/firebase/session_providers.dart';
import 'package:astrum/core/theme/astrum_colors.dart';
import 'package:astrum/core/widgets/starfield.dart';
import 'package:astrum/features/profile/presentation/account_controller.dart';
import 'package:astrum/features/profile/presentation/delete_account_controller.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const deleteAccountBody =
    'Esta ação é permanente e não pode ser desfeita. Vamos apagar: seu perfil '
    'e seus dados de nascimento, seu mapa astral e horóscopos salvos, sua '
    'Poeira Estelar e todos os seus itens, seus eventos e rituais, todo o '
    'histórico de conversas com o oráculo, sua lista de amigos e as '
    'notificações que você recebeu, as intenções que você enviou, seu perfil '
    'público (você deixa de aparecer na busca de amigos), os registros de uso '
    'associados à sua conta e o acesso com seu e-mail e senha. Poeira Estelar '
    'e itens não podem ser recuperados nem reembolsados. Seu nome pode '
    'continuar aparecendo na lista de amigos de quem adicionou você, até essa '
    'pessoa removê-lo. Cópias de segurança do provedor (Google/Firebase) '
    'podem levar algum tempo para serem eliminadas.';

const deleteAccountMissingBody =
    'Esta conta não tem um perfil completo, por isso não é possível usar o '
    'app. Você pode excluí-la agora para apagar o que restou e liberar o '
    'e-mail para um novo cadastro. A exclusão é permanente.';

const deleteAccountFinalTitle = 'Excluir a conta definitivamente?';
const deleteAccountFinalBody = 'Não será possível desfazer.';

/// Tela `/account/delete`: funciona com ou sem perfil (perfil ausente) e nao
/// depende de `profile`. A senha digitada fica so neste campo: e passada a
/// `run` e nunca guardada nem registrada.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start({required bool confirm}) async {
    final password = _password.text;
    if (password.isEmpty) return;
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(deleteAccountFinalTitle),
          content: const Text(deleteAccountFinalBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: AstrumColors.destructive),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir definitivamente'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await ref.read(deleteAccountControllerProvider.notifier).run(password);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(deleteAccountControllerProvider);
    final profileAsync = ref.watch(profileProvider);
    final uid = ref.watch(currentUidProvider);
    final missing = uid != null &&
        !profileAsync.isLoading &&
        profileAsync.hasValue &&
        profileAsync.value == null &&
        !s.started;
    final running = s.phase == DeletePhase.running;
    final failed = s.phase == DeletePhase.failed;

    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(title: const Text('Excluir conta')),
        body: Starfield(
          child: SafeArea(
            child: running ? _progress(s) : _form(s, missing, failed),
          ),
        ),
      ),
    );
  }

  Widget _progress(DeleteAccountState s) {
    final n = s.step.index + 1;
    final total = DeleteStep.values.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          label: 'Excluindo sua conta. ${s.step.label} Etapa $n de $total.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                'Excluindo sua conta… Não feche o app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: AstrumColors.cream),
              ),
              const SizedBox(height: 12),
              Text(
                '${s.step.label} ($n de $total)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AstrumColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(DeleteAccountState s, bool missing, bool failed) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          missing ? deleteAccountMissingBody : deleteAccountBody,
          style: const TextStyle(color: AstrumColors.cream, height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _password,
          focusNode: _focus,
          autofocus: true,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline),
            labelText: 'Digite sua senha para confirmar',
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
        if (failed && s.message != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(s.message!,
                style: const TextStyle(color: AstrumColors.destructive)),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AstrumColors.destructive,
              foregroundColor: Colors.white),
          onPressed:
              _password.text.isEmpty ? null : () => _start(confirm: !failed),
          child: Text(failed ? 'Tentar de novo' : 'Excluir minha conta'),
        ),
        if (failed || missing) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                ref.read(accountControllerProvider.notifier).signOut(),
            child: const Text('Sair'),
          ),
        ],
      ],
    );
  }
}
