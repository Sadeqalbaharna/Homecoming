import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum KaiCashImportDirection { income, expense }

class KaiCashImportCandidate {
  const KaiCashImportCandidate({
    required this.date,
    required this.description,
    required this.amount,
    required this.direction,
    required this.source,
    this.category = 'Uncategorised',
    this.subcategory = '',
    this.selected = true,
    this.importIdentity = '',
  });

  final String date;
  final String description;
  final double amount;
  final KaiCashImportDirection direction;
  final String source;
  final String category;
  final String subcategory;
  final bool selected;
  final String importIdentity;

  String get month => date.length >= 7 ? date.substring(0, 7) : '';

  String get fingerprint {
    final canonical = [
      date.trim(),
      description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      amount.toStringAsFixed(3),
      direction.name,
      source.trim().toLowerCase(),
      importIdentity.trim().toLowerCase(),
    ].join('\u001f');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  KaiCashImportCandidate copyWith({
    String? date,
    String? description,
    double? amount,
    KaiCashImportDirection? direction,
    String? source,
    String? category,
    String? subcategory,
    bool? selected,
    String? importIdentity,
  }) =>
      KaiCashImportCandidate(
        date: date ?? this.date,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        source: source ?? this.source,
        category: category ?? this.category,
        subcategory: subcategory ?? this.subcategory,
        selected: selected ?? this.selected,
        importIdentity: importIdentity ?? this.importIdentity,
      );
}

class KaiCashStatementParser {
  const KaiCashStatementParser._();

  static String extractPdfText(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  }

  static List<KaiCashImportCandidate> parse(
    String text, {
    required String source,
  }) {
    final cleaned = text.replaceFirst('\ufeff', '').trim();
    if (cleaned.isEmpty) return const [];
    final lines = const LineSplitter()
        .convert(cleaned)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return const [];

    final csv = _parseDelimited(lines, source: source);
    if (csv.isNotEmpty) return _dedupe(csv);
    final columnOrderedRows =
        _parseColumnOrderedAccountRows(lines, source: source);
    if (columnOrderedRows.isNotEmpty) return _dedupe(columnOrderedRows);
    final namedMonthRows = _parseNamedMonthAccountRows(lines, source: source);
    if (namedMonthRows.isNotEmpty) return _dedupe(namedMonthRows);
    return _dedupe(_parseStatementLines(lines, source: source));
  }

  static List<KaiCashImportCandidate> _parseColumnOrderedAccountRows(
    List<String> lines, {
    required String source,
  }) {
    final datePattern = RegExp(
      r'^\d{1,2}\s+[A-Z]{3}\s+\d{4}$',
      caseSensitive: false,
    );
    final referencePattern = RegExp(
      r'^[A-Z0-9][A-Z0-9-]{7,}$',
      caseSensitive: false,
    );
    final amountPattern = RegExp(
      r'^\(([+-])\)\s+([\d,]+(?:\.\d{1,3})?)$',
    );
    final out = <KaiCashImportCandidate>[];
    for (var index = 2; index < lines.length; index++) {
      if (!referencePattern.hasMatch(lines[index]) ||
          !datePattern.hasMatch(lines[index - 1]) ||
          !datePattern.hasMatch(lines[index - 2])) {
        continue;
      }
      final date = _normaliseNamedDate(lines[index - 2]);
      if (date == null) continue;
      RegExpMatch? amountMatch;
      var amountIndex = -1;
      for (var cursor = index + 1;
          cursor < lines.length && cursor <= index + 40;
          cursor++) {
        final candidate = amountPattern.firstMatch(lines[cursor]);
        if (candidate != null) {
          amountMatch = candidate;
          amountIndex = cursor;
          break;
        }
        if (cursor > index + 1 &&
            referencePattern.hasMatch(lines[cursor]) &&
            datePattern.hasMatch(lines[cursor - 1])) {
          break;
        }
      }
      if (amountMatch == null || amountIndex < 0) continue;
      final amount = double.tryParse(amountMatch.group(2)!.replaceAll(',', ''));
      if (amount == null || amount <= 0) continue;
      final details = lines
          .sublist(index + 1, amountIndex)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      out.add(KaiCashImportCandidate(
        date: date,
        description: details.isEmpty ? lines[index] : details,
        amount: amount,
        direction: amountMatch.group(1) == '+'
            ? KaiCashImportDirection.income
            : KaiCashImportDirection.expense,
        source: source,
        importIdentity: lines[index],
      ));
      index = amountIndex;
    }
    return out;
  }

