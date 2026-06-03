require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

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
          # Generate encryption key from secret base
          # The key should be 32 bytes for AES-256-CBC
          secret = ENV.fetch('SECRET_KEY_BASE', 'default_secret_for_development_only')
          key = ActiveSupport::KeyGenerator.new(secret).generate_key('token_encryption', 16)

          ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-cbc')
        end
      end
    end

    class DecryptionError < StandardError; end
  end
end
