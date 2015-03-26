#
# == subscription_handler.ex
#
# This module contains the GenServer for managing subscription callbacks
#
require Logger

defmodule CloudOS.Messaging.AMQP.SubscriptionHandler do
	use GenServer
	use AMQP

  alias CloudOS.Messaging.ConnectionOptions
  alias CloudOS.Messaging.AMQP.ConnectionPools
  alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

  @doc """
  Creation method for subscription handlers

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
  	Logger.debug("Subscribing synchronously to exchange #{exchange.name}, queue #{queue.name}...")

  	Exchange.declare(channel, exchange.name, exchange.type, exchange.options)

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
	  Queue.declare(channel, queue.name, queue.options)

	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)

	  subscription_handler = self()
	  Queue.subscribe(channel, queue.name, fn payload, meta ->
	    CloudOS.Messaging.AMQP.SubscriptionHandler.process_request(subscription_handler, payload, meta)
	  end)

	  {:reply, :ok, state}
  end

  def handle_call({:subscribe_async}, _from, %{channel: channel, exchange: exchange, queue: queue, callback_handler: callback_handler} = state) do
  	Logger.debug("Subscribing asynchronously to exchange #{exchange.name}, queue #{queue.name}...")

  	Exchange.declare(channel, exchange.name, exchange.type, exchange.options)

	  # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
	  Queue.declare(channel, queue.name, queue.options)

	  Queue.bind(channel, queue.name, exchange.name, queue.binding_options)

	  #link these processes together
	  subscription_handler = self()
	  request_handler_pid = spawn_link fn -> 
	  	Logger.debug("Attempting to establish connection (subscription handler #{inspect subscription_handler}, child #{inspect self()})...")
	  	start_async_handler(channel, callback_handler, subscription_handler) 
	  end

	  try do
	  	Logger.debug("Attempting to register connection #{inspect request_handler_pid} with the AMQP client...")
    	Basic.consume(channel, queue.name, request_handler_pid)
    	Logger.debug("Successfully registered connection #{inspect request_handler_pid} with the AMQP client")
	  rescue e ->
	  	Logger.error("An exception occurred registering connection #{inspect request_handler_pid} with the AMQP client:  #{inspect e}")
	  end

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
  	case deserialize_payload(payload, delivery_tag, subscription_handler_options) do
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
				        Logger.debug("An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}.  Requeueing message...")
				        Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: not redelivered)
				      else
				        Logger.error("An error occurred processing request #{inspect delivery_tag}:  #{inspect exception}")
				        #let AMQP.Queue fail the message
				        stacktrace = System.stacktrace
				        reraise exception, stacktrace
				      end
				    end
          #async
	  			is_function(subscription_handler_options[:callback_handler], 3) -> 
	  				spawn_link fn -> 
					    try do
								subscription_handler_options[:callback_handler].(deserialized_payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag})
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
	  			true -> 
	  				Logger.error("An error occurred processing request #{inspect delivery_tag}:  callback_handler is an unknown arity!")
	  				Basic.reject(subscription_handler_options[:channel], delivery_tag, requeue: true)
	  		end
  	end
	end

  @doc """
  Method to deserialize the request payload

  ## Options
  
  The `payload` option represents raw payload of the message

  The `delivery_tag` option represents the identifier of the message  

  The `subscription_handler_options` option represents the options of the SubscriptionHandler associated with the request

  ## Return Value

  {deserialization success/failure, payload}

  """
  @spec deserialize_payload(String.t(), term, term) :: term  
	def deserialize_payload(payload, delivery_tag, subscription_handler_options) do
  	try do
    	{true, deserialize(payload)}
    rescue exception ->
      Logger.debug("An error occurred deserializing the payload for request #{inspect delivery_tag}:  #{inspect exception}\n\n#{inspect payload}")
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
  @spec start_async_handler(String.t(), term, term) :: term  
  def start_async_handler(channel, callback_handler, subscription_handler) do
  	Logger.debug("Waiting to establish connection...")
		receive do
      {:basic_consume_ok, %{consumer_tag: consumer_tag}} -> 
      	Logger.debug("Successfully established connection to the broker!  Waiting for messages...")
      	process_async_request(channel, callback_handler, subscription_handler)
      other ->
      	Logger.error("Failed to established connection to the broker:  #{inspect other}")
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
  @spec process_async_request(String.t(), term, term) :: term
  def process_async_request(channel, callback_handler, subscription_handler) do
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