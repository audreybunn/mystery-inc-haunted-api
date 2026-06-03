require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 10_000 # milliseconds — extended to cover slower upserts

    # Redlock acquisition tuning: more retries with jittered backoff
    # to gracefully handle concurrent workers contending for the same key.
    LOCK_RETRY_COUNT = 10
    LOCK_RETRY_DELAY = 200       # base delay in milliseconds
    LOCK_RETRY_JITTER = 100      # random jitter in milliseconds

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      acquired = false

      lock_manager.lock(lock_key, LOCK_TTL) do |locked|
        if locked
          acquired = true
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        end
      end

      unless acquired
        # Do NOT hard-fail. Re-raise a transient error so Shoryuken/SQS
        # redelivers the message later instead of exhausting retries here.
        raise DistributedLockException,
              "Reached max DistributedLockException retries for UpsertRecordJob for #{record_type}/#{record_id} with guid #{message_id}"
      end
    rescue DistributedLockException => e
      # Lock contention is transient; log and re-raise so the message is
      # retried via the queue's visibility-timeout / redrive policy.
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
        # Increased retry budget + jitter dramatically reduces the chance
        # of failing to acquire a contended lock within a single perform.
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

    class DistributedLockException < StandardError; end
  end
end