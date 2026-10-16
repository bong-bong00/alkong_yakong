import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/session/mvp_session.dart';
import '../../../core/widgets/senior_button.dart';
import '../../../core/widgets/senior_feedback.dart';
import '../../../core/widgets/senior_header.dart';
import '../application/current_user_controller.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final userId = MvpSession.userId.trim();
    if (userId.isEmpty) {
      setState(() => _error = '다시 로그인해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(userRepositoryProvider)
          .changePassword(
            userId,
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      await showSeniorNoticeDialog(
        context: context,
        title: '비밀번호를 수정했어요',
        message: '다음 로그인부터 새 비밀번호를 사용해 주세요.',
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '비밀번호를 변경하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.pageBg,
    body: SafeArea(
      child: Column(
        children: [
          const SeniorBackHeader(title: '비밀번호 수정', alignStart: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _current,
                      obscureText: true,
                      enabled: !_saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '현재 비밀번호'),
                      validator: (v) =>
                          (v ?? '').isEmpty ? '현재 비밀번호를 입력해 주세요.' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _next,
                      obscureText: true,
                      enabled: !_saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '새 비밀번호',
                        helperText: '6자 이상 입력해 주세요.',
                      ),
                      validator: (v) =>
                          (v ?? '').length < 6 ? '비밀번호는 6자 이상이어야 해요.' : null,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      enabled: !_saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                      validator: (v) => v != _next.text || (v ?? '').isEmpty
                          ? '새 비밀번호와 같게 입력해 주세요.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SeniorButton(
                      label: _saving ? '저장하는 중…' : '저장하기',
                      minHeight: 56,
                      fontSize: 20,
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
