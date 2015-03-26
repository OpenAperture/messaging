#
# == connection_pools.ex
#
# This module contains the GenServer for managing getting ConnectionPools
#
require Logger

defmodule CloudOS.Messaging.AMQP.SubscriptionHandler do
	use GenServer
	use AMQP

  alias CloudOS.Messaging.ConnectionOptions
  alias CloudOS.Messaging.AMQP.ConnectionPools
  alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

  @doc """
  Creation method for synchronous request handling

  ## Options

  The `options` option provides the required AMQP subscription options.  The following options are required
  	* channel
  	* exchange
  	* queue
  	* callback_handler

  ## Return Values

  pid or rasies an error
  """
  @spec subscribe(Map) :: pid
  def subscribe(options) do
    case GenServer.start_link(__MODULE__, options) do
    	{:ok, subscription_handler} -> 
    		cond do
    			is_function(options[:callback_handler], 2) -> GenServer.call(subscription_handler, {:subscribe_sync})
    			is_function(options[:callback_handler], 3) -> GenServer.call(subscription_handler, {:subscribe_async})
    			true -> raise "An error occurred creating synchronous SubscriptionHandler:  callback_handler is an unknown arity!"
    		end

    		subscription_handler
    	{:error, reason} -> raise "An error occurred creating synchronous SubscriptionHandler:  #{inspect reason}"
    end
  end

  def process_request(subscription_handler, payload, meta) do
  	GenServer.call(subscription_handler, {:process_request, payload, meta})
  end

  def get_subscription_options(subscription_handler) do
  	GenServer.call(subscription_handler, {:get_subscription_options})
  end

  def acknowledge(subscription_handler, delivery_tag) do
  	GenServer.call(subscription_handler, {:acknowledge, delivery_tag})
  end

  def reject(subscription_handler, delivery_tag, redeliver \\ false) do
  	GenServer.call(subscription_handler, {:reject, delivery_tag, redeliver})
  end

  def handle_call({:get_subscription_options}, _from, state) do
  	{:reply, state, state}
  end

  def handle_call({:subscribe_sync}, _from, %{channel: channel, exchange: exchange, queue: queue, callback_handler: callback_handler} = state) do
  	Exchange.declare(channel, exchange.name, exchange.type, exchange.options)

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
	  Queue.declare(channel, queue.name, queue.options)

	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)

	  Queue.subscribe(channel, queue.name, fn payload, meta ->
	    SubscriptionHandler.process_request(self(), payload, meta)
	  end)

	  {:reply, :ok, state}
  end

  def handle_call({:subscribe_async}, _from, %{channel: channel, exchange: exchange, queue: queue, callback_handler: callback_handler} = state) do
  	Exchange.declare(channel, exchange.name, exchange.type, exchange.options)

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
	  Queue.declare(channel, queue.name, queue.options)

	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)

	  #link these processes together
	  request_handler_pid = spawn_link fn -> start_async_handler(channel, callback_handler, self()) end
    Basic.consume(channel, queue)

	  {:reply, :ok, state}
  end

  def handle_call({:process_request, payload, meta}, _from, state) do
    execute_callback_handler(state, self(), payload, meta)
    {:reply, :ok, state}
  end

  def handle_call({:acknowledge, delivery_tag}, _from, state) do
    Basic.ack(state[:channel], delivery_tag)
    {:reply, :ok, state}
  end

  def handle_call({:reject, delivery_tag, redeliver}, _from, state) do
    Basic.reject(state[:channel], delivery_tag, requeue: redeliver)
    {:reply, :ok, state}
  end

  defp execute_callback_handler(subscription_handler_options, subscription_handler, payload, %{delivery_tag: delivery_tag, redelivered: redelivered} = meta) do
    try do
      deserialized_payload = deserialize(payload)
  		cond do
  			is_function(subscription_handler_options[:callback_handler], 2) -> 
  				subscription_handler_options[:callback_handler].(deserialized_payload, meta)
  			is_function(subscription_handler_options[:callback_handler], 3) -> 
  				subscription_handler_options[:callback_handler].(deserialized_payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag})
  			true -> raise "callback_handler is an unknown arity!"
  		end
    rescue exception ->
      if subscription_handler_options[:queue].requeue_on_error == true && redelivered == false do
        Logger.debug("An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}.  Requeueing message...")
        Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: not redelivered)
      else
        Logger.error("An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}")
        #let AMQP.Queue fail the message
        stacktrace = System.stacktrace
        reraise exception, stacktrace
      end
    end
	end

  # once the queue is registered, it sends a basic_consume_ok.  Once you receive that, 
  # you can wait for requests to come in
  def start_async_handler(channel, callback_handler, subscription_handler) do
		receive do
      {:basic_consume_ok, %{consumer_tag: consumer_tag}} -> process_async_request(channel, callback_handler, subscription_handler)
    end
  end

  # async handler started, wait for messages
  defp process_async_request(channel, callback_handler, subscription_handler) do
    receive do
      {:basic_deliver, payload, meta} -> 
      	subscription_handler_options = CloudOS.Messaging.AMQP.SubscriptionHandler.get_subscription_options(subscription_handler)
      	execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
        process_async_request(channel, callback_handler, subscription_handler)
      {:basic_cancel, %{no_wait: _}} ->
        exit(:basic_cancel)
      {:basic_cancel_ok, %{}} ->
        exit(:normal)
    end  	
  end

  @doc """
  Proxies to :erlang.term_to_binary

  ## Accepts:
  * term — a single data structure of any type

  ## Returns
  binary
  """
  @spec deserialize(term) :: binary
  def serilalize(term) do
    :erlang.term_to_binary(term)
  end

  @doc """
  Proxies to :erlang.term_to_binary

  ## Accepts:
  * binary

  ## Returns
  * term
  """
  @spec deserialize(binary) :: term
  def deserialize(binary) do
    :erlang.binary_to_term(binary)
  end   
end