require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

    # AES-256-GCM requires a 32-byte (256-bit) key.
    CIPHER = 'aes-256-gcm'.freeze
    KEY_LEN = ActiveSupport::MessageEncryptor.key_len(CIPHER) # 32 for aes-256-gcm

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
          # Generate encryption key from secret base.
          # The key MUST match the cipher's required length (32 bytes for AES-256).
          secret = ENV.fetch('SECRET_KEY_BASE', 'default_secret_for_development_only')

          # Use a stable, explicit salt and the correct key length derived
          # from the cipher to guarantee deterministic, consistent key material.
          key = ActiveSupport::KeyGenerator.new(secret).generate_key(
            'token_encryption',
            KEY_LEN
          )

          ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
        end
      end
    end

    class DecryptionError < StandardError; end
  end
end