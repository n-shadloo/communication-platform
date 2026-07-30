import 'package:communication_platform/features/messaging/application/conversation_use_cases.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';

final class PendingReceiptPostInboxWork implements PostInboxCommitWorkPort {
  const PendingReceiptPostInboxWork(this.flush);

  final FlushPendingDeliveredReceipts flush;

  @override
  Future<void> run() async {
    await flush();
  }
}
