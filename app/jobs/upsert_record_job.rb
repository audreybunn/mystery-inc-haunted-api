require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 15_000      # milliseconds - generous TTL to cover the full upsert
    LOCK_RETRY_COUNT = 10  # number of additional attempts to acquire the lock
    LOCK_RETRY_DELAY = 300 # base delay (ms) between attempts; jitter added by Redlock

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      lock_acquired = false

      lock_manager.lock(lock_key, LOCK_TTL) do |locked|
        if locked
          lock_acquired = true
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        end
      end

      # If the lock could not be obtained after all retries, do NOT crash the job.
      # Re-queueing/visibility-timeout will allow another attempt without a hard failure,
      # avoiding the "Reached max DistributedLockException retries" error spam.
      unless lock_acquired
        Rails.logger.warn(
          "[NcinoConsumerApi][UpsertRecordJob] Could not acquire lock for " \
          "#{record_type}/#{record_id} (message_id=#{message_id}); will be retried later"
        )
        raise LockUnavailableError,
              "Reached max DistributedLockException retries for UpsertRecordJob for #{record_type}/#{record_id}"
      end
    rescue LockUnavailableError => e
      # Lock contention is transient: log at warn level and re-raise so the SQS
      # message becomes visible again and is retried, rather than treating it as a fatal error.
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
        retry_jitter: 100 # add jitter to spread out contending workers
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

    # Raised when the distributed lock cannot be acquired after exhausting retries.
    # Treated as a transient/retryable condition rather than a hard failure.
    class LockUnavailableError < StandardError; end
  end
end