  static List<KaiCashImportCandidate> _parseNamedMonthAccountRows(
    List<String> lines, {
    required String source,
  }) {
    final header = RegExp(
      r'^(\d{1,2})\s+([A-Z]{3})\s+(\d{4})\s+(\S+)\s+\d{1,2}\s+[A-Z]{3}\s+\d{4}\s+\(([+-])\)\s+([\d,]+(?:\.\d{1,3})?)\s+[\d,]+(?:\.\d{1,3})?$',
      caseSensitive: false,
    );
    final pageBoundary = RegExp(
      r'^(?:Page\s+\d+\s+of\s+\d+|Statement of Account|From:|To:|SWIFT Code|IBAN\b|Account Number\b|Account Currency\b|Account Description\b|Posting Date\b|Opening Balance\b|This is a Computer Generated Statement|confirmed by you\b|Al Salam Bank\b)',
      caseSensitive: false,
    );
    const months = <String, int>{
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12,
    };
    final out = <KaiCashImportCandidate>[];
    RegExpMatch? active;
    var narrative = <String>[];
    var collectingNarrative = false;

    void flush() {
      final match = active;
      if (match == null) return;
      final month = months[match.group(2)!.toUpperCase()];
      final day = int.tryParse(match.group(1)!);
      final year = int.tryParse(match.group(3)!);
      final amount = double.tryParse(match.group(6)!.replaceAll(',', ''));
      if (month != null && day != null && year != null && amount != null) {
        final date = _normaliseDate(
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        );
        if (date != null && amount > 0) {
          final reference = match.group(4)!.trim();
          final details =
              narrative.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
          out.add(KaiCashImportCandidate(
            date: date,
            description: details.isEmpty ? reference : details,
            amount: amount,
            direction: match.group(5) == '+'
                ? KaiCashImportDirection.income
                : KaiCashImportDirection.expense,
            source: source,
            importIdentity: reference,
          ));
        }
      }
      active = null;
      narrative = <String>[];
    }

    for (final line in lines) {
      final match = header.firstMatch(line);
      if (match != null) {
        flush();
        active = match;
        collectingNarrative = true;
        continue;
      }
      if (pageBoundary.hasMatch(line)) {
        collectingNarrative = false;
        continue;
      }
      if (active != null && collectingNarrative) narrative.add(line);
    }
    flush();
    return out;
  }

  static List<KaiCashImportCandidate> _parseDelimited(
    List<String> lines, {
    required String source,
  }) {
    final delimiter = _delimiterFor(lines.first);
    if (delimiter == null) return const [];
    final header = _splitDelimited(lines.first, delimiter)
        .map(_normaliseHeader)
        .toList(growable: false);
    final dateIndex = _firstHeader(header, const ['date', 'transactiondate']);
    final descriptionIndex = _firstHeader(header,
        const ['description', 'details', 'memo', 'narrative', 'merchant']);
    final amountIndex =
        _firstHeader(header, const ['amount', 'transactionamount']);
    final debitIndex =
        _firstHeader(header, const ['debit', 'withdrawal', 'spent']);
    final creditIndex =
        _firstHeader(header, const ['credit', 'deposit', 'received']);
    final categoryIndex = _firstHeader(header, const ['category']);
    if (dateIndex < 0 ||
        descriptionIndex < 0 ||
        (amountIndex < 0 && debitIndex < 0 && creditIndex < 0)) {
      return const [];
    }

    final out = <KaiCashImportCandidate>[];
    for (final line in lines.skip(1)) {
      final cells = _splitDelimited(line, delimiter);
      String cell(int index) =>
          index >= 0 && index < cells.length ? cells[index].trim() : '';
      final date = _normaliseDate(cell(dateIndex));
      final description = cell(descriptionIndex);
      if (date == null || description.isEmpty) continue;

      double signed = 0;
      if (amountIndex >= 0) {
        signed = _signedAmount(cell(amountIndex)) ?? 0;
      } else {
        final credit = _unsignedAmount(cell(creditIndex));
        final debit = _unsignedAmount(cell(debitIndex));
        signed = credit > 0 ? credit : -debit;
      }
      if (signed == 0) continue;
      out.add(KaiCashImportCandidate(
        date: date,
        description: description,
        amount: signed.abs(),
        direction: signed > 0
            ? KaiCashImportDirection.income
            : KaiCashImportDirection.expense,
        source: source,
        category:
            cell(categoryIndex).isEmpty ? 'Uncategorised' : cell(categoryIndex),
      ));
    }
    return out;
  }

