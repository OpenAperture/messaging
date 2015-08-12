#
# == connection_pool.ex
#
# This module contains the GenServer for a specific connection pool, which manages
# all connections to the AMQP host.  This class also provides reconnection logic in the event
# the connection or channel dies
#
require Logger

defmodule OpenAperture.Messaging.AMQP.ConnectionPool do
  use GenServer
	use AMQP

  alias OpenAperture.Messaging.AMQP.ConnectionPools
  alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler
  alias OpenAperture.Messaging.Queue

  @moduledoc """
  This module contains the GenServer for a specific connection pool, which manages all connections to the AMQP host
  """  

  ## Consumer Methods

  @doc """
  Specific start_link implementation

  ## Options

  The `connection_options` option representings the AMQP connection options required to connect to the host

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(Keyword.t) :: {:ok, pid} | {:error, String.t}	
  def start_link(connection_options) do
    # 1. create event manager as argument
    case GenEvent.start_link do
      {:ok, event_manager} -> 
        Logger.debug("[ConnectionPool] GenEvent start was successful, starting...")
        case GenServer.start_link(__MODULE__, event_manager, []) do
          {:ok, pool} -> 
            __MODULE__.set_connection_options(pool, connection_options)
            {:ok, pool}
          {:error, reason} -> {:error, "[ConnectionPool] Failed to create ConnectionPool: #{inspect reason}"}
        end

      {:error, reason} -> {:error, "[ConnectionPool] Failed to create ConnectionPool: #{inspect reason}"}
    end
  end

  @doc """
  Method to set the connection options into the GenServer.  This should be a Keyword List

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `connection_options` option represents the AMQP connection options required to connect to the host

  ## Return Values

  :ok | {:error, reason}
  """
  @spec set_connection_options(pid, Keyword.t) :: :ok | {:error, String.t}
  def set_connection_options(connection_pool, connection_options) do
    GenServer.call(connection_pool, {:set_connection_options, connection_options})
  end

  @doc """
  Method to subscribe to a queue and provide a callback handler

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `exchange` option represents the AMQP exchange

  The `queue_name` option represents the AMQP queue

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 arguments (sync) or 3 arguments (async).

  ## Return Values

  {:ok, subscription_handler} | {:error, reason}
  """
  @spec subscribe(pid, AMQPExchange.t, Queue.t, term) :: {:ok, term} | {:error, String.t}
  def subscribe(connection_pool, exchange, queue, callback_handler) do
    GenServer.call(connection_pool, {:subscribe, exchange, queue, callback_handler})
  end

  @doc """
  Method to subscribe to a queue and provide a callback handler

  ## Options

  The `subscription_handler` option represents the PID of the SubscriptionHandler

  ## Return Values

  :ok | {:error, reason}
  """
  @spec unsubscribe(pid, pid) :: :ok | {:error, String.t}
  def unsubscribe(connection_pool, subscription_handler) do
    GenServer.call(connection_pool, {:unsubscribe, subscription_handler})
  end

  @doc """
  Method to public a message onto to a queue

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `exchange` option represents the AMQP exchange

  The `queue_name` option represents the AMQP queue

  The `payload` option represents the message data

  ## Return Values

  :ok | {:error, reason}
  """
  @spec publish(pid, AMQPExchange.t, Queue.t, term) :: :ok | {:error, String.t}
  def publish(connection_pool, exchange, queue, payload) do
    GenServer.call(connection_pool, {:publish, exchange, queue, payload})    
  end

  @doc """
  Method to close all subscriptions, channels, and connections associated with this ConnectionPool

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  ## Return Values

  :ok | {:error, reason}
  """
  @spec close(pid) :: :ok | {:error, String.t}
  def close(connection_pool) do
    GenServer.call(connection_pool, {:prepare_close})
    GenServer.call(connection_pool, {:close})
  end

  ## Server callbacks

  @doc """
  GenServer callback - invoked when the server is started.

  ## Options

  The `args` option represents the args to the GenServer.  In this case, we're expecting
  this to be the GenEvent server, generated during start_link

  ## Return Values

  {:ok, state}
  """  
  @spec init(term) :: {:ok, map}
  def init(args) do
    # 2. The init callback now receives the event manager.
    #    We have also changed the manager state from a tuple
    #    to a map, allowing us to add new fields in the future
    #    without needing to rewrite all callbacks.
    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    {:ok, %{
      events: args,
      connection_options: [],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info
    }}
  end  

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:set_connection_options, ...} messages;
  this callback will store the connection options into the server's state.

  ## Options

  The `connection_options` option contains the AMQP conection options

  ## Return Values

  {:reply, reply, new_state}
  """  
  @spec handle_call({:set_connection_options, Keyword.t}, term, term) :: {:reply, term, term}
  def handle_call({:set_connection_options, connection_options}, _from, state) do
    if connection_options != nil && connection_options[:max_connection_cnt] != nil do
      max_connection_cnt = connection_options[:max_connection_cnt]
    else
      max_connection_cnt = 1
    end

    state = Map.put(state, :connection_options, connection_options)
    state = Map.put(state, :max_connection_cnt, max_connection_cnt)
    {:reply, connection_options, state}
  end

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:publish, ...} messages;
  this callback will store the connection options into the server's state.

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `exchange` option represents the AMQP exchange

  The `queue` option represents the AMQP queue

  The `payload` option represents the message data

  ## Return Values

  {:reply, reply, new_state}
  """  
  @spec handle_call({:publish, AMQPExchange.t, Queue.t, term}, term, term) :: {:reply, term, term}
  def handle_call({:publish, exchange, queue, payload}, _from, state) do
    try do
      if state[:failover_connection_pool] != nil do
        {:reply, :ok, publish_to_failover(state, exchange, queue, payload)}
      else
        case get_channel(state) do
          {nil, resolved_state} -> 
            #get_channel can create the failover connection pool
            if resolved_state[:failover_connection_pool] != nil do
              {:reply, :ok, publish_to_failover(resolved_state, exchange, queue, payload)}
            else
              {:reply, {:error, "[ConnectionPool] Unable to publish to queue on the AMQP broker because no channel was found"}, resolved_state}        
            end
          {channel_id, resolved_state} ->
            channel = resolved_state[:channels_info][:channels][channel_id]
            Logger.debug("[ConnectionPool] Publishing message to exchange #{exchange.root_exchange_name}, route #{exchange.routing_key}.#{queue.name}")
            Basic.publish(channel, exchange.root_exchange_name, "#{exchange.routing_key}.#{queue.name}", serilalize(payload), [persistent: true])
            {:reply, :ok, resolved_state}
        end
      end
    rescue e in RuntimeError ->
      reason = "[ConnectionPool] Failed to publish a msg to RabbitMQ: #{inspect e}"
      Logger.error(reason)
      {:reply, {:error, reason}, state}
    end
  end

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:unsubscribe, ...} messages;
  this callback will unsubsribe a consumer from a queue (associated with the SubscriptionHandler)

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `subscription_handler` option represents the AMQP SubscriptionHandler

  ## Return Values

  {:reply, :ok | {:error, reason}, new_state}
  """  
  @spec handle_call({:unsubscribe, pid}, term, map) :: {:reply, term, term}
  def handle_call({:unsubscribe, subscription_handler}, _from, state) do
    Logger.debug("[ConnectionPool] Unsubscribing...")
    if state[:failover_connection_pool] != nil do
      {:reply, :ok, unsubscribe_from_failover(state, subscription_handler)}
    else
      subscription_options = SubscriptionHandler.get_subscription_options(subscription_handler)
      subscription_channel_id = subscription_options[:channel_id]

      queues_for_channel = state[:channels_info][:queues_for_channel][subscription_channel_id]
      queues_for_channel = unless queues_for_channel == nil do
        List.delete(queues_for_channel, subscription_handler)
      else
        queues_for_channel
      end

      queues = Map.put(state[:channels_info][:queues_for_channel], subscription_channel_id, queues_for_channel)
      channels_info = Map.put(state[:channels_info], :queues_for_channel, queues)
      resolved_state = Map.put(state, :channels_info, channels_info)

      SubscriptionHandler.unsubscribe(subscription_handler)

      {:reply, :ok, resolved_state}
    end
  end

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:prepare_close, ...} messages;
  this callback will set the server state to "closed", so that all connections and channels
  can be closed without restarting

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  ## Return Values

  {:reply, :ok, new_state}
  """  
  @spec handle_call({:prepare_close}, term, map) :: {:reply, term, term}
  def handle_call({:prepare_close}, _from, state) do
    Logger.debug("[ConnectionPool] Closing all channels and connections...")
    {:reply, :ok, Map.put(state, :closed, true)}
  end

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:prepare_close, ...} messages;
  this callback will close all subscriptions, channels and connections

  ## Options

  ## Return Values

  {:reply, :ok, new_state}
  """  
  @spec handle_call({:close}, term, map) :: {:reply, term, term}
  def handle_call({:close}, _from, state) do
    Logger.debug("[ConnectionPool] Closing ConnectionPool...")

    Logger.debug("[ConnectionPool] Stopping GenEvent server...")
    try do
      GenEvent.stop(state[:events])
    rescue e ->
      Logger.error("[ConnectionPool] An error occurred stopping GenEvent server: #{inspect e}")
    end

    Logger.debug("[ConnectionPool] Closing all subscriptions...")
    channels_subscriptions = Map.values(state[:channels_info][:queues_for_channel])
    unless length(channels_subscriptions) == 0 do
      Enum.reduce channels_subscriptions, nil, fn(queue_subscriptions, _result) ->
        unless queue_subscriptions == nil || length(queue_subscriptions) == 0 do
          Enum.reduce queue_subscriptions, nil, fn(subscription_handler, _result) ->
            try do
              SubscriptionHandler.unsubscribe(subscription_handler)
            rescue e ->
              Logger.error("[ConnectionPool] An error occurred unsubscribing from queue:  #{inspect e}")
            end
          end
        end
      end
    end
    
    Logger.debug("[ConnectionPool] Closing all channels...")
    channels = Map.values(state[:channels_info][:channels])
    unless length(channels) == 0 do
      Enum.reduce channels, nil, fn(channel, _result) ->
        try do
          Channel.close(channel)
        rescue e ->
          Logger.error("[ConnectionPool] An error occurred closing channel:  #{inspect e}")
        end          
      end
    end

    Logger.debug("[ConnectionPool] Closing all connections...")
    connections = Map.values(state[:connections_info][:connections])
    unless length(connections) == 0 do
      Enum.reduce connections, nil, fn(connection, _result) ->
        try do
          Connection.close(connection)
        rescue e ->
          Logger.error("[ConnectionPool] An error occurred closing connection:  #{inspect e}")
        end          
      end
    end

    event_manager = case GenEvent.start_link do
      {:ok, event_manager} -> 
        Logger.debug("[ConnectionPool] GenEvent server restart was successful")
        event_manager
      {:error, reason} -> 
        Logger.error("[ConnectionPool] Failed to start GenEvent server:  #{inspect reason}")
        nil
    end

    #reset the server state
    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }

    resolved_state =  %{
      events: event_manager,
      connection_options: [],
      max_connection_cnt: state[:max_connection_cnt],
      connections_info: connections_info, 
      channels_info: channels_info
    }

    {:reply, :ok, resolved_state}
  end

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:subscribe, ...} messages;
  this callback will store the connection options into the server's state.

  ## Options

  The `connection_pool` option represents the PID of the GenServer

  The `exchange` option represents the AMQP exchange

  The `queue` option represents the AMQP queue

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 arguments.

  ## Return Values

  {:reply, {:ok, subscription_handler} | {:error, reason}, new_state}
  """  
  @spec handle_call({:subscribe, AMQPExchange.t, Queue.t, term}, term, term) :: {:reply, term, term}
  def handle_call({:subscribe, exchange, queue, callback_handler}, _from, state) do
    Logger.debug("[ConnectionPool] Subscribing to exchange #{exchange.name}, queue #{queue.name}...")
    if state[:failover_connection_pool] != nil do
      {:reply, :ok, subscribe_to_failover(state, exchange, queue, callback_handler)}
    else
      case get_channel(state) do
        {nil, resolved_state} -> 
          #get_channel can create the failover connection pool
          if resolved_state[:failover_connection_pool] != nil do
            {:reply, :ok, subscribe_to_failover(resolved_state, exchange, queue, callback_handler)}
          else
             {:reply, {:error, "[ConnectionPool] Unable to subsribe to queue on the AMQP broker because no channel was found"}, resolved_state}        
          end
        {channel_id, resolved_state} ->
          Logger.debug("[ConnectionPool] Using channel #{channel_id}...")
          {resolved_state, subscription_handler} = subscribe_to_queue(resolved_state, channel_id, exchange, queue, callback_handler)
          {:reply, {:ok, subscription_handler}, resolved_state}
      end
    end
  end  

  @doc false
  # Method to publish to the failover connection pool
  #
  ## Options
  # The `exchange` option represents the AMQP exchange
  #
  # The `queue` option represents the AMQP queue
  #
  # The `payload` option represents the message data
  #
  ## Return Value
  #
  # updated state
  #
  @spec publish_to_failover(term, AMQPExchange.t, Queue.t, term) :: term
  defp publish_to_failover(state, exchange, queue, payload) do    
    Logger.debug("[ConnectionPool] Rerouting publishing request to failover connection pool...")
    publish(state[:failover_connection_pool], AMQPExchange.get_failover(exchange), queue, payload)
    state
  end

  @doc false
  # Method to subscribe to the failover connection pool
  #
  ## Options
  #
  # The `state` option represents the server state
  # 
  # The `exchange` option represents the AMQP exchange
  #
  # The `queue` option represents the AMQP queue
  #
  # The `callback_handler` option represents the method that should be called when a message is received.  The handler
  # should be a function with 2 arguments.
  #
  ## Return Value
  #
  # updated state
  #
  @spec subscribe_to_failover(term, AMQPExchange.t, Queue.t, term) :: term
  defp subscribe_to_failover(state, exchange, queue, callback_handler) do    
    Logger.debug("[ConnectionPool] Rerouting subscribe request to failover connection pool...")
    subscribe(state[:failover_connection_pool], AMQPExchange.get_failover(exchange), queue, callback_handler)
    state
  end

  @doc false
  # Method to unsubscribe from the failover connection pool
  #
  ## Options
  # The `state` option represents the server state
  #
  # The `subscription_handler` option represents the AMQP SubscriptionHandler
  #
  ## Return Value
  #
  # updated state
  #
  @spec unsubscribe_from_failover(term, pid) :: term
  defp unsubscribe_from_failover(state, subscription_handler) do    
    Logger.debug("[ConnectionPool] Rerouting unsubscribe request to failover connection pool...")
    unsubscribe(state[:failover_connection_pool], subscription_handler)
    state
  end

  @doc """
  GenServer callback - invoked to handle all other messages which are received by the process.  This handler
  will restart any connection or channel PIDs that have failed

  ## Options

  The `ref` option defines the PID reference

  The `_pid` option defines the PID

  The `reason` option represents the reason the PID has stopped

  ## Return Values

  {:noreply, new_state}
  """  
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if (state[:closed] == true) do
      Logger.debug("[ConnectionPool] ConnectionPool is closed, ignoring reference #{inspect ref} :DOWN notification")
      {:noreply, state}
    else
      retry_cnt = state[:connection_options][:retry_cnt]
      if retry_cnt == nil do
        retry_cnt = 5
      end

      #determine if this is a connection or a channel
      {channel_id, remaining_channel_refs} = HashDict.pop(state[:channels_info][:refs], ref)
      {connection_url, remaining_connection_refs} = HashDict.pop(state[:connections_info][:refs], ref)
      resolved_state = cond do
        channel_id != nil ->
          Logger.info("[ConnectionPool] Channel #{channel_id} is down, attempting to restart...")
          channels_info = Map.put(state[:channels_info], :refs, remaining_channel_refs)
          resolved_state = Map.put(state, :channels_info, channels_info)

          #attempt to restart the channel
          case restart_channel(state, state[:connection_options][:connection_url], channel_id, 5) do
            {resolved_state, {:ok, _new_channel_id}} -> resolved_state
            {resolved_state, {:error, _reason}} -> resolved_state
          end
        connection_url != nil ->
          Logger.info("[ConnectionPool] Connection #{connection_url} is down, attempting to restart...")
          connections_info = Map.put(state[:connections_info], :refs, remaining_connection_refs)
          resolved_state = Map.put(state, :connections_info, connections_info)

          #attempt to restart the connection
          restart_connection(resolved_state, connection_url, retry_cnt)
        true ->
          Logger.error("[ConnectionPool] Process #{inspect ref} is down, but not managed by this connection pool")
          state
      end

      {:noreply, resolved_state}
    end
  end

  @doc """
  GenServer callback - invoked to handle all other messages which are received by the process.

  ## Options

  The `ref` option defines the PID reference

  The `_pid` option defines the PID

  The `reason` option represents the reason the PID has stopped

  ## Return Values

  {:noreply, new_state}
  """  
  @spec handle_info({term, term, term, term, String.t}, term) :: {:noreply, term}
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @doc """
  GenServer callback - called when the server is about to terminate, useful for cleaning up. It must return :ok.

  ## Options

  The `pid` option defines the PID of the server

  The `state` option represents the final state of the server

  ## Return Values

  :ok
  """  
  @spec terminate(pid, term) :: :ok
  def terminate(process, state) do
    Logger.debug("[ConnectionPool] Terminate:  #{inspect process} #{inspect state}")
  end

  ## Utility Methods

  @doc """
  Method to restart a connection, in the event of a failure

  ## Options

  The `state` option defines the state of the server

  The `connection_url` option represents the URL of the AMQP connection

  The `retry_cnt` option defines the number of remaining retries left

  ## Return Values

  :ok
  """  
  @spec restart_connection(term, String.t, term) :: :ok  
  def restart_connection(state, connection_url, retry_cnt) do
    if retry_cnt <= 0 do
      Logger.error("[ConnectionPool] Failed to restart the connection to #{state[:connection_options][:host]}; no more retries available...")
      failover_connection(state, connection_url)
    else
      Logger.info("[ConnectionPool] Attempting to restart the connection to #{state[:connection_options][:host]}; (remaining retries #{retry_cnt})...")
      old_channel_ids = state[:connections_info][:channels_for_connections][connection_url]
      if old_channel_ids == nil do
        old_channel_ids = []
      end
      connections_info = Map.put(state[:connections_info], :channels_for_connections, Map.put(state[:connections_info][:channels_for_connections], connection_url, []))
      resolved_state = Map.put(state, :connections_info, connections_info)

      {connection_ref, resolved_state} = create_connection(resolved_state[:connection_options], resolved_state)
      if connection_ref == nil do
        Logger.error("[ConnectionPool] Failed to restart the connection to #{resolved_state[:connection_options][:host]}, retrying...")
        :timer.sleep(1000)
        restart_connection(resolved_state, connection_url, retry_cnt-1)
      else
        Enum.reduce old_channel_ids, resolved_state, fn (old_channel_id, resolved_state) ->
          {updated_state, _} = restart_channel(resolved_state, connection_url, old_channel_id, 5)
          updated_state
        end
      end
    end
  end

  @doc """
  Method to connect to a configured failover AMQP broker/exchange

  ## Options

  The `state` option defines the state of the server

  The `old_connection_url` option represents the URL of the AMQP connection

  ## Return Values

  :ok | {:error, reason}
  """  
  @spec failover_connection(term, String.t) :: :ok | {:error, String.t}
  def failover_connection(state, old_connection_url) do
    failover_options = get_failover_options(state[:connection_options])
    cond do
      state[:failover_connection_pool] -> 
        Logger.error("[ConnectionPool] Unable to failover - connection has already been failed over")
        state
      length(failover_options) == 0 ->
        Logger.error("[ConnectionPool] Failed to connect to failover exchange - no failover connection options have been configured!")
        state
      true ->
        Logger.info("[ConnectionPool] Attempting to connect to failover exchange on host #{failover_options[:host]}...")
        failover_connection_pool = ConnectionPools.get_pool(failover_options)
        if failover_connection_pool == nil do
          Logger.error("[ConnectionPool] Unable to connect to failover host #{failover_options[:host]}!")
          state
        else
          #re-register subscribers
          old_channel_ids = state[:connections_info][:channels_for_connections][old_connection_url]
          if old_channel_ids != nil && length(old_channel_ids) > 0 do
            Enum.reduce old_channel_ids, state, fn (old_channel_id, state) ->
              Logger.debug("[ConnectionPool] Migrating subscribers to failover connection pool...")
              queues_for_channel = state[:channels_info][:queues_for_channel][old_channel_id]
              if queues_for_channel != nil do
                {result, reason} = Enum.reduce queues_for_channel, {:ok, nil}, fn (subscription_handler, {result, reason}) ->
                  queue_info = SubscriptionHandler.get_subscription_options(subscription_handler)
                  if result == :ok do
                    case ConnectionPool.subscribe(failover_connection_pool, queue_info[:exchange], queue_info[:queue], queue_info[:callback_handler]) do
                      :ok -> {result, reason}
                      {:error, reason} -> {:error, reason}
                    end
                  end
                end

                if result != :ok do
                  Logger.error("[ConnectionPool] An error occurred migrating subscribers to the failover connection:  #{inspect reason}")
                else
                  Logger.debug("[ConnectionPool] Successfully migrated subscribers to the failover connection")
                end
              end
            end
          end
          Map.put(state, :failover_connection_pool, failover_connection_pool)
        end
    end
  end

  # Method to retrieve the implementation-specific failover options (implementation)
  @spec get_failover_options(any) :: [{:failover_host | :failover_password | :failover_username | :failover_virtual_host, term}]
  defp get_failover_options(options) do
    failover_options = []

    if options[:failover_username] != nil do
      failover_options = failover_options ++ [failover_username: options[:failover_username]]
    end

    if options[:failover_password] != nil do
      failover_options = failover_options ++ [failover_password: options[:failover_password]]
    end    

    if options[:failover_host] != nil do
      failover_options = failover_options ++ [failover_host: options[:failover_host]]
    end 

    if options[:failover_virtual_host] != nil do
      failover_options = failover_options ++ [failover_virtual_host: options[:failover_virtual_host]]
    end 

    failover_options
  end

  @doc """
  Method to restart a channel within a specific connection, in the event of a failure

  ## Options

  The `state` option defines the state of the server

  The `connection_url` option represents the URL of the AMQP connection

  The `old_channel_id` option represents the the original ID of the AMQP channel

  The `retry_cnt` option defines the number of remaining retries left

  ## Return Values

  {state, {:ok, channel_id}} | {state, {:error, reason}}
  """  
  @spec restart_channel(term, String.t, String.t, term) :: {term, {:ok, String.t}} | {term, {:error, String.t}}
  def restart_channel(state, connection_url, old_channel_id, retry_cnt) do
    #have to clear out channels data first, because channel_id is process id which won't change
    old_queues_for_channel = state[:channels_info][:queues_for_channel][old_channel_id]

    #clear out expired channel info (key is ref, not channel_id)
    remaining_channel_refs = Enum.reduce HashDict.keys(state[:channels_info][:refs]), HashDict.new, fn (key, remaining_channel_refs) ->
      channel_id_for_key = HashDict.get(state[:channels_info][:refs], key)
      if channel_id_for_key == old_channel_id do
        remaining_channel_refs
      else
        HashDict.put(remaining_channel_refs, key, channel_id_for_key)
      end
    end

    channels_info = Map.put(state[:channels_info], :refs, remaining_channel_refs)
    channels_info = Map.put(channels_info, :channels, Map.delete(channels_info[:channels], old_channel_id))
    channels_info = Map.put(channels_info, :queues_for_channel, Map.delete(channels_info[:queues_for_channel], old_channel_id))   
    resolved_state = Map.put(state, :channels_info, channels_info)

    #start a new channel
    {resolved_state, result} = case create_channel_for_connection(resolved_state, connection_url) do
      {nil, resolved_state} -> 
        if retry_cnt <= 0 do
          Logger.error("[ConnectionPool] Failed to restart the channel #{old_channel_id} on connection #{resolved_state[:connection_options][:host]}, retrying...")
          :timer.sleep(1000)  
          restart_channel(resolved_state, connection_url, old_channel_id, retry_cnt-1)        
        else
          {resolved_state, {:error, "[ConnectionPool] Failed to restart channel #{old_channel_id}"}}
        end
      {channel_id, resolved_state} ->
        #re-register subscribers
        
        resolved_state = if old_queues_for_channel != nil do
          Enum.reduce old_queues_for_channel, resolved_state, fn (subscription_handler, resolved_state) ->
            queue_info = SubscriptionHandler.get_subscription_options(subscription_handler)
            {updated_state, _subscription_handler} = subscribe_to_queue(resolved_state, channel_id, queue_info[:exchange], queue_info[:queue], queue_info[:callback_handler])
            updated_state
          end
        else
          resolved_state
        end
        {resolved_state, {:ok, channel_id}}
    end

    {resolved_state, result}
  end

  @doc """
  Method to subscribe a callback handler to a specific queue

  ## Options

  The `state` option defines the state of the server

  The `channel_id` option represents the ID of the AMQP channel

  The `exchange` option represents the AMQP exchange name

  The `queue` option represents the AMQP queue name

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 or 3arguments.  

  ## Return Values

  {the updated state, the new SubscriptionHandler}
  """  
  @spec subscribe_to_queue(term, String.t, AMQPExchange.t, Queue.t, term) :: {map, pid}
  def subscribe_to_queue(state, channel_id, exchange, queue, callback_handler) do
    Logger.debug("[ConnectionPool] On channel #{channel_id}, subscribing to exchange #{exchange.name}, queue #{queue.name}, queue options #{inspect queue.options}, binding options #{inspect queue.binding_options}...")

    channel = state[:channels_info][:channels][channel_id]
    subscription_handler = SubscriptionHandler.subscribe(%{channel_id: channel_id, channel: channel, exchange: exchange, queue: queue, callback_handler: callback_handler})
    queues_for_channel = state[:channels_info][:queues_for_channel][channel_id]
    if queues_for_channel == nil do
      queues_for_channel = []
    end
    queues_for_channel = queues_for_channel ++ [subscription_handler]
    queues = Map.put(state[:channels_info][:queues_for_channel], channel_id, queues_for_channel)
    channels_info = Map.put(state[:channels_info], :queues_for_channel, queues)
    {Map.put(state, :channels_info, channels_info), subscription_handler}
  end

  @doc """
  Method to retrieve a channel identifier, for a connection (existing or to be created)

  ## Options

  The `state` option defines the state of the server

  ## Return Values

  {channel_id, state} | {nil, state}
  """  
  @spec get_channel(term) :: {term, term}
  def get_channel(state) do
    case get_connection(state) do
      {nil, resolved_state} ->
        Logger.error("[ConnectionPool] Unable to create a channel on the AMQP broker because an invalid connection was returned!")
        {nil, resolved_state}
      {connection_url, resolved_state} -> 
        channel_id = "#{inspect self()}"
        if state[:channels_info][:channels][channel_id] == nil do
          create_channel_for_connection(resolved_state, connection_url)    
        else
          {channel_id, resolved_state}
        end
    end
  end

  @doc """
  Method to create a channel on an existing connection

  ## Options

  The `state` option defines the state of the server

  The `connection_url` option defines which connection to use for creating the channel

  ## Return Values

  {channel_id, state} | {nil, state}
  """  
  @spec create_channel_for_connection(term, String.t) :: {term, term}
  def create_channel_for_connection(state, connection_url) do
    connection = state[:connections_info][:connections][connection_url]
    if connection == nil do
      Logger.error("[ConnectionPool] Unable to create a channel for connection #{connection_url}, because the cached connection is invalid!")
      {nil, state}      
    else
      case Channel.open(connection) do
        {:ok, channel} -> 
          channel_id = "#{inspect self()}"
          ref = Process.monitor(channel.pid)

          channels_info = state[:channels_info]
          channels_info = Map.put(channels_info, :refs, HashDict.put(state[:channels_info][:refs], ref, channel_id))
          channels_info = Map.put(channels_info, :channels, Map.put(channels_info[:channels], channel_id, channel))

          channels = Map.put(channels_info[:channels], channel_id, channel)
          channels_info = Map.put(channels_info, :channels, channels)

          GenEvent.sync_notify(state[:events], {:create, channel_id, channel})

          resolved_state = Map.put(state, :channels_info, channels_info)

          #store the fact that we've created a channel for that connection
          channels_for_connection = resolved_state[:connections_info][:channels_for_connections][connection_url]
          if channels_for_connection == nil do
            channels_for_connection = []
          end
          channels_for_connection = channels_for_connection ++ [channel_id]

          channels = Map.put(resolved_state[:connections_info][:channels_for_connections], connection_url, channels_for_connection)
          connections_info = Map.put(resolved_state[:connections_info], :channels_for_connections, channels)
          resolved_state = Map.put(resolved_state, :connections_info, connections_info)

          # Set a prefetch count so that a single Queue subscriber doesn't become bogged down.  Currently, this setting
          # will apply to all consumers, since the channels are controlled by the ConnectionPool
          prefetch_count = Application.get_env(:openaperture_messaging, :global_prefetch_count, 10)
          Logger.debug("[ConnectionPool] Channel #{channel_id} has a prefetch_count of #{prefetch_count}")
          Basic.qos(channel, prefetch_count: prefetch_count)

          {channel_id, resolved_state}
        {:error, reason} ->             
          Logger.error("[ConnectionPool] Unable to create a channel on the AMQP broker: #{inspect reason}")
          {nil, state}
      end     
    end      
  end

  @doc """
  Method to create a existing connection, based on the state's connection options and max_connection_cnt

  ## Options

  The `state` option defines the state of the server

  ## Return Values

  {connection_url, state} | {nil, state}
  """  
  @spec get_connection(term) :: {term, term}
  def get_connection(state) do   
    resolved_state = cond do
      #unlimited connections
      state[:max_connection_cnt] == -1 -> 
        Logger.debug("[ConnectionPool] Opening a new connection (unlimited)...")
        create_connections(1, state[:connection_options], state)
      state[:connections_info][:connections] != nil && length(Map.keys(state[:connections_info][:connections])) > 0 -> 
        Logger.debug("[ConnectionPool] Returning existing connections...")
        state
      true ->
        Logger.debug("[ConnectionPool] Opening a new connection...")
        create_connections(state[:max_connection_cnt], state[:connection_options], state)
    end
    
    if resolved_state[:connections_info][:connections] != nil do
      connection_urls = Map.keys(resolved_state[:connections_info][:connections])
      connection_cnt = length(connection_urls)
      connection_url = cond do 
        connection_cnt == 0 -> 
          Logger.error("[ConnectionPool] Unable to connect to AMQP broker #{state[:connection_options][:host]}: No available connection pools could be found!")
          nil
        connection_cnt == 1 -> List.first(connection_urls)
        true ->
          idx = :random.uniform(connection_cnt) - 1
          Enum.reduce connection_cnt, {0, nil}, fn (current_connection_url, {current_idx, connection_url}) ->
            if current_idx == idx do
              {current_idx+1, current_connection_url}
            else
              {current_idx+1, connection_url}
            end
          end
      end

      {connection_url, resolved_state}
    else
      Logger.error("[ConnectionPool] Failed to connect to the exchange!")
      {nil, failover_connection(state, "")}
    end
  end

  @doc """
  Method to create connections, based on connection options

  ## Options

  The `connection_cnt` option defines the number of remaining connections to create

  The `connection_options` option defines the connection options to use

  The `state` option defines the state of the server

  ## Return Values

  state
  """  
  def create_connections(0, _, state) do
    state
  end

  @doc """
  Method to create connections, based on connection options

  ## Options

  The `connection_cnt` option defines the number of remaining connections to create

  The `connection_options` option defines the connection options to use

  The `state` option defines the state of the server

  ## Return Values

  state
  """  
  @spec create_connections(term, list, term) :: term
  def create_connections(connection_cnt, connection_options, state) do
    {_, resolved_state} = create_connection(connection_options, state)
    create_connections(connection_cnt-1, connection_options, resolved_state)
  end

  @doc """
  Method to create a connection, based on connection options

  ## Options

  The `connection_options` option defines the connection options to use

  The `state` option defines the state of the server

  ## Return Values

  {ref, state}
  """  
  @spec create_connection(list, term) :: {reference | nil, term}
  def create_connection(connection_options, state) do
    #port is optional, but if it's nil we need to remove it before connecting
    if connection_options[:port] == nil do
      connection_options = Keyword.delete(connection_options, :port)
    end
    case Connection.open(connection_options) do
      {:ok, connection} -> 
        Logger.debug("[ConnectionPool] Successfully created connection to #{connection_options[:host]}")
        ref = Process.monitor(connection.pid)

        connections_info = state[:connections_info]
        connections_info = Map.put(connections_info, :refs, HashDict.put(connections_info[:refs], ref, connection_options[:connection_url]))

        connections = Map.put(connections_info[:connections], connection_options[:connection_url], connection)
        connections_info = Map.put(connections_info, :connections, connections)

        GenEvent.sync_notify(state[:events], {:create, connection_options[:connection_url], connection})

        {ref, Map.put(state, :connections_info, connections_info)}
      {:error, reason} -> 
        Logger.error("[ConnectionPool] Unable to connect to AMQP broker #{connection_options[:host]}: #{inspect reason}")
        {nil, state}
    end
  end

  @doc """
  Proxies to :erlang.term_to_binary

  ## Accepts:
  * term — a single data structure of any type

  ## Returns
  binary
  """
  @spec serilalize(term) :: binary
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