// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_turso_suppression.dart';

const _tracerName = 'dartastic_otel_libs_turso';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

/// Pair returned from `tracedTursoQuery` callback.
class TursoQueryResult<T> {
  /// Creates a result.
  const TursoQueryResult({
    required this.value,
    this.rowsAffected,
    this.lastInsertRowId,
  });

  /// The value returned to the caller.
  final T value;
  final int? rowsAffected;
  final int? lastInsertRowId;
}

const _maxStatementLength = 1024;
String _truncate(String s) =>
    s.length <= _maxStatementLength ? s : s.substring(0, _maxStatementLength);

/// Wraps a Turso / libSQL query in a CLIENT span. db.system is
/// `sqlite` (libSQL is a SQLite fork with HTTP/WS replication).
Future<T> tracedTursoQuery<T>({
  required String statement,
  required Future<TursoQueryResult<T>> Function() invoke,
  String? databaseUrl,
  String? operation,
  String? collection,
  bool? replica,
}) async {
  if (tursoInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final op = operation ?? _operationFromStatement(statement);
  final m = <String, Object>{
    'db.system': 'sqlite',
    'db.statement': _truncate(statement),
    'turso.driver': 'libsql',
    if (op != null) 'db.operation': op,
    if (collection != null) 'db.collection.name': collection,
  };
  if (databaseUrl != null) m['turso.database.url'] = databaseUrl;
  if (replica != null) m['turso.replica'] = replica;

  final spanName =
      collection == null ? (op ?? 'query') : '${op ?? 'query'} $collection';
  final span = _tracer().startSpan(
    spanName,
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    final extras = <Attribute<Object>>[];
    if (r.rowsAffected != null) {
      extras.add(OTelAPI.attributeInt('db.rows_affected', r.rowsAffected!));
    }
    if (r.lastInsertRowId != null) {
      extras.add(OTelAPI.attributeInt(
        'turso.last_insert_rowid',
        r.lastInsertRowId!,
      ));
    }
    if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

String? _operationFromStatement(String statement) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first.toUpperCase();
  const known = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'BEGIN',
    'COMMIT',
    'ROLLBACK',
    'CREATE',
    'ALTER',
    'DROP',
    'REPLACE',
    'PRAGMA',
  };
  return known.contains(first) ? first : null;
}
