import 'dart:io';
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../tool_base.dart';

/// Generate a QR code image from text/data and return the saved file path.
class QrCodeTool extends KoloTool {
  @override
  String get name => 'qr_code';
  @override
  String get description => 'Generate a QR code image from text or a URL. Returns the saved file path.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'data': {'type': 'string', 'description': 'Text or URL to encode into a QR code'},
      'size': {'type': 'integer', 'description': 'Image size in pixels (default 512)'},
    },
    'required': ['data'],
  };
  @override
  ToolPermission get permission => ToolPermission.safe;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final data = params['data'] as String;
    final size = params['size'] as int? ?? 512;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/qr_${DateTime.now().millisecondsSinceEpoch}.png';

      final qrPainter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
      );

      final picRecorder = PictureRecorder();
      final canvas = Canvas(picRecorder);
      qrPainter.paint(canvas, Size(size.toDouble(), size.toDouble()));
      final picture = picRecorder.endRecording();
      final image = await picture.toImage(size, size);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) return ToolResult.err('Failed to generate QR code image');

      final file = File(filePath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      return ToolResult.ok('QR code saved to: $filePath\nData: ${data.length > 100 ? "${data.substring(0, 100)}..." : data}', metadata: {
        'path': filePath,
        'data_length': data.length,
        'size': size,
      });
    } catch (e) {
      return ToolResult.err('QR code generation failed: $e');
    }
  }
}