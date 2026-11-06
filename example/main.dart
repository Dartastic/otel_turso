// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_turso/otel_turso.dart';

/// Traces Turso calls with OpenTelemetry.
///
/// `otel_turso` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Turso call in
/// [tracedTursoQuery]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'turso-example');

  // Wraps a Turso / libSQL query in a CLIENT span.
  final tursoQueryId = await tracedTursoQuery<String>(
    statement: 'active',
    databaseUrl: 'https://api.example.com/v1/resource',
    collection: 'orders',
    replica: true,
    invoke: () async {
      // Make the Turso call here, then report what it returned.
      const id = 'turso_8f3a2c';
      return const TursoQueryResult(
          value: id, rowsAffected: 1, lastInsertRowId: 1);
    },
  );
  OTelLog.info('tracedTursoQuery returned $tursoQueryId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutTursoInstrumentationAsync.
  await runWithoutTursoInstrumentationAsync(
    () => tracedTursoQuery<String>(
      statement: 'active',
      databaseUrl: 'https://api.example.com/v1/resource',
      collection: 'orders',
      replica: true,
      invoke: () async {
        const id = 'turso_8f3a2c';
        return const TursoQueryResult(
            value: id, rowsAffected: 1, lastInsertRowId: 1);
      },
    ),
  );

  await OTel.shutdown();
}
