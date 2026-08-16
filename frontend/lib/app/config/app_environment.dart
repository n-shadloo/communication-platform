enum AppEnvironment {
  development,
  beta,
  production;

  bool get isProduction => this == AppEnvironment.production;

  String get provisioningPrefix => switch (this) {
    AppEnvironment.development => 'DEVELOPMENT',
    AppEnvironment.beta => 'BETA',
    AppEnvironment.production => 'PRODUCTION',
  };
}
