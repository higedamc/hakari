import 'dart:async';

import 'package:hive/hive.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/repositories/weight_repository.dart';

/// [WeightRepository] backed by a Hive box.
///
/// Entries are stored keyed by [WeightEntry.id] as the plain map produced
/// by [WeightEntry.toMap], so no Hive TypeAdapter is required.
///
/// Open the box once at startup (after `Hive.initFlutter()` /
/// `Hive.init(path)`) via [openBox] and inject it here.
class HiveWeightRepository implements WeightRepository {
  static const String boxName = 'weight_entries';

  final Box _box;

  HiveWeightRepository(this._box);

  /// Opens (or returns the already-open) box backing this repository.
  static Future<Box> openBox() async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      throw StorageFailure('Failed to open Hive box "$boxName"', e);
    }
  }

  List<WeightEntry> _readAllSorted() {
    final entries = _box.values
        .map((raw) => WeightEntry.fromMap(raw as Map))
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return entries;
  }

  @override
  Future<List<WeightEntry>> getAll() async {
    try {
      return _readAllSorted();
    } catch (e) {
      throw StorageFailure('Failed to read weight entries', e);
    }
  }

  @override
  Future<WeightEntry?> getById(String id) async {
    try {
      final raw = _box.get(id);
      if (raw == null) return null;
      return WeightEntry.fromMap(raw as Map);
    } catch (e) {
      throw StorageFailure('Failed to read weight entry "$id"', e);
    }
  }

  @override
  Future<void> upsert(WeightEntry entry) async {
    try {
      await _box.put(entry.id, entry.toMap());
    } catch (e) {
      throw StorageFailure('Failed to save weight entry "${entry.id}"', e);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _box.delete(id);
    } catch (e) {
      throw StorageFailure('Failed to delete weight entry "$id"', e);
    }
  }

  @override
  Future<List<WeightEntry>> getUnpublished() async {
    try {
      return _readAllSorted()
          .where((entry) => entry.nostrEventId == null)
          .toList();
    } catch (e) {
      throw StorageFailure('Failed to read unpublished weight entries', e);
    }
  }

  @override
  Stream<List<WeightEntry>> watchAll() {
    // A StreamController (not async*) so that cancelling the subscription
    // completes immediately instead of waiting for the next box event.
    late final StreamController<List<WeightEntry>> controller;
    StreamSubscription<BoxEvent>? boxSub;

    Future<void> emit() async {
      try {
        controller.add(await getAll());
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller = StreamController<List<WeightEntry>>(
      onListen: () {
        emit();
        boxSub = _box.watch().listen((_) => emit());
      },
      onCancel: () async {
        await boxSub?.cancel();
      },
    );
    return controller.stream;
  }
}
