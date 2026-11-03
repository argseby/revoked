/// A place this workspace sends its events to.
class WebhookEndpoint {
  final String id;
  final String url;
  final String description;
  final List<String> events;
  final bool enabled;

  /// `failing` when the server turned it off, `manual` when a person did.
  final String disabledReason;
  final DateTime? failingSince;
  final DateTime? created;
  final int succeeded;
  final int failed;
  final int pending;

  /// The last day, hour by hour, for the small chart in the list.
  final List<WebhookBucket> series;

  const WebhookEndpoint({
    required this.id,
    required this.url,
    required this.description,
    required this.events,
    required this.enabled,
    required this.disabledReason,
    required this.failingSince,
    required this.created,
    required this.succeeded,
    required this.failed,
    required this.pending,
    this.series = const [],
  });

  factory WebhookEndpoint.fromJson(Map<String, dynamic> json) {
    final stats = (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    return WebhookEndpoint(
      id: json['id'] as String,
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      events: ((json['events'] as List<dynamic>?) ?? const [])
          .cast<String>()
          .toList(),
      enabled: json['enabled'] as bool? ?? false,
      disabledReason: json['disabledReason'] as String? ?? '',
      failingSince: _date(json['failingSince']),
      created: _date(json['created']),
      succeeded: (stats['succeeded'] as num?)?.toInt() ?? 0,
      failed: (stats['failed'] as num?)?.toInt() ?? 0,
      pending: (stats['pending'] as num?)?.toInt() ?? 0,
      series: WebhookBucket.list(json['series']),
    );
  }

  bool get sendsEverything => events.contains('*');

  bool get isFailing => enabled && failingSince != null;

  /// The address without its scheme, for a title.
  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}

/// One event a webhook can be sent, as the server lists them.
class WebhookEventType {
  final String type;
  final String group;
  final String description;

  /// Left out of "every event" unless picked by name.
  final bool noisy;

  const WebhookEventType({
    required this.type,
    required this.group,
    required this.description,
    required this.noisy,
  });

  factory WebhookEventType.fromJson(Map<String, dynamic> json) =>
      WebhookEventType(
        type: json['type'] as String,
        group: json['group'] as String? ?? '',
        description: json['description'] as String? ?? '',
        noisy: json['noisy'] as bool? ?? false,
      );
}

/// One try at sending a delivery.
class WebhookAttempt {
  final int responseStatus;
  final String responseBody;
  final String error;
  final int durationMs;
  final bool manual;
  final DateTime? created;

  const WebhookAttempt({
    required this.responseStatus,
    required this.responseBody,
    required this.error,
    required this.durationMs,
    required this.manual,
    required this.created,
  });

  factory WebhookAttempt.fromJson(Map<String, dynamic> json) => WebhookAttempt(
    responseStatus: (json['responseStatus'] as num?)?.toInt() ?? 0,
    responseBody: json['responseBody'] as String? ?? '',
    error: json['error'] as String? ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    manual: json['manual'] as bool? ?? false,
    created: _date(json['created']),
  );

  bool get ok => error.isEmpty && responseStatus >= 200 && responseStatus < 300;
}

/// One event on its way to one webhook.
class WebhookDelivery {
  final String id;
  final String endpoint;
  final String type;
  final bool test;

  /// `pending`, `succeeded` or `failed`.
  final String status;
  final int attempts;
  final int lastStatus;
  final String lastError;
  final DateTime? nextAttemptAt;
  final DateTime? created;

  /// Only on a delivery loaded on its own: what was sent, and every try.
  final Map<String, dynamic>? payload;
  final List<WebhookAttempt> attemptLog;

  const WebhookDelivery({
    required this.id,
    required this.endpoint,
    required this.type,
    required this.test,
    required this.status,
    required this.attempts,
    required this.lastStatus,
    required this.lastError,
    required this.nextAttemptAt,
    required this.created,
    this.payload,
    this.attemptLog = const [],
  });

  factory WebhookDelivery.fromJson(Map<String, dynamic> json) =>
      WebhookDelivery(
        id: json['id'] as String,
        endpoint: json['endpoint'] as String? ?? '',
        type: json['type'] as String? ?? '',
        test: json['test'] as bool? ?? false,
        status: json['status'] as String? ?? '',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastStatus: (json['lastStatus'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String? ?? '',
        nextAttemptAt: _date(json['nextAttemptAt']),
        created: _date(json['created']),
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
        attemptLog: ((json['attemptLog'] as List<dynamic>?) ?? const [])
            .map((e) => WebhookAttempt.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

DateTime? _date(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// One slice of a time range: attempts answered with a 2xx, the others, and
/// how long the endpoint took to answer.
class WebhookBucket {
  final DateTime start;
  final int delivered;
  final int failed;
  final int p50Ms;
  final int p95Ms;

  const WebhookBucket({
    required this.start,
    required this.delivered,
    required this.failed,
    required this.p50Ms,
    required this.p95Ms,
  });

  int get total => delivered + failed;

  factory WebhookBucket.fromJson(Map<String, dynamic> json) => WebhookBucket(
    start: _date(json['start']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    delivered: (json['delivered'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    p50Ms: (json['p50Ms'] as num?)?.toInt() ?? 0,
    p95Ms: (json['p95Ms'] as num?)?.toInt() ?? 0,
  );

  static List<WebhookBucket> list(Object? json) =>
      ((json as List<dynamic>?) ?? const [])
          .map((e) => WebhookBucket.fromJson(e as Map<String, dynamic>))
          .toList();
}

/// How an endpoint has done over a range.
class WebhookMetrics {
  final String range;
  final List<WebhookBucket> buckets;
  final int deliveries;
  final int firstTry;
  final int retrying;
  final int p95Ms;

  /// Attempts by answer: `2xx`, `4xx`, `5xx`, and `none` for no answer.
  final Map<String, int> codes;

  /// The event types sent most, most first.
  final List<(String, int)> events;

  const WebhookMetrics({
    required this.range,
    required this.buckets,
    required this.deliveries,
    required this.firstTry,
    required this.retrying,
    required this.p95Ms,
    required this.codes,
    required this.events,
  });

  int get attempts => buckets.fold(0, (n, b) => n + b.total);

  /// The share of deliveries that got through on the first try, or null when
  /// there were none.
  double? get firstTryRate => deliveries == 0 ? null : firstTry / deliveries;

  factory WebhookMetrics.fromJson(Map<String, dynamic> json) {
    final codes = (json['codes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return WebhookMetrics(
      range: json['range'] as String? ?? '24h',
      buckets: WebhookBucket.list(json['buckets']),
      deliveries: (json['deliveries'] as num?)?.toInt() ?? 0,
      firstTry: (json['firstTry'] as num?)?.toInt() ?? 0,
      retrying: (json['retrying'] as num?)?.toInt() ?? 0,
      p95Ms: (json['p95Ms'] as num?)?.toInt() ?? 0,
      codes: {
        for (final k in const ['2xx', '4xx', '5xx', 'none'])
          k: (codes[k] as num?)?.toInt() ?? 0,
      },
      events: [
        for (final e in (json['events'] as List<dynamic>?) ?? const [])
          (
            (e as Map)['type'] as String? ?? '',
            (e['count'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }
}
