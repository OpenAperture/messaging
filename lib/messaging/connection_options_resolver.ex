#
# == connection_options_resolver.ex
#
# This module contains the logic to resolve the appropriate connection options for a messaging client
#
require Logger

defmodule OpenAperture.Messaging.ConnectionOptionsResolver do
	use GenServer

  @moduledoc """
  This module contains the logic to resolve the appropriate connection options for a messaging client
  """  

  alias OpenAperture.ManagerApi.MessagingExchange
  alias OpenAperture.ManagerApi.MessagingBroker

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    GenServer.start_link(__MODULE__, %{exchanges: %{}, broker_connection_options: %{}, brokers: %{}}, name: __MODULE__)
  end

  @doc """
  Method to retrieve the appropriate connection options for a messaging client

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `src_broker_id` option defines the source broker identifier (where is the message going to start)

  The `src_exchange_id` option defines the source exchange identifier (where is the message going to start)

  The `dest_exchange_id` option defines the destination exchange identifier (where is the message going to end)

  ## Return Values

  Returns the connection_option
  """
  @spec resolve(term, String.t(), String.t(), String.t()) :: term
  def resolve(api, src_broker_id, src_exchange_id, dest_exchange_id) do
  	GenServer.call(__MODULE__, {:resolve, api, src_broker_id, src_exchange_id, dest_exchange_id})
  end

  @doc """
  Method to retrieve the appropriate connection option for a messaging client to a specific broker

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `src_broker_id` option defines the source broker identifier (where is the message going to start)

  ## Return Values

  Returns the connection_option
  """
  @spec get_for_broker(term, String.t()) :: term
  def get_for_broker(api, broker_id) do
    GenServer.call(__MODULE__, {:get_for_broker, api, broker_id})
  end

  @doc """
  Call handler to resolve the connection options

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `broker_id` option defines the source broker identifier (where is the message going to start)

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state
  
  ## Return Values

  {:reply, OpenAperture.Messaging.ConnectionOptions.t, resolved_state}
  """
  @spec handle_call({:get_for_broker, term, String.t(), String.t(), String.t()}, term, Map) :: {:reply, OpenAperture.Messaging.ConnectionOptions.t, Map}
  def handle_call({:get_for_broker, api, broker_id}, _from, state) do
    {connection_option, resolved_state} = get_connection_option_for_broker(state, api, broker_id)

    #right now, simply convert into AMQP options
    amqp_options = if connection_option != nil do
      OpenAperture.Messaging.AMQP.ConnectionOptions.from_map(connection_option)
    else
      nil
    end
    {:reply, amqp_options, resolved_state}
  end

  @doc """
  Call handler to resolve the connection options

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `src_broker_id` option defines the source broker identifier (where is the message going to start)

  The `src_exchange_id` option defines the source exchange identifier (where is the message going to start)

  The `dest_exchange_id` option defines the destination exchange identifier (where is the message going to end)

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state
  
  ## Return Values

  {:reply, OpenAperture.Messaging.ConnectionOptions, resolved_state}
  """
  @spec handle_call({:resolve, term, String.t(), String.t(), String.t()}, term, Map) :: {:reply, OpenAperture.Messaging.ConnectionOptions.t, Map}
  def handle_call({:resolve, api, src_broker_id, src_exchange_id, dest_exchange_id}, _from, state) do
    #is src exchange restricted?
    {src_exchange_restrictions, resolved_state} = get_restrictions_for_exchange(state, api, src_exchange_id)

    #is dest exchange restricted?
    {dest_exchange_restrictions, resolved_state} = get_restrictions_for_exchange(resolved_state, api, dest_exchange_id)

    {connection_option, resolved_state} = cond do
      #if the dest is restricted, we have to use the dest broker options
      dest_exchange_restrictions != nil && length(dest_exchange_restrictions) > 0 -> 
        get_connection_option_for_brokers(resolved_state, api, dest_exchange_restrictions)

      #if the src is restricted, we have to use the dest broker options (don't know if src can connect to dest)
      src_exchange_restrictions != nil && length(src_exchange_restrictions) > 0 -> 
        if dest_exchange_restrictions == nil || length(dest_exchange_restrictions) == 0 do
          Logger.warn("[ConnectionOptionsResolver] The source exchange #{src_exchange_id} has restrictions, but no restrictions on destination exchange #{dest_exchange_id} were found.  Attempting to use source restrictions (but this may not work)...")
          get_connection_option_for_brokers(resolved_state, api, src_exchange_restrictions)
        else
          get_connection_option_for_brokers(resolved_state, api, dest_exchange_restrictions)
        end

      #nothing is restricted, use broker associated to the source exchange
      true -> 
        get_connection_option_for_broker(resolved_state, api, src_broker_id)
    end

    #right now, simply convert into AMQP options
    amqp_options = if connection_option != nil do
      OpenAperture.Messaging.AMQP.ConnectionOptions.from_map(connection_option)
    else
      nil
    end
    {:reply, amqp_options, resolved_state}
  end

  @doc """
  Method to determine if the cached options are stale (i.e. retrieved > 5 minutes prior)

  ## Return Values

  Boolean
  """
  @spec cache_stale?(Map | nil) :: term
  def cache_stale?(cache) do
    if cache == nil || cache[:retrieval_time] == nil do
      true
    else
      seconds = :calendar.datetime_to_gregorian_seconds(cache[:retrieval_time])
      now_seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
      (now_seconds - seconds) > 300
    end
  end

  @doc """
  Method to identify a single connection option for a set of brokers

  ## Options

  The `state` option represents the server state

  The `api` option represents a OpenAperture.ManagerApi

  The `exchange_id` option represents an MessageExchange identifier

  ## Return Values

  {Map, state}
  """
  @spec get_connection_option_for_brokers(Map, term, String.t()) :: {term, Map}
  def get_connection_option_for_brokers(state, api, brokers) do
    idx = :random.uniform(length(brokers))-1
    {broker, _cur_idx} = Enum.reduce brokers, {nil, 0}, fn (cur_broker, {broker, cur_idx}) ->
      if cur_idx == idx do
        {cur_broker, cur_idx+1}
      else
        {broker, cur_idx+1}
      end
    end

    get_connection_option_for_broker(state, api, broker["id"])
  end

  @doc """
  Method to select a connection option from a list of available options

  ## Options

  The `state` option represents the server state

  The `api` option represents a OpenAperture.ManagerApi

  The `broker_id` option represents an MessageBroker identifier

  ## Return Values

  {Map, state}
  """
  @spec get_connection_option_for_broker(Map, term, String.t()) :: {term, Map}
  def get_connection_option_for_broker(state, api, broker_id) do
    {connection_options, resolved_state} = case get_connection_options_from_cache(state, broker_id) do
      nil ->
        Logger.debug("[ConnectionOptionsResolver] Retrieving connection options for broker #{broker_id}...")
        connection_options = MessagingBroker.broker_connections!(api, broker_id)
        if connection_options == nil do
          Logger.error("[ConnectionOptionsResolver] No connection options have been defined for broker #{broker_id}!")
        else
          Logger.debug("[ConnectionOptionsResolver] There are #{length(connection_options)} connection options defined for broker #{broker_id}")
        end
        {connection_options, cache_connection_options(state, broker_id, connection_options)}
      connection_options -> {connection_options, state}
    end
    connection_option = resolve_connection_option_for_broker(connection_options)

    {failover_connection_option, resolved_state} = case get_broker(resolved_state, broker_id, api) do
      {nil, resolved_state} ->
        Logger.error("[ConnectionOptionsResolver] Failed to retrieve broker #{broker_id}!")
        {nil, resolved_state}
      {broker, resolved_state} ->
        if broker["failover_broker_id"] != nil do
          case get_connection_options_from_cache(resolved_state, broker["failover_broker_id"]) do
            nil ->
              failover_connection_options = MessagingBroker.broker_connections!(api, broker["failover_broker_id"])
              {resolve_connection_option_for_broker(failover_connection_options), cache_connection_options(resolved_state, broker["failover_broker_id"], failover_connection_options)}
            failover_connection_options -> {resolve_connection_option_for_broker(failover_connection_options), resolved_state}
          end
        else
          {nil, resolved_state}
        end        
    end

    cond do 
      connection_option == nil -> {nil, resolved_state}
      failover_connection_option == nil -> {connection_option, resolved_state}
      true ->
        {Map.merge(connection_option, %{
          "failover_id" => failover_connection_option["id"],
          "failover_username" => failover_connection_option["username"],
          "failover_password" => failover_connection_option["password"],
          "failover_host" => failover_connection_option["host"],
          "failover_port" => failover_connection_option["port"],
          "failover_virtual_host" => failover_connection_option["virtual_host"]
        }), resolved_state}
    end
  end

  @doc """
  Method to check the cache for existing connection options

  ## Options

  The `api` option represents a OpenAperture.ManagerApi

  The `broker_id` option represents an MessageBroker identifier

  ## Return Values

  Map
  """
  @spec get_connection_options_from_cache(Map, String.t()) :: List | nil
  def get_connection_options_from_cache(state, broker_id) do
    broker_id_cache = state[:broker_connection_options][broker_id]
    if cache_stale?(broker_id_cache) do
      Logger.debug("[ConnectionOptionsResolver] Connection options for broker #{broker_id} are not cached")
      nil
    else
      Logger.debug("[ConnectionOptionsResolver] Connection options for broker #{broker_id} are cached")
      broker_id_cache[:connection_options]
    end    
  end

  @doc """
  Method to cache connection options

  ## Options

  The `api` option represents a OpenAperture.ManagerApi

  The `broker_id` option represents an MessageBroker identifier

  The `connection_options` option represents the options to cache

  ## Return Values

  updated state
  """
  @spec cache_connection_options(Map, String.t(), List) :: List
  def cache_connection_options(state, broker_id, connection_options) do
    broker_id_cache = %{
      retrieval_time: :calendar.universal_time,
      connection_options: connection_options
    }

    broker_cache = Map.put(state[:broker_connection_options], broker_id, broker_id_cache)
    Map.put(state, :broker_connection_options, broker_cache)
  end

  @doc """
  Method to retrieve a broker from cache or from the Manager

  ## Options

  The `state` option represents the current server state

  The `broker_id` option represents an MessagingBroker identifier

  The `api` option represents a OpenAperture.ManagerApi

  ## Return Values

  Map of the MessagingBroker
  """
  @spec get_broker(Map, String.t, pid) :: {Map | nil, Map}
  def get_broker(state, broker_id, api) do
    broker_cache = state[:brokers][broker_id]
    if cache_stale?(broker_cache) do
      Logger.debug("[ConnectionOptionsResolver] Broker #{broker_id} is not cached, retrieving...")
      case MessagingBroker.get_broker!(api, broker_id) do
        nil ->
          Logger.error("[ConnectionOptionsResolver] Failed to retrieve broker #{broker_id}!")
          {nil, state}
        broker ->
          broker_cache = %{
            retrieval_time: :calendar.universal_time,
            broker: broker
          }

          broker_cache = Map.put(state[:brokers], broker_id, broker_cache)
          state = Map.put(state, :brokers, broker_cache)
          {broker, state}    
      end
    else
      {broker_cache[:broker], state}
    end  
  end

  @doc """
  Method to select a connection option from a list of available options

  ## Options

  The `api` option represents a OpenAperture.ManagerApi

  The `exchange_id` option represents an MessageExchange identifier

  ## Return Values

  Map
  """
  @spec resolve_connection_option_for_broker(List) :: {term, Map} | nil
  def resolve_connection_option_for_broker(connection_options) do
    if connection_options != nil && length(connection_options) > 0 do
      idx = :random.uniform(length(connection_options))-1
      {connection_option, _cur_idx} = Enum.reduce connection_options, {nil, 0}, fn (cur_connection_option, {connection_option, cur_idx}) ->
        if cur_idx == idx do
          {cur_connection_option, cur_idx+1}
        else
          {connection_option, cur_idx+1}
        end
      end
      connection_option
    else
      nil
    end
  end

  @doc """
  Method to retrieve any broker restrictions for a specific exchange identifier

  ## Options

  The `state` option represents the server state

  The `api` option represents a OpenAperture.ManagerApi

  The `exchange_id` option represents an MessageExchange identifier

  ## Return Values

  {List of broker Maps, state}
  """
  @spec get_restrictions_for_exchange(Map, term, String.t()) :: {List, Map}
  def get_restrictions_for_exchange(state, api, exchange_id) do
    exchange_id_cache = state[:exchanges][exchange_id]
    unless cache_stale?(exchange_id_cache) do
      {exchange_id_cache[:broker_restrictions], state}
    else
      if exchange_id_cache == nil do
        exchange_id_cache = %{}
      end
      exchange_id_cache = Map.put(exchange_id_cache, :retrieval_time, :calendar.universal_time)

      #Find any restrictions
      restrictions = MessagingExchange.exchange_brokers!(api, exchange_id)

      exchange_id_cache = Map.put(exchange_id_cache, :broker_restrictions, restrictions)
      exchange_cache = Map.put(state[:exchanges], exchange_id, exchange_id_cache)
      state = Map.put(state, :exchanges, exchange_cache)

      {restrictions, state}
    end
  end
end