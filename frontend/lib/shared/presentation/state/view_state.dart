import 'package:communication_platform/core/result/failure.dart';

/// Immutable state exposed by presentation providers.
///
/// Durable content is projected from repositories; this type is not a database.
sealed class ViewState<T> {
  const ViewState();

  const factory ViewState.idle() = IdleViewState<T>;
  const factory ViewState.loading() = LoadingViewState<T>;
  const factory ViewState.data(T value) = DataViewState<T>;
  const factory ViewState.failure(Failure failure) = FailureViewState<T>;
}

final class IdleViewState<T> extends ViewState<T> {
  const IdleViewState();
}

final class LoadingViewState<T> extends ViewState<T> {
  const LoadingViewState();
}

final class DataViewState<T> extends ViewState<T> {
  const DataViewState(this.value);

  final T value;
}

final class FailureViewState<T> extends ViewState<T> {
  const FailureViewState(this.failure);

  final Failure failure;
}
