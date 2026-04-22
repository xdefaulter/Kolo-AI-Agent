import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../tool_base.dart';

class FlutterTaskTool extends KoloTool {
  @override
  String get name => 'run_flutter_task';
  @override
  String get description =>
      'Run a Flutter development task (analyze, test, build) and return structured results. '
      'Parses compiler/analyzer output into a structured error list.';
  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'task': {
            'type': 'string',
            'enum': ['analyze', 'test', 'build_apk', 'build_ios', 'pub_get'],
            'description': 'The Flutter task to run.',
          },
          'project_path': {
            'type': 'string',
            'description': 'Path to the Flutter project directory.',
          },
          'extra_args': {
            'type': 'string',
            'description':
                'Extra arguments to pass to the flutter command (e.g. "--fatal-warnings").',
          },
        },
        'required': ['task', 'project_path'],
      };
  @override
  ToolPermission get permission => ToolPermission.dangerous;
  @override
  ToolPlatform get platform => ToolPlatform.android;

  @override
  Future<ToolResult> execute(
      Map<String, dynamic> params, ToolContext context) async {
    if (Platform.isIOS) {
      return ToolResult.err(
          'Flutter tasks are not available on iOS due to sandbox restrictions.');
    }

    final task = params['task'] as String;
    final projectPath = params['project_path'] as String;
    final extraArgs = params['extra_args'] as String?;

    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      return ToolResult.err('Project directory not found: $projectPath');
    }

    final command = _buildCommand(task, extraArgs);

    try {
      final result = await Process.run(
        '/bin/sh',
        ['-c', command],
        workingDirectory: projectPath,
      ).timeout(const Duration(minutes: 5));

      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      final exitCode = result.exitCode;

      if (task == 'analyze') {
        return _parseAnalyzeOutput(stdout, stderr, exitCode);
      }
      if (task == 'test') {
        return _parseTestOutput(stdout, stderr, exitCode);
      }

      // Generic output for build/pub_get
      final output = StringBuffer();
      if (stdout.isNotEmpty) output.writeln(stdout);
      if (stderr.isNotEmpty) output.writeln(stderr);
      return ToolResult.ok(
        output.toString().trim().isEmpty
            ? '(no output, exit $exitCode)'
            : output.toString().trim(),
        metadata: {
          'exitCode': exitCode,
          'task': task,
          'category': 'build',
        },
      );
    } on TimeoutException {
      return ToolResult.err('Flutter $task timed out after 5 minutes.');
    } catch (e) {
      return ToolResult.err('Failed to run flutter $task: $e');
    }
  }

  String _buildCommand(String task, String? extraArgs) {
    final args = extraArgs ?? '';
    switch (task) {
      case 'analyze':
        return 'flutter analyze $args';
      case 'test':
        return 'flutter test $args';
      case 'build_apk':
        return 'flutter build apk $args';
      case 'build_ios':
        return 'flutter build ios $args';
      case 'pub_get':
        return 'flutter pub get $args';
      default:
        return 'flutter $task $args';
    }
  }

  ToolResult _parseAnalyzeOutput(
      String stdout, String stderr, int exitCode) {
    final allOutput = '$stdout\n$stderr';
    final issues = <Map<String, dynamic>>[];

    // Parse lines like: "   info • Unused import • lib/foo.dart:3:8 • unused_import"
    // Or: "lib/foo.dart:3:8: error: message"
    final dartAnalyzerPattern =
        RegExp(r'^\s*(info|warning|error)\s+[•-]\s+(.+?)\s+[•-]\s+(.+?):(\d+):(\d+)\s+[•-]\s+(.+)$', multiLine: true);
    final simplePattern =
        RegExp(r'^(.+?):(\d+):(\d+):\s+(error|warning|info):\s+(.+)$', multiLine: true);

    for (final match in dartAnalyzerPattern.allMatches(allOutput)) {
      issues.add({
        'severity': match.group(1),
        'message': match.group(2)!.trim(),
        'file': match.group(3),
        'line': int.parse(match.group(4)!),
        'column': int.parse(match.group(5)!),
        'rule': match.group(6)!.trim(),
      });
    }

    if (issues.isEmpty) {
      for (final match in simplePattern.allMatches(allOutput)) {
        issues.add({
          'severity': match.group(4),
          'message': match.group(5)!.trim(),
          'file': match.group(1),
          'line': int.parse(match.group(2)!),
          'column': int.parse(match.group(3)!),
        });
      }
    }

    final errors = issues.where((i) => i['severity'] == 'error').length;
    final warnings = issues.where((i) => i['severity'] == 'warning').length;
    final infos = issues.where((i) => i['severity'] == 'info').length;

    final summary =
        'Analyze: $errors errors, $warnings warnings, $infos infos (exit $exitCode)';

    if (issues.isEmpty && exitCode == 0) {
      return ToolResult.ok('No issues found!', metadata: {
        'exitCode': 0,
        'task': 'analyze',
        'category': 'build',
        'errors': 0,
        'warnings': 0,
      });
    }

    final structured = jsonEncode({'summary': summary, 'issues': issues});
    return ToolResult.ok(structured, metadata: {
      'exitCode': exitCode,
      'task': 'analyze',
      'category': 'build',
      'errors': errors,
      'warnings': warnings,
    });
  }

  ToolResult _parseTestOutput(String stdout, String stderr, int exitCode) {
    final allOutput = '$stdout\n$stderr';

    // Count test results
    final passedMatch = RegExp(r'(\d+) tests? passed').firstMatch(allOutput);
    final failedMatch = RegExp(r'(\d+) tests? failed').firstMatch(allOutput);
    final allTestsMatch =
        RegExp(r'All (\d+) tests? passed').firstMatch(allOutput);

    final passed =
        allTestsMatch != null ? int.parse(allTestsMatch.group(1)!) : (passedMatch != null ? int.parse(passedMatch.group(1)!) : 0);
    final failed =
        failedMatch != null ? int.parse(failedMatch.group(1)!) : 0;

    final output = StringBuffer();
    output.writeln('Tests: $passed passed, $failed failed (exit $exitCode)');
    if (exitCode != 0) {
      // Include last 50 lines of output for failures
      final lines = allOutput.split('\n');
      final tail = lines.length > 50 ? lines.sublist(lines.length - 50) : lines;
      output.writeln(tail.join('\n'));
    }

    return ToolResult.ok(output.toString().trim(), metadata: {
      'exitCode': exitCode,
      'task': 'test',
      'category': 'build',
      'passed': passed,
      'failed': failed,
    });
  }
}