  static List<KaiCashImportCandidate> _parseStatementLines(
    List<String> lines, {
    required String source,
  }) {
    final out = <KaiCashImportCandidate>[];
    final row = RegExp(
      r'^(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s+(.+?)\s+((?:BHD|BD)?\s*\(?[-+]?\d[\d,]*(?:\.\d{1,3})?\)?\s*(?:CR|DR)?)$',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = row.firstMatch(line);
      if (match == null) continue;
      final date = _normaliseDate(match.group(1)!);
      final description = match.group(2)!.trim();
      final signed = _signedAmount(match.group(3)!, unsignedIsExpense: true);
      if (date == null ||
          description.isEmpty ||
          signed == null ||
          signed == 0) {
        continue;
      }
      out.add(KaiCashImportCandidate(
        date: date,
        description: description,
        amount: signed.abs(),
        direction: signed > 0
            ? KaiCashImportDirection.income
            : KaiCashImportDirection.expense,
        source: source,
      ));
    }
    return out;
  }

  static List<KaiCashImportCandidate> _dedupe(
      List<KaiCashImportCandidate> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value.fingerprint)) value
    ];
  }

  static String? _delimiterFor(String header) {
    final lower = _normaliseHeader(header);
    if (!lower.contains('date')) return null;
    final candidates = <String, int>{
      ',': ','.allMatches(header).length,
      ';': ';'.allMatches(header).length,
      '\t': '\t'.allMatches(header).length,
    };
    final best =
        candidates.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 0 ? best.key : null;
  }

  static List<String> _splitDelimited(String line, String delimiter) {
    final cells = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char == delimiter) {
        cells.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    cells.add(current.toString());
    return cells;
  }

  static int _firstHeader(List<String> header, List<String> names) {
    for (final name in names) {
      final index = header.indexOf(name);
      if (index >= 0) return index;
    }
    return -1;
  }

  static String _normaliseHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static double _unsignedAmount(String value) =>
      (_signedAmount(value) ?? 0).abs();

  static double? _signedAmount(
    String value, {
    bool unsignedIsExpense = false,
  }) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final upper = raw.toUpperCase();
    final negative =
        raw.contains('(') || upper.endsWith('DR') || raw.startsWith('-');
    final positive = upper.endsWith('CR') || raw.startsWith('+');
    final cleaned = raw
        .replaceAll(RegExp(r'BHD|BD|CR|DR', caseSensitive: false), '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[()\s+]'), '')
        .trim();
    final parsed = double.tryParse(cleaned);
    if (parsed == null) return null;
    if (negative) return -parsed.abs();
    if (positive) return parsed.abs();
    // A single signed amount column follows the common bank-export convention:
    // positive is money in, negative is money out. Unsigned statement lines are
    // expenses unless explicitly marked CR/credit.
    return unsignedIsExpense ? -parsed.abs() : parsed;
  }

  static String? _normaliseDate(String value) {
    final parts = value.trim().split(RegExp(r'[-/]'));
    if (parts.length != 3) return null;
    int? year;
    int? month;
    int? day;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    var c = int.tryParse(parts[2]);
    if (a == null || b == null || c == null) return null;
    if (parts[0].length == 4) {
      year = a;
      month = b;
      day = c;
    } else {
      day = a;
      month = b;
      year = c < 100 ? 2000 + c : c;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime.tryParse(
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}');
    if (parsed == null || parsed.day != day || parsed.month != month) {
      return null;
    }
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  static String? _normaliseNamedDate(String value) {
    final match = RegExp(
      r'^(\d{1,2})\s+([A-Z]{3})\s+(\d{4})$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    const months = <String, int>{
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12,
    };
    final month = months[match.group(2)!.toUpperCase()];
    if (month == null) return null;
    return _normaliseDate(
      '${match.group(3)}-${month.toString().padLeft(2, '0')}-${match.group(1)!.padLeft(2, '0')}',
    );
  }
}
