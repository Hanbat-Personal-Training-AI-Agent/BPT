import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.calendar)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              size: 48,
              color: AppColors.darkTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              s.calendarComingSoon,
              style: const TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
