import 'package:flutter/services.dart';
import '../tool_base.dart';

class ClipboardReadTool extends KoloTool {
  @override
  String get name => 'clipboard_read';
  @override
  String get description => 'Read the current text content from the device clipboard.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
    'required': [],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    try {
      final content = await Clipboard.getData(Clipboard.kTextPlain);
      if (content == null || content.text == null) {
        return ToolResult.err('Clipboard is empty');
      }
      return ToolResult.ok(content.text!);
    } catch (e) {
      return ToolResult.err('Failed to read clipboard: $e');
    }
  }
}

class ClipboardWriteTool extends KoloTool {
  @override
  String get name => 'clipboard_write';
  @override
  String get description => 'Copy text to the device clipboard.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': 'The text to copy to the clipboard'},
    },
    'required': ['text'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final text = params['text'] as String;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ToolResult.ok('Copied ${text.length} characters to clipboard');
    } catch (e) {
      return ToolResult.err('Failed to write to clipboard: $e');
    }
  }
}