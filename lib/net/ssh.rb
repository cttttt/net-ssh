require 'logger'

require 'net/ssh/config'
require 'net/ssh/errors'
require 'net/ssh/loggable'
require 'net/ssh/transport/session'
require 'net/ssh/authentication/session'
require 'net/ssh/connection/session'

module Net

  # Net::SSH is a library for interacting, programmatically, with remote
  # processes via the SSH2 protocol. Sessions are always initiated via
  # Net::SSH.start. From there, a program interacts with the new SSH session
  # via the convenience methods on Net::SSH::Connection::Session, by opening
  # and interacting with new channels (Net::SSH::Connection:Session#open_channel
  # and Net::SSH::Connection::Channel), or by forwarding local and/or
  # remote ports through the connection (Net::SSH::Service::Forward).
  #
  # The SSH protocol is very event-oriented. Requests are sent from the client
  # to the server, and are answered asynchronously. This gives great flexibility
  # (since clients can have multiple requests pending at a time), but it also
  # adds complexity. Net::SSH tries to manage this complexity by providing
  # some simpler methods of synchronous communication (see Net::SSH::Connection::Session#exec!).
  #
  # In general, though, and if you want to do anything more complicated than
  # simply executing commands and capturing their output, you'll need to use
  # channels (Net::SSH::Connection::Channel) to build state machines that are
  # executed while the event loop runs (Net::SSH::Connection::Session#loop).
  #
  # Net::SSH::Connection::Session and Net::SSH::Connection::Channel have more
  # information about this technique.
  module SSH
    # This is the set of options that Net::SSH.start recognizes. See
    # Net::SSH.start for a description of each option.
    VALID_OPTIONS = [
      :auth_methods, :compression, :compression_level, :config, :encryption,
      :forward_agent, :hmac, :host_key, :kex, :keys, :languages,
      :logger, :paranoid, :password, :port, :proxy, :rekey_blocks_limit,
      :rekey_limit, :rekey_packet_limit, :timeout, :verbose,
      :global_known_hosts_file, :user_known_hosts_file
    ]

    # The standard means of starting a new SSH connection. When used with a
    # block, the connection will be closed when the block terminates, otherwise
    # the connection will just be returned. The yielded (or returned) value
    # will be an instance of Net::SSH::Connection::Session (q.v.). (See also
    # Net::SSH::Connection::Channel and Net::SSH::Service::Forward.)
    #
    #   Net::SSH.start("host", "user") do |ssh|
    #     ssh.exec! "cp /some/file /another/location"
    #     hostname = ssh.exec!("hostname")
    #
    #     ssh.open_channel do |ch|
    #       ch.exec "sudo -p 'sudo password: ' ls" do |ch, success|
    #         abort "could not execute sudo ls" unless success
    #
    #         ch.on_data do |ch, data|
    #           print data
    #           if data =~ /sudo password: /
    #             ch.send_data("password\n")
    #           end
    #         end
    #       end
    #     end
    #
    #     ssh.loop
    #   end
    #
    # This method accepts the following options (all are optional):
    #
    # * :auth_methods => an array of authentication methods to try
    # * :compression => the compression algorithm to use, or +true+ to use
    #   whatever is supported.
    # * :compression_level => the compression level to use when sending data
    # * :config => set to +true+ to load the default OpenSSH config files
    #   (~/.ssh/config, /etc/ssh_config), or to +false+ to not load them, or to
    #   a file-name (or array of file-names) to load those specific configuration
    #   files. Defaults to +true+.
    # * :encryption => the encryption cipher (or ciphers) to use
    # * :forward_agent => set to true if you want the SSH agent connection to
    #   be forwarded
    # * :global_known_hosts_file => the location of the global known hosts
    #   file. Set to an array if you want to specify multiple global known
    #   hosts files. Defaults to %w(/etc/ssh/known_hosts /etc/ssh/known_hosts2).
    # * :hmac => the hmac algorithm (or algorithms) to use
    # * :host_key => the host key algorithm (or algorithms) to use
    # * :kex => the key exchange algorithm (or algorithms) to use
    # * :keys => an array of file names of private keys to use for publickey
    #   and hostbased authentication
    # * :logger => the logger instance to use when logging
    # * :paranoid => either true, false, or :very, specifying how strict
    #   host-key verification should be
    # * :password => the password to use to login
    # * :port => the port to use when connecting to the remote host
    # * :proxy => a proxy instance (see Proxy) to use when connecting
    # * :rekey_blocks_limit => the max number of blocks to process before rekeying
    # * :rekey_limit => the max number of bytes to process before rekeying
    # * :rekey_packet_limit => the max number of packets to process before rekeying
    # * :timeout => how long to wait for the initial connection to be made
    # * :user_known_hosts_file => the location of the user known hosts file.
    #   Set to an array to specify multiple user known hosts files.
    #   Defaults to %w(~/.ssh/known_hosts ~/.ssh/known_hosts2).
    # * :verbose => how verbose to be (Logger verbosity constants, Logger::DEBUG
    #   is very verbose, Logger::FATAL is all but silent). Logger::FATAL is the
    #   default.
    def self.start(host, user, options={}, &block)
      invalid_options = options.keys - VALID_OPTIONS
      if invalid_options.any?
        raise ArgumentError, "invalid option(s): #{invalid_options.join(', ')}"
      end

      files = case options.fetch(:config, true)
        when true then Net::SSH::Config.default_files
        when false, nil then []
        else Array(options[:config])
        end
      
      options = Net::SSH::Config.for(host, files).merge(options)

      if !options.key?(:logger)
        options[:logger] = Logger.new(STDERR)
        options[:logger].level = Logger::FATAL
      end

      options[:logger].level = options[:verbose] if options[:verbose]

      transport = Transport::Session.new(host, options)
      auth = Authentication::Session.new(transport, options)

      if auth.authenticate("ssh-connection", user, options[:password])
        connection = Connection::Session.new(transport, options)
        if block_given?
          yield connection
          connection.close
        else
          return connection
        end
      else
        raise AuthenticationFailed, user
      end
    end
  end
end