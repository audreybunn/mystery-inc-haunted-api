require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

    # AES-256-GCM requires a 32-byte key. We standardize on GCM (authenticated
    # encryption) and derive a deterministic key of the correct length.
    CIPHER = 'aes-256-gcm'.freeze
    KEY_SALT = 'token_encryption'.freeze

    class << self
      def encrypt(token)
        encryptor.encrypt_and_sign(token)
      end

      def decrypt(encrypted_token)
        encryptor.decrypt_and_verify(encrypted_token)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
        Rails.logger.error "[TokenEncryptor] Error #{e.class} raised. Message: #{e.message}"
        raise DecryptionError, "Failed to decrypt token: #{e.message}"
      end

      private

      def encryptor
        @encryptor ||= begin
          # The secret MUST be stable across all processes/requests. A random or
          # changing fallback would cause "mismatched digest" InvalidMessage errors
          # because tokens encrypted with one key cannot be verified with another.
          secret = ENV.fetch('SECRET_KEY_BASE') do
            unless Rails.env.development? || Rails.env.test?
              raise KeyError, 'SECRET_KEY_BASE must be set outside of development/test'
            end
            'default_secret_for_development_only'
          end

          # Derive a key whose length matches the cipher's required key length.
          # For aes-256-gcm this is 32 bytes (not 16).
          key_len = ActiveSupport::MessageEncryptor.key_len(CIPHER)
          key = ActiveSupport::KeyGenerator.new(secret).generate_key(KEY_SALT, key_len)

          ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
        end
      end
    end

    class DecryptionError < StandardError; end
  end
end