import 'dart:async';

import 'package:logging/logging.dart';

import 'common.dart';
import 'messages.dart';
import 'produce_api.dart';
import 'serialization.dart';
import 'session.dart';

final Logger _logger = new Logger('Producer');

/// Produces messages to Kafka cluster.
///
/// Automatically discovers leader brokers for each topic-partition to
/// send messages to.
abstract class Producer<K, V> {
  factory Producer(Serializer<K> keySerializer, Serializer<V> valueSerializer,
          ProducerConfig config) =>
      new _Producer(keySerializer, valueSerializer, config);

  /// Sends [record] to Kafka cluster.
  Future<ProduceResult> send(ProducerRecord<K, V> record);

  /// Closes this producer's connections to Kafka cluster.
  Future close();
}

class ProducerRecord<K, V> {
  final String topic;
  final int partition;
  final K key;
  final V value;
  final int timestamp;

  ProducerRecord(this.topic, this.partition, this.key, this.value,
      {this.timestamp});
}

class ProduceResult {
  final TopicPartition topicPartition;
  final int offset;
  final int timestamp;

  ProduceResult(this.topicPartition, this.offset, this.timestamp);

  @override
  toString() =>
      'ProduceResult{${topicPartition}, offset: $offset, timestamp: $timestamp}';
}

class _Producer<K, V> implements Producer<K, V> {
  final ProducerConfig config;
  final Serializer<K> keySerializer;
  final Serializer<V> valueSerializer;
  final Session session;

  _Producer(this.keySerializer, this.valueSerializer, this.config)
      : session = new Session(config.bootstrapServers) {
    _logger.info('Producer created with config:');
    _logger.info(config);
  }

  @override
  Future<ProduceResult> send(ProducerRecord<K, V> record) async {
    var key = keySerializer.serialize(record.key);
    var value = valueSerializer.serialize(record.value);
    var timestamp =
        record.timestamp ?? new DateTime.now().millisecondsSinceEpoch;
    var message = new Message(value, key: key, timestamp: timestamp);
    var messages = {
      record.topic: {
        record.partition: [message]
      }
    };
    var req = new ProduceRequest(config.acks, config.timeoutMs, messages);
    var meta = await session.metadata.fetchTopics([record.topic]);
    var leaderId = meta[record.topic].partitions[record.partition].leader;
    var broker = meta.brokers[leaderId];
    var response = await session.send(req, broker.host, broker.port);
    var result = response.results.first;

    return new Future.value(new ProduceResult(
        result.topicPartition, result.offset, result.timestamp));
  }

  @override
  Future close() => session.close();
}

/// Configuration for [Producer].
///
/// The only required setting which must be set is [bootstrapServers],
/// other settings are optional and have default values. Refer
/// to settings documentation for more details.
class ProducerConfig {
  /// A list of host/port pairs to use for establishing the initial
  /// connection to the Kafka cluster. The client will make use of
  /// all servers irrespective of which servers are specified here
  /// for bootstrapping - this list only impacts the initial hosts
  /// used to discover the full set of servers. The values should
  /// be in the form `host:port`.
  /// Since these servers are just used for the initial connection
  /// to discover the full cluster membership (which may change
  /// dynamically), this list need not contain the full set of
  /// servers (you may want more than one, though, in case a
  /// server is down).
  final List<String> bootstrapServers;

  /// The number of acknowledgments the producer requires the leader to have
  /// received before considering a request complete.
  /// This controls the durability of records that are sent.
  final int acks;

  /// Controls the maximum amount of time the server
  /// will wait for acknowledgments from followers to meet the acknowledgment
  /// requirements the producer has specified with the [acks] configuration.
  /// If the requested number of acknowledgments are not met when the timeout
  /// elapses an error is returned by the server. This timeout is measured on the
  /// server side and does not include the network latency of the request.
  final int timeoutMs;

  /// Setting a value greater than zero will cause the client to resend any
  /// record whose send fails with a potentially transient error.
  final int retries;

  /// An id string to pass to the server when making requests.
  /// The purpose of this is to be able to track the source of requests
  /// beyond just ip/port by allowing a logical application name to be
  /// included in server-side request logging.
  final String clientId;

  /// The maximum size of a request in bytes. This is also effectively a
  /// cap on the maximum record size. Note that the server has its own
  /// cap on record size which may be different from this.
  final int maxRequestSize;

  /// The maximum number of unacknowledged requests the client will
  /// send on a single connection before blocking. Note that if this
  /// setting is set to be greater than 1 and there are failed sends,
  /// there is a risk of message re-ordering due to retries (i.e.,
  /// if retries are enabled).
  final int maxInFlightRequestsPerConnection;

  ProducerConfig({
    this.bootstrapServers,
    this.acks = 1,
    this.timeoutMs = 30000,
    this.retries = 0,
    this.clientId = '',
    this.maxRequestSize = 1048576,
    this.maxInFlightRequestsPerConnection = 5,
  }) {
    assert(bootstrapServers != null);
  }

  @override
  String toString() => '''
ProducerConfig(
  bootstrapServers: $bootstrapServers, 
  acks: $acks, 
  timeoutMs: $timeoutMs,
  retries: $retries,
  clientId: $clientId,
  maxRequestSize: $maxRequestSize,
  maxInFlightRequestsPerConnection: $maxInFlightRequestsPerConnection
)
''';
}
