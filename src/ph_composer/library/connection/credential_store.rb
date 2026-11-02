# frozen_string_literal: true

module PhComposer
  module Library
    module Connection
      # The OS credential store a hosted library extension keeps its secrets in, one item per provider
      # and connection, keyed by public ids only (never a firm name or an email). The value never
      # leaves the process: no helper process, argument, environment variable or file carries it.
      #
      # macOS keeps one generic-password item per connection in the login keychain (service
      # `ph-composer.<provider id>`, account the connection id), replaced in place by one modify call,
      # so a crash mid-write leaves the last complete value. Windows keeps a generic credential with
      # target `ph-composer/<provider id>/<connection id>`; that path is written and not yet observed on a
      # host. Both are reached through Fiddle, loaded on first use, so a platform without them loads
      # this file and reports `library.credential_store_unavailable` instead.
      #
      # A failed write raises `library.credential_store_failed`; the extension reports it as
      # `reauthorization_required` rather than keep a credential it could not store.
      module CredentialStore
        MAX_BYTES = 2_560

        module_function

        def write(provider_id, connection_id, value)
          check_ids!(provider_id, connection_id)
          unless value.is_a?(String) && !value.empty? && value.bytesize <= MAX_BYTES
            raise Error.new("library.credential_store_failed", "The credential cannot be stored.")
          end

          guarded { backend.write(provider_id, connection_id, value.b) }
          nil
        end

        # The stored bytes (a binary String), or nil when there is none.
        def read(provider_id, connection_id)
          check_ids!(provider_id, connection_id)
          guarded { backend.read(provider_id, connection_id) }
        end

        # True when an item was deleted, false when there was none.
        def delete(provider_id, connection_id)
          check_ids!(provider_id, connection_id)
          guarded { backend.delete(provider_id, connection_id) }
        end

        def backend
          @backend ||= if RUBY_PLATFORM.include?("darwin") then Keychain.new
                       elsif Gem.win_platform? then CredentialManager.new
                       else Unavailable.new
                       end
        end

        # A test or another host supplies its own; nil restores the platform's.
        def backend=(value)
          @backend = value
        end

        def check_ids!(provider_id, connection_id)
          return if [provider_id, connection_id].all? { |id| id.is_a?(String) && PUBLIC_ID.match?(id) }

          raise Error.new("library.credential_store_failed", "The credential key is invalid.")
        end

        # A backend failure keeps only its code; OS messages and status numbers stay out of outcomes.
        def guarded
          yield
        rescue Error
          raise
        rescue StandardError, LoadError
          raise Error.new("library.credential_store_failed", "The credential store refused the request."),
                :cause => nil
        end
        private_class_method :check_ids!, :guarded

        class Unavailable
          %i[write read delete].each do |name|
            define_method(name) do |*_arguments|
              raise Error.new("library.credential_store_unavailable", "This platform has no credential store.")
            end
          end
        end

        # `Security.framework` generic passwords.
        class Keychain
          NOT_FOUND = -25_300

          def write(provider_id, connection_id, value)
            service = service(provider_id)
            status, item = find(service, connection_id, :data => false)
            if status.zero?
              begin
                check!(api.SecKeychainItemModifyAttributesAndData(item, nil, value.bytesize, value))
              ensure
                api.CFRelease(item)
              end
            else
              check!(status) unless status == NOT_FOUND
              check!(api.SecKeychainAddGenericPassword(nil, service.bytesize, service, connection_id.bytesize,
                                                       connection_id, value.bytesize, value, nil))
            end
          end

          def read(provider_id, connection_id)
            status, item, value = find(service(provider_id), connection_id, :data => true)
            return nil if status == NOT_FOUND

            api.CFRelease(item) if status.zero?
            check!(status)
            value
          end

          def delete(provider_id, connection_id)
            status, item = find(service(provider_id), connection_id, :data => false)
            return false if status == NOT_FOUND

            check!(status)
            begin
              check!(api.SecKeychainItemDelete(item))
            ensure
              api.CFRelease(item)
            end
            true
          end

          private

          def service(provider_id)
            "ph-composer.#{provider_id}"
          end

          # [status, item, value]; the value is read only when asked for and freed at once.
          def find(service, account, data:)
            functions = api
            length = Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE)
            content = slot
            item = slot
            status = functions.SecKeychainFindGenericPassword(nil, service.bytesize, service, account.bytesize,
                                                              account, data ? length : nil, data ? content : nil, item)
            return [status, nil, nil] unless status.zero?

            value = nil
            if data
              value = content.ptr[0, length[0, 4].unpack1("L")].dup
              functions.SecKeychainItemFreeContent(nil, content.ptr)
            end
            [status, item.ptr, value]
          end

          def slot
            Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE).tap do |pointer|
              pointer[0, Fiddle::SIZEOF_VOIDP] = "\0" * Fiddle::SIZEOF_VOIDP
            end
          end

          def check!(status)
            raise Error.new("library.credential_store_failed", "The keychain refused the request.") unless status.zero?
          end

          def api
            @api ||= begin
              require "fiddle"
              require "fiddle/import"
              Module.new do
                extend Fiddle::Importer

                dlload "/System/Library/Frameworks/Security.framework/Security",
                       "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
                extern "int SecKeychainAddGenericPassword(void*, unsigned int, const char*, unsigned int, " \
                       "const char*, unsigned int, const void*, void*)"
                extern "int SecKeychainFindGenericPassword(void*, unsigned int, const char*, unsigned int, " \
                       "const char*, void*, void*, void*)"
                extern "int SecKeychainItemModifyAttributesAndData(void*, void*, unsigned int, const void*)"
                extern "int SecKeychainItemDelete(void*)"
                extern "int SecKeychainItemFreeContent(void*, void*)"
                extern "void CFRelease(void*)"
              end
            end
          end
        end

        # Windows Credential Manager (`advapi32.dll`) generic credentials, persisted per machine user.
        # Written to the documented API; no Windows host has run it yet.
        class CredentialManager
          CRED_TYPE_GENERIC = 1
          CRED_PERSIST_LOCAL_MACHINE = 2
          ERROR_NOT_FOUND = 1168

          def write(provider_id, connection_id, value)
            functions = api
            credential = functions::CREDENTIALW.malloc(Fiddle::RUBY_FREE)
            target = wide(target(provider_id, connection_id))
            blob = Fiddle::Pointer[value]
            credential.Flags = 0
            credential.Type = CRED_TYPE_GENERIC
            credential.TargetName = target
            credential.Comment = nil
            credential.LastWrittenLow = 0
            credential.LastWrittenHigh = 0
            credential.CredentialBlobSize = value.bytesize
            credential.CredentialBlob = blob
            credential.Persist = CRED_PERSIST_LOCAL_MACHINE
            credential.AttributeCount = 0
            credential.Attributes = nil
            credential.TargetAlias = nil
            credential.UserName = nil
            check!(functions.CredWriteW(credential, 0))
          end

          def read(provider_id, connection_id)
            functions = api
            out = Fiddle::Pointer.malloc(Fiddle::SIZEOF_VOIDP, Fiddle::RUBY_FREE)
            unless functions.CredReadW(wide(target(provider_id, connection_id)), CRED_TYPE_GENERIC, 0, out) == 1
              return nil if last_error == ERROR_NOT_FOUND

              check!(0)
            end
            credential = functions::CREDENTIALW.new(out.ptr)
            value = Fiddle::Pointer.to_ptr(credential.CredentialBlob)[0, credential.CredentialBlobSize].dup
            functions.CredFree(out.ptr)
            value
          end

          def delete(provider_id, connection_id)
            return true if api.CredDeleteW(wide(target(provider_id, connection_id)), CRED_TYPE_GENERIC, 0) == 1
            return false if last_error == ERROR_NOT_FOUND

            check!(0)
          end

          private

          def target(provider_id, connection_id)
            "ph-composer/#{provider_id}/#{connection_id}"
          end

          def wide(text)
            Fiddle::Pointer[(text + "\0").encode("UTF-16LE")]
          end

          def last_error
            Fiddle.win32_last_error
          end

          def check!(result)
            return if result == 1

            raise Error.new("library.credential_store_failed", "The credential store refused the request.")
          end

          def api
            @api ||= begin
              require "fiddle"
              require "fiddle/import"
              Module.new do
                extend Fiddle::Importer

                dlload "advapi32.dll"
                typealias "DWORD", "unsigned long"
                const_set(:CREDENTIALW, struct([
                  "DWORD Flags", "DWORD Type", "void* TargetName", "void* Comment",
                  "DWORD LastWrittenLow", "DWORD LastWrittenHigh", "DWORD CredentialBlobSize",
                  "void* CredentialBlob", "DWORD Persist", "DWORD AttributeCount", "void* Attributes",
                  "void* TargetAlias", "void* UserName"
                ]))
                extern "int CredWriteW(void*, DWORD)"
                extern "int CredReadW(void*, DWORD, DWORD, void*)"
                extern "int CredDeleteW(void*, DWORD, DWORD)"
                extern "void CredFree(void*)"
              end
            end
          end
        end
      end
    end
  end
end
