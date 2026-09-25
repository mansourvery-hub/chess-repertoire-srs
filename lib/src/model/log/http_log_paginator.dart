import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'http_log_paginator.freezed.dart';

/// The number of HTTP logs to fetch per page.
const _pageSize = 20;

/// A provider for [HttpLogPaginator].
///
/// The family argument is the optional search query string.
final httpLogPaginatorProvider = AsyncNotifierProvider.autoDispose
    .family<HttpLogPaginator, HttpLogState, String?>(
      HttpLogPaginator.new,
      name: 'HttpLogPaginatorProvider',
    );

/// A Riverpod controller for managing HTTP logs.
/// The `HttpLogController` class is responsible for fetching and managing
/// paginated HTTP log entries from the storage. It uses a throttler to limit
/// the rate of fetching new pages.
class HttpLogPaginator extends AsyncNotifier<HttpLogState> {
  HttpLogPaginator(this._searchQuery);

  final String? _searchQuery;

  /// Set while a page is being fetched.
  ///
  /// Two scroll notifications can arrive before the first has updated the state. Both then read
  /// the same cursor, fetch the same page, and append it — so the list showed every row of that
  /// page twice and the following page was skipped.
  bool _isFetchingPage = false;

  @override
  Future<HttpLogState> build() async {
    final storage = await ref.read(httpLogStorageProvider.future);
    return HttpLogState(
      data: IList.new([
        await AsyncValue.guard(() => storage.page(limit: _pageSize, searchQuery: _searchQuery)),
      ]),
    );
  }

  /// Fetches the next page of HTTP logs.
  ///
  /// Ignored while a page is already in flight; the next scroll once that one lands will fetch
  /// it. It updates the state with the new page of HTTP logs.
  Future<void> next() async {
    if (_isFetchingPage) return;
    if (!state.hasValue || !state.requireValue.hasMore) return;

    _isFetchingPage = true;
    try {
      final storage = await ref.read(httpLogStorageProvider.future);
      final asyncPage = await AsyncValue.guard(
        () => storage.page(
          limit: _pageSize,
          cursor: state.requireValue.nextPage,
          searchQuery: _searchQuery,
        ),
      );
      // The paginator can be disposed while the read is out — a refresh, or the search query
      // changing. Writing state afterwards throws.
      if (!ref.mounted) return;
      state = AsyncValue.data(
        state.requireValue.copyWith(data: state.requireValue.data.add(asyncPage)),
      );
    } finally {
      _isFetchingPage = false;
    }
  }

  /// Deletes all HTTP logs from the storage.
  ///
  /// This method reads the `httpLogStorageProvider` to get the storage instance
  /// and then deletes all the logs from the storage. After deletion, it updates
  /// the state with an empty list of HTTP logs.
  ///
  /// Returns a [Future] that completes when the deletion is done.
  Future<void> deleteAll() async {
    final storage = await ref.read(httpLogStorageProvider.future);
    await storage.deleteAll();
    ref.invalidateSelf();
  }

  /// Refreshes the HTTP logs by fetching the first page again.
  ///
  /// This method updates the state with the first page of HTTP logs.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@freezed
sealed class HttpLogState with _$HttpLogState {
  const HttpLogState._();

  const factory HttpLogState({required IList<AsyncValue<HttpLog>> data}) = _HttpLogState;

  bool get initialized => data.isNotEmpty;
  List<HttpLogEntry> get logs => data.expand((e) => e.value?.items ?? <HttpLogEntry>[]).toList();
  int? get nextPage => data.lastOrNull?.value?.next;
  bool get hasMore => initialized && nextPage != null;
  bool get isLoading => data.lastOrNull?.isLoading == true;
  bool get isDeleteButtonVisible => logs.isNotEmpty;
}
