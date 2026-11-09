import 'package:tra_list/business_intelligence/business_context.dart';

enum ChatPeriodKind { none, resolved, needsSelection, comparison }

class ChatPeriodResult {
  const ChatPeriodResult(this.kind, {this.period, this.suggested});
  final ChatPeriodKind kind;
  final ReportingPeriod? period;
  final DateTime? suggested;
}

bool isTransactionCommand(String text) => RegExp(
  r'^\s*(record|rekodi|sajili|hifadhi|andika)\s+(?:ya\s+)?(matumizi|mapato|expense|income)\b',
  caseSensitive: false,
).hasMatch(text);

ChatPeriodResult resolveChatPeriod(String text, DateTime now) {
  final input = text.toLowerCase();
  if (isTransactionCommand(input)) {
    return const ChatPeriodResult(ChatPeriodKind.none);
  }
  final today = DateTime(now.year, now.month, now.day);
  ReportingPeriod day(DateTime date) =>
      ReportingPeriod(date, DateTime(date.year, date.month, date.day + 1));
  const needsSelection = ChatPeriodResult(ChatPeriodKind.needsSelection);
  if (RegExp(
    r'\b(compare|comparison|linganisha|versus|vs)\b',
  ).hasMatch(input)) {
    return const ChatPeriodResult(ChatPeriodKind.comparison);
  }
  final relativeDates = RegExp(
    r'\b(leo|today|jana|yesterday|mwezi huu|this month|mwezi uliopita|last month|previous month)\b',
  ).allMatches(input).length;
  if (relativeDates > 1) {
    return const ChatPeriodResult(ChatPeriodKind.comparison);
  }
  if (RegExp(
        r'\b\d{4}-\d{1,2}-\d{1,2}\b|\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b',
      ).allMatches(input).length >
      1) {
    return const ChatPeriodResult(ChatPeriodKind.comparison);
  }
  if (RegExp(r'\b(hadi|mpaka|between|through|until)\b').hasMatch(input)) {
    return needsSelection;
  }
  if (RegExp(r'\b(leo|today)\b').hasMatch(input)) {
    return ChatPeriodResult(ChatPeriodKind.resolved, period: day(today));
  }
  if (RegExp(r'\b(jana|yesterday)\b').hasMatch(input)) {
    return ChatPeriodResult(
      ChatPeriodKind.resolved,
      period: day(DateTime(now.year, now.month, now.day - 1)),
    );
  }
  if (RegExp(r'\b(mwezi huu|this month)\b').hasMatch(input)) {
    return ChatPeriodResult(
      ChatPeriodKind.resolved,
      period: ReportingPeriod.fromKey('month', now),
    );
  }
  if (RegExp(
    r'\b(mwezi uliopita|last month|previous month)\b',
  ).hasMatch(input)) {
    return ChatPeriodResult(
      ChatPeriodKind.resolved,
      period: ReportingPeriod.fromKey('previous', now),
    );
  }
  final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(input);
  final numeric = RegExp(
    r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b',
  ).firstMatch(input);
  const months = {
    'januari': 1,
    'january': 1,
    'februari': 2,
    'february': 2,
    'machi': 3,
    'march': 3,
    'aprili': 4,
    'april': 4,
    'mei': 5,
    'may': 5,
    'juni': 6,
    'june': 6,
    'julai': 7,
    'july': 7,
    'agosti': 8,
    'august': 8,
    'septemba': 9,
    'september': 9,
    'oktoba': 10,
    'october': 10,
    'novemba': 11,
    'november': 11,
    'desemba': 12,
    'december': 12,
  };
  final named = RegExp(
    r'\b(\d{1,2})\s+(?:mwezi\s+wa\s+)?(januari|january|februari|february|machi|march|aprili|april|mei|may|juni|june|julai|july|agosti|august|septemba|september|oktoba|october|novemba|november|desemba|december)\s+(\d{4})\b',
  ).firstMatch(input);
  int? year, month, dayOfMonth;
  if (iso != null) {
    year = int.parse(iso[1]!);
    month = int.parse(iso[2]!);
    dayOfMonth = int.parse(iso[3]!);
  } else if (numeric != null) {
    dayOfMonth = int.parse(numeric[1]!);
    month = int.parse(numeric[2]!);
    year = int.parse(numeric[3]!);
  } else if (named != null) {
    dayOfMonth = int.parse(named[1]!);
    month = months[named[2]!];
    year = int.parse(named[3]!);
  }
  if (year != null && month != null && dayOfMonth != null) {
    final date = DateTime(year, month, dayOfMonth);
    if (date.year != year ||
        date.month != month ||
        date.day != dayOfMonth ||
        date.isAfter(today) ||
        year < 1970) {
      return needsSelection;
    }
    return ChatPeriodResult(ChatPeriodKind.resolved, period: day(date));
  }
  final partial = RegExp(
    r'\b(?:tarehe|tarhe|date|dated)\s*(\d{1,2})\b',
  ).firstMatch(input);
  if (partial != null) {
    final number = int.parse(partial[1]!);
    final suggestion = DateTime(now.year, now.month, number);
    return ChatPeriodResult(
      ChatPeriodKind.needsSelection,
      suggested:
          number >= 1 &&
              number <= 31 &&
              suggestion.month == now.month &&
              !suggestion.isAfter(today)
          ? suggestion
          : today,
    );
  }
  final explicitDateWords = input.replaceAll(
    RegExp(
      r'\b(siku hiyo|siku ile|that day|the same day|same period|kipindi hicho)\b',
    ),
    '',
  );
  if (RegExp(
        r'\b(tarehe|tarhe|date|dates|siku|day|days|wiki|week|weeks|mwezi|month|months|mwaka|year|years|juzi|kesho|tomorrow)\b',
      ).hasMatch(explicitDateWords) ||
      RegExp(r'\b\d{1,4}[/-]\d{1,2}\b').hasMatch(input) ||
      months.keys.any((name) => RegExp('\\b$name\\b').hasMatch(input))) {
    return needsSelection;
  }
  return const ChatPeriodResult(ChatPeriodKind.none);
}
