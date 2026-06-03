require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 15_000 # milliseconds (increased to safely cover upsert duration)
    LOCK_RETRY_COUNT = 10 # number of attempts to acquire the lock
    LOCK_RETRY_DELAY = 200 # base retry delay in milliseconds
    LOCK_RETRY_JITTER = 100 # random jitter to avoid thundering herd

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      # Use the block form of lock. Redlock will internally retry up to
      # LOCK_RETRY_COUNT times with backoff + jitter before yielding nil/false.
      lock_info = lock_manager.lock(lock_key, LOCK_TTL)

      if lock_info
        begin
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        ensure
          # Always release the lock, even if the upsert raises.
          lock_manager.unlock(lock_info)
        end
      else
        # Could not acquire the lock after all retries. Do NOT raise a fatal
        # error that gets logged as "max retries"; instead, let the message
        # be retried later by re-raising a transient error so SQS/Shoryuken
        # redelivers it after the visibility timeout.
        Rails.logger.warn(
          "[NcinoConsumerApi][UpsertRecordJob] Could not acquire lock for " \
          "#{record_type}/#{record_id} (guid #{message_id}); will retry via redelivery"
        )
        raise LockAcquisitionTimeout,
              "Lock currently held for #{record_type}/#{record_id}; deferring to redelivery"
      end
    rescue LockAcquisitionTimeout => e
      # Transient: allow Shoryuken/SQS to redeliver. Re-raise so the message
      # is not deleted and becomes visible again after the visibility timeout.
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

    # Transient error used to signal that the lock could not be acquired and
    # the message should be redelivered rather than treated as a hard failure.
    class LockAcquisitionTimeout < StandardError; end
  end
end