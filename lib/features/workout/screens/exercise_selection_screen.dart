import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/route_constants.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/mock_data.dart';
import '../../../models/exercise_model.dart';

enum _SetMode { same, rampUp, pyramid }

class _SetConfig {
  _SetConfig({required this.reps, required this.weight});
  int reps;
  int weight;

  _SetConfig copy() => _SetConfig(reps: reps, weight: weight);
}

class ExerciseSelectionScreen extends ConsumerStatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  ConsumerState<ExerciseSelectionScreen> createState() =>
      _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState
    extends ConsumerState<ExerciseSelectionScreen> {
  static const _minSets = 3;
  static const _maxSets = 10;
  static const _defaultWeight = 20;

  late String _selectedExerciseId;
  late int _setCount;
  late int _uniformReps;
  late int _uniformWeight;
  bool _perSetEnabled = false;
  _SetMode _mode = _SetMode.same;
  late List<_SetConfig> _perSetValues;

  int _restSeconds = 60;
  bool _customRest = false;
  final _restCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final first = mockExercises.first;
    _selectedExerciseId = first.id;
    _setCount = first.defaultSets.clamp(_minSets, _maxSets);
    _uniformReps = first.defaultReps;
    _uniformWeight = _defaultWeight;
    _perSetValues = List.generate(
      _setCount,
      (_) => _SetConfig(reps: _uniformReps, weight: _uniformWeight),
    );
  }

  @override
  void dispose() {
    _restCtrl.dispose();
    super.dispose();
  }

  ExerciseModel get _selectedExercise =>
      mockExercises.firstWhere((e) => e.id == _selectedExerciseId);

  bool get _usesWeight => _selectedExercise.usesWeight;

  void _selectExercise(String id) {
    setState(() {
      _selectedExerciseId = id;
      _uniformReps = mockExercises.firstWhere((e) => e.id == id).defaultReps;
      if (!_perSetEnabled) {
        _perSetValues = List.generate(
          _setCount,
          (_) => _SetConfig(reps: _uniformReps, weight: _uniformWeight),
        );
      }
    });
  }

  void _changeSetCount(int delta) {
    setState(() {
      final next = (_setCount + delta).clamp(_minSets, _maxSets);
      if (next == _setCount) return;
      if (next > _setCount) {
        final seed = _perSetValues.isNotEmpty
            ? _perSetValues.last.copy()
            : _SetConfig(reps: _uniformReps, weight: _uniformWeight);
        _perSetValues.addAll(
          List.generate(next - _setCount, (_) => seed.copy()),
        );
      } else {
        _perSetValues.removeRange(next, _perSetValues.length);
      }
      _setCount = next;
    });
  }

  void _setToggle(bool value) {
    setState(() {
      _perSetEnabled = value;
      if (value) {
        // 토글을 직접 켠 경우 현재 공통 값으로 세트 리스트를 채워서 시작한다.
        _perSetValues = List.generate(
          _setCount,
          (_) => _SetConfig(reps: _uniformReps, weight: _uniformWeight),
        );
      } else {
        _mode = _SetMode.same;
        if (_perSetValues.isNotEmpty) {
          _uniformReps = _perSetValues.first.reps;
          _uniformWeight = _perSetValues.first.weight;
        }
      }
    });
  }

  void _selectMode(_SetMode mode) {
    setState(() {
      _mode = mode;
      if (mode == _SetMode.same) {
        if (_perSetValues.isNotEmpty) {
          _uniformReps = _perSetValues.first.reps;
          _uniformWeight = _perSetValues.first.weight;
        }
        _perSetValues = List.generate(
          _setCount,
          (_) => _SetConfig(reps: _uniformReps, weight: _uniformWeight),
        );
      } else {
        // 램프업/피라미드 선택 시 자동으로 "세트별로 다르게 설정"을 켠다.
        _perSetEnabled = true;
      }
    });
  }

  void _updateUniform({int? reps, int? weight}) {
    setState(() {
      if (reps != null) _uniformReps = reps.clamp(1, 999);
      if (weight != null) _uniformWeight = weight.clamp(0, 999);
    });
  }

  void _updatePerSet(int index, {int? reps, int? weight}) {
    setState(() {
      if (reps != null) _perSetValues[index].reps = reps.clamp(1, 999);
      if (weight != null) _perSetValues[index].weight = weight.clamp(0, 999);
    });
  }

  int get _totalVolume {
    if (!_perSetEnabled) {
      return _setCount * _uniformReps * _uniformWeight;
    }
    return _perSetValues.fold(0, (sum, s) => sum + s.reps * s.weight);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStringsProvider);
    final isKo = s.locale == 'ko';
    final ex = _selectedExercise;

    final repsForStart =
        _perSetEnabled ? _perSetValues.first.reps : _uniformReps;

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(isKo: isKo),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ExerciseGrid(
                        selectedId: _selectedExerciseId,
                        onSelect: _selectExercise,
                      ),
                      const SizedBox(height: 14),
                      _SetConfigCard(
                        isKo: isKo,
                        setCount: _setCount,
                        min: _minSets,
                        max: _maxSets,
                        onChangeSetCount: _changeSetCount,
                        perSetEnabled: _perSetEnabled,
                        onToggleChanged: _setToggle,
                      ),
                      const SizedBox(height: 16),
                      if (!_perSetEnabled) ...[
                        _UniformStepperCard(
                          isKo: isKo,
                          reps: _uniformReps,
                          weight: _uniformWeight,
                          usesWeight: _usesWeight,
                          onChanged: _updateUniform,
                        ),
                        const SizedBox(height: 16),
                        _UniformSummaryCard(
                          isKo: isKo,
                          reps: _uniformReps,
                          weight: _uniformWeight,
                          totalVolume: _totalVolume,
                          usesWeight: _usesWeight,
                        ),
                      ] else
                        _SetDetailsCard(
                          isKo: isKo,
                          mode: _mode,
                          totalVolume: _totalVolume,
                          perSetValues: _perSetValues,
                          usesWeight: _usesWeight,
                          onSelectMode: _selectMode,
                          onPerSetChanged: _updatePerSet,
                        ),
                      const SizedBox(height: 16),
                      _RestTimeCard(
                        isKo: isKo,
                        restSeconds: _restSeconds,
                        customRest: _customRest,
                        controller: _restCtrl,
                        onSelectPreset: (v) => setState(() {
                          _customRest = false;
                          _restSeconds = v;
                        }),
                        onSelectCustom: () => setState(() {
                          _customRest = true;
                          _restCtrl.text = '$_restSeconds';
                        }),
                        onCustomChanged: (v) => setState(() {
                          _restSeconds = int.tryParse(v) ?? _restSeconds;
                        }),
                      ),
                      const SizedBox(height: 20),
                      _StartButton(
                        isKo: isKo,
                        onStart: () => context.push(
                          RouteConstants.cameraGuide,
                          extra: {
                            'exerciseId': ex.id,
                            'targetReps': repsForStart,
                            'targetSets': _setCount,
                          },
                        ),
                      ),
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

