enum AppEnvironment {
  development,
  beta,
  production;

  // There is deliberately no `isProduction`. It existed to drive a two-way
  // branch on the application title, which is how the Private Experimental
  // build came to call itself "(Development)" in the task switcher. Anything
  // user-facing switches over all three values, so adding a fourth build can
  // never inherit another build's wording by default (ADR-045).

  String get provisioningPrefix => switch (this) {
    AppEnvironment.development => 'DEVELOPMENT',
    AppEnvironment.beta => 'BETA',
    AppEnvironment.production => 'PRODUCTION',
  };
}
