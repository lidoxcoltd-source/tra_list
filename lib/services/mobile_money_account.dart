class MobileMoneyNetwork {
  const MobileMoneyNetwork({required this.name, required this.colorValue});

  final String name;
  final int colorValue;

  static const supported = [
    MobileMoneyNetwork(name: 'M-Pesa', colorValue: 0xFFCF202E),
    MobileMoneyNetwork(name: 'Tigo Pesa / Mixx by Yas', colorValue: 0xFF139DD8),
    MobileMoneyNetwork(name: 'Airtel Money', colorValue: 0xFFEF3038),
    MobileMoneyNetwork(name: 'HaloPesa', colorValue: 0xFF61A82B),
  ];

  static String? canonicalName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'm-pesa':
      case 'mpesa':
      case 'vodacom m-pesa':
        return supported[0].name;
      case 'tigo':
      case 'tigo pesa':
      case 'mixx by yas':
      case 'tigo pesa / mixx by yas':
      case 'mixx by yas (tigo pesa)':
        return supported[1].name;
      case 'airtel':
      case 'airtel money':
        return supported[2].name;
      case 'halo':
      case 'halopesa':
      case 'halo pesa':
        return supported[3].name;
      default:
        return null;
    }
  }

  static int colorFor(String network) {
    final canonical = canonicalName(network);
    for (final provider in supported) {
      if (provider.name == canonical) return provider.colorValue;
    }
    return 0xFF718096;
  }
}

class MobileMoneyAccount {
  const MobileMoneyAccount({
    required this.network,
    required this.payeeName,
    required this.payNumber,
    required this.qrData,
  });

  final String network;
  final String payeeName;
  final String payNumber;
  final String qrData;

  int get networkColorValue => MobileMoneyNetwork.colorFor(network);

  static MobileMoneyAccount? fromMap(Map<String, dynamic> data) {
    final storedNetwork = data['network']?.toString().trim() ?? '';
    final network =
        MobileMoneyNetwork.canonicalName(storedNetwork) ?? storedNetwork;
    final payeeName = data['payeeName']?.toString().trim() ?? '';
    final payNumber = data['payNumber']?.toString().trim() ?? '';
    final qrData = data['qrData']?.toString() ?? '';
    if (network.isEmpty ||
        payeeName.isEmpty ||
        payNumber.isEmpty ||
        qrData.trim().isEmpty) {
      return null;
    }
    return MobileMoneyAccount(
      network: network,
      payeeName: payeeName,
      payNumber: payNumber,
      qrData: qrData,
    );
  }

  static List<MobileMoneyAccount> fromList(dynamic value) {
    if (value is! List) return const [];
    final accounts = <MobileMoneyAccount>[];
    for (final item in value) {
      if (item is! Map) continue;
      final account = MobileMoneyAccount.fromMap(
        Map<String, dynamic>.from(item),
      );
      if (account != null) accounts.add(account);
    }
    return accounts;
  }

  Map<String, String> toMap() => {
    'network': network,
    'payeeName': payeeName,
    'payNumber': payNumber,
    'qrData': qrData,
  };
}
