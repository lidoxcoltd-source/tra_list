import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:tra_list/invoice/invoice_share_service.dart';
import 'package:tra_list/theme/app_theme.dart';

Future<void> showDocumentShareSheet({
  required BuildContext context,
  required String businessUid,
  required String documentId,
  required Map<String, dynamic> document,
  String? existingToken,
  String? suggestedName,
  String? suggestedPhone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DocumentShareSheet(
      businessUid: businessUid,
      documentId: documentId,
      document: document,
      existingToken: existingToken,
      suggestedName: suggestedName,
      suggestedPhone: suggestedPhone,
    ),
  );
}

class _DocumentShareSheet extends StatefulWidget {
  const _DocumentShareSheet({
    required this.businessUid,
    required this.documentId,
    required this.document,
    this.existingToken,
    this.suggestedName,
    this.suggestedPhone,
  });

  final String businessUid;
  final String documentId;
  final Map<String, dynamic> document;
  final String? existingToken;
  final String? suggestedName;
  final String? suggestedPhone;

  @override
  State<_DocumentShareSheet> createState() => _DocumentShareSheetState();
}

class _DocumentShareSheetState extends State<_DocumentShareSheet> {
  late final _phoneController = TextEditingController(
    text: widget.suggestedPhone ?? '',
  );
  late final _nameController = TextEditingController(
    text: widget.suggestedName ?? '',
  );
  bool _busy = false;
  String? _readyUrl;
  String? _readyToken;

  bool get _contactsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    if (!_contactsSupported) {
      _showMessage(
        'Contacts are available on Android and iPhone. Enter the number manually.',
      );
      return;
    }

    try {
      final permission = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (permission != PermissionStatus.granted &&
          permission != PermissionStatus.limited) {
        _showMessage(
          permission == PermissionStatus.permanentlyDenied
              ? 'Allow contacts access in your device settings to choose a contact.'
              : 'Contacts permission was not granted. You can enter the number manually.',
        );
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final selected = await showDialog<Contact>(
        context: context,
        builder: (_) => _ContactsPickerDialog(contacts: contacts),
      );
      if (selected == null || selected.phones.isEmpty) return;
      setState(() {
        _nameController.text = selected.displayName?.trim().isNotEmpty == true
            ? selected.displayName!.trim()
            : selected.name?.first ?? '';
        _phoneController.text = selected.phones.first.number;
      });
    } on PlatformException catch (error) {
      _showMessage('Could not access contacts: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Could not load contacts: $error');
    }
  }

  Future<void> _share() async {
    final phone = _phoneController.text.trim();
    try {
      InvoiceShareService.normalizeWhatsAppNumber(phone);
    } on FormatException catch (error) {
      _showMessage(error.message);
      return;
    }

    setState(() => _busy = true);
    try {
      final kind = (widget.document['kind']?.toString() ?? 'invoice');
      final invoice = widget.document['invoice'] as Map? ?? const {};
      final client = widget.document['client'] as Map? ?? const {};
      final token =
          widget.existingToken ??
          _readyToken ??
          (await InvoiceShareService.createLink(
            businessUid: widget.businessUid,
            documentId: widget.documentId,
            data: widget.document,
          )).token;
      final url = InvoiceShareService.createPublicUrl(token);
      if (mounted) {
        setState(() {
          _readyToken = token;
          _readyUrl = url;
        });
      }
      final opened = await InvoiceShareService.openWhatsApp(
        businessUid: widget.businessUid,
        documentId: widget.documentId,
        token: token,
        module: kind == 'quotation' ? 'quotations' : 'invoices',
        kind: kind,
        documentNumber: (invoice['number'] ?? '').toString(),
        clientName: (client['name'] ?? '').toString(),
        total: (widget.document['total'] as num?) ?? 0,
        recipientName: _nameController.text,
        recipientPhone: phone,
      );
      if (!mounted) return;
      _showMessage(
        opened
            ? 'WhatsApp opened with the invoice link. Review the message and tap Send.'
            : 'Could not open WhatsApp. Your link is ready below; copy it to share manually.',
      );
    } catch (error) {
      if (mounted) _showMessage('Could not prepare the document link: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    final url = _readyUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _showMessage('Customer link copied.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final kind = widget.document['kind']?.toString() ?? 'invoice';
    final invoice = widget.document['invoice'] as Map? ?? const {};
    final documentNumber = (invoice['number'] ?? '').toString();

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        decoration: const BoxDecoration(
          color: MjasiColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MjasiColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F0),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.chat_rounded,
                    color: Color(0xFF168A62),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.existingToken == null
                            ? 'Send ${_label(kind)}'
                            : 'Send ${_label(kind)} again',
                        style: const TextStyle(
                          color: MjasiColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Document ${documentNumber.isEmpty ? '' : '#$documentNumber'}',
                        style: const TextStyle(
                          color: MjasiColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (_contactsSupported) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickContact,
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Choose from contacts'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer name (optional)',
                prefixIcon: Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp number',
                hintText: '+255 712 345 678',
                prefixIcon: Icon(Icons.phone_rounded),
                helperText: 'Include the country code, e.g. +255.',
                border: OutlineInputBorder(),
              ),
            ),
            if (_readyUrl case final url?) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MjasiColors.lightBlue,
                  borderRadius: BorderRadius.circular(MjasiRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      color: MjasiColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        url,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      onPressed: _copyLink,
                      tooltip: 'Copy link',
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _share,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168A62),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MjasiRadius.md),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _busy ? 'Preparing secure link…' : 'Continue to WhatsApp',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'WhatsApp will open with a message ready. Review it and tap Send; the app cannot send messages without your confirmation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MjasiColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(String kind) => switch (kind) {
    'quotation' => 'quotation',
    'proforma' => 'proforma',
    'delivery' => 'delivery note',
    'advance_payment' || 'advance' => 'advance payment',
    'reminder' => 'payment reminder',
    'payment_details' => 'payment details',
    _ => 'invoice',
  };
}

class _ContactsPickerDialog extends StatefulWidget {
  const _ContactsPickerDialog({required this.contacts});

  final List<Contact> contacts;

  @override
  State<_ContactsPickerDialog> createState() => _ContactsPickerDialogState();
}

class _ContactsPickerDialogState extends State<_ContactsPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts =
        widget.contacts
            .where(
              (contact) =>
                  contact.phones.isNotEmpty &&
                  (contact.displayName ?? contact.name?.first ?? '')
                      .toLowerCase()
                      .contains(_query),
            )
            .toList()
          ..sort(
            (a, b) => (a.displayName ?? a.name?.first ?? '').compareTo(
              b.displayName ?? b.name?.first ?? '',
            ),
          );

    return AlertDialog(
      title: const Text('Choose a contact'),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search contacts',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(
                      child: Text('No contacts with phone numbers found.'),
                    )
                  : ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: MjasiColors.lightBlue,
                            child: Text(
                              (contact.displayName ??
                                      contact.name?.first ??
                                      '?')
                                  .characters
                                  .first
                                  .toUpperCase(),
                            ),
                          ),
                          title: Text(
                            contact.displayName ??
                                contact.name?.first ??
                                'Unnamed contact',
                          ),
                          subtitle: Text(contact.phones.first.number),
                          onTap: () => Navigator.pop(context, contact),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
