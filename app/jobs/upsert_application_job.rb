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
      # SQS provides at-least-once delivery, so duplicate messages are expected.
      # Use the unique business key (guid) to find-or-create, then update
      # attributes so the operation is truly idempotent and never causes a
      # duplicate-entry violation on the unique index.
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
      # Handles the race condition where two messages for the same guid are
      # processed concurrently and both pass find_or_initialize_by before
      # either commits. Re-fetch the now-existing row and apply the update.
      Rails.logger.warn "[UpsertApplicationJob] Concurrent insert detected for guid #{data[:guid]}, retrying as update: #{e.message}"

      loan_app = LoanApplication.find_by!(guid: data[:guid])
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