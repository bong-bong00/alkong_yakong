import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../drug_explain/drug_explain_screen.dart';
import '../../application/guardians_provider.dart';

/// Recreate the chat when its subject changes: medicines, requests, caches and
/// histories must never cross the general/patient boundary.
class GuardianPharmacistScreen extends ConsumerStatefulWidget {
  final String? initialPatientId;
  final ApiClient? apiClient;
  final ApiClient? medicationApiClient;
  final VoidCallback? onBack;
  const GuardianPharmacistScreen({
    super.key,
    this.initialPatientId,
    this.apiClient,
    this.medicationApiClient,
    this.onBack,
  });

  @override
  ConsumerState<GuardianPharmacistScreen> createState() =>
      _GuardianPharmacistScreenState();
}

class _GuardianPharmacistScreenState
    extends ConsumerState<GuardianPharmacistScreen> {
  String? _patientId;
  @override
  void initState() {
    super.initState();
    _patientId = widget.initialPatientId;
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(careOverviewProvider);
    final patients = overview.valueOrNull?.patients ?? const [];
    final matches = patients.where((p) => p.patientId == _patientId);
    final patient = matches.isEmpty ? null : matches.first;
    // A removed link must not silently become a general chat with old history.
    if (_patientId != null && patient == null) {
      if (overview.isLoading) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('AI 약사 상담'),
            leading: widget.onBack == null
                ? null
                : BackButton(onPressed: widget.onBack),
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI 약사 상담'),
          leading: widget.onBack == null
              ? null
              : BackButton(onPressed: widget.onBack),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('환자 연결을 확인하지 못했어요. 연결 상태와 인터넷을 확인해 주세요.'),
              TextButton(
                onPressed: () => ref.invalidate(careOverviewProvider),
                child: const Text('다시 확인'),
              ),
              TextButton(
                onPressed: () => setState(() => _patientId = null),
                child: const Text('일반 약 상담으로 이동'),
              ),
            ],
          ),
        ),
      );
    }
    return DrugExplainScreen(
      key: ValueKey('guardian-consultation-${_patientId ?? 'general'}'),
      generalConsultation: patient == null,
      patientId: patient?.patientId,
      patientName: patient?.name,
      registeredMedicinesOnly: patient != null,
      onBack: widget.onBack,
      apiClient: widget.apiClient,
      medicationApiClient: widget.medicationApiClient,
      consultationSelector: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(
                'guardian-subject-picker-${_patientId ?? 'general'}',
              ),
              initialValue: _patientId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '상담 대상',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('일반 약 상담')),
                for (final p in patients)
                  DropdownMenuItem(
                    value: p.patientId,
                    child: Text(
                      '${p.name} 님 약 상담',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) =>
                  setState(() => _patientId = id == '' ? null : id),
            ),
          ],
        ),
      ),
    );
  }
}
