import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';

abstract base class DriftRepositoryBase {
  const DriftRepositoryBase(this.database);

  final LocalDatabase database;

  Future<Result<T>> runWrite<T>(Future<T> Function() operation) async {
    try {
      return Result.success(await database.writeTransaction(operation));
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }
}
