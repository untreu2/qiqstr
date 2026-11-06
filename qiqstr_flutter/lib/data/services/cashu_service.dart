import 'dart:convert';

import '../../core/base/result.dart';
import '../../src/rust/api/cashu.dart' as rust_cashu;

class CashuTokenInfo {
  final String mintUrl;
  final int amountSats;

  const CashuTokenInfo({required this.mintUrl, required this.amountSats});
}

class CashuMintBalance {
  final String mintUrl;
  final int sats;

  const CashuMintBalance({required this.mintUrl, required this.sats});
}

class CashuBalance {
  final int totalSats;
  final List<CashuMintBalance> mints;

  const CashuBalance({required this.totalSats, required this.mints});
}

class CashuService {
  const CashuService();

  Result<CashuTokenInfo> decodeToken(String token) {
    try {
      final jsonStr = rust_cashu.cashuDecodeToken(token: token.trim());
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Result.success(CashuTokenInfo(
        mintUrl: map['mint_url'] as String,
        amountSats: (map['amount_sats'] as num).toInt(),
      ));
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<int>> receiveAndMelt({
    required String token,
    required String lightningTarget,
  }) async {
    try {
      final jsonStr = await rust_cashu.cashuReceiveAndMelt(
        token: token.trim(),
        lightningTarget: lightningTarget.trim(),
      );
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final amountSats = (map['amount_sats'] as num).toInt();
      return Result.success(amountSats);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<int>> meltAll({required String lightningTarget}) async {
    try {
      final jsonStr = await rust_cashu.cashuMeltAll(
        lightningTarget: lightningTarget.trim(),
      );
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final totalSats = (map['total_sats'] as num).toInt();
      return Result.success(totalSats);
    } catch (e) {
      return Result.error(e.toString());
    }
  }

  Future<Result<CashuBalance>> getBalance() async {
    try {
      final jsonStr = await rust_cashu.cashuGetBalance();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final totalSats = (map['total_sats'] as num).toInt();
      final mintsRaw = (map['mints'] as List<dynamic>);
      final mints = mintsRaw
          .map((m) => CashuMintBalance(
                mintUrl: m['mint_url'] as String,
                sats: (m['sats'] as num).toInt(),
              ))
          .toList();
      return Result.success(CashuBalance(totalSats: totalSats, mints: mints));
    } catch (e) {
      return Result.error(e.toString());
    }
  }
}
