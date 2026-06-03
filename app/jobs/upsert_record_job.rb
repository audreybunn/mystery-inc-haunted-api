require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: false,
                      body_parser: :json

    LOCK_TTL = 5000 # milliseconds

    # Redlock-level retry settings (applied inside the client)
    REDLOCK_RETRY_COUNT = 3
    REDLOCK_RETRY_DELAY = 200 # milliseconds (base; jitter added by Redlock)

    # Application-level retry settings for lock contention
    MAX_LOCK_ACQUISITION_ATTEMPTS = 5
    LOCK_ACQUISITION_BACKOFF = 0.25 # seconds (base for exponential backoff)

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      with_distributed_lock(lock_key, record_type, record_id) do
        perform_upsert(record_type, record_id, body['data'])
        Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
      end

      # Only delete the message once processing fully succeeds
      sqs_msg.delete
    rescue DistributedLockException => e
      # Lock could not be acquired after all retries. Do NOT delete the
      # message; let SQS redeliver it later (visibility timeout) so the
      # update is not lost. Log and return so Shoryuken does not treat
      # transient contention as a fatal crash.
      Rails.logger.warn "[NcinoConsumerApi][UpsertRecordJob] #{e.message} - leaving message for redelivery"
      raise
    rescue StandardError => e
      Rails.logger.error "[NcinoConsumerApi][UpsertRecordJob] Error processing record: #{e.class} - #{e.message}"
      raise
    end

    private

    # Acquire the lock with explicit application-level retry/backoff.
    # The block is only executed if the lock is actually held. If the lock
    # cannot be acquired after MAX_LOCK_ACQUISITION_ATTEMPTS, we raise a
    # DistributedLockException so the message can be retried by SQS rather
    # than being lost.
    def with_distributed_lock(lock_key, record_type, record_id)
      attempt = 0

      loop do
        attempt += 1
        lock_info = lock_manager.lock(lock_key, LOCK_TTL)

        if lock_info
          begin
            return yield
          ensure
            lock_manager.unlock(lock_info)
          end
        end

        if attempt >= MAX_LOCK_ACQUISITION_ATTEMPTS
          raise DistributedLockException,
                "Reached max DistributedLockException retries (#{MAX_LOCK_ACQUISITION_ATTEMPTS}) " \
                "for UpsertRecordJob for #{record_type}/#{record_id}"
        end

        # Exponential backoff with jitter to reduce thundering-herd contention
        sleep_time = (LOCK_ACQUISITION_BACKOFF * (2**(attempt - 1))) + rand(0.0..0.1)
        Rails.logger.info "[UpsertRecordJob] Lock busy for #{record_type}/#{record_id}, " \
                          "attempt #{attempt}/#{MAX_LOCK_ACQUISITION_ATTEMPTS}, retrying in #{sleep_time.round(2)}s"
        sleep(sleep_time)
      end
    end

    def lock_manager
      @lock_manager ||= Redlock::Client.new(
        [ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')],
        retry_count: REDLOCK_RETRY_COUNT,
        retry_delay: REDLOCK_RETRY_DELAY
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