require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

    CIPHER = 'aes-256-cbc'.freeze
    SALT = 'token_encryption'.freeze

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
          secret = ENV.fetch('SECRET_KEY_BASE', 'default_secret_for_development_only')

          # The key length MUST match the cipher's expected key size.
          # AES-256-CBC requires a 32-byte key. Using 16 bytes here was the
          # root cause of the "mismatched digest" InvalidMessage errors.
          key_len = ActiveSupport::MessageEncryptor.key_len(CIPHER)
          key = ActiveSupport::KeyGenerator.new(secret).generate_key(SALT, key_len)

          ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
        end
      end
    end

    class DecryptionError < StandardError; end
  end
end