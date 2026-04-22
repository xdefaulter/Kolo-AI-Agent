import 'dart:math';
import '../tool_base.dart';

class CalculatorTool extends KoloTool {
  @override
  String get name => 'calculator';

  @override
  String get description => 'Evaluate a mathematical expression. Supports +, -, *, /, %, parentheses, sin, cos, sqrt, abs, pow, log, pi, e.';

  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': 'The mathematical expression to evaluate (e.g., "2 + 3 * 4", "sqrt(144)", "pow(2, 10)")',
          },
        },
        'required': ['expression'],
      };

  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final expression = params['expression'] as String;
    try {
      final result = _evaluate(expression);
      return ToolResult.ok(
        '$expression = $result',
        metadata: {'expression': expression, 'result': result},
      );
    } catch (e) {
      return ToolResult.err('Failed to evaluate: $e');
    }
  }

  double _evaluate(String expr) {
    final parser = _ExprParser(expr.replaceAll(' ', ''));
    final result = parser.parseExpr();
    return result;
  }
}

class _ExprParser {
  final String s;
  int i = 0;

  _ExprParser(this.s);

  double parseExpr() {
    double result = parseTerm();
    while (i < s.length) {
      if (s[i] == '+') {
        i++;
        result += parseTerm();
      } else if (s[i] == '-') {
        i++;
        result -= parseTerm();
      } else {
        break;
      }
    }
    return result;
  }

  double parseTerm() {
    double result = parseFactor();
    while (i < s.length) {
      if (s[i] == '*') {
        i++;
        result *= parseFactor();
      } else if (s[i] == '/') {
        i++;
        result /= parseFactor();
      } else if (s[i] == '%') {
        i++;
        result %= parseFactor();
      } else {
        break;
      }
    }
    return result;
  }

  double parseFactor() {
    if (i < s.length && s[i] == '-') {
      i++;
      return -parseFactor();
    }
    if (i < s.length && s[i] == '+') {
      i++;
      return parseFactor();
    }
    if (i < s.length && s[i] == '(') {
      i++; // skip (
      double result = parseExpr();
      if (i < s.length && s[i] == ')') {
        i++; // skip )
      }
      return result;
    }

    // Check for function names
    for (final func in _functions) {
      if (s.substring(i).startsWith(func.name) &&
          i + func.name.length < s.length &&
          s[i + func.name.length] == '(') {
        i += func.name.length;
        i++; // skip (
        final args = <double>[];
        args.add(parseExpr());
        while (i < s.length && s[i] == ',') {
          i++;
          args.add(parseExpr());
        }
        if (i < s.length && s[i] == ')') {
          i++;
        }
        return func.fn(args);
      }
    }

    // Handle named constants
    if (s.substring(i).startsWith('pi')) {
      i += 2;
      return pi;
    }
    if (s.substring(i).startsWith('e') && (i + 1 >= s.length || !s[i + 1].contains(RegExp(r'[a-z]')))) {
      i += 1;
      return e;
    }

    return _parseNumber();
  }

  double _parseNumber() {
    final start = i;
    while (i < s.length && (s[i] == '.' || _isDigit(s[i]))) {
      i++;
    }
    if (start == i) {
      throw FormatException('Expected number at position $i');
    }
    return double.parse(s.substring(start, i));
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  static final _functions = <_MathFunc>[
    _MathFunc('sqrt', (args) => args.isEmpty ? 0 : sqrt(args[0])),
    _MathFunc('abs', (args) => args.isEmpty ? 0 : args[0].abs()),
    _MathFunc('pow', (args) => args.length < 2 ? 0 : pow(args[0], args[1]).toDouble()),
    _MathFunc('log', (args) => args.isEmpty ? 0 : log(args[0])),
    _MathFunc('sin', (args) => args.isEmpty ? 0 : sin(args[0])),
    _MathFunc('cos', (args) => args.isEmpty ? 0 : cos(args[0])),
    _MathFunc('tan', (args) => args.isEmpty ? 0 : tan(args[0])),
    _MathFunc('round', (args) => args.isEmpty ? 0 : args[0].roundToDouble()),
    _MathFunc('floor', (args) => args.isEmpty ? 0 : args[0].floorToDouble()),
    _MathFunc('ceil', (args) => args.isEmpty ? 0 : args[0].ceilToDouble()),
  ];
}

class _MathFunc {
  final String name;
  final double Function(List<double>) fn;
  const _MathFunc(this.name, this.fn);
}