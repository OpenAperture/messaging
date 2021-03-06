#
# == subscription_handler.ex
#
# This module contains the GenServer for managing subscription callbacks
#
require Logger

defmodule OpenAperture.Messaging.AMQP.SubscriptionHandler do
	use GenServer
	use AMQP

  alias OpenAperture.Messaging.RpcRequest
  @moduledoc """
  This module contains the GenServer for managing subscription callbacks
  """

  @doc """
  Creation method for subscription handlers (sync and async)

  ## Options

  The `options` option provides the required AMQP subscription options.  The following options are required
  	* channel
  	* exchange
  	* queue
  	* callback_handler

  ## Return Values

  pid or rasies an error
  """
  @spec subscribe(map) :: pid
  def subscribe(options) do
    case GenServer.start_link(__MODULE__, options) do
    	{:ok, subscription_handler} ->
    		cond do
    			is_function(options[:callback_handler], 2) -> GenServer.call(subscription_handler, {:subscribe_sync})
    			is_function(options[:callback_handler], 3) -> GenServer.call(subscription_handler, {:subscribe_async})
    			true -> raise "[SubscriptionHandler] An error occurred creating synchronous SubscriptionHandler:  callback_handler is an unknown arity!"
    		end

    		subscription_handler
    	{:error, reason} -> raise "[SubscriptionHandler] An error occurred creating synchronous SubscriptionHandler:  #{inspect reason}"
    end
  end

  def process_request(subscription_handler, payload, meta) do
  	GenServer.call(subscription_handler, {:process_request, payload, meta})
  end

  @doc """
  Method to get the options from the handler server

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
  :ok
  """
  @spec get_subscription_options(pid) :: map
  def get_subscription_options(subscription_handler) do
  	GenServer.call(subscription_handler, {:get_subscription_options})
  end

  @doc """
  Method to acknowledge a message from via the handler server

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  The `delivery_tag` option defines the delivery tag of the messsage

  ## Return Value
  :ok
  """
  @spec acknowledge(pid, String.t) :: :ok
  def acknowledge(subscription_handler, delivery_tag) do
  	GenServer.call(subscription_handler, {:acknowledge, delivery_tag})
  end

  @doc """
  Method to acknowledge an RPC request from via the handler server

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  The `delivery_tag` option defines the delivery tag of the messsage

  The `api` option defines the ManagerApi that should be used for updates

  The `rpc_request` option represents the RpcRequest to be updated

  ## Return Value
  :ok
  """
  @spec acknowledge_rpc(pid, String.t, pid, RpcRequest.t) :: :ok
  def acknowledge_rpc(subscription_handler, delivery_tag, api, rpc_request) do
    case RpcRequest.save(api, rpc_request) do
      {:ok, _} -> Logger.debug("Successfully updated RPC request (acknowledging tag #{delivery_tag})")
      {:error, _} -> Logger.error("Failed to update RPC request (acknowledging tag #{delivery_tag})!")
    end

    GenServer.call(subscription_handler, {:acknowledge, delivery_tag})
  end

  @doc """
  Method to reject a message from via the handler server

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  The `delivery_tag` option defines the delivery tag of the messsage

  The `redeliver` option defines a boolean that can requeue a message

  ## Return Value
  :ok
  """
  @spec reject(pid, String.t, term) :: :ok
  def reject(subscription_handler, delivery_tag, redeliver \\ false) do
  	GenServer.call(subscription_handler, {:reject, delivery_tag, redeliver})
  end

  @doc """
  Method to reject an RPC request via the handler server

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  The `delivery_tag` option defines the delivery tag of the messsage

  The `api` option defines the ManagerApi that should be used for updates

  The `rpc_request` option represents the RpcRequest to be updated

  The `redeliver` option defines a boolean that can requeue a message

  ## Return Value
  :ok
  """
  @spec reject_rpc(pid, String.t, pid, RpcRequest.t, term) :: :ok
  def reject_rpc(subscription_handler, delivery_tag, api, rpc_request, redeliver \\ false) do
    case RpcRequest.save(api, rpc_request) do
      {:ok, _} -> Logger.debug("Successfully updated RPC request (rejecting tag #{delivery_tag})")
      {:error, _} -> Logger.error("Failed to update RPC request (rejecting tag #{delivery_tag})!")
    end

    GenServer.call(subscription_handler, {:reject, delivery_tag, redeliver})
  end

  @doc """
  Method to unsubscribe from a queue (tied to the SubscriptionHandler)

  ## Options

  The `subscription_handler` option defines the PID of the SubscriptionHandler

  ## Return Value
  :ok
  """
  @spec unsubscribe(pid) :: :ok
  def unsubscribe(subscription_handler) do
    GenServer.call(subscription_handler, {:unsubscribe})
  end

  @doc """
  Method to unsubscribe from a channel

  ## Options

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
      {:reply, :ok, state}
  """
  @spec handle_call({:unsubscribe}, term, map) :: {:reply, :ok, map}
  def handle_call({:unsubscribe}, _from, %{channel: channel, consumer_tag: consumer_tag} = state) do
    unless consumer_tag == nil do
      Basic.cancel(channel, consumer_tag)
    end
    state = Map.put(state, :consumer_tag, nil)
    {:reply, :ok, state}
  end

  @doc """
  Method to get options from the handler server

  ## Options

  The `options` option defines the new server state

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
  {:reply, state, state}
  """
  @spec handle_call({:get_subscription_options}, term, map) :: {:reply, :ok, map}
  def handle_call({:get_subscription_options}, _from, state) do
  	{:reply, state, state}
  end

  @doc """
  Method to set the options into the handler server

  ## Options

  The `options` option defines the new server state

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
  {:reply, state, state}
  """
  @spec handle_call({:set_subscription_options, map}, term, map) :: {:reply, map, map}
  def handle_call({:set_subscription_options, options}, _from, _state) do
    {:reply, options, options}
  end

  @doc """
  Method to subscribe to a queue (synchronously receive messages)

  ## Options

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
      {:reply, :ok, state}
  """
  @spec handle_call({:subscribe_sync}, term, map) :: {:reply, :ok, map}
  def handle_call({:subscribe_sync}, _from, %{channel: channel, exchange: exchange, queue: queue, callback_handler: _callback_handler} = state) do
  	Logger.debug("[SubscriptionHandler] Subscribing synchronously to queue #{queue.name}...")

    if exchange.auto_declare do
      Logger.debug("[SubscriptionHandler] Declaring exchange #{exchange.name}")
  	  Exchange.declare(channel, exchange.name, exchange.type, exchange.options)
    end

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
    if queue.auto_declare do
      Logger.debug("[SubscriptionHandler] Declaring queue #{queue.name}")
  	  Queue.declare(channel, queue.name, queue.options)
  	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)
    end

	  subscription_handler = self()
	  {:ok, consumer_tag} = Queue.subscribe(channel, queue.name, fn payload, meta ->
	    OpenAperture.Messaging.AMQP.SubscriptionHandler.process_request(subscription_handler, payload, meta)
	  end)

    state = Map.put(state, :consumer_tag, consumer_tag)
	  {:reply, :ok, state}
  end

  @doc """
  Method to subscribe to a queue (asynchronously receive messages)

  ## Options

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
  {:reply, :ok, state}
  """
  @spec handle_call({:subscribe_async}, term, map) :: {:reply, :ok, map}
  def handle_call({:subscribe_async}, _from, %{channel: channel, exchange: exchange, queue: queue, callback_handler: callback_handler} = state) do
  	Logger.debug("[SubscriptionHandler] Subscribing asynchronously queue #{queue.name}...")

    if exchange.auto_declare do
      Logger.debug("[SubscriptionHandler] Declaring exchange #{exchange.name}")
  	  Exchange.declare(channel, exchange.name, exchange.type, exchange.options)
    end

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
    if queue.auto_declare do
      Logger.debug("[SubscriptionHandler] Declaring queue #{queue.name}")
  	  Queue.declare(channel, queue.name, queue.options)
  	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)
    end

	  #link these processes together
	  subscription_handler = self()
	  request_handler_pid = spawn_link fn ->
	  	Logger.debug("[SubscriptionHandler] Attempting to establish connection (subscription handler #{inspect subscription_handler}, child #{inspect self()})...")
	  	start_async_handler(channel, callback_handler, subscription_handler)
	  end

	  try do
	  	Logger.debug("[SubscriptionHandler] Attempting to register connection #{inspect request_handler_pid} with the AMQP client...")
    	{:ok, consumer_tag} = Basic.consume(channel, queue.name, request_handler_pid, [])
      state = Map.put(state, :consumer_tag, consumer_tag)
    	Logger.debug("[SubscriptionHandler] Successfully registered connection #{inspect request_handler_pid} with the AMQP client")
      {:reply, :ok, state}
	  rescue e ->
	  	Logger.error("[SubscriptionHandler] An exception occurred registering connection #{inspect request_handler_pid} with the AMQP client:  #{inspect e}")
      {:reply, :ok, state}
	  end
  end

  @doc """
  Method to process a message

  ## Options

  The `payload` option represents raw payload of the message

  The `meta` option represents the metadata associated with the message

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
      {:reply, :ok, state}
  """
  @spec handle_call({:process_request, map, map}, term, map) :: {:reply, :ok, map}
  def handle_call({:process_request, payload, meta}, _from, state) do
    execute_callback_handler(state, self(), payload, meta)
    {:reply, :ok, state}
  end

  @doc """
  Method to execute acknowledge a message, based on delivery tag

  ## Options

  The `delivery_tag` option defines the delivery tag of the messsage

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
  {:reply, :ok, state}
  """
  @spec handle_call({:acknowledge, String.t}, term, map) :: {:reply, :ok, map}
  def handle_call({:acknowledge, delivery_tag}, _from, state) do
    Logger.debug("[SubscriptionHandler] Acknowledging message #{delivery_tag} on channel #{inspect state[:channel]}")
    Basic.ack(state[:channel], delivery_tag)
    {:reply, :ok, state}
  end

  @doc """
  Method to execute reject a message, based on delivery tag

  ## Options

  The `delivery_tag` option defines the delivery tag of the messsage

  The `redeliver` option defines a boolean that can requeue a message

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Value
      {:reply, :ok, state}
  """
  @spec handle_call({:reject, String.t, term}, term, map) :: {:reply, :ok, map}
  def handle_call({:reject, delivery_tag, redeliver}, _from, state) do
    Logger.debug("[SubscriptionHandler] Rejecting message #{delivery_tag} on channel #{inspect state[:channel]}")
    Basic.reject(state[:channel], delivery_tag, requeue: redeliver)
    {:reply, :ok, state}
  end

  @doc """
  Method to execute the associated callback handler (either async or sync)

  ## Options

  The `subscription_handler_options` option defines the options associated with the SubscriptionHandler that will be used to process the message

  The `subscription_handler` option defines the PID of the SubscriptionHandler that will be used to process the message

  The `payload` option represents raw payload of the message

  The `meta` option represents the metadata associated with the message
  """
  @spec execute_callback_handler(map, pid, term, map) :: term
  def execute_callback_handler(subscription_handler_options, subscription_handler, payload, %{delivery_tag: delivery_tag, redelivered: redelivered} = meta) do
  	case deserialize_payload(payload, delivery_tag) do
  		{false, _} ->
  			Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: false)
  		{true, deserialized_payload} ->
	  		cond do
          #sync
	  			is_function(subscription_handler_options[:callback_handler], 2) ->
				    try do
							subscription_handler_options[:callback_handler].(deserialized_payload, meta)
				    rescue exception ->
				      if subscription_handler_options[:queue].requeue_on_error == true && redelivered == false do
				        Logger.debug("[SubscriptionHandler] An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}.  Requeueing message...")
				        Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: not redelivered)
				      else
				        Logger.error("[SubscriptionHandler] An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}")
				        #let AMQP.Queue fail the message
				        stacktrace = System.stacktrace
				        reraise exception, stacktrace
				      end
				    end
          #async
	  			is_function(subscription_handler_options[:callback_handler], 3) ->
	  				spawn fn ->
					    try do
								subscription_handler_options[:callback_handler].(deserialized_payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag})
					    rescue exception ->
					      if subscription_handler_options[:queue].requeue_on_error == true && redelivered == false do
					        Logger.debug("[SubscriptionHandler] An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}.  Requeueing message...")
					        Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: not redelivered)
					      else
					        Logger.error("[SubscriptionHandler] An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}")
					        #let AMQP.Queue fail the message
					        stacktrace = System.stacktrace
					        reraise exception, stacktrace
					      end
					    end
	  				end
	  			true ->
	  				Logger.error("[SubscriptionHandler] An error occurred processing request #{inspect delivery_tag}:  callback_handler is an unknown arity!")
	  				Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: true)
	  		end
  	end
	end

  @doc """
  Method to deserialize the request payload

  ## Options

  The `payload` option represents raw payload of the message

  The `delivery_tag` option represents the identifier of the message

  ## Return Value

  {deserialization success/failure, payload}

  """
  @spec deserialize_payload(String.t, term) :: term
	def deserialize_payload(payload, delivery_tag) do
  	try do
    	{true, deserialize(payload)}
    rescue exception ->
      Logger.debug("[SubscriptionHandler] An error occurred deserializing the payload for request #{inspect delivery_tag}:  #{inspect exception}\n\n#{inspect payload}")
      {false, nil}
    end
	end

  @doc """
  Method to establish a connection to the AMQP client.  Once you've received confirmation (:basic_consume_ok),
  you'll start to receive messages

  ## Options

  The `channel_id` option represents the ID of the AMQP channel

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 or 3 arguments.

  The `subscription_handler` option defines the PID of the SubscriptionHandler that will be used to process the message

  """
  @spec start_async_handler(String.t, term, pid) :: term
  def start_async_handler(channel, callback_handler, subscription_handler) do
  	Logger.debug("[SubscriptionHandler] Waiting to establish connection...")
		receive do
      {:basic_consume_ok, %{consumer_tag: _consumer_tag}} ->
      	Logger.debug("[SubscriptionHandler] Successfully established connection to the broker!  Waiting for messages...")
      	process_async_request(channel, callback_handler, subscription_handler)
      other ->
      	Logger.error("[SubscriptionHandler] Failed to established connection to the broker:  #{inspect other}")
    end
  end

  @doc """
  Method to process messages from the AMQP client, and execute the corresponding callback_handler

  ## Options

  The `channel_id` option represents the ID of the AMQP channel

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 or 3 arguments.

  The `subscription_handler` option defines the PID of the SubscriptionHandler that will be used to process the message

  """
  @spec process_async_request(String.t, term, pid) :: term
  def process_async_request(channel, callback_handler, subscription_handler) do
    receive do
      {:basic_deliver, payload, meta} ->
      	subscription_handler_options = OpenAperture.Messaging.AMQP.SubscriptionHandler.get_subscription_options(subscription_handler)
      	execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
        process_async_request(channel, callback_handler, subscription_handler)
      {:basic_cancel, %{no_wait: _}} ->
        exit(:basic_cancel)
      {:basic_cancel_ok, %{}} ->
        exit(:normal)
    end
  end

  @doc """
  Method to serialize an object going to the AMQP callback handler

  ## Options

  The `term` option defines the term to serialize

  ## Return Value

  term
  """
  @spec serilalize(term) :: binary
  def serilalize(term) do
    :erlang.term_to_binary(term)
  end

  @doc """
  Method to deserialize an object from the AMQP callback handler

  ## Options

  The `binary` option defines the term to deserialize

  ## Return Value

  term
  """
  @spec deserialize(binary) :: term
  def deserialize(binary) do
    :erlang.binary_to_term(binary)
  end
end