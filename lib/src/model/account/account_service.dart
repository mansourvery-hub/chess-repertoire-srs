import 'dart:async';

import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider for [AccountService].
final accountServiceProvider = Provider<AccountService>((Ref ref) {
  final service = AccountService(ref);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
}, name: 'AccountServiceProvider');

class AccountService {
  AccountService(this._ref);

  final Ref _ref;

  /// Stream of bookmark changes for the current user.
  final StreamController<(GameId, bool)> _bookmarkChangesController = StreamController.broadcast();

  /// Stream of bookmark changes for the current user.
  Stream<(GameId, bool)> get bookmarkChanges => _bookmarkChangesController.stream;

  void start() {}

  void dispose() {
    _bookmarkChangesController.close();
  }

  Future<void> setGameBookmark(GameId id, {required bool bookmark}) async {
    final authUser = _ref.read(authControllerProvider);
    if (authUser == null) return;

    await _ref.read(accountRepositoryProvider).bookmark(id, bookmark: bookmark);

    _bookmarkChangesController.add((id, bookmark));
  }
}
