import 'dart:convert';
import 'dart:io';

Future<bool> verifyNip05(String nip05, String expectedPubkey) async {
  try {
    final parts = nip05.split('@');
    if (parts.length != 2) return false;
    final localPart = parts[0].toLowerCase();
    final domain = parts[1];
    final url = 'https://$domain/.well-known/nostr.json?name=$localPart';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return false;
    final responseBody = await response.transform(utf8.decoder).join();
    final jsonResponse = jsonDecode(responseBody);
    final returnedPubKey = jsonResponse['names']?[localPart];
    return returnedPubKey?.toLowerCase() == expectedPubkey.toLowerCase();
  } catch (e) {
    print('NIP-05 verification failed for $nip05: $e');
    return false;
  }
}
