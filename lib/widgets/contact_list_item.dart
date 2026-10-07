import 'package:decimal/decimal.dart';
import 'package:finance_tracker/domain/entities/contact.dart';
import 'package:finance_tracker/utils/app_formatters.dart';
import 'package:flutter/material.dart';

class ContactListItem extends StatelessWidget {
  final Contact contact;
  final VoidCallback? onTap;

  const ContactListItem({
    super.key,
    required this.contact,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isReceivable = contact.getCurrentBalance([]) >= Decimal.zero;
    final balance = contact.getCurrentBalance([]);
    final String balanceText =
        '${isReceivable ? '+' : '-'}\$${balance.abs().toStringAsFixed(2)}';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isReceivable ? Colors.green.shade100 : Colors.red.shade100,
          child: Text(
            contact.name.isNotEmpty ? contact.name[0] : '?',
            style: TextStyle(
              color: isReceivable ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          contact.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.mobile != null && contact.mobile!.isNotEmpty)
              Text('Mobile: ${contact.mobile}'),
            if (contact.email != null && contact.email!.isNotEmpty)
              Text('Email: ${contact.email}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              balanceText,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isReceivable ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              contact.openingBalanceType == 'receivable'
                  ? 'Receivable'
                  : 'Payable',
              style: TextStyle(
                fontSize: 12,
                color: contact.openingBalanceType == 'receivable'
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}