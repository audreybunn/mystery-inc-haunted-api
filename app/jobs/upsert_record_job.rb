require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 5000 # milliseconds

    # Lock acquisition tuning.
    # Redlock retries the lock acquisition internally `LOCK_RETRY_COUNT` times,
    # sleeping a randomized interval between `min` and `max` (jitter) to avoid
    # thundering-herd contention when multiple workers target the same record.
    LOCK_RETRY_COUNT = 5
    LOCK_RETRY_DELAY_MIN = 200  # milliseconds
    LOCK_RETRY_DELAY_MAX = 600  # milliseconds

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      # Use the lock_manager's configured retry/backoff settings. We do NOT
      # override retry_count/retry_delay here with tiny values, otherwise the
      # lock fails almost instantly under concurrent load and raises
      # DistributedLockException for hot records (e.g. Deposit updates).
      lock_acquired = false

      lock_manager.lock(lock_key, LOCK_TTL) do |locked|
        if locked
          lock_acquired = true
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        end
      end

      unless lock_acquired
        # Lock could not be acquired after all retries. Rather than treating
        # this as a fatal error, raise so SQS redelivers the message later
        # (with visibility-timeout backoff), allowing the in-flight worker to
        # finish first. This serializes updates instead of failing them.
        raise DistributedLockException,
              "Could not acquire lock after #{LOCK_RETRY_COUNT} retries for #{record_type}/#{record_id} (message_id: #{message_id})"
      end
    rescue DistributedLockException => e
      # Lock contention is transient; log at warn and re-raise so the message
      # is retried by SQS rather than discarded.
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
        retry_delay: ->(_attempt) { rand(LOCK_RETRY_DELAY_MIN..LOCK_RETRY_DELAY_MAX) },
        retry_jitter: 50
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
      when 'deposit'
        upsert_deposit(record_id, data)
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

    def upsert_deposit(record_id, data)
      deposit = Deposit.find_or_initialize_by(id: record_id)
      deposit.update!(data)
      Rails.logger.info "[UpsertRecordJob] Upserting deposit record #{record_id}"
    end

    class DistributedLockException < StandardError; end
  end
end