#
# == cloudos_messaging.ex
#
# This module contains definition the CloudOS Messaging implementation
#
defmodule CloudOS.Messaging do
  use Application

  @moduledoc """
  This module contains definition the CloudOS Messaging implementation
  """  

  @doc """
  Starts the given `_type`.

  If the `_type` is not loaded, the application will first be loaded using `load/1`.
  Any included application, defined in the `:included_applications` key of the
  `.app` file will also be loaded, but they won't be started.

  Furthermore, all applications listed in the `:applications` key must be explicitly
  started before this application is. If not, `{:error, {:not_started, app}}` is
  returned, where `_type` is the name of the missing application.

  In case you want to automatically  load **and start** all of `_type`'s dependencies,
  see `ensure_all_started/2`.

  The `type` argument specifies the type of the application:

    * `:permanent` - if `_type` terminates, all other applications and the entire
      node are also terminated.

    * `:transient` - if `_type` terminates with `:normal` reason, it is reported
      but no other applications are terminated. If a transient application
      terminates abnormally, all other applications and the entire node are
      also terminated.

    * `:temporary` - if `_type` terminates, it is reported but no other
      applications are terminated (the default).

  Note that it is always possible to stop an application explicitly by calling
  `stop/1`. Regardless of the type of the application, no other applications will
  be affected.

  Note also that the `:transient` type is of little practical use, since when a
  supervision tree terminates, the reason is set to `:shutdown`, not `:normal`.
  """
  @spec start(atom, [any]) :: :ok | {:error, String.t()}
  def start(_type, _args) do
    CloudOS.Messaging.AMQP.ConnectionSupervisor.start_link
  end

	defmacro __using__(_) do
    quote do
    	require Logger
    	use AMQP

      alias AMQP.Connection
      alias AMQP.Channel
      alias AMQP.Exchange
      alias AMQP.Queue
      alias AMQP.Basic
      alias AMQP.Confirm

      alias CloudOS.Messaging.ConnectionOptions
      alias CloudOS.Messaging.Queue
      alias CloudOS.Messaging.AMQP.ConnectionPools
			alias CloudOS.Messaging.AMQP.ConnectionPool
			alias CloudOS.Messaging.AMQP.AMQPOptions

		  @doc """
		  Subscribes to a specific queue within the Messaging system

		  ## Options

		  The `connection_options` options value provides the ConnectionOptions; defaults to the @connection_options attribute

		  The `queue` options value provides the Queue to which to subscribe

  		The `callback_handler` option represents the method that should be called when a message is received.  The handler
  		should be a function with 2 arguments.

		  ## Returns

		  :ok | {:error, reason}
		  """
		  @spec subscribe(term, term, term) :: :ok | {:error, String.t()} 
			def subscribe(connection_options \\ @connection_options, queue, callback_handler) when is_function(callback_handler, 2) do
				case ConnectionOptions.type(connection_options) do
					nil -> {:error, "The queue does not have a type defined!"}
					:amqp ->
						Logger.debug("Retrieving connection pool for #{connection_options.host}...")
						connection_pool = ConnectionPools.get_pool(ConnectionOptions.get(connection_options))
						if connection_pool == nil do
							{:error, "Failed to retrieve a connection pool for #{connection_options.host}!"}
						else
							Logger.debug("Subscribing to connection pool  #{connection_options.host}...")
							ConnectionPool.subscribe(connection_pool, queue.exchange, queue, callback_handler)						
						end
					_ -> {:error, "Queue type #{inspect queue.type} is unknown!"}
				end
			end

		  @doc """
		  Publishes a message/payload to a specific queue within the Messaging system

		  ## Options

		  The `connection_options` options value provides the ConnectionOptions; defaults to the @connection_options attribute

		  The `queue` options value provides the Queue to which to subscribe

  		The `payload` option represents the message data

		  ## Returns
		  
		  :ok | {:error, reason}
		  """
		  @spec subscribe(term, term, term) :: :ok | {:error, String.t()} 
		  def publish(connection_options \\ @connection_options, queue, payload) do
				case ConnectionOptions.type(connection_options) do
					nil -> {:error, "The queue does not have a type defined!"}
					:amqp ->
						Logger.debug("Retrieving connection pool for #{connection_options.host}...")
						connection_pool = ConnectionPools.get_pool(ConnectionOptions.get(connection_options))
						if connection_pool == nil do
							{:error, "Failed to retrieve a connection pool for #{connection_options.host}!"}
						else						
							Logger.debug("Publishing to connection pool  #{connection_options.host}...")
							ConnectionPool.publish(connection_pool, queue.exchange, queue, payload)						
						end
					_ -> {:error, "Queue type #{inspect queue.type} is unknown!"}
				end
		  end		
    end
  end
end