// ── Header ───────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.isKo});
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Center(
        child: Text(
          isKo ? '오늘 뭐 할까?' : 'What shall we do today?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ── Exercise Grid ────────────────────────────────────────────────────────
class _ExerciseGrid extends StatelessWidget {
  const _ExerciseGrid({required this.selectedId, required this.onSelect});
  final String selectedId;
  final ValueChanged<String> onSelect;

  static const double _buttonHeight = 46;
  static const int _columns = 3;

  Widget _button(ExerciseModel ex) {
    final isSelected = ex.id == selectedId;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(ex.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _buttonHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.green : AppColors.grey,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            ex.nameKr,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected
                  ? AppColors.black
                  : Colors.white.withValues(alpha: 0.55),
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < mockExercises.length; i += _columns) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      final rowItems = <Widget>[];
      for (var c = 0; c < _columns; c++) {
        final idx = i + c;
        if (c > 0) rowItems.add(const SizedBox(width: 8));
        rowItems.add(
          idx < mockExercises.length
              ? _button(mockExercises[idx])
              : const Spacer(),
        );
      }
      rows.add(Row(children: rowItems));
    }
    return Column(children: rows);
  }
}

// ── Set Count + Per-set Toggle Card (한 카드에 합쳐서 표시) ────────────────
class _SetConfigCard extends StatelessWidget {
  const _SetConfigCard({
    required this.isKo,
    required this.setCount,
    required this.min,
    required this.max,
    required this.onChangeSetCount,
    required this.perSetEnabled,
    required this.onToggleChanged,
  });
  final bool isKo;
  final int setCount;
  final int min;
  final int max;
  final ValueChanged<int> onChangeSetCount;
  final bool perSetEnabled;
  final ValueChanged<bool> onToggleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isKo ? '세트 수' : 'Sets',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Row(
                  children: [
                    _RoundStepButton(
                      icon: Icons.remove,
                      filled: false,
                      onTap: setCount > min ? () => onChangeSetCount(-1) : null,
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        isKo ? '$setCount세트' : '$setCount sets',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _RoundStepButton(
                      icon: Icons.add,
                      filled: true,
                      onTap: setCount < max ? () => onChangeSetCount(1) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isKo ? '세트별로 다르게 설정' : 'Customize each set',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Transform.scale(
                  scale: 0.95,
                  child: Switch(
                    value: perSetEnabled,
                    onChanged: onToggleChanged,
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
        ],
      ),
    );
  }
}

class _RoundStepButton extends StatelessWidget {
  const _RoundStepButton({
    required this.icon,
    required this.filled,
    required this.onTap,
    this.size = 32,
  });
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !enabled
              ? Colors.white.withValues(alpha: 0.06)
              : (filled
                  ? AppColors.green
                  : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(
          icon,
          size: size * 0.56,
          color: !enabled
              ? Colors.white.withValues(alpha: 0.25)
              : (filled ? AppColors.black : Colors.white),
        ),
      ),
    );
  }
}

// ── Per-set Toggle Row ───────────────────────────────────────────────────
// ── Set Details Card (전세트동일 / 램프업 / 피라미드) ───────────────────
class _SetDetailsCard extends StatelessWidget {
  const _SetDetailsCard({
    required this.isKo,
    required this.mode,
    required this.totalVolume,
    required this.perSetValues,
    required this.usesWeight,
    required this.onSelectMode,
    required this.onPerSetChanged,
  });

  final bool isKo;
  final _SetMode mode;
  final int totalVolume;
  final List<_SetConfig> perSetValues;
  final bool usesWeight;
  final ValueChanged<_SetMode> onSelectMode;
  final void Function(int index, {int? reps, int? weight}) onPerSetChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                usesWeight
                    ? (isKo ? '세트별 반복·무게' : 'Reps & weight per set')
                    : (isKo ? '세트별 반복 횟수' : 'Reps per set'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (usesWeight)
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: isKo ? '총 볼륨 ' : 'Total ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '${totalVolume}kg',
                        style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ModePill(
                label: isKo ? '전 세트 동일' : 'Same',
                selected: mode == _SetMode.same,
                onTap: () => onSelectMode(_SetMode.same),
              ),
              const SizedBox(width: 8),
              _ModePill(
                label: isKo ? '램프업' : 'Ramp-up',
                selected: mode == _SetMode.rampUp,
                onTap: () => onSelectMode(_SetMode.rampUp),
              ),
              const SizedBox(width: 8),
              _ModePill(
                label: isKo ? '피라미드' : 'Pyramid',
                selected: mode == _SetMode.pyramid,
                onTap: () => onSelectMode(_SetMode.pyramid),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PerSetList(
            isKo: isKo,
            perSetValues: perSetValues,
            usesWeight: usesWeight,
            onPerSetChanged: onPerSetChanged,
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.purple
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Uniform reps/weight input (toggle off / 전세트동일) ──────────────────
class _UniformInputRow extends StatelessWidget {
  const _UniformInputRow({
    required this.isKo,
    required this.reps,
    required this.weight,
    required this.showWeight,
    required this.onChanged,
  });
  final bool isKo;
  final int reps;
  final int weight;
  final bool showWeight;
  final void Function({int? reps, int? weight}) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InlineStepperRow(
          label: isKo ? '반복 횟수' : 'Reps',
          value: reps,
          unit: isKo ? '회' : ' reps',
          step: 1,
          min: 1,
          onChanged: (v) => onChanged(reps: v),
        ),
        if (showWeight) ...[
          const SizedBox(height: 10),
          _InlineStepperRow(
            label: isKo ? '무게' : 'Weight',
            value: weight,
            unit: 'kg',
            step: 5,
            min: 0,
            onChanged: (v) => onChanged(weight: v),
          ),
        ],
      ],
    );
  }
}

// ── 토글 off 상태: 반복/무게 스테퍼만 있는 카드 ───────────────────────────
class _UniformStepperCard extends StatelessWidget {
  const _UniformStepperCard({
    required this.isKo,
    required this.reps,
    required this.weight,
    required this.usesWeight,
    required this.onChanged,
  });
  final bool isKo;
  final int reps;
  final int weight;
  final bool usesWeight;
  final void Function({int? reps, int? weight}) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _UniformInputRow(
        isKo: isKo,
        reps: reps,
        weight: weight,
        showWeight: usesWeight,
        onChanged: onChanged,
      ),
    );
  }
}

