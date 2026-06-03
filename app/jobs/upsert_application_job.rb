module NcinoConsumerApi
  class UpsertApplicationJob
    include Shoryuken::Worker

    shoryuken_options queue: 'loan-applications',
                      auto_delete: true,
                      body_parser: :json

    # Process loan application messages from SQS queue
    # Creates or updates loan application records in the database
    def perform(sqs_msg, body)
      message_id = sqs_msg.message_id
      Rails.logger.info "[NcinoConsumerApi][UpsertApplicationJob] Processing message #{message_id}"

      application_data = parse_application_data(body)
      loan_app = upsert_application(application_data)

      Rails.logger.info "[NcinoConsumerApi][UpsertApplicationJob] Successfully processed application #{loan_app.guid}"
    rescue StandardError => e
      Rails.logger.error "[NcinoConsumerApi][UpsertApplicationJob] Error processing message: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end

    private

    def parse_application_data(body)
      {
        guid: body['application_guid'],
        applicant_name: body['applicant_name'],
        status: body['status'] || 'pending',
        loan_amount: body['loan_amount'],
        product_type: body['product_type'],
        submitted_at: body['submitted_at']
      }
    end

    def upsert_application(data)
      # SQS guarantees at-least-once delivery, so the same message can arrive
      # multiple times. We must idempotently create-or-update the record keyed
      # by its unique business identifier (guid) to avoid duplicate-key errors.
      #
      # find_or_initialize_by atomically resolves on the unique guid; we then
      # update the mutable attributes and save. A RecordNotUnique can still
      # occur under a race (two concurrent inserts), so we retry once by
      # re-fetching and updating the now-existing row.
      loan_app = LoanApplication.find_or_initialize_by(guid: data[:guid])

      loan_app.assign_attributes(
        applicant_name: data[:applicant_name],
        status: data[:status],
        loan_amount: data[:loan_amount],
        product_type: data[:product_type],
        submitted_at: data[:submitted_at]
      )

      loan_app.save!
      loan_app
    rescue ActiveRecord::RecordNotUnique => e
      # Lost an insert race against a concurrent delivery of the same message.
      # The row now exists; fetch it and apply the update idempotently.
      Rails.logger.warn "[UpsertApplicationJob] Duplicate insert race for guid #{data[:guid]}: #{e.message}. Retrying as update."

      loan_app = LoanApplication.find_by(guid: data[:guid])
      raise if loan_app.nil?

      loan_app.update!(
        applicant_name: data[:applicant_name],
        status: data[:status],
        loan_amount: data[:loan_amount],
        product_type: data[:product_type],
        submitted_at: data[:submitted_at]
      )
      loan_app
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[UpsertApplicationJob] Validation failed: #{e.message}"
      raise
    end
  end
end