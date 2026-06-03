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
      # SQS ensures at-least-once delivery, so the same message may be
      # processed multiple times. To make this idempotent we look up the
      # record by its unique key (guid) and update it, otherwise create it.
      #
      # find_or_initialize_by + save handles the common case, but we still
      # guard against a race where two concurrent consumers insert the same
      # guid simultaneously (RecordNotUnique). In that case we retry as an
      # update of the now-existing row.
      attributes = {
        applicant_name: data[:applicant_name],
        status: data[:status],
        loan_amount: data[:loan_amount],
        product_type: data[:product_type],
        submitted_at: data[:submitted_at]
      }

      begin
        loan_app = LoanApplication.find_or_initialize_by(guid: data[:guid])
        loan_app.assign_attributes(attributes)
        loan_app.save!
        loan_app
      rescue ActiveRecord::RecordNotUnique => e
        # Lost a race to another consumer that just inserted this guid.
        # The duplicate is expected/benign; load the existing row and update it.
        Rails.logger.warn(
          "[UpsertApplicationJob] Duplicate insert for guid #{data[:guid]} " \
          "(at-least-once delivery race), updating existing record: #{e.message}"
        )
        loan_app = LoanApplication.find_by(guid: data[:guid])
        raise if loan_app.nil? # genuinely unexpected unique violation

        loan_app.update!(attributes)
        loan_app
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[UpsertApplicationJob] Validation failed: #{e.message}"
      raise
    end
  end
end