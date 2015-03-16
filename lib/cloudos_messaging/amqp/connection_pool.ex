#
# == connection_pool.ex
#
# This module contains the GenServer for a specific connection pool, which manages
# all connections to the AMQP host.  This class also provides reconnection logic in the event
# the connection or channel dies
#
require Logger

defmodule CloudOS.Messaging.AMQP.ConnectionPool do
  use GenServer
	use AMQP

  alias CloudOS.Messaging.ConnectionOptions
  alias CloudOS.Messaging.AMQP.ConnectionPools

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
  @spec start_link(List) :: {:ok, pid} | {:error, String.t()}	
  def start_link(connection_options) do
    # 1. create event manager as argument
    case GenEvent.start_link do
      {:ok, event_manager} -> 
        Logger.debug("GenEvent start was successful, starting ConnectionPool...")
        case GenServer.start_link(__MODULE__, event_manager, []) do
          {:ok, pool} -> 
            CloudOS.Messaging.AMQP.ConnectionPool.set_connection_options(pool, connection_options)
            {:ok, pool}
          {:error, reason} -> {:error, "Failed to create ConnectionPool: #{inspect reason}"}
        end

      {:error, reason} -> {:error, "Failed to create ConnectionPool: #{inspect reason}"}
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
  @spec set_connection_options(pid, List) :: :ok | {:error, String.t()}
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
  should be a function with 2 arguments.

  ## Return Values

  :ok | {:error, reason}
  """
  @spec subscribe(pid, String.t(), String.t(), term) :: :ok | {:error, String.t()}
  def subscribe(connection_pool, exchange, queue, callback_handler) when is_function(callback_handler, 2) do
    GenServer.call(connection_pool, {:subscribe, exchange, queue, callback_handler})
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
  @spec publish(pid, String.t(), String.t(), term) :: :ok | {:error, String.t()}
  def publish(connection_pool, exchange, queue, payload) do
    GenServer.call(connection_pool, {:publish, exchange, queue, payload})    
  end

  ## Server callbacks

  @doc """
  GenServer callback - invoked when the server is started.

  ## Options

  The `args` option represents the args to the GenServer.  In this case, we're expecting
  this to be the GenEvent server, generated during start_link

  ## Return Values

  {:ok, state} | {:ok, state, timeout} | :ignore | {:stop, reason}
  """  
  @spec init(term) :: {:ok, term} | {:ok, term, term} | :ignore | {:stop, String.t()}
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
  @spec handle_call({:set_connection_options, List}, term, term) :: {:reply, term, term}
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
  @spec handle_call({:publish, String.t(), String.t(), term}, term, term) :: {:reply, term, term}
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
              {:reply, {:error, "Unable to publish to queue on the AMQP broker because no channel was found"}, resolved_state}        
            end
          {channel_id, resolved_state} ->
            channel = resolved_state[:channels_info][:channels][channel_id]
            Basic.publish(channel, exchange.name, queue.name, serilalize(payload), [:persistent])
            {:reply, :ok, resolved_state}
        end
      end
    rescue e in RuntimeError ->
      reason = "Failed to publish a msg to RabbitMQ: #{inspect e}"
      Logger.error(reason)
      {:reply, {:error, reason}, state}
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
  @spec publish_to_failover(term, String.t(), term, term) :: term
  defp publish_to_failover(state, exchange, queue, payload) do    
    Logger.debug("Rerouting publishing request to failover connection pool...")
    CloudOS.Messaging.AMQP.ConnectionPool.publish(state[:failover_connection_pool], exchange, queue, payload)
    state
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

  {:reply, reply, new_state}
  """  
  @spec handle_call({:subscribe, String.t(), String.t(), term}, term, term) :: {:reply, term, term}
  def handle_call({:subscribe, exchange, queue, callback_handler}, _from, state) do
    Logger.debug("Subscribing to exchange #{exchange.name}, queue #{queue.name}...")
    if state[:failover_connection_pool] != nil do
      {:reply, :ok, subscribe_to_failover(state, exchange, queue, callback_handler)}
    else
      case get_channel(state) do
        {nil, resolved_state} -> 
          #get_channel can create the failover connection pool
          if resolved_state[:failover_connection_pool] != nil do
            {:reply, :ok, subscribe_to_failover(resolved_state, exchange, queue, callback_handler)}
          else
             {:reply, {:error, "Unable to subsribe to queue on the AMQP broker because no channel was found"}, resolved_state}        
          end
        {channel_id, resolved_state} ->
          Logger.debug("Using channel #{channel_id}...")
          resolved_state = subscribe_to_queue(resolved_state, channel_id, exchange, queue, callback_handler)
          {:reply, :ok, resolved_state}
      end
    end
  end

  @doc false
  # Method to subscribe to the failover connection pool
  #
  ## Options
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
  @spec subscribe_to_failover(term, String.t(), term, term) :: term
  defp subscribe_to_failover(state, exchange, queue, callback_handler) do    
    Logger.debug("Rerouting subscribe request to failover connection pool...")
    CloudOS.Messaging.AMQP.ConnectionPool.subscribe(state[:failover_connection_pool], exchange, queue, callback_handler)
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
  @spec handle_info({:DOWN, term, term, term, String.t()}, term) :: {:noreply, term}
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    retry_cnt = state[:connection_options][:retry_cnt]
    if retry_cnt == nil do
      retry_cnt = 5
    end

    #determine if this is a connection or a channel
    {channel_id, remaining_channel_refs} = HashDict.pop(state[:channels_info][:refs], ref)
    {connection_url, remaining_connection_refs} = HashDict.pop(state[:connections_info][:refs], ref)
    resolved_state = cond do
      channel_id != nil ->
        Logger.info("Channel #{channel_id} is down, attempting to restart...")
        channels_info = Map.put(state[:channels_info], :refs, remaining_channel_refs)
        resolved_state = Map.put(state, :channels_info, channels_info)

        #attempt to restart the channel
        case restart_channel(state, connection_url, channel_id, 5) do
          {resolved_state, {:ok, new_channel_id}} -> resolved_state
          {resolved_state, {:error, reason}} -> resolved_state
        end
      connection_url != nil ->
        Logger.info("Connection #{connection_url} is down, attempting to restart...")
        connections_info = Map.put(state[:connections_info], :refs, remaining_connection_refs)
        resolved_state = Map.put(state, :connections_info, connections_info)

        #attempt to restart the connection
        restart_connection(resolved_state, connection_url, retry_cnt)
      true ->
        Logger.error("Process #{ref} is down, but not managed by this connection pool")
        state
    end

    {:noreply, resolved_state}
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
  @spec handle_info({term, term, term, term, String.t()}, term) :: {:noreply, term}
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
    Logger.debug("Terminate:  #{inspect process} #{inspect state}")
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
  @spec restart_connection(term, String.t(), term) :: :ok  
  def restart_connection(state, connection_url, retry_cnt) do
    if retry_cnt <= 0 do
      Logger.error("Failed to restart the connection to #{state[:connection_options][:host]}; no more retries available...")
      failover_connection(state, connection_url)
    else
      Logger.info("Attempting to restart the connection to #{state[:connection_options][:host]}; (remaining retries #{retry_cnt})...")
      old_channel_ids = state[:connections_info][:channels_for_connections][connection_url]
      if old_channel_ids == nil do
        old_channel_ids = []
      end
      connections_info = Map.put(state[:connections_info], :channels_for_connections, Map.put(state[:connections_info][:channels_for_connections], connection_url, []))
      resolved_state = Map.put(state, :connections_info, connections_info)

      {connection_ref, resolved_state} = create_connection(resolved_state[:connection_options], resolved_state)
      if connection_ref == nil do
        Logger.error("Failed to restart the connection to #{resolved_state[:connection_options][:host]}, retrying...")
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
  @spec failover_connection(term, String.t()) :: :ok | {:error, String.t()}
  def failover_connection(state, old_connection_url) do
    failover_options = get_failover_options(state[:connection_options])
    cond do
      state[:failover_connection_pool] -> 
        Logger.error("Unable to failover - connection has already been failed over")
        state
      failover_options == nil || length(failover_options) == 0 ->
        Logger.error("Failed to connect to failover exchange - no failover connection options have been configured!")
        state
      true ->
        Logger.info("Attempting to connect to failover exchange on host #{failover_options[:host]}...")
        failover_connection_pool = ConnectionPools.get_pool(failover_options)
        if failover_connection_pool == nil do
          Logger.error("Unable to connect to failover host #{failover_options[:host]}!")
          state
        else
          #re-register subscribers
          old_channel_ids = state[:connections_info][:channels_for_connections][old_connection_url]
          if old_channel_ids != nil && length(old_channel_ids) > 0 do
            Enum.reduce old_channel_ids, state, fn (old_channel_id, state) ->
              Logger.debug("Migrating subscribers to failover connection pool...")
              queues_for_channel = state[:channels_info][:queues_for_channel][old_channel_id]
              if queues_for_channel != nil do
                {result, reason} = Enum.reduce queues_for_channel, {:ok, nil}, fn (queue_info, {result, reason}) ->
                  if result == :ok do
                    case ConnectionPool.subscribe(failover_connection_pool, queue_info[:exchange], queue_info[:queue], queue_info[:callback_handler]) do
                      :ok -> {result, reason}
                      {:error, reason} -> {:error, reason}
                    end
                  end
                end

                if result != :ok do
                  Logger.error("An error occurred migrating subscribers to the failover connection:  #{inspect reason}")
                else
                  Logger.debug("Successfully migrated subscribers to the failover connection")
                end
              end
            end
          end
          Map.put(state, :failover_connection_pool, failover_connection_pool)
        end
    end
  end

  @doc """
  Method to retrieve the implementation-specific failover options (implementation)

  ## Options

  The `options` option containing options map

  ## Return Values

  The implementation-specific options term
  """
  @spec get_failover_options(any) :: term
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
  @spec restart_channel(term, String.t(), String.t(), term) :: {term, {:ok, String.t()}} | {term, {:error, String.t()}}
  def restart_channel(state, connection_url, old_channel_id, retry_cnt) do
    #start a new channel
    {resolved_state, result} = case create_channel_for_connection(state, connection_url) do
      {nil, resolved_state} -> 
        if retry_cnt <= 0 do
          Logger.error("Failed to restart the channel #{old_channel_id} on connection #{state[:connection_options][:host]}, retrying...")
          :timer.sleep(1000)  
          restart_channel(resolved_state, connection_url, old_channel_id, retry_cnt-1)        
        else
          {resolved_state, {:error, "Failed to restart channel #{old_channel_id}"}}
        end
      {channel_id, resolved_state} ->
        #re-register subscribers
        queues_for_channel = resolved_state[:channels_info][:queues_for_channel][old_channel_id]
        resolved_state = if queues_for_channel != nil do
          resolved_state = Enum.reduce queues_for_channel, resolved_state, fn (queue_info, resolved_state) ->
            subscribe_to_queue(resolved_state, channel_id, queue_info[:exchange], queue_info[:queue], queue_info[:callback_handler])
          end
        else
          resolved_state
        end
        {resolved_state, {:ok, channel_id}}
    end

    #clear out expired channel info (key is ref, not channel_id)
    remaining_channel_refs = Enum.reduce HashDict.keys(resolved_state[:channels_info][:refs]), HashDict.new, fn (key, remaining_channel_refs) ->
      channel_id_for_key = HashDict.get(resolved_state[:channels_info][:refs], key)
      if channel_id_for_key == old_channel_id do
        remaining_channel_refs
      else
        HashDict.put(remaining_channel_refs, key, channel_id_for_key)
      end
    end

    channels_info = Map.put(resolved_state[:channels_info], :refs, remaining_channel_refs)

    queues_for_channel = Map.delete(channels_info[:queues_for_channel], old_channel_id)
    channels_info = Map.put(channels_info, :queues_for_channel, queues_for_channel)
    resolved_state = Map.put(resolved_state, :channels_info, channels_info)

    {resolved_state, result}
  end

  @doc """
  Method to subscribe a callback handler to a specific queue

  ## Options

  The `state` option defines the state of the server

  The `channel_id` option represents the ID of the AMQP channel

  The `exchangee` option represents the AMQP exchange name

  The `queue` option represents the AMQP queue name

  The `callback_handler` option represents the method that should be called when a message is received.  The handler
  should be a function with 2 arguments.  

  ## Return Values

  the updated state
  """  
  @spec subscribe_to_queue(term, String.t(), String.t(), String.t(), term) :: term
  def subscribe_to_queue(state, channel_id, exchange, queue, callback_handler) do
    Logger.debug("On channel #{channel_id}, subscribing to exchange #{exchange.name}, queue #{queue.name}, queue options #{inspect queue.options}, binding options #{inspect queue.binding_options}...")

    channel = state[:channels_info][:channels][channel_id]
    Exchange.declare(channel, exchange.name, exchange.type, exchange.options)
    
    # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
    Queue.declare(channel, queue.name, queue.options)

    Queue.bind(channel, queue.name, exchange.name, queue.binding_options)
    Queue.subscribe(channel, queue.name, fn payload, _meta ->
      payload |> deserialize |> callback_handler.(_meta)
    end)

    queues_for_channel = state[:channels_info][:queues_for_channel][channel_id]
    if queues_for_channel == nil do
      queues_for_channel = []
    end
    queues_for_channel = queues_for_channel ++ [%{exchange: exchange, queue: queue, callback_handler: callback_handler}]

    queues = Map.put(state[:channels_info][:queues_for_channel], channel_id, queues_for_channel)
    channels_info = Map.put(state[:channels_info], :queues_for_channel, queues)
    Map.put(state, :channels_info, channels_info)
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
        Logger.error("Unable to create a channel on the AMQP broker because an invalid connection was returned!")
        {nil, resolved_state}
      {connection_url, resolved_state} -> create_channel_for_connection(resolved_state, connection_url)    
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
  @spec create_channel_for_connection(term, String.t()) :: {term, term}
  def create_channel_for_connection(state, connection_url) do
    connection = state[:connections_info][:connections][connection_url]
    case Channel.open(connection) do
      {:ok, channel} -> 
        channel_id = "#{UUID.uuid1()}"
        ref = Process.monitor(channel.pid)

        channels_info = state[:channels_info]
        channels_info = Map.put(channels_info, :refs, HashDict.put(state[:channels_info][:refs], ref, channel_id))

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

        {channel_id, resolved_state}
      {:error, reason} ->             
        Logger.error("Unable to create a channel on the AMQP broker: #{inspect reason}")
        {nil, state}
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
        Logger.debug("Opening a new connection (unlimited)...")
        create_connections(1, state[:connection_options], state)
      state[:connections_info][:connections] != nil && length(Map.keys(state[:connections_info][:connections])) > 0 -> 
        Logger.debug("Returning existing connections...")
        state
      true ->
        Logger.debug("Opening a new connection...")
        create_connections(state[:max_connection_cnt], state[:connection_options], state)
    end
    
    if resolved_state[:connections_info][:connections] != nil do
      connection_urls = Map.keys(resolved_state[:connections_info][:connections])
      connection_cnt = length(connection_urls)
      connection_url = cond do 
        connection_cnt == 0 -> 
          Logger.error("Unable to connect to AMQP broker #{state[:connection_options][:host]}: No available connection pools could be found!")
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
      Logger.error("Failed to connect to the exchange!")
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
  @spec create_connections(0, List, term) :: term
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
  @spec create_connections(term, List, term) :: term
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
  @spec create_connection(List, term) :: {term, term}
  def create_connection(connection_options, state) do
    case Connection.open(connection_options) do
      {:ok, connection} -> 
        Logger.debug("Successfully created connection to #{connection_options[:host]}")
        ref = Process.monitor(connection.pid)

        connections_info = state[:connections_info]
        connections_info = Map.put(connections_info, :refs, HashDict.put(connections_info[:refs], ref, connection_options[:connection_url]))

        connections = Map.put(connections_info[:connections], connection_options[:connection_url], connection)
        connections_info = Map.put(connections_info, :connections, connections)

        GenEvent.sync_notify(state[:events], {:create, connection_options[:connection_url], connection})

        {ref, Map.put(state, :connections_info, connections_info)}
      {:error, reason} -> 
        Logger.error("Unable to connect to AMQP broker #{connection_options[:host]}: #{inspect reason}")
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