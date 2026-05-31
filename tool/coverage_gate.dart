import 'dart:io';

const _defaultCoveragePath = 'coverage/lcov.info';
const _defaultMinLineCoverage = 14.3;
const _defaultTopMissed = 10;

void main(List<String> args) {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final coverageFile = File(options.coveragePath);
  if (!coverageFile.existsSync()) {
    stderr.writeln(
      'Coverage file not found: ${options.coveragePath}\n'
      'Run: flutter test --coverage --no-pub',
    );
    exitCode = 2;
    return;
  }

  final report = _LcovReport.parse(coverageFile.readAsLinesSync());
  if (report.totalLines == 0) {
    stderr.writeln(
      'No line coverage records found in ${options.coveragePath}.',
    );
    exitCode = 2;
    return;
  }

  final coverage = report.lineCoveragePercent;
  stdout.writeln(
    'Line coverage: ${coverage.toStringAsFixed(2)}% '
    '(${report.hitLines}/${report.totalLines})',
  );

  if (options.topMissed > 0) {
    final missedFiles =
        report.files.where((file) => file.missedLines > 0).toList()
          ..sort((a, b) => b.missedLines.compareTo(a.missedLines));

    if (missedFiles.isNotEmpty) {
      stdout.writeln('\nMost uncovered files:');
      for (final file in missedFiles.take(options.topMissed)) {
        stdout.writeln(
          '${file.missedLines.toString().padLeft(5)} missed  '
          '${file.lineCoveragePercent.toStringAsFixed(2).padLeft(6)}%  '
          '${file.path}',
        );
      }
    }
  }

  if (coverage < options.minLineCoverage) {
    stderr.writeln(
      '\nCoverage gate failed: '
      '${coverage.toStringAsFixed(2)}% < '
      '${options.minLineCoverage.toStringAsFixed(2)}%',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    '\nCoverage gate passed: '
    '${coverage.toStringAsFixed(2)}% >= '
    '${options.minLineCoverage.toStringAsFixed(2)}%',
  );
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart tool/coverage_gate.dart [coverage/lcov.info] [--min-line=14.3] [--top-missed=10]

Examples:
  flutter test --coverage --no-pub
  dart tool/coverage_gate.dart --min-line=14.3
''');
}

class _Options {
  const _Options({
    required this.coveragePath,
    required this.minLineCoverage,
    required this.topMissed,
    required this.showHelp,
  });

  final String coveragePath;
  final double minLineCoverage;
  final int topMissed;
  final bool showHelp;

  static _Options parse(List<String> args) {
    var coveragePath = _defaultCoveragePath;
    var minLineCoverage = _defaultMinLineCoverage;
    var topMissed = _defaultTopMissed;
    var showHelp = false;

    for (final arg in args) {
      if (arg == '--help' || arg == '-h') {
        showHelp = true;
      } else if (arg.startsWith('--min-line=')) {
        minLineCoverage = _parseDouble(
          arg.substring('--min-line='.length),
          '--min-line',
        );
      } else if (arg.startsWith('--top-missed=')) {
        topMissed = _parseInt(
          arg.substring('--top-missed='.length),
          '--top-missed',
        );
      } else if (arg.startsWith('--')) {
        stderr.writeln('Unknown option: $arg');
        exit(64);
      } else {
        coveragePath = arg;
      }
    }

    return _Options(
      coveragePath: coveragePath,
      minLineCoverage: minLineCoverage,
      topMissed: topMissed,
      showHelp: showHelp,
    );
  }

  static double _parseDouble(String value, String optionName) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0 || parsed > 100) {
      stderr.writeln('$optionName must be a number from 0 to 100.');
      exit(64);
    }
    return parsed;
  }

  static int _parseInt(String value, String optionName) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      stderr.writeln('$optionName must be a non-negative integer.');
      exit(64);
    }
    return parsed;
  }
}

class _LcovReport {
  const _LcovReport(this.files);

  final List<_FileCoverage> files;

  int get hitLines => files.fold(0, (sum, file) => sum + file.hitLines);
  int get totalLines => files.fold(0, (sum, file) => sum + file.totalLines);
  double get lineCoveragePercent => hitLines * 100 / totalLines;

  static _LcovReport parse(List<String> lines) {
    final files = <_FileCoverage>[];
    String? currentPath;
    var hitLines = 0;
    var totalLines = 0;

    void finishCurrentFile() {
      final path = currentPath;
      if (path == null) {
        return;
      }
      files.add(
        _FileCoverage(path: path, hitLines: hitLines, totalLines: totalLines),
      );
      currentPath = null;
      hitLines = 0;
      totalLines = 0;
    }

    for (final line in lines) {
      if (line.startsWith('SF:')) {
        finishCurrentFile();
        currentPath = line.substring(3);
      } else if (line.startsWith('DA:') && currentPath != null) {
        final commaIndex = line.indexOf(',');
        if (commaIndex == -1) {
          continue;
        }
        final hitCount = int.tryParse(line.substring(commaIndex + 1));
        if (hitCount == null) {
          continue;
        }
        totalLines += 1;
        if (hitCount > 0) {
          hitLines += 1;
        }
      } else if (line == 'end_of_record') {
        finishCurrentFile();
      }
    }

    finishCurrentFile();
    return _LcovReport(files);
  }
}

class _FileCoverage {
  const _FileCoverage({
    required this.path,
    required this.hitLines,
    required this.totalLines,
  });

  final String path;
  final int hitLines;
  final int totalLines;

  int get missedLines => totalLines - hitLines;
  double get lineCoveragePercent =>
      totalLines == 0 ? 100 : hitLines * 100 / totalLines;
}
