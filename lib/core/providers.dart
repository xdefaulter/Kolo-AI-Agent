import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Shared provider for the active chat ID
final activeChatIdProvider = StateProvider<String>((ref) => const Uuid().v4());