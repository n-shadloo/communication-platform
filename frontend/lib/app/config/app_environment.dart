enum AppEnvironment {
  development,
  production;

  bool get isProduction => this == AppEnvironment.production;

  String get provisioningPrefix => switch (this) {
    AppEnvironment.development => 'DEVELOPMENT',
    AppEnvironment.production => 'PRODUCTION',
  };
}
