import 'package:flutter_contacts/flutter_contacts.dart';
import '../tool_base.dart';

/// Search contacts on the device by name or phone number.
class ContactsTool extends KoloTool {
  @override
  String get name => 'contacts';
  @override
  String get description => 'Search the device contacts by name or phone number. Returns matching contact details.';
  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Name or phone number to search for'},
      'limit': {'type': 'integer', 'description': 'Max results to return (default 10)'},
    },
    'required': ['query'],
  };
  @override
  ToolPermission get permission => ToolPermission.sensitive;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params, ToolContext context) async {
    final query = params['query'] as String;
    final limit = params['limit'] as int? ?? 10;

    try {
      // Request permission
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        return ToolResult.err('Contacts permission denied by user.');
      }

      // Search contacts by name or phone
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email},
        filter: ContactFilter.name(query),
        limit: limit,
      );

      final results = <String>[];
      for (final contact in contacts) {
        final name = (contact.displayName?.isNotEmpty == true) ? contact.displayName! : 'Unknown';
        final phones = contact.phones.map((p) => p.number).where((p) => p.isNotEmpty).join(', ');
        final emails = contact.emails.map((e) => e.address).where((e) => e.isNotEmpty).join(', ');
        results.add('$name: ${phones.isNotEmpty ? phones : "No phone"}${emails.isNotEmpty ? " | $emails" : ""}');
      }

      if (results.isEmpty) {
        return ToolResult.ok('No contacts found matching "$query"');
      }
      return ToolResult.ok('Found ${results.length} contact(s):\n${results.join("\n")}');
    } catch (e) {
      return ToolResult.err('Contacts search failed: $e. Ensure CONTACTS permission is granted.');
    }
  }
}