import 'package:bolt11_decoder/bolt11_decoder.dart';
import 'package:bech32/bech32.dart';

class LightningInvoiceParser {
  static int? getSatoshiAmount(String invoice) {
    try {
      print('Parsing invoice: $invoice');
      final decoded = Bech32Codec().decode(invoice, invoice.length);
      print('Bech32 decoded: $decoded');

      final humanReadablePart = decoded.hrp;
      print('Human Readable Part: $humanReadablePart');

      final amountPart = humanReadablePart.replaceFirst(RegExp(r'^lnbc'), '');
      print('Amount Part: $amountPart');

      if (amountPart.isEmpty) {
        print('Amount part is empty.');
        return null;
      }

      final regex = RegExp(r'^(\d+)([munp]?)$');
      final match = regex.firstMatch(amountPart);

      if (match == null) {
        print('No match found for amount and unit.');
        return null;
      }

      final amountStr = match.group(1);
      final unit = match.group(2) ?? '';

      print('Parsed Amount String: $amountStr');
      print('Parsed Unit: $unit');

      if (amountStr == null) {
        print('Amount string is null.');
        return null;
      }

      final amount = int.tryParse(amountStr);
      if (amount == null) {
        print('Failed to parse amount string to int.');
        return null;
      }

      int? satoshiAmount;
      switch (unit) {
        case 'm':
          satoshiAmount = amount * 100000;
          break;
        case 'u':
          satoshiAmount = amount * 100;
          break;
        case 'n':
          satoshiAmount = (amount * 0.1).toInt();
          break;
        case 'p':
          satoshiAmount = (amount * 0.0001).toInt();
          break;
        default:
          satoshiAmount = amount * 100000000;
      }

      print('Satoshi Amount: $satoshiAmount');
      return satoshiAmount;
    } catch (e) {
      print('Error parsing invoice amount: $e');
      return null;
    }
  }

  static String? getMemo(String invoice) {
    try {
      print('Parsing memo from invoice: $invoice');

      var req = Bolt11PaymentRequest(invoice);
      var description =
          req.tags.firstWhere((tag) => tag.type == 'description').data;

      print('Extracted Memo: $description');
      return description;
    } catch (e) {
      print('Error parsing memo: $e');
      return null;
    }
  }
}
