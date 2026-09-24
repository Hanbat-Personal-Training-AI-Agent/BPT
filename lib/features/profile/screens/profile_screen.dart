import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/home/providers/home_provider.dart';
import '../../../features/onboarding/providers/onboarding_provider.dart';
import '../../../models/user_model.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_confirm_dialog.dart';

const _goalOptions = ['근력 증가', '체중 감량', '체형 교정', '건강 관리'];
const _frequencyOptions = [2, 3, 4, 5, 6];

/// 온보딩에서 고른 성별을 신체 정보 카드에 표시할 라벨로 변환한다.
/// 계정에 저장된 [UserModel.gender]가 아직 없을 때의 폴백으로만 쓰인다 —
/// 회원가입이 실제 계정 생성으로 이어지면(현재는 미연동) 이 폴백은 자연히
/// 안 쓰이게 된다.
String? _genderLabelFromOnboarding(Gender? gender) => switch (gender) {
      Gender.male => '남성',
      Gender.female => '여성',
      _ => null,
    };

/// 바텀시트 하단 여백. MainShell의 캡슐형 플로팅 네비게이션 바는 Scaffold의
/// body 영역(=여기서 뜨는 바텀시트가 속한 영역) 위로 그려지기 때문에, 시트를
/// 화면 맨 아래까지 붙이면 저장 버튼 등이 네비게이션 바에 가려진다. 키보드가
/// 없을 때는 저장 버튼이 네비게이션 바 바로 위(최소 간격)에 오는 정도만 띄운다.
double _sheetBottomPadding(BuildContext context) {
  final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
  if (keyboardInset > 0) return keyboardInset + 24;
  final safeBottom = MediaQuery.of(context).padding.bottom;
  final navBarMargin = safeBottom > 0 ? safeBottom - 8 : 16.0;
  return navBarMargin + 16;
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 고정 영역: 헤더는 스크롤에 영향받지 않음
              const _ProfileHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                  child: Column(
                    children: [
                      _UserCard(user: user),
                      const SizedBox(height: 14),
                      _BodyInfoCard(user: user),
                      const SizedBox(height: 14),
                      _GoalCard(user: user),
                      const SizedBox(height: 14),
                      const _BodyCheckCta(),
                      const SizedBox(height: 14),
                      const _SettingsCard(),
                      const SizedBox(height: 24),
                      const _LogoutButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 헤더 (고정) ────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '내정보',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ── 유저 카드 (이름 · 코리와 함께한 일수) ───────────────────────────────────
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final UserModel user;

  int get _daysWithKori {
    final joined =
        DateTime(user.joinedAt.year, user.joinedAt.month, user.joinedAt.day);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return todayOnly.difference(joined).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(RouteConstants.editProfile),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 104,
          color: AppColors.purple,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 22,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${user.username} · 코리와 $_daysWithKori일째',
                        style: TextStyle(
                          color: AppColors.black.withValues(alpha: 0.65),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 19,
                top: 2,
                bottom: -18,
                child: Image.asset(
                  'assets/images/character/face.png',
                  width: 108,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 신체 정보 ──────────────────────────────────────────────────────────────
class _BodyInfoCard extends ConsumerWidget {
  const _BodyInfoCard({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bmi = user.heightCm > 0
        ? user.weightKg / ((user.heightCm / 100) * (user.heightCm / 100))
        : 0.0;
    final onboardingGender = ref.watch(onboardingProvider).gender;
    final genderLabel =
        user.gender ?? _genderLabelFromOnboarding(onboardingGender) ?? '-';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '신체 정보',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900),
              ),
              GestureDetector(
                onTap: () => _showEditBodyInfoSheet(context, ref, user),
                child: const Text(
                  '수정',
                  style: TextStyle(
                      color: AppColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _InfoStat(label: '성별', value: genderLabel)),
              Expanded(
                child: _InfoStat(
                  label: '키',
                  value: user.heightCm > 0 ? '${user.heightCm.round()}' : '-',
                  unit: user.heightCm > 0 ? 'cm' : '',
                ),
              ),
              Expanded(
                child: _InfoStat(
                  label: '몸무게',
                  value: user.weightKg > 0
                      ? user.weightKg.toStringAsFixed(1)
                      : '-',
                  unit: user.weightKg > 0 ? 'kg' : '',
                ),
              ),
              Expanded(
                child: _InfoStat(
                  label: 'BMI',
                  value: bmi > 0 ? bmi.toStringAsFixed(1) : '-',
                  valueColor: AppColors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoStat extends StatelessWidget {
  const _InfoStat({
    required this.label,
    required this.value,
    this.unit = '',
    this.valueColor,
  });
  final String label;
  final String value;
  final String unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: unit,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

void _showEditBodyInfoSheet(
    BuildContext context, WidgetRef ref, UserModel user) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.grey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditBodyInfoSheet(user: user),
  );
}

class _EditBodyInfoSheet extends ConsumerStatefulWidget {
  const _EditBodyInfoSheet({required this.user});
  final UserModel user;

  @override
  ConsumerState<_EditBodyInfoSheet> createState() => _EditBodyInfoSheetState();
}

const _editHeightMin = 140.0;
const _editHeightMax = 200.0;
const _editWeightMin = 35.0;
const _editWeightMax = 120.0;

class _EditBodyInfoSheetState extends ConsumerState<_EditBodyInfoSheet> {
  String? _gender;
  late double _height;
  late double _weight;

  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightFocus = FocusNode();
  final _weightFocus = FocusNode();
  bool _editingHeight = false;
  bool _editingWeight = false;

  @override
  void initState() {
    super.initState();
    _gender = widget.user.gender ??
        _genderLabelFromOnboarding(ref.read(onboardingProvider).gender);
    _height = widget.user.heightCm > 0
        ? widget.user.heightCm.clamp(_editHeightMin, _editHeightMax)
        : 170.0;
    _weight = widget.user.weightKg > 0
        ? widget.user.weightKg.clamp(_editWeightMin, _editWeightMax)
        : 60.0;
    _heightFocus.addListener(() {
      if (!_heightFocus.hasFocus) _commitHeight();
    });
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) _commitWeight();
    });
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _heightFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  void _startEditingHeight() {
    _heightController.text = _height.round().toString();
    setState(() => _editingHeight = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _heightFocus.requestFocus();
    });
  }

  void _startEditingWeight() {
    _weightController.text = _weight.toStringAsFixed(1);
    setState(() => _editingWeight = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _weightFocus.requestFocus();
    });
  }

  void _commitHeight() {
    if (!_editingHeight) return;
    final parsed = double.tryParse(_heightController.text);
    setState(() {
      if (parsed != null) {
        _height = parsed.clamp(_editHeightMin, _editHeightMax);
      }
      _editingHeight = false;
    });
  }

  void _commitWeight() {
    if (!_editingWeight) return;
    final parsed = double.tryParse(_weightController.text);
    setState(() {
      if (parsed != null) {
        _weight = parsed.clamp(_editWeightMin, _editWeightMax);
      }
      _editingWeight = false;
    });
  }

  void _save() {
    // 슬라이더 값 입력 중(키보드 편집 중)이었다면 저장 전에 먼저 반영한다.
    _commitHeight();
    _commitWeight();
    final updated = widget.user.copyWith(
      gender: _gender,
      heightCm: _height,
      weightKg: _weight,
    );
    // updateProfile은 로컬 상태를 동기적으로(첫 await 이전에) 반영하므로,
    // 서버 저장/동기화를 기다리지 않고 시트를 바로 닫아도 최신 값이 보인다.
    ref.read(authNotifierProvider).updateProfile(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: _sheetBottomPadding(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '신체 정보 수정',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PickChip(
                  label: '남성',
                  selected: _gender == '남성',
                  onTap: () => setState(() => _gender = '남성'),
                  fill: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickChip(
                  label: '여성',
                  selected: _gender == '여성',
                  onTap: () => setState(() => _gender = '여성'),
                  fill: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MeasurementCard(
            label: '키',
            unit: 'cm',
            value: _height,
            min: _editHeightMin,
            max: _editHeightMax,
            sliderColor: AppColors.green,
            valueText: _height.round().toString(),
            isEditing: _editingHeight,
            controller: _heightController,
            focus: _heightFocus,
            onTapValue: _startEditingHeight,
            onEditSubmitted: (_) => _heightFocus.unfocus(),
            onSliderChanged: (v) => setState(() {
              _height = v;
              // 숫자를 직접 입력 중일 때 막대를 움직이면 입력창 값도 바로
              // 따라가야 한다.
              if (_editingHeight) _heightController.text = v.round().toString();
            }),
          ),
          const SizedBox(height: 10),
          _MeasurementCard(
            label: '몸무게',
            unit: 'kg',
            value: _weight,
            min: _editWeightMin,
            max: _editWeightMax,
            sliderColor: AppColors.purple,
            valueText: _weight.toStringAsFixed(1),
            isEditing: _editingWeight,
            controller: _weightController,
            focus: _weightFocus,
            onTapValue: _startEditingWeight,
            onEditSubmitted: (_) => _weightFocus.unfocus(),
            onSliderChanged: (v) => setState(() {
              _weight = v;
              if (_editingWeight) {
                _weightController.text = v.toStringAsFixed(1);
              }
            }),
            allowDecimal: true,
          ),
          const SizedBox(height: 16),
          _SaveButton(onTap: _save),
        ],
      ),
    );
  }
}

// 온보딩 체형 입력 화면(OnboardingBodyScreen)의 측정값 카드와 동일한 스타일 —
// 라벨은 값 위/옆이 아니라 카드 자체 안에서 분리돼 있고, 슬라이더로 조절하거나
// 값을 탭해 직접 숫자를 입력할 수 있다.
class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.sliderColor,
    required this.valueText,
    required this.isEditing,
    required this.controller,
    required this.focus,
    required this.onTapValue,
    required this.onEditSubmitted,
    required this.onSliderChanged,
    this.allowDecimal = false,
  });

  final String label;
  final String unit;
  final double value;
  final double min;
  final double max;
  final Color sliderColor;
  final String valueText;
  final bool isEditing;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onTapValue;
  final ValueChanged<String> onEditSubmitted;
  final ValueChanged<double> onSliderChanged;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.black,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (isEditing)
                  SizedBox(
                    width: 100,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        textSelectionTheme: TextSelectionThemeData(
                          cursorColor: AppColors.green,
                          selectionColor:
                              AppColors.green.withValues(alpha: 0.3),
                          selectionHandleColor: AppColors.green,
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        autofocus: true,
                        textAlign: TextAlign.right,
                        cursorColor: AppColors.green,
                        keyboardType: TextInputType.numberWithOptions(
                            decimal: allowDecimal),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(allowDecimal
                              ? RegExp(r'[0-9.]')
                              : RegExp(r'[0-9]')),
                        ],
                        onSubmitted: onEditSubmitted,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900),
                        // 테마의 InputDecorationTheme(청록색 focusedBorder)가
                        // 새어 들어오지 않도록 모든 보더 상태를 명시적으로 없앤다.
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onTapValue,
                    child: Text(valueText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900)),
                  ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: sliderColor,
                inactiveTrackColor: const Color(0xFF3A3A3A),
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onSliderChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(min.round().toString(),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12)),
                  Text(max.round().toString(),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── 운동 목표 ──────────────────────────────────────────────────────────────
class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = user.workoutGoal ?? _goalOptions.first;
    final frequency = ref.watch(weeklyWorkoutGoalProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '운동 목표',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900),
              ),
              GestureDetector(
                onTap: () => _showEditGoalSheet(context, ref, user, frequency),
                child: const Text(
                  '변경',
                  style: TextStyle(
                      color: AppColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _GoalChip(label: goal, color: AppColors.green),
              const SizedBox(width: 8),
              _GoalChip(label: '주 $frequency회', color: AppColors.pink),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: AppColors.black, fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

void _showEditGoalSheet(
    BuildContext context, WidgetRef ref, UserModel user, int frequency) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.grey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EditGoalSheet(user: user, initialFrequency: frequency),
  );
}

class _EditGoalSheet extends ConsumerStatefulWidget {
  const _EditGoalSheet({required this.user, required this.initialFrequency});
  final UserModel user;
  final int initialFrequency;

  @override
  ConsumerState<_EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends ConsumerState<_EditGoalSheet> {
  late String _goal;
  late int _frequency;

  @override
  void initState() {
    super.initState();
    _goal = widget.user.workoutGoal ?? _goalOptions.first;
    _frequency = widget.initialFrequency;
  }

  void _save() {
    ref
        .read(authNotifierProvider)
        .updateProfile(widget.user.copyWith(workoutGoal: _goal));
    ref.read(weeklyWorkoutGoalProvider.notifier).state = _frequency;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: _sheetBottomPadding(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '운동 목표 변경',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _goalOptions)
                _PickChip(
                  label: g,
                  selected: _goal == g,
                  onTap: () => setState(() => _goal = g),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '일주일에 몇 번?',
            style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final freq in _frequencyOptions) ...[
                if (freq != _frequencyOptions.first) const SizedBox(width: 8),
                Expanded(
                  child: _FrequencyPickChip(
                    frequency: freq,
                    selected: _frequency == freq,
                    onTap: () => setState(() => _frequency = freq),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          _SaveButton(onTap: _save),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fill = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fill ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.green : AppColors.black,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? AppColors.black : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14),
        ),
      ),
    );
  }
}

class _FrequencyPickChip extends StatelessWidget {
  const _FrequencyPickChip({
    required this.frequency,
    required this.selected,
    required this.onTap,
  });
  final int frequency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.pink : AppColors.black,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          '$frequency회',
          style: TextStyle(
              color: selected ? AppColors.black : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text(
          '저장',
          style: TextStyle(
              color: AppColors.black,
              fontSize: 15,
              fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ── 체형 다시 측정 CTA ───────────────────────────────────────────────────────
class _BodyCheckCta extends ConsumerWidget {
  const _BodyCheckCta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 홈 화면의 체형 재측정 배너와 같은 값을 공유한다 — 두 화면이 서로 다른
    // 경과일을 보여주지 않도록 daysSinceLastBodyCheckProvider가 단일 소스.
    final daysSinceLastCheck = ref.watch(daysSinceLastBodyCheckProvider);
    final daysUntilNext =
        (bodyCheckCycleDays - daysSinceLastCheck).clamp(0, bodyCheckCycleDays);
    final state = resolveBodyCheckState(daysSinceLastCheck);

    final lastCheckDate =
        DateTime.now().subtract(Duration(days: daysSinceLastCheck));
    final dateLabel = '${lastCheckDate.month}.${lastCheckDate.day}';

    late final Color bg;
    late final Color fg;
    late final Color iconColor;
    late final String subtitle;

    switch (state) {
      case BodyCheckState.fresh:
        bg = AppColors.grey;
        fg = AppColors.green;
        iconColor = AppColors.green;
        subtitle = '마지막 $dateLabel · 다음 확인까지 $daysUntilNext일';
      case BodyCheckState.dueSoon:
        bg = AppColors.purple.withValues(alpha: 0.18);
        fg = AppColors.purple;
        iconColor = AppColors.purple;
        subtitle = '마지막 $dateLabel · 다음 측정까지 $daysUntilNext일';
      case BodyCheckState.overdue:
        bg = AppColors.red;
        fg = Colors.white;
        iconColor = AppColors.pink;
        subtitle = '마지막 $dateLabel · $daysSinceLastCheck일 지났어';
    }

    return GestureDetector(
      onTap: () => context.push(RouteConstants.onboardingCapture),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.crop_free_rounded, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '체형 다시 측정',
                    style: TextStyle(
                        color: fg, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        color: fg.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: fg.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

// ── 알림 / 코리 잔소리 시간 / 계정 · 개인정보 / 앱 정보 (한 카드) ─────────
class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final reminderTime = ref.watch(koriReminderTimeProvider);
    final divider = Divider(
        height: 1,
        indent: 18,
        endIndent: 18,
        color: Colors.white.withValues(alpha: 0.08));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '알림',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
                // 운동 시작 화면의 "세트별로 다르게 설정" 토글과 동일한 스타일.
                Transform.scale(
                  scale: 0.95,
                  child: Switch(
                    value: notificationsEnabled,
                    onChanged: (v) => ref
                        .read(notificationsEnabledProvider.notifier)
                        .state = v,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeTrackColor: AppColors.green,
                    thumbColor: const WidgetStatePropertyAll(AppColors.black),
                    trackOutlineColor:
                        const WidgetStatePropertyAll(Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
          divider,
          _SettingsRow(
            label: '코리 잔소리 시간',
            trailing: _formatTimeOfDay(reminderTime),
            enabled: notificationsEnabled,
            onTap: !notificationsEnabled
                ? null
                : () => _showReminderTimeSheet(context, ref, reminderTime),
          ),
          divider,
          _SettingsRow(
            label: '계정 · 개인정보',
            showChevron: true,
            onTap: () => context.push(RouteConstants.accountInfo),
          ),
          divider,
          const _SettingsRow(label: '앱 정보', trailing: 'v 1.0.0'),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    this.trailing,
    this.showChevron = false,
    this.onTap,
    this.enabled = true,
  });
  final String label;
  final String? trailing;
  final bool showChevron;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dim = enabled ? 1.0 : 0.4;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: dim),
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45 * dim),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                if (showChevron) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.35 * dim),
                      size: 20),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimeOfDay(TimeOfDay t) {
  final isAm = t.hour < 12;
  final hour12raw = t.hour % 12;
  final hour12 = hour12raw == 0 ? 12 : hour12raw;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = isAm ? '오전' : '오후';
  return '$period $hour12:$minute';
}

// ── 코리 잔소리 시간 선택 (숫자 스크롤 휠 바텀시트) ────────────────────────
void _showReminderTimeSheet(
    BuildContext context, WidgetRef ref, TimeOfDay current) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.grey,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReminderTimeSheet(initial: current),
  );
}

class _ReminderTimeSheet extends ConsumerStatefulWidget {
  const _ReminderTimeSheet({required this.initial});
  final TimeOfDay initial;

  @override
  ConsumerState<_ReminderTimeSheet> createState() => _ReminderTimeSheetState();
}

class _ReminderTimeSheetState extends ConsumerState<_ReminderTimeSheet> {
  late bool _isAm;
  late int _hour12; // 1–12
  late int _minute; // 0–59

  @override
  void initState() {
    super.initState();
    _isAm = widget.initial.hour < 12;
    final h = widget.initial.hour % 12;
    _hour12 = h == 0 ? 12 : h;
    _minute = widget.initial.minute;
  }

  void _save() {
    final hour24 = _isAm
        ? (_hour12 == 12 ? 0 : _hour12)
        : (_hour12 == 12 ? 12 : _hour12 + 12);
    ref.read(koriReminderTimeProvider.notifier).state =
        TimeOfDay(hour: hour24, minute: _minute);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: _sheetBottomPadding(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '코리 잔소리 시간',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: _TimeWheel(
                    itemCount: 2,
                    initialIndex: _isAm ? 0 : 1,
                    labelBuilder: (i) => i == 0 ? '오전' : '오후',
                    onChanged: (i) => setState(() => _isAm = i == 0),
                  ),
                ),
                Expanded(
                  child: _TimeWheel(
                    itemCount: 12,
                    initialIndex: _hour12 - 1,
                    labelBuilder: (i) => '${i + 1}',
                    onChanged: (i) => setState(() => _hour12 = i + 1),
                  ),
                ),
                Expanded(
                  child: _TimeWheel(
                    itemCount: 60,
                    initialIndex: _minute,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onChanged: (i) => setState(() => _minute = i),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SaveButton(onTap: _save),
        ],
      ),
    );
  }
}

/// 단순한 숫자 스크롤(휠) 컬럼 — 시스템 시계 다이얼 대신 앱 톤에 맞춘
/// 심플한 피커.
class _TimeWheel extends StatefulWidget {
  const _TimeWheel({
    required this.itemCount,
    required this.initialIndex,
    required this.labelBuilder,
    required this.onChanged,
  });
  final int itemCount;
  final int initialIndex;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPicker(
      scrollController:
          FixedExtentScrollController(initialItem: widget.initialIndex),
      itemExtent: 40,
      diameterRatio: 1.4,
      selectionOverlay: null,
      onSelectedItemChanged: (i) {
        setState(() => _selected = i);
        widget.onChanged(i);
      },
      children: [
        for (int i = 0; i < widget.itemCount; i++)
          Center(
            child: Text(
              widget.labelBuilder(i),
              style: TextStyle(
                  color: i == _selected ? AppColors.green : Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }
}

// ── 로그아웃 ───────────────────────────────────────────────────────────────
class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _confirmLogout(context, ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.grey,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const Text(
          '로그아웃',
          style: TextStyle(
              color: AppColors.red, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

void _confirmLogout(BuildContext context, WidgetRef ref) {
  showProfileConfirmDialog(
    context,
    title: '로그아웃',
    message: '정말 로그아웃할까?',
    confirmLabel: '로그아웃',
    onConfirm: () => ref.read(authNotifierProvider).logout(),
  );
}
