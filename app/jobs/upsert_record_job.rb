require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 30_000 # milliseconds - generous TTL to cover slow upserts (DB writes)

    # Redlock acquisition tuning: retry more times with jittered backoff so that
    # transient contention (multiple workers on same record) is handled gracefully
    # instead of immediately raising DistributedLockException.
    LOCK_RETRY_COUNT = 5
    LOCK_RETRY_DELAY = 200 # milliseconds (base)
    LOCK_RETRY_JITTER = 100 # milliseconds

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      # Use the imperative lock/unlock API so we control TTL extension and ensure
      # the lock is always released, even if the upsert raises.
      lock_info = nil
      begin
        lock_info = lock_manager.lock(lock_key, LOCK_TTL)

        unless lock_info
          # Could not acquire after configured retries. Raise so the SQS message
          # is NOT auto-deleted prematurely and can be retried by the queue.
          raise DistributedLockException,
                "Reached max DistributedLockException retries for UpsertRecordJob for #{record_type}/#{record_id}"
        end

        perform_upsert(record_type, record_id, body['data'])
        Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
      ensure
        # Always release the lock we hold to avoid leaving stale locks that
        # cause subsequent workers to fail acquisition.
        lock_manager.unlock(lock_info) if lock_info
      end
    rescue DistributedLockException => e
      Rails.logger.error "[NcinoConsumerApi][UpsertRecordJob] #{e.message}"
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

    class DistributedLockException < StandardError; end
  end
end