// ── 토글 off 상태: 전 세트 요약 카드 (총 볼륨 + 코리) ─────────────────────
class _UniformSummaryCard extends StatelessWidget {
  const _UniformSummaryCard({
    required this.isKo,
    required this.reps,
    required this.weight,
    required this.totalVolume,
    required this.usesWeight,
  });
  final bool isKo;
  final int reps;
  final int weight;
  final int totalVolume;
  final bool usesWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usesWeight
                      ? (isKo
                          ? '전 세트 $reps회 · ${weight}kg'
                          : 'All sets $reps reps · ${weight}kg')
                      : (isKo ? '전 세트 $reps회' : 'All sets $reps reps'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (usesWeight) ...[
                  const SizedBox(height: 4),
                  Text(
                    isKo
                        ? '총 볼륨 ${totalVolume}kg'
                        : 'Total volume ${totalVolume}kg',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Image.asset(
            'assets/images/character/face.png',
            width: 44,
            height: 44,
          ),
        ],
      ),
    );
  }
}

class _InlineStepperRow extends StatelessWidget {
  const _InlineStepperRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.step,
    required this.min,
    required this.onChanged,
  });
  final String label;
  final int value;
  final String unit;
  final int step;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          children: [
            _RoundStepButton(
              icon: Icons.remove,
              filled: false,
              onTap: value - step >= min ? () => onChanged(value - step) : null,
            ),
            const SizedBox(width: 10),
            _InlineNumberField(
              value: value,
              unit: unit,
              width: 36,
              textStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
              onChanged: onChanged,
            ),
            const SizedBox(width: 10),
            _RoundStepButton(
              icon: Icons.add,
              filled: true,
              onTap: () => onChanged(value + step),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Per-set 리스트 (행을 탭하면 그 자리에서 펼쳐지는 인라인 편집) ─────────
class _PerSetList extends StatefulWidget {
  const _PerSetList({
    required this.isKo,
    required this.perSetValues,
    required this.usesWeight,
    required this.onPerSetChanged,
  });
  final bool isKo;
  final List<_SetConfig> perSetValues;
  final bool usesWeight;
  final void Function(int index, {int? reps, int? weight}) onPerSetChanged;

  @override
  State<_PerSetList> createState() => _PerSetListState();
}

class _PerSetListState extends State<_PerSetList> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(widget.perSetValues.length, (i) {
        final expanded = _expandedIndex == i;
        return _PerSetRow(
          isKo: widget.isKo,
          index: i,
          config: widget.perSetValues[i],
          expanded: expanded,
          usesWeight: widget.usesWeight,
          onToggleExpand: () =>
              setState(() => _expandedIndex = expanded ? null : i),
          onChanged: (reps, weight) =>
              widget.onPerSetChanged(i, reps: reps, weight: weight),
        );
      }),
    );
  }
}

