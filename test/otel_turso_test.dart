// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_turso/otel_turso.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_turso-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SELECT records CLIENT span', () async {
    await tracedTursoQuery<String>(
      statement: 'SELECT * FROM logs',
      databaseUrl: 'libsql://my-db.turso.io',
      collection: 'logs',
      replica: true,
      invoke: () async => const TursoQueryResult(value: 'rows'),
    );
    final span = spans.findSpanByName('SELECT logs');
    expect(span, isNotNull);
    expect(span!.kind, SpanKind.client);
    final a = attrsOf(span);
    expect(a['db.system'], 'sqlite');
    expect(a['db.operation'], 'SELECT');
    expect(a['db.collection.name'], 'logs');
    expect(a['turso.driver'], 'libsql');
    expect(a['turso.database.url'], 'libsql://my-db.turso.io');
    expect(a['turso.replica'], true);
  });

  test('INSERT records rows + rowid', () async {
    await tracedTursoQuery<String>(
      statement: 'INSERT INTO logs VALUES (?)',
      invoke: () async => const TursoQueryResult(
        value: 'ok',
        rowsAffected: 1,
        lastInsertRowId: 42,
      ),
    );
    final a = attrsOf(spans.findSpanByName('INSERT')!);
    expect(a['db.rows_affected'], 1);
    expect(a['turso.last_insert_rowid'], 42);
  });

  test('PRAGMA recognized', () async {
    await tracedTursoQuery<String>(
      statement: 'PRAGMA journal_mode = WAL',
      invoke: () async => const TursoQueryResult(value: 'ok'),
    );
    expect(spans.findSpanByName('PRAGMA'), isNotNull);
  });

  test('suppression skips spans', () async {
    await runWithoutTursoInstrumentationAsync(() async {
      await tracedTursoQuery<String>(
        statement: 'SELECT 1',
        invoke: () async => const TursoQueryResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('SELECT'), isEmpty);
  });
}
