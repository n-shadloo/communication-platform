/// Narrow core marker for an already authenticated group commit that must be
/// persisted in the same transaction as its pairwise receive state.
///
/// The synchronization domain deliberately knows no group-domain types. The
/// infrastructure composition layer validates the concrete implementation
/// before dispatching to the group repository.
abstract interface class GroupSyncReceiveCommit {
  String get opaqueEventId;

  String get senderUserId;

  String get senderDeviceId;
}
