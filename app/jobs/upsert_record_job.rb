require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 10_000          # milliseconds (raised to safely cover upsert work)
    LOCK_RETRY_COUNT = 5       # retry acquiring the lock several times before backing off
    LOCK_RETRY_DELAY = 200     # milliseconds base delay between retries
    LOCK_RETRY_JITTER = 100    # milliseconds jitter to avoid thundering herd

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      # Redlock yields the lock info (truthy) when acquired, or `false` when not.
      lock_info = lock_manager.lock(lock_key, LOCK_TTL)

      if lock_info
        begin
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        ensure
          lock_manager.unlock(lock_info)
        end
      else
        # Lock contention is transient, NOT fatal. Re-raise a retryable error so
        # Shoryuken/SQS will redeliver the message later instead of dropping it.
        Rails.logger.warn(
          "[NcinoConsumerApi][UpsertRecordJob] Could not acquire lock for " \
          "#{record_type}/#{record_id} after #{LOCK_RETRY_COUNT} attempts; will retry via redelivery"
        )
        raise LockContentionError,
              "Lock contention for UpsertRecordJob #{record_type}/#{record_id}"
      end
    rescue LockContentionError => e
      # Transient: log as warn and let the queue redeliver (do not auto_delete).
      Rails.logger.warn "[NcinoConsumerApi][UpsertRecordJob] #{e.message}"
      raise
    rescue StandardError => e
      Rails.logger.error "[NcinoConsumerApi][UpsertRecordJob] Error processing record: #{e.class} - #{e.message}"
      raise
    end

    private

    def lock_manager
      @lock_manager ||= Redlock::Client.new(
        [ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')],
        retry_count: LOCK_RETRY_COUNT,
        retry_delay: LOCK_RETRY_DELAY,
        retry_jitter: LOCK_RETRY_JITTER
      )
    end

    def perform_upsert(record_type, record_id, data)
      case record_type
      when 'conversational/conversational_app'
        upsert_conversational_record(record_id, data)
      when 'income_record'
        upsert_income_record(record_id, data)
      when 'business_relationship'
        upsert_business_relationship(record_id, data)
      else
        Rails.logger.warn "[UpsertRecordJob] Unknown record type: #{record_type}"
      end
    end

    def upsert_conversational_record(record_id, data)
      # Placeholder for conversational record upsert logic
      Rails.logger.info "[UpsertRecordJob] Upserting conversational record #{record_id}"
    end

    def upsert_income_record(record_id, data)
      income_record = IncomeRecord.find_or_initialize_by(id: record_id)
      income_record.update!(data)
    end

    def upsert_business_relationship(record_id, data)
      relationship = BusinessRelationship.find_or_initialize_by(id: record_id)
      relationship.update!(data)
    end

    # Distinct, retryable exception representing transient lock contention.
    class LockContentionError < StandardError; end
  end
end