// ── Per-set 행: 접힌 요약 줄 + (펼쳤을 때만) -,+ 인라인 스테퍼 줄 ─────────
class _PerSetRow extends StatelessWidget {
  const _PerSetRow({
    required this.isKo,
    required this.index,
    required this.config,
    required this.expanded,
    required this.usesWeight,
    required this.onToggleExpand,
    required this.onChanged,
  });
  final bool isKo;
  final int index;
  final _SetConfig config;
  final bool expanded;
  final bool usesWeight;
  final VoidCallback onToggleExpand;
  final void Function(int? reps, int? weight) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggleExpand,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: expanded
                        ? AppColors.green
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: expanded
                          ? AppColors.black
                          : Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isKo ? '${config.reps}회' : '${config.reps} reps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (usesWeight)
                  Text(
                    '${config.weight}kg',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PerSetStepper(
                      value: config.reps,
                      unit: isKo ? '회' : '',
                      step: 1,
                      min: 1,
                      onChanged: (v) => onChanged(v, null),
                    ),
                  ),
                  if (usesWeight) ...[
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    Expanded(
                      child: _PerSetStepper(
                        value: config.weight,
                        unit: 'kg',
                        step: 5,
                        min: 0,
                        onChanged: (v) => onChanged(null, v),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── 펼친 세트 행 안의 작은 -,+ 인라인 스테퍼 ──────────────────────────────
class _PerSetStepper extends StatelessWidget {
  const _PerSetStepper({
    required this.value,
    required this.unit,
    required this.step,
    required this.min,
    required this.onChanged,
  });
  final int value;
  final String unit;
  final int step;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundStepButton(
          icon: Icons.remove,
          size: 22,
          filled: false,
          onTap: value - step >= min ? () => onChanged(value - step) : null,
        ),
        const SizedBox(width: 10),
        _InlineNumberField(
          value: value,
          unit: unit,
          width: 30,
          unitWidth: 20,
          textStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(width: 10),
        _RoundStepButton(
          icon: Icons.add,
          size: 22,
          filled: true,
          onTap: () => onChanged(value + step),
        ),
      ],
    );
  }
}

// ── 탭하면 그 자리에서 숫자 키보드로 바로 수정되는 인라인 숫자 입력 ───────
class _InlineNumberField extends StatefulWidget {
  const _InlineNumberField({
    required this.value,
    required this.unit,
    required this.textStyle,
    required this.onChanged,
    this.width = 34,
    this.unitWidth = 36,
  });
  final int value;
  final String unit;
  final TextStyle textStyle;
  final ValueChanged<int> onChanged;
  final double width;
  final double unitWidth;

  @override
  State<_InlineNumberField> createState() => _InlineNumberFieldState();
}

class _InlineNumberFieldState extends State<_InlineNumberField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _InlineNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _ctrl.text = '${widget.value}';
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
    } else {
      _commit();
    }
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text);
    if (parsed != null) {
      widget.onChanged(parsed);
    } else {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: widget.textStyle,
            onSubmitted: (_) => _focusNode.unfocus(),
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        if (widget.unit.isNotEmpty)
          SizedBox(
            width: widget.unitWidth,
            child: Text(widget.unit, style: widget.textStyle),
          ),
      ],
    );
  }
}

