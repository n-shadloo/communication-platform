enum AppEnvironment {
  development,
  production;

  bool get isProduction => this == AppEnvironment.production;
}
