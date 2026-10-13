import 'package:flutter/material.dart';

/// When a child profile may use the remote. Days use [DateTime.weekday]
/// (1 = Monday); a window whose end is before its start runs past midnight.
class ViewingSchedule {
  const ViewingSchedule({
    required this.days,
    required this.start,
    required this.end,
  });

  final Set<int> days;
  final TimeOfDay start;
  final TimeOfDay end;

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool allows(DateTime now) {
    final minute = now.hour * 60 + now.minute;
    final s = _minutes(start);
    final e = _minutes(end);
    if (s == e) return days.contains(now.weekday);
    if (s < e) return days.contains(now.weekday) && minute >= s && minute < e;
    // Overnight: the late part belongs to today, the early part to the
    // window that started yesterday.
    if (minute >= s) return days.contains(now.weekday);
    final yesterday = now.weekday == 1 ? 7 : now.weekday - 1;
    return minute < e && days.contains(yesterday);
  }

  Map<String, Object?> toJson() => {
    'days': days.toList()..sort(),
    'start': _minutes(start),
    'end': _minutes(end),
  };

  static ViewingSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    TimeOfDay time(Object? v) {
      final m = (v is int ? v : 0).clamp(0, 24 * 60 - 1);
      return TimeOfDay(hour: m ~/ 60, minute: m % 60);
    }

    return ViewingSchedule(
      days: {
        for (final d in (json['days'] as List? ?? const []))
          if (d is int && d >= 1 && d <= 7) d,
      },
      start: time(json['start']),
      end: time(json['end']),
    );
  }
}

/// A household member's remote. Restrictions apply only inside this app:
/// the TV's own remote and other apps are unaffected.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.child = false,
    this.simplified = false,
    this.allowedApps,
    this.maxVolume,
    this.schedule,
  });

  static const everyoneId = 'everyone';
  static const everyone = Profile(id: everyoneId, name: 'Everyone');

  final String id;
  final String name;

  /// Locked behind the household PIN: leaving the profile, settings, macros
  /// and themes need the PIN.
  final bool child;

  /// Shows only the everyday buttons.
  final bool simplified;

  /// App names allowed on the Apps tab; null allows all.
  final Set<String>? allowedApps;
  final int? maxVolume;

  /// Null means any time.
  final ViewingSchedule? schedule;

  static String normalizeApp(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');

  bool allowsApp(String appName) =>
      allowedApps == null ||
      allowedApps!.any((a) => normalizeApp(a) == normalizeApp(appName));

  bool allowsNow(DateTime now) => schedule?.allows(now) ?? true;

  Profile copyWith({
    String? name,
    bool? child,
    bool? simplified,
    Set<String>? Function()? allowedApps,
    int? Function()? maxVolume,
    ViewingSchedule? Function()? schedule,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    child: child ?? this.child,
    simplified: simplified ?? this.simplified,
    allowedApps: allowedApps == null ? this.allowedApps : allowedApps(),
    maxVolume: maxVolume == null ? this.maxVolume : maxVolume(),
    schedule: schedule == null ? this.schedule : schedule(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'child': child,
    'simplified': simplified,
    if (allowedApps != null) 'allowed_apps': allowedApps!.toList()..sort(),
    if (maxVolume != null) 'max_volume': maxVolume,
    if (schedule != null) 'schedule': schedule!.toJson(),
  };

  static Profile fromJson(Map<String, Object?> json) => Profile(
    id: json['id']! as String,
    name: (json['name'] as String?) ?? 'Profile',
    child: json['child'] == true,
    simplified: json['simplified'] == true,
    allowedApps: json['allowed_apps'] is List
        ? {
            for (final a in json['allowed_apps']! as List)
              if (a is String) a,
          }
        : null,
    maxVolume: (json['max_volume'] as num?)?.round().clamp(1, 100),
    schedule: ViewingSchedule.fromJson(json['schedule']),
  );
}
