require 'redlock'

module NcinoConsumerApi
  class UpsertRecordJob
    include Shoryuken::Worker

    shoryuken_options queue: 'record-updates',
                      auto_delete: true,
                      body_parser: :json

    LOCK_TTL = 5000 # milliseconds

    # Redlock retry tuning. Higher retry_count + jitter reduces lock contention
    # collisions when multiple workers target the same record concurrently.
    LOCK_RETRY_COUNT = 10
    LOCK_RETRY_DELAY = 200       # base delay in milliseconds
    LOCK_RETRY_JITTER = 100      # random jitter added per retry (milliseconds)

    # Process record update messages with distributed locking
    # Prevents concurrent updates to the same record across multiple workers
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      record_type = body['record_type']
      record_id = body['record_id']

      Rails.logger.info "[NcinoConsumerApi][UpsertRecordJob] Processing #{record_type}/#{record_id}"

      lock_key = "upsert_lock:#{record_type}:#{record_id}"

      lock_acquired = false

      # Use the block form so Redlock auto-extends/releases the lock, but capture
      # whether we actually got it so we can decide how to handle contention.
      lock_manager.lock(lock_key, LOCK_TTL) do |locked|
        if locked
          lock_acquired = true
          perform_upsert(record_type, record_id, body['data'])
          Rails.logger.info "[UpsertRecordJob] Successfully upserted #{record_type}/#{record_id}"
        end
      end

      unless lock_acquired
        # Did not acquire the lock after all configured retries. Rather than
        # treating this as a fatal job error, raise so Shoryuken/SQS redelivers
        # the message later (visibility timeout) and another attempt can succeed.
        raise DistributedLockException,
              "Reached max DistributedLockException retries for #{message_id} for #{record_type} with guid #{record_id}"
      end
    rescue DistributedLockException => e
      # Log and re-raise so the message is NOT auto-deleted and gets retried.
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
        # retry_jitter spreads out competing workers so they don't all retry
        # on the same cadence, dramatically reducing repeated lock contention.
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