// ── Rest Time Card ───────────────────────────────────────────────────────
class _RestTimeCard extends StatelessWidget {
  const _RestTimeCard({
    required this.isKo,
    required this.restSeconds,
    required this.customRest,
    required this.controller,
    required this.onSelectPreset,
    required this.onSelectCustom,
    required this.onCustomChanged,
  });
  final bool isKo;
  final int restSeconds;
  final bool customRest;
  final TextEditingController controller;
  final ValueChanged<int> onSelectPreset;
  final VoidCallback onSelectCustom;
  final ValueChanged<String> onCustomChanged;

  static const _presets = [30, 60, 90];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.grey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isKo ? '쉬는 시간' : 'Rest time',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                isKo ? '$restSeconds초' : '${restSeconds}s',
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final p in _presets) ...[
                _ModePill(
                  label: isKo ? '$p초' : '${p}s',
                  selected: !customRest && restSeconds == p,
                  onTap: () => onSelectPreset(p),
                ),
                const SizedBox(width: 8),
              ],
              _ModePill(
                label: isKo ? '직접 입력' : 'Custom',
                selected: customRest,
                onTap: onSelectCustom,
              ),
            ],
          ),
          if (customRest) ...[
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              onChanged: onCustomChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                suffixText: isKo ? '초' : 's',
                suffixStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Start Button ─────────────────────────────────────────────────────────
class _StartButton extends StatelessWidget {
  const _StartButton({required this.isKo, required this.onStart});
  final bool isKo;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onStart,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded,
                color: AppColors.black, size: 20),
            const SizedBox(width: 6),
            Text(
              isKo ? '시작해볼까?' : 'Ready to start?',
              style: const TextStyle(
                color: AppColors.black,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
